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
const DEBUG = process.env.NODE_ENV !== 'production';

function debugLog(message, data = null) {
    if (DEBUG) {
        console.log(`[DEBUG] ${message}`, data || '');
    }
}

// Enhanced K-Means clustering with debug logs
function kmeansClustering(points, k) {
    debugLog('Starting clustering', { pointsCount: points.length, requestedClusters: k });
    
    if (!points || !Array.isArray(points) ){
        debugLog('Invalid points array');
        return [];
    }

    if (points.length === 0) {
        debugLog('Empty points array');
        return [];
    }

    // Adjust k if needed
    k = Math.min(Math.max(1, k), points.length);
    debugLog('Adjusted cluster count', { finalK: k });

    if (k <= 1) {
        debugLog('Single cluster needed, returning all points together');
        return [points];
    }

    const clusters = Array.from({ length: k }, () => []);
    debugLog('Initialized empty clusters', { clusterCount: clusters.length });

    // Sort by priority
    points.sort((a, b) => {
        const severityOrder = { high: 3, medium: 2, low: 1 };
        return (severityOrder[b.severity] || 1) - (severityOrder[a.severity] || 1);
    });
    debugLog('Sorted points by priority');

    try {
        const data = points.map(p => [p.lat, p.lng]);
        
        // Initialize centroids
        const centroids = [];
        for (let i = 0; i < k; i++) {
            centroids.push(data[i % data.length]);
        }
        debugLog('Initial centroids', centroids);

        let changed = true;
        let iterations = 0;
        const maxIterations = 100;

        while (changed && iterations < maxIterations) {
            iterations++;
            changed = false;
            clusters.forEach(c => c.length = 0);

            // Assignment phase
            points.forEach((point, pointIndex) => {
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

            debugLog(`Iteration ${iterations} cluster sizes`, 
                clusters.map(c => c.length));

            // Update phase
            centroids.forEach((centroid, i) => {
                if (clusters[i].length > 0) {
                    const newLat = clusters[i].reduce((sum, p) => sum + p.lat, 0) / clusters[i].length;
                    const newLng = clusters[i].reduce((sum, p) => sum + p.lng, 0) / clusters[i].length;
                    
                    const centroidMoved = haversineDistance(
                        centroid[0], centroid[1], 
                        newLat, newLng
                    ) > 0.01;

                    if (centroidMoved) {
                        changed = true;
                        centroid[0] = newLat;
                        centroid[1] = newLng;
                    }
                }
            });
        }

        debugLog('Final clusters', {
            clusterCount: clusters.length,
            sizes: clusters.map(c => c.length),
            iterations
        });

        return clusters.filter(c => c.length > 0);
    } catch (error) {
        debugLog('Clustering failed, using fallback', error);
        return points.map(p => [p]);
    }
}

// Updated assignWorkersToClusters with debug logs
async function assignWorkersToClusters(clusters, workers) {
    debugLog('Starting worker assignment', {
        clusterCount: clusters.length,
        workerCount: workers.length
    });

    if (!clusters.length || !workers.length) {
        debugLog('No clusters or workers available');
        return [];
    }

    // Calculate centroids and cost matrix
    const costMatrix = clusters.map((cluster, clusterIdx) => {
        const centroid = {
            lat: cluster.reduce((sum, p) => sum + p.lat, 0) / cluster.length,
            lng: cluster.reduce((sum, p) => sum + p.lng, 0) / cluster.length
        };
        
        debugLog(`Cluster ${clusterIdx} centroid`, centroid);

        return workers.map(worker => {
            return haversineDistance(
                worker.lat, worker.lng,
                centroid.lat, centroid.lng
            );
        });
    });

    debugLog('Cost matrix', costMatrix);

    // Apply Hungarian algorithm
    const assignments = munkres(costMatrix);
    const results = [];
    const assignedWorkers = new Set();

    debugLog('Raw assignments from Hungarian algorithm', assignments);

    assignments.forEach(([clusterIdx, workerIdx]) => {
        if (clusterIdx < clusters.length && 
            workerIdx < workers.length && 
            !assignedWorkers.has(workerIdx)) {
            
            const assignment = {
                cluster: clusters[clusterIdx],
                worker: workers[workerIdx],
                distance: costMatrix[clusterIdx][workerIdx]
            };
            
            results.push(assignment);
            assignedWorkers.add(workerIdx);
            
            debugLog('Assignment made', {
                clusterIndex: clusterIdx,
                workerId: workers[workerIdx].userid,
                distance: assignment.distance,
                clusterSize: clusters[clusterIdx].length
            });
        }
    });

    debugLog('Final assignments', {
        assignmentCount: results.length,
        unassignedWorkers: workers.length - assignedWorkers.size
    });

    return results.sort((a, b) => a.distance - b.distance);
}

// Updated group-and-assign-reports endpoint with debug logs
router.post('/group-and-assign-reports', authenticateToken, async (req, res) => {
    try {
        const { maxDistance = 5, maxReportsPerWorker = 10 } = req.body;
        debugLog('Starting report assignment', { maxDistance, maxReportsPerWorker });

        // Fetch unassigned reports
        const reportsResult = await pool.query(`
            SELECT ... (your existing query)
        `);
        debugLog('Fetched unassigned reports', { count: reportsResult.rows.length });

        if (reportsResult.rows.length === 0) {
            debugLog('No reports to assign');
            return res.status(200).json({ message: 'No unassigned reports found' });
        }

        const reports = reportsResult.rows.map(r => ({
            ...r,
            created_at: new Date(r.datetime)
        }));
        debugLog('Processed reports', reports.slice(0, 3)); // Log first 3 as sample

        // Fetch available workers
        const workersResult =  await pool.query(`
            SELECT 
                u.userid,
                ST_X(u.location::geometry) AS lng,
                ST_Y(u.location::geometry) AS lat,
                COUNT(tr.taskid) FILTER (WHERE tr.status = 'assigned') AS current_tasks
            FROM users u
            LEFT JOIN taskrequests tr ON tr.assignedworkerid = u.userid
            WHERE u.role = 'worker'
            AND u.status = 'available'
            GROUP BY u.userid
            HAVING COUNT(tr.taskid) < $1
        `, [maxReportsPerWorker]);
        debugLog('Fetched available workers', { 
            count: workersResult.rows.length,
            workers: workersResult.rows.map(w => ({
                id: w.userid,
                capacity: maxReportsPerWorker - w.current_tasks
            }))
        });

        if (workersResult.rows.length === 0) {
            debugLog('No available workers');
            return res.status(400).json({ error: 'No available workers with capacity' });
        }

        const workers = workersResult.rows.map(w => ({
            userid: w.userid,
            lat: w.lat,
            lng: w.lng,
            capacity: maxReportsPerWorker - w.current_tasks
        }));
        debugLog('Processed workers', workers);

        // Cluster reports
        const clusterCount = Math.ceil(reports.length / maxReportsPerWorker);
        debugLog('Calculated cluster count', { clusterCount });
        
        const clusters = kmeansClustering(reports, clusterCount);
        debugLog('Generated clusters', {
            clusterCount: clusters.length,
            sizes: clusters.map(c => c.length)
        });

        // Filter valid clusters
        const validClusters = clusters.filter(c => 
            c.length <= maxReportsPerWorker && 
            calculateClusterDiameter(c) <= maxDistance
        );
        debugLog('Valid clusters after filtering', {
            validCount: validClusters.length,
            invalidCount: clusters.length - validClusters.length,
            sizes: validClusters.map(c => c.length)
        });

        // Assign workers
        const assignments = await assignWorkersToClusters(validClusters, workers);
        debugLog('Final assignments before task creation', assignments);

        // Create tasks
        const results = [];
        for (const { cluster, worker } of assignments) {
            debugLog('Creating task for worker', {
                workerId: worker.userid,
                clusterSize: cluster.length
            });

            const route = solveTSP(cluster, worker);
            debugLog('Generated route', {
                waypoints: route.waypoints.length,
                totalDistance: route.totalDistance
            });

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
                await pool.query(`UPDATE users SET status = 'busy' WHERE userid = $1`, [worker.userid]);
                debugLog('Worker marked as busy', { workerId: worker.userid });
            }

            await notifyUsers(cluster, taskResult.rows[0].taskid);
            results.push({
                taskId: taskResult.rows[0].taskid,
                workerId: worker.userid,
                reportCount: cluster.length,
                estimatedDistance: route.totalDistance
            });
        }

        debugLog('Assignment process completed', {
            tasksCreated: results.length,
            unassignedReports: reports.length - results.reduce((sum, r) => sum + r.reportCount, 0)
        });

        res.status(200).json({
            success: true,
            tasksCreated: results.length,
            assignments: results,
            unassignedReports: reports.length - results.reduce((sum, r) => sum + r.reportCount, 0)
        });
    } catch (error) {
        debugLog('Assignment process failed', error);
        res.status(500).json({ 
            error: 'Internal server error',
            details: error.message 
        });
    }
});

// Enhanced notifyUsers with debug logs
async function notifyUsers(cluster, taskId) {
    debugLog('Starting user notifications', {
        clusterSize: cluster.length,
        taskId
    });

    const uniqueUserIds = [...new Set(cluster.map(r => r.userid))];
    debugLog('Unique users to notify', { count: uniqueUserIds.length });

    for (const userId of uniqueUserIds) {
        try {
            const user = await pool.query(`SELECT phone FROM users WHERE userid = $1`, [userId]);
            
            if (user.rows[0]?.phone) {
                const reports = cluster.filter(r => r.userid === userId);
                const message = `Your reports (${reports.map(r => r.wastetype).join(', ')}) have been assigned. ID: ${taskId}`;
                
                debugLog('Sending notification', {
                    userId,
                    phone: user.rows[0].phone,
                    message
                });

                await twilioClient.messages.create({
                    body: message,
                    from: process.env.TWILIO_PHONE_NUMBER,
                    to: user.rows[0].phone
                });
            } else {
                debugLog('User has no phone number', { userId });
            }
        } catch (error) {
            debugLog('Notification failed', { userId, error: error.message });
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
