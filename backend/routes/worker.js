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
    console.log('Starting report assignment process');
    
    const { startDate } = req.body;
    const k = 3;

    // Fetch all unassigned reports that aren't in any taskrequests
    const result = await pool.query(
      `SELECT reportid, wastetype, location
       FROM garbagereports
       WHERE reportid NOT IN (
         SELECT DISTINCT unnest(reportids) 
         FROM taskrequests
       )
       ORDER BY reportid ASC`
    );

    console.log(`Found ${result.rows.length} unassigned reports`);
    
    let reports = result.rows.map(row => {
      const locationMatch = row.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
      return {
        reportid: row.reportid,
        wastetype: row.wastetype,
        lat: locationMatch ? parseFloat(locationMatch[2]) : null,
        lng: locationMatch ? parseFloat(locationMatch[1]) : null,
        created_at: row.created_at,
      };
    });

    // Filter out reports with invalid locations
    reports = reports.filter(r => r.lat !== null && r.lng !== null);
    console.log(`After filtering, ${reports.length} reports with valid locations`);

    if (!reports.length) {
      console.log('No reports to process');
      return res.status(200).json({ message: 'No unassigned reports found' });
    }

    const processedReports = new Set();
    const assignments = [];

    while (reports.length > 0) {
      const T0 = startDate ? new Date(startDate) : reports[0].created_at;
      const T0Plus2Days = new Date(T0);
      T0Plus2Days.setDate(T0.getDate() + 2);

      const timeFilteredReports = reports.filter(
        report => report.created_at >= T0 && 
                 report.created_at <= T0Plus2Days && 
                 !processedReports.has(report.reportid)
      );

      if (timeFilteredReports.length === 0) break;

      // Cluster reports
      const clusters = kmeansClustering(timeFilteredReports, Math.min(k, timeFilteredReports.length));
      console.log(`Created ${clusters.length} clusters`);

      // Fetch available workers (with less than 5 active tasks)
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

      console.log(`Found ${workers.length} available workers`);

      if (workers.length === 0) {
        console.log('No workers available');
        break;
      }

      // Assign workers to clusters
      const clusterAssignments = assignWorkersToClusters(clusters, workers);
      console.log(`Made ${clusterAssignments.length} worker-cluster assignments`);

      // Process each assignment
      for (const { cluster, worker } of clusterAssignments) {
        // Generate optimal route
        const route = solveTSP(cluster, worker);
        const routeJson = {
          start: { lat: route[0].lat, lng: route[0].lng },
          waypoints: route.slice(1, -1).map(point => ({ lat: point.lat, lng: point.lng })),
          end: { lat: route[route.length - 1].lat, lng: route[route.length - 1].lng },
        };

        // Get report IDs for this cluster
        const reportIds = cluster.map(report => report.reportid);

        // Insert task into taskrequests
        const insertResult = await pool.query(
          `INSERT INTO taskrequests (reportids, assignedworkerid, status, starttime, route)
           VALUES ($1, $2, 'assigned', NOW(), $3)
           RETURNING taskid`,
          [reportIds, worker.userid, routeJson]
        );

        console.log(`Created task ${insertResult.rows[0].taskid} for worker ${worker.userid} with ${reportIds.length} reports`);

        // Mark reports as processed
        reportIds.forEach(id => processedReports.add(id));
        
        assignments.push({
          taskId: insertResult.rows[0].taskid,
          reportIds: reportIds,
          assignedWorkerId: worker.userid,
          route: routeJson,
        });
      }

      // Remove processed reports
      reports = reports.filter(r => !processedReports.has(r.reportid));
    }

    console.log('Process completed with assignments:', assignments);
    res.status(200).json({ 
      message: 'Reports grouped and assigned successfully', 
      assignments: assignments,
      totalAssigned: assignments.reduce((sum, a) => sum + a.reportIds.length, 0)
    });
  } catch (error) {
    console.error('Error in group-and-assign-reports:', error.message, error.stack);
    res.status(500).json({ 
      error: 'Internal Server Error', 
      details: error.message,
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

// Fetch Assigned Tasks for Worker
router.get('/assigned-tasks', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(workerId)) return res.status(400).json({ error: 'Invalid worker ID in token' });

    const result = await pool.query(
      `SELECT t.taskid, t.reportids, t.status, t.starttime, t.route,
              json_agg(json_build_object(
                'wastetype', g.wastetype,
                'location', g.location
              )) AS reports
       FROM taskrequests t
       JOIN garbagereports g ON g.reportid = ANY(t.reportids)
       WHERE t.assignedworkerid = $1 AND t.status != 'completed'
       GROUP BY t.taskid, t.reportids, t.status, t.starttime, t.route`,
      [workerId]
    );

    const assignedWorks = result.rows.map(row => {
      // Calculate distances for all reports in this task
      const reportsWithDistance = row.reports.map(report => {
        const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
        const reportLat = locationMatch ? parseFloat(locationMatch[2]) : null;
        const reportLng = locationMatch ? parseFloat(locationMatch[1]) : null;
        
        let distance = '0km';
        if (reportLat && reportLng) {
          distance = (haversineDistance(
            10.235865, 76.405676, // Default worker location
            reportLat, reportLng
          )).toFixed(2) + 'km';
        }

        return {
          wastetype: report.wastetype,
          location: report.location,
          distance: distance
        };
      });

      return {
        taskId: row.taskid.toString(),
        reportIds: row.reportids,
        reports: reportsWithDistance,
        startTime: row.starttime ? row.starttime.toISOString() : null,
        status: row.status,
        route: row.route
      };
    });

    res.json({ 
      success: true,
      assignedWorks 
    });
  } catch (error) {
    console.error('Error fetching assigned tasks:', error.message, error.stack);
    res.status(500).json({ 
      error: 'Internal Server Error', 
      details: error.message 
    });
  }
});

// Fetch Task Route for Map
router.get('/task/route/:taskId', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const { taskId } = req.params;
    if (!taskId) return res.status(400).json({ error: 'Task ID is required' });

    const taskIdInt = parseInt(taskId, 10);
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(taskIdInt) || isNaN(workerId)) {
      return res.status(400).json({ error: 'Invalid Task or Worker ID' });
    }

    // Verify task belongs to this worker
    const taskCheck = await pool.query(
      `SELECT 1 FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
      [taskIdInt, workerId]
    );
    if (taskCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Task not assigned to this worker' });
    }

    // Get full task details with all reports
    const result = await pool.query(
      `SELECT t.taskid, t.reportids, t.route, t.status,
              json_agg(json_build_object(
                'reportid', g.reportid,
                'wastetype', g.wastetype,
                'location', g.location
              )) AS reports
       FROM taskrequests t
       JOIN garbagereports g ON g.reportid = ANY(t.reportids)
       WHERE t.taskid = $1
       GROUP BY t.taskid, t.reportids, t.route, t.status`,
      [taskIdInt]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }

    const task = result.rows[0];
    
    // Parse all report locations
    const locations = task.reports.map(report => {
      const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
      return locationMatch ? {
        lat: parseFloat(locationMatch[2]),
        lng: parseFloat(locationMatch[1]),
        reportid: report.reportid,
        wastetype: report.wastetype
      } : null;
    }).filter(Boolean);

    res.json({
      success: true,
      taskId: task.taskid,
      status: task.status,
      route: task.route || {},
      locations: locations,
      reportIds: task.reportids
    });
  } catch (error) {
    console.error('Error fetching task route:', error.message, error.stack);
    res.status(500).json({ 
      error: 'Internal Server Error', 
      details: error.message 
    });
  }
});

// Update Task Progress
router.patch('/tasks/:taskId', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const { taskId } = req.params;
    const { status, progress } = req.body;

    if (!taskId || !status) {
      return res.status(400).json({ error: 'Task ID and status are required' });
    }

    const taskIdInt = parseInt(taskId, 10);
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(taskIdInt) || isNaN(workerId)) {
      return res.status(400).json({ error: 'Invalid Task or Worker ID' });
    }

    const validStatuses = ['assigned', 'in-progress', 'completed', 'failed'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ 
        error: 'Invalid status', 
        validStatuses: validStatuses 
      });
    }

    // Verify task belongs to this worker
    const taskCheck = await pool.query(
      `SELECT 1 FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
      [taskIdInt, workerId]
    );
    if (taskCheck.rows.length === 0) {
      return res.status(403).json({ error: 'Task not assigned to this worker' });
    }

    // Prepare update query based on status
    let query;
    let params;
    
    if (status === 'in-progress') {
      query = `
        UPDATE taskrequests 
        SET status = $1, 
            starttime = CASE WHEN starttime IS NULL THEN NOW() ELSE starttime END,
            progress = COALESCE($2, progress)
        WHERE taskid = $3
        RETURNING *`;
      params = [status, progress, taskIdInt];
    } 
    else if (status === 'completed') {
      query = `
        UPDATE taskrequests 
        SET status = $1, 
            endtime = NOW(),
            progress = 1.0
        WHERE taskid = $2
        RETURNING *`;
      params = [status, taskIdInt];
    }
    else {
      query = `
        UPDATE taskrequests 
        SET status = $1,
            progress = COALESCE($2, progress)
        WHERE taskid = $3
        RETURNING *`;
      params = [status, progress, taskIdInt];
    }

    const updateResult = await pool.query(query, params);
    
    res.json({
      success: true,
      task: updateResult.rows[0]
    });
  } catch (error) {
    console.error('Error updating task:', error.message, error.stack);
    res.status(500).json({ 
      error: 'Internal Server Error', 
      details: error.message 
    });
  }
});

// Fetch Completed Tasks
router.get('/completed-tasks', authenticateToken, checkWorkerRole, async (req, res) => {
  try {
    const workerId = parseInt(req.user.userid, 10);
    if (isNaN(workerId)) return res.status(400).json({ error: 'Invalid worker ID in token' });

    const result = await pool.query(
      `SELECT t.taskid, t.reportids, t.endtime,
              json_agg(json_build_object(
                'wastetype', g.wastetype,
                'location', g.location
              )) AS reports
       FROM taskrequests t
       JOIN garbagereports g ON g.reportid = ANY(t.reportids)
       WHERE t.assignedworkerid = $1 AND t.status = 'completed'
       GROUP BY t.taskid, t.reportids, t.endtime
       ORDER BY t.endtime DESC`,
      [workerId]
    );

    const completedTasks = result.rows.map(row => ({
      taskId: row.taskid,
      reportIds: row.reportids,
      endTime: row.endtime.toISOString(),
      reports: row.reports
    }));

    res.json({
      success: true,
      completedTasks,
      count: completedTasks.length
    });
  } catch (error) {
    console.error('Error fetching completed tasks:', error.message, error.stack);
    res.status(500).json({ 
      error: 'Internal Server Error', 
      details: error.message 
    });
  }
});

module.exports = router;