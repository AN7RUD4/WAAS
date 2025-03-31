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
  if (!token) return res.status(401).json({ message: 'Authentication token required' });
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'passwordKey');
    if (!decoded.userid || !decoded.role) return res.status(403).json({ message: 'Invalid token: Missing userid or role' });
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

// Middleware to check if the user is a worker
const checkWorkerRole = (req, res, next) => {
  if (!req.user || req.user.role.toLowerCase() !== 'worker') {
    return res.status(403).json({ message: 'Access denied: Only workers can access this endpoint' });
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
  if (points.length < k) return points.map(point => [point]);
  const kmeans = new KMeans();
  const data = points.map(p => [p.lat, p.lng]);
  kmeans.cluster(data, k);
  while (kmeans.step()) {}
  const clusters = Array.from({ length: k }, () => []);
  points.forEach((point, idx) => {
    const clusterIdx = kmeans.nearest([point.lat, point.lng])[0];
    clusters[clusterIdx].push(point);
  });
  return clusters.filter(cluster => cluster.length > 0);
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
    const costMatrix = workers.map(worker => haversineDistance(worker.lat, worker.lng, centroid.lat, centroid.lng));
    const munkres = new Munkres();
    const indices = munkres.compute(costMatrix.map(row => [row]));
    const workerIdx = indices.find(([workerIdx]) => workerIdx !== null)?.[0];
    if (workerIdx === undefined || workerIdx >= workers.length) continue;
    const assignedWorker = workers[workerIdx];
    workers.splice(workerIdx, 1);
    assignments.push({ cluster, worker: assignedWorker });
  }
  return assignments;
}

// Step 3: TSP Route Optimization (Nearest Neighbor Heuristic)
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

// New Endpoint: Group and Assign Reports
router.post('/group-and-assign-reports', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
  try {
    const { startDate } = req.body;
    const k = 3;

    // Fetch all unassigned reports
    const result = await pool.query(
      `SELECT reportid, wastetype, location
       FROM garbagereports
       WHERE reportid NOT IN (SELECT UNNEST(reportids) FROM taskrequests)
       ORDER BY reportid ASC`
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

    reports = reports.filter(r => r.lat !== null && r.lng !== null);

    const processedReports = new Set();
    const assignments = [];

    while (reports.length > 0) {
      const T0 = startDate ? new Date(startDate) : reports[0].created_at;
      const T0Plus2Days = new Date(T0);
      T0Plus2Days.setDate(T0.getDate() + 2);

      const timeFilteredReports = reports.filter(
        report => report.created_at >= T0 && report.created_at <= T0Plus2Days && !processedReports.has(report.reportid)
      );

      if (timeFilteredReports.length === 0) break;

      const clusters = kmeansClustering(timeFilteredReports, Math.min(k, timeFilteredReports.length));

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
          lat: locMatch ? parseFloat(locMatch[2]) : 10.235865,
          lng: locMatch ? parseFloat(locMatch[1]) : 76.405676,
        };
      });

      if (workers.length === 0) break;

      const clusterAssignments = assignWorkersToClusters(clusters, workers);

      for (const { cluster, worker } of clusterAssignments) {
        const route = solveTSP(cluster, worker);
        const routeJson = {
          start: { lat: route[0].lat, lng: route[0].lng },
          waypoints: route.slice(1, -1).map(point => ({ lat: point.lat, lng: point.lng })),
          end: { lat: route[route.length - 1].lat, lng: route[route.length - 1].lng },
        };

        // Aggregate report IDs for the cluster
        const reportIds = cluster.map(report => report.reportid);

        // Insert one row per cluster
        await pool.query(
          `INSERT INTO taskrequests (reportids, assignedworkerid, status, starttime, route)
           VALUES ($1, $2, 'assigned', NOW(), $3)`,
          [reportIds, worker.userid, routeJson]
        );

        reportIds.forEach(id => processedReports.add(id));
        assignments.push({
          reportids: reportIds,
          assignedWorkerId: worker.userid,
          route: routeJson,
        });
      }

      reports = reports.filter(r => !processedReports.has(r.reportid));
    }

    res.status(200).json({ message: 'Reports grouped and assigned successfully', assignments });
  } catch (error) {
    console.error('Error in group-and-assign-reports:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Fetch Assigned Tasks for Worker
router.get('/assigned-tasks', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(workerId)) return res.status(400).json({ error: 'Invalid worker ID in token' });

    const result = await pool.query(
      `SELECT t.taskid, t.reportids, t.status, t.starttime, 
              array_agg(g.wastetype) AS wastetypes, array_agg(g.location) AS locations
       FROM taskrequests t
       JOIN garbagereports g ON g.reportid = ANY(t.reportids)
       WHERE t.assignedworkerid = $1 AND t.status != 'completed'
       GROUP BY t.taskid, t.reportids, t.status, t.starttime`,
      [workerId]
    );

    const assignedWorks = result.rows.map(row => {
      const distances = row.locations.map(loc => {
        const locationMatch = loc.match(/POINT\(([^ ]+) ([^)]+)\)/);
        const reportLat = locationMatch ? parseFloat(locationMatch[2]) : null;
        const reportLng = locationMatch ? parseFloat(locationMatch[1]) : null;
        const workerLat = 10.235865;
        const workerLng = 76.405676;
        if (reportLat && reportLng) {
          const earthRadius = 6371;
          const dLat = (reportLat - workerLat) * (Math.PI / 180);
          const dLng = (reportLng - workerLng) * (Math.PI / 180);
          const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                    Math.cos(workerLat * (Math.PI / 180)) * Math.cos(reportLat * (Math.PI / 180)) *
                    Math.sin(dLng / 2) * Math.sin(dLng / 2);
          const c = 2 * Math.asin(Math.sqrt(a));
          return (earthRadius * c).toFixed(2) + 'km';
        }
        return '0km';
      });

      return {
        taskId: row.taskid.toString(),
        reportIds: row.reportids,
        titles: row.wastetypes,
        locations: row.locations,
        distances: distances,
        time: row.starttime ? row.starttime.toISOString() : 'Not Started',
        status: row.status,
      };
    });

    res.json({ assignedWorks });
  } catch (error) {
    console.error('Error fetching assigned tasks:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Fetch Task Route for Map
router.get('/task/route', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const { taskId } = req.query;
    if (!taskId) return res.status(400).json({ error: 'Task ID is required' });

    const taskIdInt = parseInt(taskId, 10);
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(taskIdInt) || isNaN(workerId)) return res.status(400).json({ error: 'Invalid Task or Worker ID' });

    const taskCheck = await pool.query(
      `SELECT 1 FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
      [taskIdInt, workerId]
    );
    if (taskCheck.rows.length === 0) return res.status(403).json({ error: 'Task not assigned to this worker' });

    const result = await pool.query(
      `SELECT route FROM taskrequests WHERE taskid = $1`,
      [taskIdInt]
    );
    if (result.rows.length === 0 || !result.rows[0].route) return res.status(404).json({ error: 'Task or route not found' });

    res.json({ route: result.rows[0].route });
  } catch (error) {
    console.error('Error fetching task route:', error.message, error.stack);
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
    const workerId = parseInt(req.user.userid, 10);
    const progressFloat = parseFloat(progress);
    if (isNaN(taskIdInt) || isNaN(workerId) || isNaN(progressFloat) || progressFloat < 0 || progressFloat > 1) {
      return res.status(400).json({ error: 'Invalid input values' });
    }

    const validStatuses = ['pending', 'assigned', 'in-progress', 'completed', 'failed'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
    }

    const taskCheck = await pool.query(
      `SELECT 1 FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
      [taskIdInt, workerId]
    );
    if (taskCheck.rows.length === 0) return res.status(403).json({ error: 'Task not assigned to this worker' });

    await pool.query(
      `UPDATE taskrequests SET status = $1, starttime = CASE WHEN $1 = 'in-progress' AND starttime IS NULL THEN NOW() ELSE starttime END WHERE taskid = $2`,
      [status, taskIdInt]
    );

    res.json({ message: 'Task updated successfully' });
  } catch (error) {
    console.error('Error updating task progress:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Fetch Completed Tasks
router.get('/completed-tasks', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(workerId)) return res.status(400).json({ error: 'Invalid worker ID in token' });

    const result = await pool.query(
      `SELECT t.taskid, t.reportids, array_agg(g.wastetype) AS wastetypes, array_agg(g.location) AS locations, t.endtime
       FROM taskrequests t
       JOIN garbagereports g ON g.reportid = ANY(t.reportids)
       WHERE t.assignedworkerid = $1 AND t.status = 'completed'
       GROUP BY t.taskid, t.reportids, t.endtime`,
      [workerId]
    );

    const completedWorks = result.rows.map(row => ({
      taskId: row.taskid.toString(),
      reportIds: row.reportids,
      titles: row.wastetypes,
      locations: row.locations,
      endTime: row.endtime ? row.endtime.toISOString() : null,
    }));

    res.json({ completedWorks });
  } catch (error) {
    console.error('Error fetching completed tasks:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// Updated /task-route/:taskid endpoint
router.get('/task-route/:taskid', authenticateToken, checkWorkerRole, async (req, res) => {
  const taskId = parseInt(req.params.taskid, 10);
  const workerId = req.user.userid;
  const workerLat = parseFloat(req.query.workerLat) || 10.235865;
  const workerLng = parseFloat(req.query.workerLng) || 76.405676;

  try {
    const taskResult = await pool.query(
      `SELECT t.taskid, t.reportids, t.assignedworkerid, t.status, t.route,
              array_agg(g.location) AS report_locations, array_agg(g.wastetype) AS wastetypes
       FROM taskrequests t
       JOIN garbagereports g ON g.reportid = ANY(t.reportids)
       WHERE t.taskid = $1 AND t.assignedworkerid = $2
       GROUP BY t.taskid, t.reportids, t.assignedworkerid, t.status, t.route`,
      [taskId, workerId]
    );

    if (taskResult.rows.length === 0) return res.status(404).json({ message: 'Task not found or not assigned to this worker' });

    const task = taskResult.rows[0];
    const collectionPoints = task.report_locations.map(loc => {
      const locationMatch = loc.match(/POINT\(([^ ]+) ([^)]+)\)/);
      return locationMatch ? { lat: parseFloat(locationMatch[2]), lng: parseFloat(locationMatch[1]) } : null;
    }).filter(point => point !== null);

    const routeData = task.route || { start: {}, end: {}, waypoints: [] };
    const routePoints = [];
    if (routeData.start && routeData.start.lat && routeData.start.lng) {
      routePoints.push({ lat: parseFloat(routeData.start.lat), lng: parseFloat(routeData.start.lng) });
    }
    if (routeData.waypoints && Array.isArray(routeData.waypoints)) {
      routeData.waypoints.forEach(waypoint => {
        if (waypoint.lat && waypoint.lng) routePoints.push({ lat: parseFloat(waypoint.lat), lng: parseFloat(waypoint.lng) });
      });
    }
    if (routeData.end && routeData.end.lat && routeData.end.lng) {
      routePoints.push({ lat: parseFloat(routeData.end.lat), lng: parseFloat(routeData.end.lng) });
    }

    res.status(200).json({
      taskid: task.taskid,
      reportids: task.reportids,
      status: task.status,
      route: [], // Let the app fetch the route from OSRM
      locations: collectionPoints,
      wastetypes: task.wastetypes,
    });
  } catch (error) {
    console.error('Error fetching task route:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

module.exports = router;