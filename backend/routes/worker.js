require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const KMeans = require('kmeans-js'); 
const Munkres = require('munkres-js'); 

const router = express.Router();
router.use(cors());
router.use(express.json());

// Database connection
const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
  ssl: { rejectUnauthorized: false },
});

// Test database connection on startup
pool.connect((err, client, release) => {
  if (err) {
    console.error('Error connecting to the database in worker.js:', err.stack);
    process.exit(1);
  } else {
    console.log('Worker.js successfully connected to the database');
    release();
  }
});

// Middleware to verify JWT token
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ message: 'Authentication token required' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'passwordKey');
    if (!decoded.userid || !decoded.role) {
      return res.status(403).json({ message: 'Invalid token: Missing userid or role' });
    }
    req.user = decoded;
    next();
  } catch (err) {
    console.error('Token verification error in worker.js:', err.message);
    return res.status(403).json({ message: 'Invalid or expired token' });
  }
};

// Middleware to check if the user is a worker or admin
const checkWorkerOrAdminRole = (req, res, next) => {
  if (!req.user || (req.user.role.toLowerCase() !== 'worker' && req.user.role.toLowerCase() !== 'admin')) {
    return res.status(403).json({ message: 'Access denied: Only workers or admins can access this endpoint' });
  }
  next();
};

// Haversine Distance Calculation
function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth radius in kilometers
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distance in kilometers
}

// Step 1: K-Means Clustering
function kmeansClustering(points, k) {
  if (points.length < k) return points.map(point => [point]); // Not enough points to cluster

  const kmeans = new KMeans();
  const data = points.map(p => [p.lat, p.lng]);
  kmeans.cluster(data, k);

  // Wait for clustering to complete
  while (kmeans.step()) {
    // Continue iterating until convergence
  }

  const clusters = Array.from({ length: k }, () => []);
  points.forEach((point, idx) => {
    const clusterIdx = kmeans.nearest([point.lat, point.lng])[0];
    clusters[clusterIdx].push(point);
  });

  return clusters.filter(cluster => cluster.length > 0); // Remove empty clusters
}

// Step 2: Munkres Algorithm for Worker Allocation
function assignWorkersToClusters(clusters, workers) {
  const assignments = [];

  for (const cluster of clusters) {
    if (workers.length === 0) break;

    const centroid = {
      lat: cluster.reduce((sum, r) => sum + r.lat, 0) / cluster.length,
      lng: cluster.reduce((sum, r) => sum + r.lng, 0) / cluster.length,
    };

    // Create a cost matrix: distance between each worker and the cluster centroid
    const costMatrix = workers.map(worker =>
      haversineDistance(worker.lat, worker.lng, centroid.lat, centroid.lng)
    );

    // Run Hungarian Algorithm using munkres-js
    const munkres = new Munkres();
    const indices = munkres.compute(costMatrix.map(row => [row])); // Convert to 2D array

    // Find the first valid assignment
    const workerIdx = indices.find(([workerIdx]) => workerIdx !== null)?.[0];
    if (workerIdx === undefined || workerIdx >= workers.length) continue; // No valid assignment

    const assignedWorker = workers[workerIdx];

    // Remove the assigned worker from the pool
    workers.splice(workerIdx, 1);

    assignments.push({ cluster, worker: assignedWorker });
  }

  return assignments;
}

// Step 3: TSP Route Optimization (Nearest Neighbor Heuristic)
function solveTSP(points, worker) {
  if (points.length === 0) return [];

  // Start from the worker's location
  const route = [{ lat: worker.lat, lng: worker.lng }];
  const unvisited = [...points];
  let current = { lat: worker.lat, lng: worker.lng };

  // Nearest Neighbor: Always go to the closest unvisited point
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

// Endpoint to group and assign reports
router.post('/group-and-assign-reports', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
  try {
    const { startDate } = req.body; // Start date to process reports from
    const k = 3; // Number of clusters for K-Means (adjust as needed)

    // Step 1: Fetch all unassigned reports sorted by created_at
    const result = await pool.query(
      `SELECT reportid, wastetype, location, datetime
       FROM garbagereports
       WHERE reportid NOT IN (
         SELECT unnest(reportids) FROM taskrequests
       )
       ORDER BY datetime ASC`
    );

    let reports = result.rows.map(row => {
      const locationMatch = row.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
      return {
        reportid: row.reportid,
        wastetype: row.wastetype,
        lat: locationMatch ? parseFloat(locationMatch[2]) : null,
        lng: locationMatch ? parseFloat(locationMatch[1]) : null,
        created_at: new Date(row.datetime),
      };
    });

    if (!reports.length) {
      return res.status(200).json({ message: 'No unassigned reports found' });
    }

    // Filter out reports with invalid locations
    reports = reports.filter(r => r.lat !== null && r.lng !== null);

    // Step 2: Temporal Filtering and Clustering
    const processedReports = new Set();
    const assignments = [];

    while (reports.length > 0) {
      // Get the earliest report
      const T0 = startDate ? new Date(startDate) : reports[0].created_at;
      const T0Plus2Days = new Date(T0);
      T0Plus2Days.setDate(T0.getDate() + 2);

      // Filter reports within 2 days of T0
      const timeFilteredReports = reports.filter(
        report =>
          report.created_at >= T0 &&
          report.created_at <= T0Plus2Days &&
          !processedReports.has(report.reportid)
      );

      if (timeFilteredReports.length === 0) break;

      // Step 3: K-Means Clustering
      const clusters = kmeansClustering(timeFilteredReports, Math.min(k, timeFilteredReports.length));

      // Step 4: Fetch available workers
      const workerResult = await pool.query(
        `SELECT userid, location
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

      let workers = workerResult.rows.map(row => {
        const locMatch = row.location ? row.location.match(/POINT\(([^ ]+) ([^)]+)\)/) : null;
        return {
          userid: row.userid,
          lat: locMatch ? parseFloat(locMatch[2]) : 10.235865, // Default worker location
          lng: locMatch ? parseFloat(locMatch[1]) : 76.405676,
        };
      });

      if (workers.length === 0) {
        break; // No workers available
      }

      // Step 5: Assign Workers to Clusters using Hungarian Algorithm
      const clusterAssignments = assignWorkersToClusters(clusters, workers);

      // Step 6: For each cluster, solve TSP and assign tasks
      for (const { cluster, worker } of clusterAssignments) {
        // Solve TSP for the cluster starting from the worker's location
        const route = solveTSP(cluster, worker);

        // Format the route as a JSONB object
        const routeJson = {
          start: { lat: route[0].lat, lng: route[0].lng },
          waypoints: route.slice(1, -1).map(point => ({ lat: point.lat, lng: point.lng })),
          end: { lat: route[route.length - 1].lat, lng: route[route.length - 1].lng },
        };

        // Instead of creating a task per report, create one task per cluster
        const reportIds = cluster.map(report => report.reportid);
        
        // Insert a single task with multiple report IDs
        const taskResult = await pool.query(
          `INSERT INTO taskrequests (reportids, assignedworkerid, status, starttime, route)
           VALUES ($1, $2, 'assigned', NOW(), $3)
           RETURNING taskid`,
          [reportIds, worker.userid, routeJson]
        );
        
        const taskId = taskResult.rows[0].taskid;
        
        // Mark all reports in this cluster as processed
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

    res.status(200).json({
      message: 'Reports grouped and assigned successfully',
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
      `SELECT taskid, reportids, status, progress, starttime, route 
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
          progress: task.progress,
        });
      }
    }

    res.json({ assignedWorks });
  } catch (error) {
    console.error('Error fetching assigned tasks in worker.js:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Updated /task-route/:taskid endpoint
router.get('/task-route/:taskid', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
  const taskId = parseInt(req.params.taskid, 10);
  const workerId = req.user.userid;
  const workerLat = parseFloat(req.query.workerLat) || 10.235865;
  const workerLng = parseFloat(req.query.workerLng) || 76.405676;

  try {
    // Fetch the task details, ensuring it belongs to the worker
    const taskResult = await pool.query(
      `SELECT taskid, reportids, assignedworkerid, status, route, progress, starttime, endtime
       FROM taskrequests
       WHERE taskid = $1 AND assignedworkerid = $2`,
      [taskId, workerId]
    );

    if (taskResult.rows.length === 0) {
      return res.status(404).json({ message: 'Task not found or not assigned to this worker' });
    }

    const task = taskResult.rows[0];
    
    // Fetch all reports in this task
    const reportsResult = await pool.query(
      `SELECT reportid, wastetype, location 
       FROM garbagereports 
       WHERE reportid = ANY($1)`,
      [task.reportids]
    );
    
    // Parse collection points from all reports
    const collectionPoints = [];
    const wasteTypes = new Set();
    
    for (const report of reportsResult.rows) {
      wasteTypes.add(report.wastetype);
      
      if (report.location) {
        const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
        if (locationMatch) {
          collectionPoints.push({
            reportid: report.reportid,
            lat: parseFloat(locationMatch[2]),
            lng: parseFloat(locationMatch[1]),
            wastetype: report.wastetype
          });
        }
      }
    }

    // Parse the route from the jsonb field or create one from worker location to all collection points
    let routePoints = [];
    const routeData = task.route || { start: {}, end: {}, waypoints: [] };

    // If route is empty or invalid, construct a route from worker to collection points
    if (
      (!routeData.start || !routeData.start.lat || !routeData.start.lng) &&
      (!routeData.end || !routeData.end.lat || !routeData.end.lng) &&
      (!routeData.waypoints || routeData.waypoints.length === 0)
    ) {
      if (collectionPoints.length > 0) {
        routePoints.push({
          lat: workerLat,
          lng: workerLng,
        });
        
        // Add all collection points to route
        collectionPoints.forEach(point => {
          routePoints.push({
            lat: point.lat,
            lng: point.lng,
          });
        });
      }
    } else {
      // Use the existing route
      if (routeData.start && routeData.start.lat && routeData.start.lng) {
        routePoints.push({
          lat: parseFloat(routeData.start.lat),
          lng: parseFloat(routeData.start.lng),
        });
      }

      if (routeData.waypoints && Array.isArray(routeData.waypoints)) {
        routeData.waypoints.forEach(waypoint => {
          if (waypoint.lat && waypoint.lng) {
            routePoints.push({
              lat: parseFloat(waypoint.lat),
              lng: parseFloat(waypoint.lng),
            });
          }
        });
      }

      if (routeData.end && routeData.end.lat && routeData.end.lng) {
        routePoints.push({
          lat: parseFloat(routeData.end.lat),
          lng: parseFloat(routeData.end.lng),
        });
      }
    }

    res.status(200).json({
      taskid: task.taskid,
      reportids: task.reportids,
      status: task.status,
      route: [], // Let the app fetch the route from OSRM
      locations: collectionPoints,
      wasteTypes: Array.from(wasteTypes),
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

module.exports=router;