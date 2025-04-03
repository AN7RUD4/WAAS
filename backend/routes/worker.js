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
const twilioClient = new twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
);

const pool = new Pool({
    connectionString: process.env.DATABASE_URL
    ,
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

    if (!token) {
        console.log('No token provided');
        return res.status(401).json({ message: 'Authentication token required' });
    }

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET || 'passwordKey');
        console.log('Decoded token:', decoded);
        if (!decoded.userid || !decoded.role) {
            console.log('Invalid token: missing userid or role');
            return res.status(403).json({ message: 'Invalid token: Missing userid or role' });
        }
        req.user = decoded;
        next();
    } catch (err) {
        console.error('Token verification error:', err.message);
        return res.status(403).json({ message: 'Invalid or expired token' });
    }
};

// Role check middleware
const checkWorkerOrAdminRole = (req, res, next) => {
    console.log('Checking role for user:', req.user);
    if (!req.user || (req.user.role.toLowerCase() !== 'worker' && req.user.role.toLowerCase() !== 'admin')) {
        console.log('Access denied: role not worker or admin');
        return res.status(403).json({ message: 'Access denied: Only workers or admins can access this endpoint' });
    }
    next();
};

// Haversine distance function
function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

// Distance calculation for clustering
function calculateDistance(point1, point2) {
    const latDiff = point1[0] - point2[0];
    const lngDiff = point1[1] - point2[1];
    return Math.sqrt(latDiff * latDiff + lngDiff * lngDiff);
}

// Ensure unique centroids
function uniqueCentroids(centroids) {
    const unique = [];
    const seen = new Set();

    centroids.forEach((centroid) => {
        const key = centroid.join(",");
        if (!seen.has(key)) {
            seen.add(key);
            unique.push(centroid);
        }
    });

    return unique;
}

// K-Means clustering function
function kmeansClustering(points, k) {
    if (!Array.isArray(points) || points.length === 0) {
        console.log('kmeansClustering: Invalid or empty points array, returning empty clusters');
        return [];
    }
    if (points.length < k) {
        console.log(`kmeansClustering: Fewer points (${points.length}) than clusters (${k}), returning single-point clusters`);
        return points.map(point => [point]);
    }

    console.log('kmeansClustering: Starting with points:', points);
    const kmeans = new KMeans();
    const data = points.map(p => [p.lat, p.lng]);
    console.log('kmeansClustering: Data for clustering:', data);

    try {
        let centroids;
        let attempts = 0;
        const maxAttempts = 5; // Retry up to 5 times to get k unique centroids

        // Keep trying until we get k unique centroids or reach max attempts
        do {
            centroids = kmeans.cluster(data, k, "kmeans++");
            centroids = uniqueCentroids(centroids);
            attempts++;
            console.log(`kmeansClustering: Attempt ${attempts}, Centroids:`, centroids);
        } while (centroids.length < k && attempts < maxAttempts);

        k = Math.min(k, centroids.length); // Adjust k to the number of unique centroids
        console.log('kmeansClustering: Final centroids after unique filtering:', centroids);

        if (!Array.isArray(centroids) || centroids.length === 0) {
            console.log('kmeansClustering: No valid centroids, returning single-point clusters');
            return points.map(point => [point]);
        }

        const clusters = Array.from({ length: k }, () => []);
        points.forEach((point) => {
            const pointCoords = [point.lat, point.lng];
            let closestCentroidIdx = 0;
            let minDistance = calculateDistance(pointCoords, centroids[0]);

            for (let i = 1; i < centroids.length; i++) {
                const distance = calculateDistance(pointCoords, centroids[i]);
                if (distance < minDistance) {
                    minDistance = distance;
                    closestCentroidIdx = i;
                }
            }

            if (closestCentroidIdx >= clusters.length) {
                console.error(`⚠️ Invalid centroid index ${closestCentroidIdx} for point ${point.reportid}`);
                return;
            }

            clusters[closestCentroidIdx].push(point);
        });

        const validClusters = clusters.filter(cluster => cluster.length > 0);
        console.log('kmeansClustering: Resulting clusters:', validClusters);
        return validClusters;
    } catch (error) {
        console.error('kmeansClustering: Clustering failed:', error.message);
        return points.map(point => [point]);
    }
}

// Updated assignWorkersToClusters function (using munkres)
function assignWorkersToClusters(clusters, workers) {
    if (!clusters.length || !workers.length) {
        console.log('assignWorkersToClusters: No clusters or workers, returning empty assignments');
        return [];
    }

    console.log('assignWorkersToClusters: Clusters:', clusters);
    console.log('assignWorkersToClusters: Workers:', workers);

    // Step 1: Construct the cost matrix (distance between each cluster centroid and each worker)
    const costMatrix = clusters.map(cluster => {
        const centroid = {
            lat: cluster.reduce((sum, r) => sum + r.lat, 0) / cluster.length,
            lng: cluster.reduce((sum, r) => sum + r.lng, 0) / cluster.length,
        };
        return workers.map(worker => {
            const distance = haversineDistance(worker.lat, worker.lng, centroid.lat, centroid.lng);
            // Add small random noise to avoid numerical precision issues
            return distance + Math.random() * 0.0001;
        });
    });
    console.log('assignWorkersToClusters: Cost matrix:', costMatrix);

    // Step 2: Pad the cost matrix to make it square (required by the Hungarian algorithm)
    const maxDim = Math.max(clusters.length, workers.length);
    const paddedMatrix = costMatrix.map(row => [...row]);
    paddedMatrix.forEach(row => {
        while (row.length < maxDim) row.push(Number.MAX_SAFE_INTEGER); // Use Number.MAX_SAFE_INTEGER instead of Infinity
    });
    while (paddedMatrix.length < maxDim) {
        paddedMatrix.push(Array(maxDim).fill(Number.MAX_SAFE_INTEGER));
    }
    console.log('assignWorkersToClusters: Padded cost matrix:', paddedMatrix);

    try {
        // Step 3: Run the Hungarian algorithm using munkres
        const indices = munkres(paddedMatrix);
        console.log('assignWorkersToClusters: Munkres indices:', indices);

        // Step 4: Process the assignments
        const assignments = [];
        const usedWorkers = new Set();

        indices.forEach(([clusterIdx, workerIdx]) => {
            if (clusterIdx < clusters.length && workerIdx < workers.length && !usedWorkers.has(workerIdx)) {
                assignments.push({
                    cluster: clusters[clusterIdx],
                    worker: workers[workerIdx],
                });
                usedWorkers.add(workerIdx);
            }
        });

        console.log('assignWorkersToClusters: Assignments:', assignments);
        return assignments;
    } catch (error) {
        console.error('assignWorkersToClusters: Munkres failed:', error.message);
        // Fallback: Greedy assignment
        const assignments = [];
        const availableWorkers = [...workers];
        for (const cluster of clusters) {
            if (availableWorkers.length === 0) break;
            const centroid = {
                lat: cluster.reduce((sum, r) => sum + r.lat, 0) / cluster.length,
                lng: cluster.reduce((sum, r) => sum + r.lng, 0) / cluster.length,
            };
            const bestWorkerIdx = availableWorkers.reduce((best, w, idx) => {
                const dist = haversineDistance(w.lat, w.lng, centroid.lat, centroid.lng);
                return dist < best.dist ? { idx, dist } : best;
            }, { idx: 0, dist: Infinity }).idx;
            assignments.push({
                cluster,
                worker: availableWorkers[bestWorkerIdx],
            });
            availableWorkers.splice(bestWorkerIdx, 1);
        }
        console.log('assignWorkersToClusters: Fallback assignments:', assignments);
        return assignments;
    }
}

// Solve TSP for route optimization
function solveTSP(points, worker) {
    if (points.length === 0) return [];

    const route = [{ lat: worker.lat, lng: worker.lng }];
    const unvisited = [...points];
    let current = { lat: worker.lat, lng: worker.lng };

    while (unvisited.length > 0) {
        const nearest = unvisited.reduce((closest, point) => {
            const distance = haversineDistance(current.lat, current.lng, point.lat, point.lng);
            return (!closest || distance < closest.distance) ? { point, distance } : closest;
        }, null);

        route.push({ lat: nearest.point.lat, lng: nearest.point.lng });
        current = { lat: nearest.point.lat, lng: nearest.point.lng };
        unvisited.splice(unvisited.indexOf(nearest.point), 1);
    }

    return route;
}

// Send SMS notification function
async function sendSMS(phoneNumber, messageBody) {
    try {
        await twilioClient.messages.create({
            body: messageBody,
            from: process.env.TWILIO_PHONE_NUMBER,
            to: phoneNumber,
        });
        console.log(`SMS sent to ${phoneNumber}: ${messageBody}`);
    } catch (smsError) {
        console.error('Error sending SMS:', smsError.message, smsError.stack);
        throw new Error('Failed to send SMS notification');
    }
}

// Group and assign reports endpoint with SMS notification
router.post('/group-and-assign-reports', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    console.log('Reached /group-and-assign-reports endpoint');
    try {
        console.log('Starting /group-and-assign-reports execution');
        const { startDate } = req.body;
        const k = 3;
        console.log('Request body:', req.body);

        console.log('Fetching unassigned reports from garbagereports...');
        let result;
        try {
            result = await pool.query(
                `SELECT reportid, wastetype, ST_AsText(location) AS location, datetime, userid
                 FROM garbagereports
                 WHERE reportid NOT IN (
                   SELECT unnest(reportids) FROM taskrequests
                 )
                 ORDER BY datetime ASC`
            );
        } catch (dbError) {
            console.error('Database query error:', dbError.message, dbError.stack);
            throw dbError;
        }
        console.log('Fetched reports:', result.rows);

        let reports = result.rows.map(row => {
            const locationMatch = row.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
            return {
                reportid: row.reportid,
                wastetype: row.wastetype,
                lat: locationMatch ? parseFloat(locationMatch[2]) : null,
                lng: locationMatch ? parseFloat(locationMatch[1]) : null,
                created_at: new Date(row.datetime),
                userid: row.userid,
            };
        });

        if (!reports.length) {
            console.log('No unassigned reports found, exiting endpoint');
            return res.status(200).json({ message: 'No unassigned reports found' });
        }
        console.log('Reports with user IDs:', reports);

        reports = reports.filter(r => r.lat !== null && r.lng !== null);
        console.log('Filtered reports with valid locations:', reports);

        const processedReports = new Set();
        const assignments = [];

        while (reports.length > 0) {
            console.log('Entering temporal filtering loop, remaining reports:', reports.length);
            const T0 = startDate ? new Date(startDate) : reports[0].created_at;
            const T0Plus2Days = new Date(T0);
            T0Plus2Days.setDate(T0.getDate() + 2);
            console.log('Temporal window - T0:', T0, 'T0Plus2Days:', T0Plus2Days);

            const timeFilteredReports = reports.filter(
                report =>
                    report.created_at >= T0 &&
                    report.created_at <= T0Plus2Days &&
                    !processedReports.has(report.reportid)
            );
            console.log('Time-filtered reports:', timeFilteredReports);

            if (timeFilteredReports.length === 0) {
                console.log('No reports within temporal window, breaking loop');
                break;
            }

            console.log('Performing K-Means clustering...');
            const clusters = kmeansClustering(timeFilteredReports, Math.min(k, timeFilteredReports.length));
            console.log('Clusters formed:', clusters);

            console.log('Fetching available workers...');
            let workerResult;
            try {
                workerResult = await pool.query(
                    `SELECT userid, ST_AsText(location) AS location
                     FROM users
                     WHERE role = 'worker'
                     AND userid NOT IN (
                       SELECT assignedworkerid
                       FROM taskrequests
                       WHERE status != 'completed'
                       GROUP BY assignedworkerid
                       HAVING COUNT(*) >= 5
                     )`
                );
            } catch (dbError) {
                console.error('Worker query error:', dbError.message, dbError.stack);
                throw dbError;
            }
            let workers = workerResult.rows.map(row => {
                const locMatch = row.location ? row.location.match(/POINT\(([^ ]+) ([^)]+)\)/) : null;
                return {
                    userid: row.userid,
                    lat: locMatch ? parseFloat(locMatch[2]) : 10.235865,
                    lng: locMatch ? parseFloat(locMatch[1]) : 76.405676,
                };
            });
            console.log('Available workers:', workers);

            if (workers.length === 0) {
                console.log('No workers available, breaking loop');
                break;
            }

            console.log('Assigning workers to clusters...');
            const clusterAssignments = assignWorkersToClusters(clusters, workers);
            console.log('Cluster assignments:', clusterAssignments);

            if (clusterAssignments.length === 0) {
                console.log('No assignments made, skipping insertion');
                break;
            }

            for (const { cluster, worker } of clusterAssignments) {
                console.log(`Processing cluster for worker ${worker.userid}, reports:`, cluster);
                const route = solveTSP(cluster, worker);
                console.log('TSP Route:', route);

                const routeJson = {
                    start: { lat: route[0].lat, lng: route[0].lng },
                    waypoints: route.slice(1, -1).map(point => ({ lat: point.lat, lng: point.lng })),
                    end: { lat: route[route.length - 1].lat, lng: route[route.length - 1].lng },
                };
                console.log('Formatted routeJson:', routeJson);

                const reportIds = cluster.map(report => report.reportid);
                console.log('Report IDs for task:', reportIds);

                console.log('Inserting task into taskrequests...');
                let taskResult;
                try {
                    taskResult = await pool.query(
                        `INSERT INTO taskrequests (reportids, assignedworkerid, status, starttime, route)
                         VALUES ($1, $2, 'assigned', NOW(), $3)
                         RETURNING taskid`,
                        [reportIds, worker.userid, routeJson]
                    );
                } catch (dbError) {
                    console.error('Task insertion error:', dbError.message, dbError.stack);
                    throw dbError;
                }
                const taskId = taskResult.rows[0].taskid;
                console.log(`Task inserted successfully with taskId: ${taskId}`);

                // Send SMS to users whose reports are in this cluster
                const uniqueUserIds = [...new Set(cluster.map(report => report.userid))];
                for (const userId of uniqueUserIds) {
                    try {
                        const userResult = await pool.query(
                            `SELECT phone 
                             FROM users 
                             WHERE userid = $1`,
                            [userId]
                        );
                        if (userResult.rows.length > 0 && userResult.rows[0].phone) {
                            const phoneNumber = userResult.rows[0].phone;
                            const messageBody = `Your garbage report has been assigned to a worker (Task ID: ${taskId}).`;
                            await sendSMS(phoneNumber, messageBody);
                        } else {
                            console.warn(`No phone number found for user ${userId}`);
                        }
                    } catch (error) {
                        console.error(`Failed to send SMS for user ${userId}:`, error.message);
                    }
                }

                cluster.forEach(report => processedReports.add(report.reportid));
                assignments.push({
                    taskId: taskId,
                    reportIds: reportIds,
                    assignedWorkerId: worker.userid,
                    route: routeJson,
                });
            }

            reports = reports.filter(r => !processedReports.has(r.reportid));
        }

        console.log('Endpoint completed successfully, assignments:', assignments);
        res.status(200).json({
            message: 'Reports grouped and assigned successfully, SMS notifications sent where possible',
            assignments,
        });
    } catch (error) {
        console.error('Error in group-and-assign-reports:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Fetch Assigned Tasks for Worker
router.get('/assigned-tasks', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        // First get all tasks assigned to this worker
        const tasksResult = await pool.query(
            `SELECT taskid, reportids, status, starttime, route 
       FROM taskrequests 
       WHERE assignedworkerid = $1 AND status != 'completed'`,
            [workerId]
        );

        if (tasksResult.rows.length === 0) {
            return res.json({ assignedWorks: [] });
        }

        // For each task, get the reports information
        const assignedWorks = [];

        for (const task of tasksResult.rows) {
            // Get the first report for the title (you can change this logic if needed)
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

                // Worker location (replace with actual worker location if available)
                const workerLat = 10.235865;
                const workerLng = 76.405676;

                // Calculate distance to first report
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

//map
router.get('/task-route/:taskid', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    const taskId = parseInt(req.params.taskid, 10);
    const workerId = req.user.userid;
    const workerLat = parseFloat(req.query.workerLat) || 10.235865;
    const workerLng = parseFloat(req.query.workerLng) || 76.405676;

    try {
        // Fetch the task details, ensuring it belongs to the worker
        const taskResult = await pool.query(
            `SELECT taskid, reportids, assignedworkerid, status, route, starttime, endtime
             FROM taskrequests
             WHERE taskid = $1 AND assignedworkerid = $2`,
            [taskId, workerId]
        );

        if (taskResult.rows.length === 0) {
            return res.status(404).json({ message: 'Task not found or not assigned to this worker' });
        }

        const task = taskResult.rows[0];

        // Fetch all reports in this task for additional context (optional)
        const reportsResult = await pool.query(
            `SELECT reportid, wastetype, ST_AsText(location) AS location 
             FROM garbagereports 
             WHERE reportid = ANY($1)`,
            [task.reportids]
        );

        // Parse collection points from reports
        const collectionPoints = reportsResult.rows.map(report => {
            const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
            return {
                reportid: report.reportid,
                wastetype: report.wastetype,
                lat: locationMatch ? parseFloat(locationMatch[2]) : null,
                lng: locationMatch ? parseFloat(locationMatch[1]) : null,
            };
        }).filter(point => point.lat !== null && point.lng !== null);

        // Use the route from the taskrequests table
        const routeData = task.route || { start: {}, waypoints: [], end: {} };

        res.status(200).json({
            taskid: task.taskid,
            reportids: task.reportids,
            status: task.status,
            route: routeData, // Return the full route object from JSONB
            locations: collectionPoints, // Include report locations for reference
            wasteTypes: [...new Set(collectionPoints.map(p => p.wastetype))],
            workerLocation: { lat: workerLat, lng: workerLng } // Include worker's location
        });
    } catch (error) {
        console.error('Error fetching task route:', error.message, error.stack);
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
            `SELECT 1 
       FROM taskrequests 
       WHERE taskid = $1 AND assignedworkerid = $2`,
            [taskIdInt, workerId]
        );

        if (taskCheck.rows.length === 0) {
            return res.status(403).json({ error: 'Task not assigned to this worker' });
        }

        // Update task status and progress
        const updateFields = ['progress = $1', 'status = $2'];
        const updateValues = [progressFloat, status];

        // If task is completed, set endtime
        if (status === 'completed') {
            updateFields.push('endtime = NOW()');
        }

        await pool.query(
            `UPDATE taskrequests SET ${updateFields.join(', ')} WHERE taskid = $3`,
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

        // Get all completed tasks
        const tasksResult = await pool.query(
            `SELECT taskid, reportids, endtime 
       FROM taskrequests 
       WHERE assignedworkerid = $1 AND status = 'completed'`,
            [workerId]
        );

        const completedWorks = [];

        for (const task of tasksResult.rows) {
            // Get summaries of waste types and locations for this task
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

// Mark report as collected
// Start task endpoint
router.post('/start-task', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId } = req.body;
        const workerId = req.user.userid;

        // Verify the task is assigned to this worker
        const taskCheck = await pool.query(
            `SELECT 1 FROM taskrequests 
             WHERE taskid = $1 AND assignedworkerid = $2 AND status = 'assigned'`,
            [taskId, workerId]
        );

        if (taskCheck.rows.length === 0) {
            return res.status(403).json({ 
                error: 'Task not assigned to this worker or already started' 
            });
        }

        // Update task status to in-progress
        await pool.query(
            `UPDATE taskrequests 
             SET status = 'in-progress', 
                 starttime = NOW()
             WHERE taskid = $1`,
            [taskId]
        );

        res.status(200).json({ 
            message: 'Task started successfully' 
        });
    } catch (error) {
        console.error('Error starting task:', error.message, error.stack);
        res.status(500).json({ 
            error: 'Internal Server Error', 
            details: error.message 
        });
    }
});

// Mark collected endpoint (same as previously provided)
router.post('/mark-collected', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId, reportId } = req.body;
        const workerId = req.user.userid;

        // 1. Verify the task is assigned to this worker
        const taskCheck = await pool.query(
            `SELECT 1 FROM taskrequests 
             WHERE taskid = $1 AND assignedworkerid = $2 AND status = 'in-progress'`,
            [taskId, workerId]
        );

        if (taskCheck.rows.length === 0) {
            return res.status(403).json({ 
                error: 'Task not assigned to this worker or not in progress' 
            });
        }

        // 2. Verify the report is part of this task
        const reportCheck = await pool.query(
            `SELECT 1 FROM taskrequests 
             WHERE taskid = $1 AND $2 = ANY(reportids)`,
            [taskId, reportId]
        );

        if (reportCheck.rows.length === 0) {
            return res.status(404).json({ 
                error: 'Report not found in this task' 
            });
        }

        // 3. Update the garbagereports table
        await pool.query(
            `UPDATE garbagereports 
             SET status = 'collected', 
                 collected_at = NOW(), 
                 collected_by = $1 
             WHERE reportid = $2`,
            [workerId, reportId]
        );

        // 4. Update task progress
        const progressResult = await pool.query(
            `SELECT 
                COUNT(*) FILTER (WHERE status = 'collected')::float / 
                COUNT(*) as progress
             FROM garbagereports 
             WHERE reportid = ANY(
                 SELECT reportids FROM taskrequests WHERE taskid = $1
             )`,
            [taskId]
        );

        const progress = progressResult.rows[0]?.progress || 0;

        await pool.query(
            `UPDATE taskrequests 
             SET progress = $1
             WHERE taskid = $2`,
            [progress, taskId]
        );

        // 5. Check if all reports are collected
        const allReports = await pool.query(
            `SELECT reportid FROM garbagereports 
             WHERE reportid = ANY(
                 SELECT reportids FROM taskrequests WHERE taskid = $1
             ) AND status != 'collected'`,
            [taskId]
        );

        // 6. If all collected, mark task as completed
        if (allReports.rows.length === 0) {
            await pool.query(
                `UPDATE taskrequests 
                 SET status = 'completed', 
                     endtime = NOW(),
                     progress = 1.0
                 WHERE taskid = $1`,
                [taskId]
            );
        }

        res.status(200).json({ 
            message: 'Report marked as collected successfully' 
        });
    } catch (error) {
        console.error('Error marking report as collected:', error.message, error.stack);
        res.status(500).json({ 
            error: 'Internal Server Error', 
            details: error.message 
        });
    }
});

module.exports = router;