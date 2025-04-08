require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');
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

// Database connection check
pool.connect((err, client, release) => {
    if (err) {
        console.error('Database connection error:', err.stack);
        process.exit(1);
    } else {
        console.log('Worker service connected to database');
        release();
    }
});

// Authentication middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader?.split(' ')[1];
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

// Middleware to check if user is a worker or admin
const checkWorkerOrAdminRole = (req, res, next) => {
    const { role } = req.user; // Assuming req.user is set by authenticateToken middleware
    if (role === 'worker' || role === 'admin') {
        return next();
    }
    return res.status(403).json({ error: 'Access denied: Worker or Admin role required' });
};

// Haversine distance function
function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth radius in km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

// Enhanced and fixed K-Means clustering
function kmeansClustering(points, k) {
    if (!points || !Array.isArray(points) || points.length === 0) {
        console.error('Invalid or empty points array');
        return [];
    }

    k = Math.min(Math.max(1, k), points.length);
    if (k <= 1) return [points];

    const clusters = Array.from({ length: k }, () => []);
    points.sort((a, b) => {
        const severityOrder = { high: 3, medium: 2, low: 1 };
        return (severityOrder[b.severity] || 1) - (severityOrder[a.severity] || 1);
    });

    try {
        const data = points.map(p => [p.lat, p.lng]);
        const centroids = [];
        for (let i = 0; i < k; i++) {
            centroids.push(data[i % data.length]);
        }

        let changed = true;
        let iterations = 0;
        const maxIterations = 100;

        while (changed && iterations < maxIterations) {
            iterations++;
            changed = false;
            clusters.forEach(cluster => cluster.length = 0);

            points.forEach(point => {
                const pointCoords = [point.lat, point.lng];
                let minDistance = Infinity;
                let closestIdx = 0;

                centroids.forEach((centroid, i) => {
                    const dist = haversineDistance(
                        pointCoords[0], pointCoords[1],
                        centroid[0], centroid[1]
                    );
                    if (dist < minDistance) {
                        minDistance = dist;
                        closestIdx = i;
                    }
                });

                clusters[closestIdx].push(point);
            });

            centroids.forEach((centroid, i) => {
                if (clusters[i].length > 0) {
                    const newLat = clusters[i].reduce((sum, p) => sum + p.lat, 0) / clusters[i].length;
                    const newLng = clusters[i].reduce((sum, p) => sum + p.lng, 0) / clusters[i].length;
                    if (haversineDistance(centroid[0], centroid[1], newLat, newLng) > 0.01) {
                        changed = true;
                    }
                    centroid[0] = newLat;
                    centroid[1] = newLng;
                }
            });
        }

        // Print clustering results
        console.log('=== Clustering Results ===');
        console.log(`Number of clusters: ${clusters.length}`);
        clusters.forEach((cluster, index) => {
            console.log(`Cluster ${index + 1}: ${cluster.length} points`);
            console.log('Points:', cluster.map(p => ({
                reportid: p.reportid,
                lat: p.lat,
                lng: p.lng,
                severity: p.severity
            })));
        });

        return clusters.filter(c => c.length > 0);
    } catch (error) {
        console.error('Clustering error:', error);
        return points.map(p => [p]);
    }
}


// Worker assignment with skill matching
async function assignWorkersToClusters(clusters, workers) {
    if (!clusters.length || !workers.length) return [];

    const costMatrix = clusters.map(cluster => {
        const centroid = {
            lat: cluster.reduce((sum, p) => sum + p.lat, 0) / cluster.length,
            lng: cluster.reduce((sum, p) => sum + p.lng, 0) / cluster.length
        };

        return workers.map(worker => {
            return haversineDistance(worker.lat, worker.lng, centroid.lat, centroid.lng);
        });
    });

    // Apply Hungarian algorithm
    const assignments = munkres(costMatrix);
    const results = [];
    const assignedWorkers = new Set();

    assignments.forEach(([clusterIdx, workerIdx]) => {
        if (clusterIdx < clusters.length && workerIdx < workers.length && !assignedWorkers.has(workerIdx)) {
            results.push({
                cluster: clusters[clusterIdx],
                worker: workers[workerIdx],
                distance: costMatrix[clusterIdx][workerIdx]
            });
            assignedWorkers.add(workerIdx);
        }
    });

    return results.sort((a, b) => a.distance - b.distance);
}

// Enhanced TSP solver with priority stops
function solveTSP(points, worker) {
    if (!points.length) {
        return {
            start: { lat: worker.lat, lng: worker.lng },
            waypoints: [],
            end: { lat: worker.lat, lng: worker.lng },
            totalDistance: 0
        };
    }

    // Sort hazardous waste first
    const sortedPoints = [...points].sort((a, b) => {
        if (a.wastetype === 'hazardous' && b.wastetype !== 'hazardous') return -1;
        if (b.wastetype === 'hazardous' && a.wastetype !== 'hazardous') return 1;
        return 0;
    });

    const allPoints = [{ lat: worker.lat, lng: worker.lng }, ...sortedPoints];
    const n = allPoints.length;
    const distMatrix = Array(n).fill().map(() => Array(n).fill(0));

    // Build distance matrix
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

    // Nearest neighbor algorithm
    const visited = new Set([0]);
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

    return {
        start: { lat: allPoints[0].lat, lng: allPoints[0].lng },
        waypoints: route.slice(1, -1).map(idx => ({
            reportid: idx > 0 ? points[idx-1].reportid : null,
            lat: allPoints[idx].lat,
            lng: allPoints[idx].lng,
            wastetype: idx > 0 ? points[idx-1].wastetype : null
        })),
        end: { lat: allPoints[0].lat, lng: allPoints[0].lng },
        totalDistance
    };
}

// Update worker location
router.post('/update-worker-location', authenticateToken, async (req, res) => {
    try {
        const { userId, lat, lng } = req.body;

        // Ensure the user is a worker
        const userCheck = await pool.query(
            `SELECT role FROM users WHERE userid = $1`,
            [userId]
        );

        if (userCheck.rows.length === 0 || userCheck.rows[0].role !== 'worker') {
            return res.status(403).json({ error: 'Only workers can update their location' });
        }

        const result = await pool.query(`
            UPDATE users 
            SET location = ST_SetSRID(ST_MakePoint($1, $2), 4326),
                status = 'available'
            WHERE userid = $3 AND role = 'worker'
            RETURNING userid, ST_AsText(location) AS location
        `, [lng, lat, userId]);

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Worker not found' });
        }

        console.log(`Location updated for worker ${userId}: ${result.rows[0].location}`);
        res.status(200).json({ 
            message: 'Location updated successfully',
            location: result.rows[0].location 
        });
    } catch (error) {
        console.error('Location update error:', error);
        res.status(500).json({ error: 'Failed to update location' });
    }
});

router.get('/available-workers-locations', authenticateToken, async (req, res) => {
    try {
        // Optional: Restrict to admin role
        if (req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Admin access required' });
        }

        const result = await pool.query(`
            SELECT 
                userid,
                ST_X(location::geometry) AS lng,
                ST_Y(location::geometry) AS lat
            FROM users
            WHERE role = 'worker' AND status = 'available'
        `);

        const workers = result.rows.map(row => ({
            userId: row.userid,
            lat: row.lat,
            lng: row.lng,
            lastUpdated: row.last_updated
        }));

        res.status(200).json({ workers });
    } catch (error) {
        console.error('Error fetching available workers locations:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Group and assign reports endpoint
router.post('/group-and-assign-reports', authenticateToken, async (req, res) => {
    try {
        const { maxDistance = 10, maxReportsPerWorker = 3, urgencyWindow = '24 hours' } = req.body;

        const reportsResult = await pool.query(`
            SELECT 
                r.reportid, 
                r.wastetype,
                ST_X(r.location::geometry) AS lng,
                ST_Y(r.location::geometry) AS lat,
                r.datetime,
                r.userid,
                CASE
                    WHEN r.wastetype = 'public' THEN 'high'
                    WHEN r.wastetype = 'home' THEN 'low'
                    ELSE 'low'
                END as severity,
                CASE
                    WHEN NOW() - r.datetime > INTERVAL '${urgencyWindow}' THEN true
                    ELSE false
                END as is_urgent
            FROM garbagereports r
            WHERE r.status = 'not-collected'
            AND r.wastetype IN ('public', 'home')
            ORDER BY 
                is_urgent DESC,
                severity DESC,
                datetime ASC
        `);

        console.log('=== Debug: Reports Retrieved ===');
        console.log(`Number of reports found: ${reportsResult.rows.length}`);
        console.log('Reports:', reportsResult.rows);

        if (reportsResult.rows.length === 0) {
            return res.status(200).json({ message: 'No unassigned reports found' });
        }

        const reports = reportsResult.rows.map(r => ({
            ...r,
            created_at: new Date(r.datetime)
        }));

        const workersResult = await pool.query(`
            SELECT 
                u.userid,
                u.status,
                ST_X(u.location::geometry) AS lng,
                ST_Y(u.location::geometry) AS lat,
                COUNT(tr.taskid) FILTER (WHERE tr.status = 'assigned') AS current_tasks
            FROM users u
            LEFT JOIN taskrequests tr ON tr.assignedworkerid = u.userid
            WHERE u.role = 'worker'
            GROUP BY u.userid, u.status
            HAVING COUNT(tr.taskid) < $1
        `, [maxReportsPerWorker]);

        console.log('=== Debug: Workers Queried ===');
        console.log(`Number of workers queried: ${workersResult.rows.length}`);
        console.log('Workers:', workersResult.rows);

        if (workersResult.rows.length === 0) {
            return res.status(400).json({ error: 'No available workers with capacity' });
        }

        const workers = workersResult.rows
            .filter(w => w.status === 'available')
            .map(w => ({
                userid: w.userid,
                lat: w.lat,
                lng: w.lng,
                capacity: maxReportsPerWorker - w.current_tasks
            }));

        console.log('=== Available Workers ===');
        console.log(`Total workers found: ${workers.length}`);
        workers.forEach(worker => {
            console.log(`Worker ${worker.userid}: Capacity=${worker.capacity}, Location=(${worker.lat}, ${worker.lng})`);
        });

        const clusterCount = Math.ceil(reports.length / maxReportsPerWorker);
        console.log('=== Debug: Clustering Setup ===');
        console.log(`Cluster count calculated: ${clusterCount}`);

        const clusters = kmeansClustering(reports, clusterCount);

        const validClusters = clusters.filter(c => 
            c.length <= maxReportsPerWorker && 
            calculateClusterDiameter(c) <= maxDistance
        );

        console.log('=== Debug: Valid Clusters ===');
        console.log(`Number of valid clusters: ${validClusters.length}`);
        validClusters.forEach((cluster, index) => {
            console.log(`Valid Cluster ${index + 1}: ${cluster.length} points`);
        });

        const assignments = await assignWorkersToClusters(validClusters, workers);

        console.log('=== Worker Assignments ===');
        console.log(`Total assignments made: ${assignments.length}`);
        assignments.forEach((assignment, index) => {
            console.log(`Assignment ${index + 1}:`);
            console.log(`Worker: ${assignment.worker.userid}`);
            console.log(`Distance to cluster: ${assignment.distance.toFixed(2)} km`);
            console.log(`Cluster size: ${assignment.cluster.length} reports`);
            console.log('Reports:', assignment.cluster.map(r => ({
                reportid: r.reportid,
                wastetype: r.wastetype,
                severity: r.severity
            })));
        });

        const results = [];
        for (const { cluster, worker } of assignments) {
            const route = solveTSP(cluster, worker);

            const taskResult = await pool.query(`
                INSERT INTO taskrequests (
                    reportids,
                    assignedworkerid,
                    status,
                    starttime,
                    route,
                    estimated_distance,
                    progress
                ) VALUES (
                    $1, $2, 'assigned', NOW(), $3, $4, 0
                ) RETURNING taskid
            `, [
                cluster.map(r => r.reportid),
                worker.userid,
                route,
                route.totalDistance
            ]);

            if (cluster.length >= worker.capacity) {
                await pool.query(`
                    UPDATE users
                    SET status = 'busy'
                    WHERE userid = $1
                `, [worker.userid]);
            }

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
            tasksCreated: results.length,
            assignments: results,
            unassignedReports: reports.length - results.reduce((sum, r) => sum + r.reportCount, 0)
        });
    } catch (error) {
        console.error('Assignment error:', error);
        res.status(500).json({ error: 'Internal server error', details: error.message });
    }
});

// Helper functions
function calculateClusterDiameter(cluster) {
    let maxDistance = 0;
    for (let i = 0; i < cluster.length; i++) {
        for (let j = i + 1; j < cluster.length; j++) {
            const dist = haversineDistance(
                cluster[i].lat, cluster[i].lng,
                cluster[j].lat, cluster[j].lng
            );
            maxDistance = Math.max(maxDistance, dist);
        }
    }
    return maxDistance;
}

async function notifyUsers(cluster, taskId) {
    const uniqueUserIds = [...new Set(cluster.map(r => r.userid))];
    
    for (const userId of uniqueUserIds) {
        try {
            const user = await pool.query(`
                SELECT phone FROM users WHERE userid = $1
            `, [userId]);
            
            if (user.rows[0]?.phone) {
                const reports = cluster.filter(r => r.userid === userId);
                const message = `Your reports (${reports.map(r => r.wastetype).join(', ')}) have been assigned. ID: ${taskId}`;
                
                await twilioClient.messages.create({
                    body: message,
                    from: process.env.TWILIO_PHONE_NUMBER,
                    to: user.rows[0].phone
                });
            }
        } catch (error) {
            console.error(`Notification failed for user ${userId}:`, error);
        }
    }
}

// Task progress update endpoint
router.post('/update-task-progress', authenticateToken, async (req, res) => {
    try {
        const { taskId, progress, completedReportIds } = req.body;
        
        await pool.query('BEGIN');
        
        // Update task progress
        await pool.query(`
            UPDATE taskrequests
            SET progress = $1
            WHERE taskid = $2
        `, [progress, taskId]);
        
        // Mark reports as completed
        if (completedReportIds?.length) {
            await pool.query(`
                UPDATE garbagereports
                SET status = 'completed'
                WHERE reportid = ANY($1)
            `, [completedReportIds]);
        }
        
        // Check if task is fully completed
        if (progress >= 100) {
            await pool.query(`
                UPDATE taskrequests
                SET status = 'completed',
                    endtime = NOW()
                WHERE taskid = $1
            `, [taskId]);
            
            // Free up the worker
            await pool.query(`
                UPDATE users
                SET status = 'available'
                WHERE userid = (
                    SELECT assignedworkerid FROM taskrequests WHERE taskid = $1
                )
            `, [taskId]);
        }
        
        await pool.query('COMMIT');
        res.status(200).json({ message: 'Progress updated successfully' });
    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Progress update error:', error);
        res.status(500).json({ error: 'Failed to update progress' });
    }
});

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