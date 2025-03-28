require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');

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
    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'Anusucha@01');
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

// Middleware to check if the user is a worker or admin (for assignment endpoint)
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
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distance in kilometers
}

// DBSCAN Clustering
function dbscan(points, eps, minPts) {
  const clusters = [];
  const visited = new Set();

  for (const point of points) {
    if (visited.has(point.reportid)) continue;
    visited.add(point.reportid);

    const neighbors = points.filter(p =>
      p.reportid !== point.reportid &&
      haversineDistance(point.lat, point.lng, p.lat, p.lng) <= eps
    );

    if (neighbors.length >= minPts - 1) { // -1 because point itself is included
      const cluster = expandCluster(point, neighbors, points, eps, minPts, visited);
      clusters.push(cluster);
    }
  }

  return clusters;
}

function expandCluster(point, neighbors, points, eps, minPts, visited) {
  const cluster = [point];

  for (const neighbor of neighbors) {
    if (!visited.has(neighbor.reportid)) {
      visited.add(neighbor.reportid);
      const newNeighbors = points.filter(p =>
        p.reportid !== neighbor.reportid &&
        haversineDistance(neighbor.lat, neighbor.lng, p.lat, p.lng) <= eps
      );

      if (newNeighbors.length >= minPts - 1) {
        neighbors.push(...newNeighbors);
      }
      cluster.push(neighbor);
    }
  }

  return cluster;
}

// New Endpoint: Group and Assign Reports
router.post('/group-and-assign-reports', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
  try {
    const { startDate } = req.body; // Start date to process reports from
    const eps = 2; // 2 km radius for clustering
    const minPts = 2; // Minimum 2 reports to form a cluster

    // Step 1: Fetch all unassigned reports sorted by created_at
    const result = await pool.query(
      `SELECT reportid, wastetype, location, created_at
       FROM garbagereports
       WHERE reportid NOT IN (SELECT reportid FROM taskrequests)
       ORDER BY created_at ASC`
    );

    let reports = result.rows.map(row => {
      const locationMatch = row.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
      return {
        reportid: row.reportid,
        wastetype: row.wastetype,
        lat: locationMatch ? parseFloat(locationMatch[2]) : null,
        lng: locationMatch ? parseFloat(locationMatch[1]) : null,
        created_at: new Date(row.created_at),
      };
    });

    if (!reports.length) {
      return res.status(200).json({ message: 'No unassigned reports found' });
    }

    // Step 2: Temporal Filtering and Clustering
    const processedReports = new Set();
    const assignments = [];

    while (reports.length > 0) {
      // Get the earliest report
      const T0 = startDate ? new Date(startDate) : reports[0].created_at;
      const T0Plus2Days = new Date(T0);
      T0Plus2Days.setDate(T0.getDate() + 2);

      // Filter reports within 2 days of T0
      const timeFilteredReports = reports.filter(report =>
        report.created_at >= T0 && report.created_at <= T0Plus2Days &&
        !processedReports.has(report.reportid)
      );

      if (timeFilteredReports.length === 0) break;

      // Run DBSCAN on filtered reports
      const clusters = dbscan(timeFilteredReports.filter(r => r.lat && r.lng), eps, minPts);

      // Step 3: Assign Workers to Clusters
      for (const cluster of clusters) {
        // Calculate cluster centroid
        const centroid = {
          lat: cluster.reduce((sum, r) => sum + r.lat, 0) / cluster.length,
          lng: cluster.reduce((sum, r) => sum + r.lng, 0) / cluster.length,
        };

        // Fetch available workers (assuming not overloaded)
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

        const workers = workerResult.rows.map(row => {
          const locMatch = row.location ? row.location.match(/POINT\(([^ ]+) ([^)]+)\)/) : null;
          return {
            userid: row.userid,
            lat: locMatch ? parseFloat(locMatch[2]) : 10.235865, // Default worker location
            lng: locMatch ? parseFloat(locMatch[1]) : 76.405676,
          };
        });

        if (workers.length === 0) {
          continue; 
        }

        // Assign closest worker
        const assignedWorker = workers.reduce((closest, worker) => {
          const distance = haversineDistance(worker.lat, worker.lng, centroid.lat, centroid.lng);
          return (!closest || distance < closest.distance) ? { ...worker, distance } : closest;
        }, null);

        // Insert tasks into taskrequests
        for (const report of cluster) {
          await pool.query(
            `INSERT INTO taskrequests (reportid, assignedworkerid, status, starttime)
             VALUES ($1, $2, 'assigned', NOW())`,
            [report.reportid, assignedWorker.userid]
          );
          processedReports.add(report.reportid);
          assignments.push({
            reportid: report.reportid,
            wastetype: report.wastetype,
            assignedWorkerId: assignedWorker.userid,
          });
        }
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

// Middleware to check if the user is a worker
const checkWorkerRole = (req, res, next) => {
  if (!req.user || req.user.role.toLowerCase() !== 'worker') {
    return res.status(403).json({ message: 'Access denied: Only workers can access this endpoint' });
  }
  next();
};

// Fetch Assigned Tasks for Worker
router.get('/assigned-tasks', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(workerId)) {
      return res.status(400).json({ error: 'Invalid worker ID in token' });
    }

    const result = await pool.query(
      `SELECT t.taskid, g.wastetype, g.location, t.status, t.progress, t.starttime
       FROM taskrequests t 
       JOIN garbagereports g ON t.reportid = g.reportid 
       WHERE t.assignedworkerid = $1 AND t.status != 'completed'`,
      [workerId]
    );

    const assignedWorks = result.rows.map(row => {
      const locationMatch = row.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
      const reportLat = locationMatch ? parseFloat(locationMatch[2]) : null;
      const reportLng = locationMatch ? parseFloat(locationMatch[1]) : null;

      const workerLat = 10.235865; // Updated to match the worker's actual location
      const workerLng = 76.405676;

      let distance = '0km';
      if (reportLat && reportLng) {
        const earthRadius = 6371;
        const dLat = (reportLat - workerLat) * (Math.PI / 180);
        const dLng = (reportLng - workerLng) * (Math.PI / 180);
        const a =
          Math.sin(dLat / 2) * Math.sin(dLat / 2) +
          Math.cos(workerLat * (Math.PI / 180)) *
          Math.cos(reportLat * (Math.PI / 180)) *
          Math.sin(dLng / 2) * Math.sin(dLng / 2);
        const c = 2 * Math.asin(Math.sqrt(a));
        distance = (earthRadius * c).toFixed(2) + 'km';
      }

      return {
        taskId: row.taskid.toString(),
        title: row.wastetype ?? 'Unknown',
        location: row.location,
        distance: distance,
        time: row.starttime ? row.starttime.toISOString() : 'Not Started',
        status: row.status,
        progress: row.progress,
      };
    });

    res.json({ assignedWorks });
  } catch (error) {
    console.error('Error fetching assigned tasks in worker.js:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Fetch Task Route for Map (used by pickup_map.dart)
router.get('/task/route', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const { taskId } = req.query;
    if (!taskId) return res.status(400).json({ error: 'Task ID is required' });

    const taskIdInt = parseInt(taskId, 10);
    if (isNaN(taskIdInt)) {
      return res.status(400).json({ error: 'Invalid Task ID' });
    }

    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(workerId)) {
      return res.status(400).json({ error: 'Invalid worker ID in token' });
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

    const result = await pool.query(
      `SELECT route 
       FROM taskrequests 
       WHERE taskid = $1`,
      [taskIdInt]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }

    const route = result.rows[0].route;
    if (!route) {
      return res.status(404).json({ error: 'No route data available for this task' });
    }

    res.json({ route });
  } catch (error) {
    console.error('Error fetching task route in worker.js:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Update Task Progress
router.patch('/update-progress', authenticateToken, checkWorkerRole, async (req, res) => {
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

    await pool.query(
      'UPDATE taskrequests SET progress = $1, status = $2 WHERE taskid = $3',
      [progressFloat, status, taskIdInt]
    );

    res.json({ message: 'Task updated successfully' });
  } catch (error) {
    console.error('Error updating task progress in worker.js:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Fetch Completed Tasks
router.get('/completed-tasks', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(workerId)) {
      return res.status(400).json({ error: 'Invalid worker ID in token' });
    }

    const result = await pool.query(
      `SELECT t.taskid, g.wastetype, g.location, t.endtime 
       FROM taskrequests t 
       JOIN garbagereports g ON t.reportid = g.reportid 
       WHERE t.assignedworkerid = $1 AND t.status = 'completed'`,
      [workerId]
    );

    const completedWorks = result.rows.map(row => ({
      taskId: row.taskid.toString(),
      title: row.wastetype,
      location: row.location,
      endTime: row.endtime ? row.endtime.toISOString() : null,
    }));

    res.json({ completedWorks });
  } catch (error) {
    console.error('Error fetching completed tasks in worker.js:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Updated /task-route/:taskid endpoint
router.get('/task-route/:taskid', authenticateToken, checkWorkerRole, async (req, res) => {
  const taskId = parseInt(req.params.taskid, 10);
  const workerId = req.user.userid;
  const workerLat = parseFloat(req.query.workerLat) || 10.235865; // Updated default
  const workerLng = parseFloat(req.query.workerLng) || 76.405676;

  try {
    // Fetch the task details, ensuring it belongs to the worker
    const taskResult = await pool.query(
      `SELECT tr.taskid, tr.reportid, tr.assignedworkerid, tr.status, tr.route, tr.progress, tr.starttime, tr.endtime,
              gr.location AS report_location, gr.wastetype
       FROM taskrequests tr
       JOIN garbagereports gr ON tr.reportid = gr.reportid
       WHERE tr.taskid = $1 AND tr.assignedworkerid = $2`,
      [taskId, workerId]
    );

    if (taskResult.rows.length === 0) {
      return res.status(404).json({ message: 'Task not found or not assigned to this worker' });
    }

    const task = taskResult.rows[0];
    console.log('Task data:', task); // Debug log

    // Parse the report location (from garbagereports)
    const reportLocation = task.report_location;
    console.log('Report location:', reportLocation); // Debug log

    let collectionPoint = null;
    if (reportLocation) {
      const locationMatch = reportLocation.match(/POINT\(([^ ]+) ([^)]+)\)/);
      if (locationMatch) {
        collectionPoint = {
          lat: parseFloat(locationMatch[2]), // Latitude
          lng: parseFloat(locationMatch[1]), // Longitude
        };
      } else {
        console.error('Failed to parse report location:', reportLocation);
      }
    } else {
      console.error('Report location is null or undefined');
    }

    // Parse the route from the jsonb field
    const routeData = task.route || { start: {}, end: {}, waypoints: [] };
    console.log('Route data:', routeData); // Debug log

    const routePoints = [];

    // If route is empty or invalid, construct a route from worker's location to collection point
    if (
      (!routeData.start || !routeData.start.lat || !routeData.start.lng) &&
      (!routeData.end || !routeData.end.lat || !routeData.end.lng) &&
      (!routeData.waypoints || routeData.waypoints.length === 0)
    ) {
      if (collectionPoint) {
        routePoints.push({
          lat: workerLat,
          lng: workerLng,
        });
        routePoints.push({
          lat: collectionPoint.lat,
          lng: collectionPoint.lng,
        });
      }
    } else {
      // Add start point
      if (routeData.start && routeData.start.lat && routeData.start.lng) {
        routePoints.push({
          lat: parseFloat(routeData.start.lat),
          lng: parseFloat(routeData.start.lng),
        });
      }

      // Add waypoints
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

      // Add end point
      if (routeData.end && routeData.end.lat && routeData.end.lng) {
        routePoints.push({
          lat: parseFloat(routeData.end.lat),
          lng: parseFloat(routeData.end.lng),
        });
      }
    }

    // Since the app fetches the route from OSRM, we can return an empty route field
    res.status(200).json({
      taskid: task.taskid,
      reportid: task.reportid,
      status: task.status,
      route: [], // Let the app fetch the route from OSRM
      locations: collectionPoint ? [collectionPoint] : [],
      wastetype: task.wastetype,
    });
  } catch (error) {
    console.error('Error fetching task route:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

module.exports = router;