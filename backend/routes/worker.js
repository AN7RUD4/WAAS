require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const KMeans = require('kmeans-js');
const munkres = require('munkres').default;
const twilio = require('twilio');

const router = express.Router();
router.use(cors());
router.use(express.json());

// Initialize Twilio client
const twilioClient = new twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
});

pool.connect((err, client, release) => {
    if (err) {
        console.error('Error connecting to the database in worker.js:', err.stack);
        process.exit(1);
    } else {
        console.log('Worker.js successfully connected to the database');
        release();
    }
});

// Authentication middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    console.log('Auth header:', authHeader);

    if (!token) return res.status(401).json({ message: 'Authentication token required' });

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET || 'passwordKey');
        if (!decoded.userid || !decoded.role) {
            return res.status(403).json({ message: 'Invalid token: Missing userid or role' });
        }
        req.user = decoded;
        next();
    } catch (err) {
        console.error('Token verification error:', err.message);
        return res.status(403).json({ message: 'Invalid or expired token' });
    }
};

// Haversine distance function
function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth's radius in kilometers
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c; // Distance in kilometers
}

// Updated K-Means clustering function with Haversine distance
function assignWorkersToClusters(clusters, workers) {
    if (!clusters.length || !workers.length) return [];

    // Calculate cost matrix (distance from each worker to each cluster centroid)
    const costMatrix = clusters.map(cluster => {
        // Calculate cluster centroid
        const centroid = {
            lat: cluster.reduce((sum, r) => sum + r.lat, 0) / cluster.length,
            lng: cluster.reduce((sum, r) => sum + r.lng, 0) / cluster.length
        };
        
        return workers.map(worker => 
            haversineDistance(worker.lat, worker.lng, centroid.lat, centroid.lng)
        );
    });

    // Pad matrix to be square if needed
    const maxDim = Math.max(clusters.length, workers.length);
    const paddedMatrix = Array(maxDim).fill().map(() => Array(maxDim).fill(Infinity));
    
    for (let i = 0; i < costMatrix.length; i++) {
        for (let j = 0; j < costMatrix[i].length; j++) {
            paddedMatrix[i][j] = costMatrix[i][j];
        }
    }

    // Apply Hungarian algorithm
    const assignments = munkres(paddedMatrix);
    
    // Process assignments
    const results = [];
    const assignedWorkers = new Set();
    const assignedClusters = new Set();

    for (const [clusterIdx, workerIdx] of assignments) {
        if (clusterIdx >= clusters.length || workerIdx >= workers.length) continue;
        if (assignedWorkers.has(workerIdx) || assignedClusters.has(clusterIdx)) continue;
        
        results.push({
            cluster: clusters[clusterIdx],
            worker: workers[workerIdx],
            distance: costMatrix[clusterIdx][workerIdx]
        });
        
        assignedWorkers.add(workerIdx);
        assignedClusters.add(clusterIdx);
    }

    // Sort by distance (closest first)
    return results.sort((a, b) => a.distance - b.distance);
}

// Solve TSP for route optimization
function solveTSP(points, worker) {
    if (!points.length) {
        return {
            start: { lat: worker.lat, lng: worker.lng },
            waypoints: [],
            end: { lat: worker.lat, lng: worker.lng }
        };
    }

    // Create distance matrix
    const allPoints = [{ lat: worker.lat, lng: worker.lng }, ...points];
    const n = allPoints.length;
    const distMatrix = Array(n).fill().map(() => Array(n).fill(0));
    
    for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
            if (i !== j) {
                distMatrix[i][j] = haversineDistance(
                    allPoints[i].lat, allPoints[i].lng,
                    allPoints[j].lat, allPoints[j].lng
                );
            }
        }
    }

    // Nearest Neighbor algorithm
    const visited = new Set([0]); // Start with worker location
    const route = [0];
    let current = 0;
    let totalDistance = 0;

    while (visited.size < n) {
        let next = -1;
        let minDist = Infinity;
        
        for (let i = 0; i < n; i++) {
            if (!visited.has(i) && distMatrix[current][i] < minDist) {
                minDist = distMatrix[current][i];
                next = i;
            }
        }
        
        if (next === -1) break;
        
        route.push(next);
        visited.add(next);
        totalDistance += minDist;
        current = next;
    }

    // Return to start
    totalDistance += distMatrix[current][0];
    route.push(0);

    // Convert to route object
    return {
        start: { lat: allPoints[0].lat, lng: allPoints[0].lng },
        waypoints: route.slice(1, -1).map(idx => ({
            lat: allPoints[idx].lat,
            lng: allPoints[idx].lng,
            reportid: idx > 0 ? points[idx-1].reportid : null
        })),
        end: { lat: allPoints[0].lat, lng: allPoints[0].lng },
        totalDistance
    };
}
// Send SMS notification
async function sendSMS(phoneNumber, messageBody) {
    try {
        await twilioClient.messages.create({
            body: messageBody,
            from: process.env.TWILIO_PHONE_NUMBER,
            to: phoneNumber,
        });
        console.log(`SMS sent to ${phoneNumber}: ${messageBody}`);
    } catch (smsError) {
        console.error('Error sending SMS:', smsError.message);
        throw new Error('Failed to send SMS notification');
    }
}

// Role check middleware
const checkWorkerOrAdminRole = (req, res, next) => {
    console.log('Checking role for user:', req.user);
    if (!req.user || (req.user.role.toLowerCase() !== 'worker' && req.user.role.toLowerCase() !== 'official')) {
        console.log('Access denied: role not worker or admin');
        return res.status(403).json({ message: 'Access denied: Only workers or admins can access this endpoint' });
    }
    next();
};

// Update worker location endpoint
router.post('/update-worker-location', authenticateToken, async (req, res) => {
    try {
        const { userId, lat, lng } = req.body;
        
        await pool.query(
            `UPDATE users 
             SET location = ST_SetSRID(ST_MakePoint($1, $2), 4326),
                 last_location_update = NOW(),
                 status = 'available'
             WHERE userid = $3 AND role = 'worker'`,
            [lng, lat, userId]
        );
        
        res.status(200).json({ message: 'Location updated successfully' });
    } catch (error) {
        console.error('Error updating worker location:', error);
        res.status(500).json({ error: 'Failed to update location' });
    }
});


// Group and assign reports endpoint
router.post('/group-and-assign-reports', authenticateToken, async (req, res) => {
    try {
        const { startDate, maxDistance = 5, maxReportsPerWorker = 10 } = req.body;

        // 1. Fetch unassigned reports
        const reportsResult = await pool.query(`
            SELECT reportid, wastetype, ST_X(location) AS lng, ST_Y(location) AS lat, 
                   datetime, userid, severity
            FROM garbagereports
            WHERE reportid NOT IN (
                SELECT unnest(reportids) FROM taskrequests
                WHERE status NOT IN ('completed', 'rejected')
            )
            AND datetime >= COALESCE($1, NOW() - INTERVAL '7 days')
            ORDER BY 
                severity DESC, -- Higher severity first
                datetime ASC  -- Older reports first
        `, [startDate]);

        if (reportsResult.rows.length === 0) {
            return res.status(200).json({ message: 'No unassigned reports found' });
        }

        // 2. Filter and prepare reports
        const reports = reportsResult.rows
            .filter(r => r.lat !== null && r.lng !== null)
            .map(r => ({
                ...r,
                created_at: new Date(r.datetime),
                location: { lat: r.lat, lng: r.lng }
            }));

        // 3. Fetch available workers with their capacity
        const workersResult = await pool.query(`
            SELECT u.userid, ST_X(u.location) AS lng, ST_Y(u.location) AS lat,
                   COUNT(tr.taskid) FILTER (WHERE tr.status = 'assigned') AS current_tasks
            FROM users u
            LEFT JOIN taskrequests tr ON tr.assignedworkerid = u.userid
            WHERE u.role = 'worker'
            AND u.status = 'available'
            GROUP BY u.userid
            HAVING COUNT(tr.taskid) < $1
        `, [maxReportsPerWorker]);

        const workers = workersResult.rows
            .filter(w => w.lat !== null && w.lng !== null)
            .map(w => ({
                userid: w.userid,
                lat: w.lat,
                lng: w.lng,
                capacity: maxReportsPerWorker - w.current_tasks
            }));

        if (workers.length === 0) {
            return res.status(400).json({ error: 'No available workers with capacity' });
        }

        // 4. Cluster reports by geographic proximity
        const clusters = kmeansClustering(reports, Math.ceil(reports.length / maxReportsPerWorker));
        
        // Filter clusters that are too large
        const validClusters = clusters.filter(c => 
            c.length <= maxReportsPerWorker && 
            calculateClusterDiameter(c) <= maxDistance
        );

        // 5. Assign workers to clusters
        const assignments = assignWorkersToClusters(validClusters, workers);

        // 6. Create tasks and notify users
        const results = [];
        for (const { cluster, worker } of assignments) {
            // Optimize route
            const route = solveTSP(cluster, worker);
            
            // Create task
            const taskResult = await pool.query(`
                INSERT INTO taskrequests (
                    reportids, 
                    assignedworkerid, 
                    status, 
                    starttime, 
                    route,
                    estimated_distance
                )
                VALUES ($1, $2, 'assigned', NOW(), $3, $4)
                RETURNING taskid
            `, [
                cluster.map(r => r.reportid),
                worker.userid,
                route,
                route.totalDistance
            ]);

            // Update worker status if they're at capacity
            if (cluster.length >= worker.capacity) {
                await pool.query(`
                    UPDATE users 
                    SET status = 'busy' 
                    WHERE userid = $1
                `, [worker.userid]);
            }

            // Notify report submitters
            await notifyUsers(cluster, taskResult.rows[0].taskid);

            results.push({
                taskId: taskResult.rows[0].taskid,
                workerId: worker.userid,
                reportCount: cluster.length,
                estimatedDistance: route.totalDistance
            });
        }

        res.status(200).json({
            success: true,
            assignments: results,
            unassignedReports: reports.length - assignments.reduce((sum, a) => sum + a.cluster.length, 0)
        });

    } catch (error) {
        console.error('Error in group-and-assign-reports:', error);
        res.status(500).json({ 
            error: 'Internal Server Error', 
            details: error.message 
        });
    }
});

// Helper function to calculate cluster diameter
function calculateClusterDiameter(cluster) {
    let maxDistance = 0;
    for (let i = 0; i < cluster.length; i++) {
        for (let j = i + 1; j < cluster.length; j++) {
            const dist = haversineDistance(
                cluster[i].lat, cluster[i].lng,
                cluster[j].lat, cluster[j].lng
            );
            if (dist > maxDistance) maxDistance = dist;
        }
    }
    return maxDistance;
}

// Helper function to notify users
async function notifyUsers(cluster, taskId) {
    const uniqueUserIds = [...new Set(cluster.map(r => r.userid))];
    
    for (const userId of uniqueUserIds) {
        try {
            const user = await pool.query(`
                SELECT phone, language FROM users WHERE userid = $1
            `, [userId]);
            
            if (user.rows.length > 0 && user.rows[0].phone) {
                const message = user.rows[0].language === 'es' ? 
                    `Su reporte de basura ha sido asignado a un trabajador (ID de tarea: ${taskId}).` :
                    `Your garbage report has been assigned to a worker (Task ID: ${taskId}).`;
                
                await sendSMS(user.rows[0].phone, message);
            }
        } catch (error) {
            console.error(`Failed to notify user ${userId}:`, error);
        }
    }
}

// Fetch Assigned Tasks for Worker
router.get('/assigned-tasks', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const tasksResult = await pool.query(
            `SELECT taskid, reportids, status, starttime, route 
             FROM taskrequests 
             WHERE assignedworkerid = $1 AND status != 'completed'`,
            [workerId]
        );

        if (tasksResult.rows.length === 0) {
            return res.json({ assignedWorks: [] });
        }

        const assignedWorks = [];

        for (const task of tasksResult.rows) {
            const reportsResult = await pool.query(
                `SELECT reportid, wastetype, location 
                 FROM garbagereports 
                 WHERE reportid = ANY($1) 
                 LIMIT 1`,
                [task.reportids]
            );

            if (reportsResult.rows.length > 0) {
                const report = reportsResult.rows[0];
                const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
                const reportLat = locationMatch ? parseFloat(locationMatch[2]) : null;
                const reportLng = locationMatch ? parseFloat(locationMatch[1]) : null;

                const workerLat = 10.235865;
                const workerLng = 76.405676;

                let distance = '0km';
                if (reportLat && reportLng) {
                    distance = (haversineDistance(workerLat, workerLng, reportLat, reportLng)).toFixed(2) + 'km';
                }

                assignedWorks.push({
                    taskId: task.taskid.toString(),
                    title: report.wastetype ?? 'Unknown',
                    reportCount: task.reportids.length,
                    firstLocation: report.location,
                    distance: distance,
                    time: task.starttime ? task.starttime.toISOString() : 'Not Started',
                    status: task.status,
                });
            }
        }

        res.json({ assignedWorks });
    } catch (error) {
        console.error('Error fetching assigned tasks in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Update Task Progress
router.patch('/update-progress', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId, progress, status } = req.body;
        if (!taskId || progress === undefined || !status) {
            return res.status(400).json({ error: 'Task ID, progress, and status are required' });
        }

        const taskIdInt = parseInt(taskId, 10);
        if (isNaN(taskIdInt)) {
            return res.status(400).json({ error: 'Invalid Task ID' });
        }

        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const progressFloat = parseFloat(progress);
        if (isNaN(progressFloat) || progressFloat < 0 || progressFloat > 1) {
            return res.status(400).json({ error: 'Progress must be a number between 0 and 1' });
        }

        const validStatuses = ['pending', 'assigned', 'in-progress', 'completed', 'failed'];
        if (!validStatuses.includes(status)) {
            return res.status(400).json({ error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
        }

        const taskCheck = await pool.query(
            `SELECT 1 FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
            [taskIdInt, workerId]
        );

        if (taskCheck.rows.length === 0) {
            return res.status(403).json({ error: 'Task not assigned to this worker' });
        }

        const updateFields = ['progress = $1', 'status = $2'];
        const updateValues = [progressFloat, status];

        if (status === 'completed') {
            updateFields.push('endtime = NOW()');
        }

        await pool.query(
            `UPDATE taskrequests SET ${updateFields.join(', ')} WHERE taskid = $${updateFields.length + 1}`,
            updateValues.concat([taskIdInt])
        );

        res.json({ message: 'Task updated successfully' });
    } catch (error) {
        console.error('Error updating task progress in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Fetch Completed Tasks
router.get('/completed-tasks', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const tasksResult = await pool.query(
            `SELECT taskid, reportids, endtime 
             FROM taskrequests 
             WHERE assignedworkerid = $1 AND status = 'completed'`,
            [workerId]
        );

        const completedWorks = [];

        for (const task of tasksResult.rows) {
            const reportsResult = await pool.query(
                `SELECT array_agg(DISTINCT wastetype) as wastetypes, COUNT(reportid) as report_count
                 FROM garbagereports 
                 WHERE reportid = ANY($1)`,
                [task.reportids]
            );
            if (reportsResult.rows.length > 0) {
                const report = reportsResult.rows[0];
                completedWorks.push({
                    taskId: task.taskid.toString(),
                    title: report.wastetypes.join(', '),
                    reportCount: report.report_count,
                    endTime: task.endtime ? task.endtime.toISOString() : null,
                });
            }
        }

        res.json({ completedWorks });
    } catch (error) {
        console.error('Error fetching completed tasks in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Start task endpoint
router.post('/start-task', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId } = req.body;
        const workerId = req.user.userid;

        console.log(`Attempting to start task with taskId: ${taskId}, workerId: ${workerId}`);

        const taskCheck = await pool.query(
            `SELECT 1 FROM taskrequests 
             WHERE taskid = $1 AND assignedworkerid = $2 AND status = 'assigned'`,
            [taskId, workerId]
        );
        console.log(`Task check query result: ${JSON.stringify(taskCheck.rows)}`);

        if (taskCheck.rows.length === 0) {
            const taskState = await pool.query(
                `SELECT status FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
                [taskId, workerId]
            );
            console.log(`Task state for taskId ${taskId}: ${JSON.stringify(taskState.rows)}`);
            return res.status(403).json({
                error: 'Task not assigned to this worker or not in assigned state',
                taskState: taskState.rows.length > 0 ? taskState.rows[0].status : 'not found'
            });
        }

        await pool.query(
            `UPDATE taskrequests 
             SET status = 'in-progress', 
                 starttime = NOW()
             WHERE taskid = $1`,
            [taskId]
        );

        console.log(`Task ${taskId} started by worker ${workerId}, status updated to in-progress`);
        res.status(200).json({
            message: 'Task started successfully',
            status: 'in-progress'
        });
    } catch (error) {
        console.error('Error starting task:', error.message, error.stack);
        res.status(500).json({
            error: 'Internal Server Error',
            details: error.message
        });
    }
});

// Mark collected endpoint
router.post('/mark-collected', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId, reportId } = req.body;
        const workerId = req.user.userid;

        // Start a transaction
        await pool.query('BEGIN');

        // 1. First check if the task is assigned to this worker
        const taskCheck = await pool.query(
            `SELECT reportids, status FROM taskrequests 
             WHERE taskid = $1 AND assignedworkerid = $2
             FOR UPDATE`, // Lock the row
            [taskId, workerId]
        );

        if (taskCheck.rows.length === 0) {
            await pool.query('ROLLBACK');
            return res.status(403).json({
                error: 'Task not assigned to this worker'
            });
        }

        // 2. Check if report exists in this task
        const reportIds = taskCheck.rows[0].reportids;
        if (!reportIds.includes(reportId)) {
            await pool.query('ROLLBACK');
            return res.status(404).json({
                error: 'Report not found in this task'
            });
        }

        // 3. Update report status
        await pool.query(
            `UPDATE garbagereports 
             SET status = 'collected' 
             WHERE reportid = $1`,
            [reportId]
        );

        // 4. Check how many reports are left uncollected
        const uncollectedCount = await pool.query(
            `SELECT COUNT(*) FROM garbagereports 
             WHERE reportid = ANY($1) AND status != 'collected'`,
            [reportIds]
        );

        const remaining = parseInt(uncollectedCount.rows[0].count);

        // 5. Update task progress
        const progress = (1 - (remaining / reportIds.length))*100;
        let taskStatus = taskCheck.rows[0].status;

        // If all reports are collected, update task status
        if (remaining === 0) {
            taskStatus = 'completed';
            await pool.query(
                `UPDATE taskrequests 
                 SET status = 'completed', 
                     endtime = NOW(),
                     progress = 1.0
                 WHERE taskid = $1`,
                [taskId]
            );
        } else {
            // Just update progress if not completed
            await pool.query(
                `UPDATE garbagereports 
                 SET status = $1
                 WHERE reportid = $2`,
                ['collected', reportId]
            );
            await pool.query(
                `UPDATE taskrequests 
                 SET progress = $1
                 WHERE taskid = $2`,
                [progress, taskId]
            );
        }

        // Commit the transaction
        await pool.query('COMMIT');

        res.status(200).json({
            message: 'Report marked as collected successfully',
            remainingReports: remaining,
            taskStatus: taskStatus
        });
    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Error marking report as collected:', error);
        res.status(500).json({
            error: 'Internal Server Error',
            details: error.message
        });
    }
});

// Get task route endpoint - updated
router.get('/task-route/:taskid', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    const taskId = parseInt(req.params.taskid, 10);
    const workerId = req.user.userid;

    try {
        // Start transaction
        await pool.query('BEGIN');

        const taskResult = await pool.query(
            `SELECT taskid, reportids, assignedworkerid, status, route, starttime, endtime
             FROM taskrequests
             WHERE taskid = $1 AND assignedworkerid = $2
             FOR UPDATE`,
            [taskId, workerId]
        );

        if (taskResult.rows.length === 0) {
            await pool.query('ROLLBACK');
            return res.status(404).json({ message: 'Task not found or not assigned to this worker' });
        }

        const task = taskResult.rows[0];

        const reportsResult = await pool.query(
            `SELECT reportid, wastetype, ST_AsText(location) AS location, status
             FROM garbagereports 
             WHERE reportid = ANY($1)`,
            [task.reportids]
        );

        // Commit transaction
        await pool.query('COMMIT');

        const collectionPoints = reportsResult.rows.map(report => {
            const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
            return {
                reportid: report.reportid,
                wastetype: report.wastetype,
                lat: locationMatch ? parseFloat(locationMatch[2]) : null,
                lng: locationMatch ? parseFloat(locationMatch[1]) : null,
                status: report.status
            };
        }).filter(point => point.lat !== null && point.lng !== null);

        // Filter out collected reports
        const uncollectedPoints = collectionPoints.filter(p => p.status !== 'collected');

        res.status(200).json({
            taskid: task.taskid,
            reportids: task.reportids,
            status: task.status,
            route: task.route || { start: {}, waypoints: [], end: {} },
            locations: uncollectedPoints,
            wasteTypes: [...new Set(uncollectedPoints.map(p => p.wastetype))],
            workerLocation: { lat: 10.235865, lng: 76.405676 } // Default location
        });
    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Error fetching task route:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// New endpoint to fetch report statuses
router.get('/garbagereports/status', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const reportIds = JSON.parse(req.query.reportIds);
        if (!Array.isArray(reportIds) || reportIds.length === 0) {
            return res.status(400).json({ error: 'Invalid or empty reportIds array' });
        }

        const result = await pool.query(
            `SELECT reportid, status FROM garbagereports WHERE reportid = ANY($1)`,
            [reportIds]
        );

        res.status(200).json(result.rows);
    } catch (error) {
        console.error('Error fetching report statuses:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

module.exports=router
// router.post('/group-and-assign-reports', authenticateToken, async (req, res) => {
//     console.log('Reached /group-and-assign-reports endpoint');
//     try {
//         console.log('Starting /group-and-assign-reports execution');
//         const { startDate } = req.body;
//         const baseK = 3; // Base number of clusters, will adjust dynamically
//         console.log('Request body:', req.body);

//         console.log('Fetching unassigned reports from garbagereports...');
//         let result = await pool.query(
//             `SELECT reportid, wastetype, ST_AsText(location) AS location, datetime, userid
//              FROM garbagereports
//              WHERE reportid NOT IN (
//                SELECT unnest(reportids) FROM taskrequests
//              )
//              ORDER BY datetime ASC`
//         );

//         // Improved location parsing with validation
//         let reports = result.rows.map(row => {
//             if (!row.location) {
//                 console.warn(`Report ${row.reportid} has null location`);
//                 return null;
//             }
//             const locationMatch = row.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
//             if (!locationMatch) {
//                 console.warn(`Invalid location format for report ${row.reportid}: ${row.location}`);
//                 return null;
//             }
//             return {
//                 reportid: row.reportid,
//                 wastetype: row.wastetype,
//                 lat: parseFloat(locationMatch[2]),
//                 lng: parseFloat(locationMatch[1]),
//                 created_at: new Date(row.datetime),
//                 userid: row.userid,
//             };
//         }).filter(report => report !== null);

//         if (!reports.length) {
//             console.log('No unassigned reports found, exiting endpoint');
//             return res.status(200).json({ message: 'No unassigned reports found' });
//         }

//         console.log(`Filtered reports with valid locations: ${reports.length}`);

//         const processedReports = new Set();
//         const assignments = [];

//         while (reports.length > 0) {
//             console.log('Entering temporal filtering loop, remaining reports:', reports.length);
//             const T0 = startDate ? new Date(startDate) : reports[0].created_at;
//             const T0Plus2Days = new Date(T0);
//             T0Plus2Days.setDate(T0.getDate() + 2);

//             const timeFilteredReports = reports.filter(
//                 report => report.created_at >= T0 && report.created_at <= T0Plus2Days && !processedReports.has(report.reportid)
//             );

//             if (timeFilteredReports.length === 0) {
//                 console.log('No reports within temporal window, breaking loop');
//                 break;
//             }

//             // Dynamic k based on report density
//             const k = Math.min(baseK, Math.max(1, Math.floor(timeFilteredReports.length / 5)));
//             console.log(`Performing K-Means clustering with k=${k}...`);
            
//             // Implement proper geographical clustering
//             const clusters = geographicalKMeans(timeFilteredReports, k);
            
//             console.log('Cluster details:', clusters.map(c => ({
//                 centroid: c.centroid,
//                 pointCount: c.points.length,
//                 area: c.points.length > 1 ? calculateClusterArea(c.points) : 0
//             })));

//             console.log('Fetching available workers with recent locations...');
//             let workerResult = await pool.query(
//                 `SELECT userid, ST_AsText(location) AS location
//                  FROM users
//                  WHERE role = 'worker'
//                  AND status = 'available'`
//             );
            
//             let workers = workerResult.rows.map(row => {
//                 if (!row.location) {
//                     console.warn(`Worker ${row.userid} has null location`);
//                     return null;
//                 }
//                 const locMatch = row.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
//                 if (!locMatch) {
//                     console.warn(`Invalid location format for worker ${row.userid}: ${row.location}`);
//                     return null;
//                 }
//                 return {
//                     userid: row.userid,
//                     lat: parseFloat(locMatch[2]),
//                     lng: parseFloat(locMatch[1]),
//                 };
//             }).filter(worker => worker !== null);

//             console.log('Available workers with valid locations:', workers.length);
            
//             if (workers.length === 0) {
//                 console.log('No workers with valid locations available, breaking loop');
//                 break;
//             }

//             console.log('Assigning workers to clusters...');
//             const clusterAssignments = assignWorkersToClusters(clusters, workers);

//             if (clusterAssignments.length === 0) {
//                 console.log('No assignments made, skipping insertion');
//                 break;
//             }

//             // Rest of your assignment logic remains the same...
//             for (const { cluster, worker } of clusterAssignments) {
//                 const route = solveTSP(cluster, worker);
//                 const reportIds = cluster.map(report => report.reportid);

//                 let taskResult = await pool.query(
//                     `INSERT INTO taskrequests (reportids, assignedworkerid, status, starttime, route)
//                      VALUES ($1, $2, 'assigned', NOW(), $3)
//                      RETURNING taskid`,
//                     [reportIds, worker.userid, route]
//                 );
//                 const taskId = taskResult.rows[0].taskid;

//                 await pool.query(
//                     `UPDATE users SET status = 'busy' WHERE userid = $1`,
//                     [worker.userid]
//                 );

//                 // SMS notifications...
//                 const uniqueUserIds = [...new Set(cluster.map(report => report.userid))];
//                 for (const userId of uniqueUserIds) {
//                     try {
//                         const userResult = await pool.query(
//                             `SELECT phone FROM users WHERE userid = $1`,
//                             [userId]
//                         );
//                         if (userResult.rows.length > 0 && userResult.rows[0].phone) {
//                             const phoneNumber = userResult.rows[0].phone;
//                             const messageBody = `Your garbage report has been assigned to a worker (Task ID: ${taskId}).`;
//                             await sendSMS(phoneNumber, messageBody);
//                         }
//                     } catch (error) {
//                         console.error(`Failed to send SMS for user ${userId}:`, error.message);
//                     }
//                 }

//                 cluster.forEach(report => processedReports.add(report.reportid));
//                 assignments.push({
//                     taskId: taskId,
//                     reportIds: reportIds,
//                     assignedWorkerId: worker.userid,
//                     route: route,
//                 });
//             }

//             reports = reports.filter(r => !processedReports.has(r.reportid));
//         }

//         console.log('Endpoint completed successfully');
//         res.status(200).json({
//             message: 'Reports grouped and assigned successfully',
//             assignments: assignments,
//             workersUsed: assignments.map(a => a.assignedWorkerId)
//         });
//     } catch (error) {
//         console.error('Error in group-and-assign-reports:', error);
//         res.status(500).json({ 
//             error: 'Internal Server Error', 
//             details: error.message 
//         });
//     }
// });
