require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');

const router = express.Router();
router.use(cors());
router.use(express.json());

// Database connection (aligned with auth.js)
const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
  ssl: { rejectUnauthorized: false },
});

// Test database connection on startup
pool.connect((err, client, release) => {
  if (err) {
    console.error('Error connecting to the database in worker.js:', err.stack);
    process.exit(1); // Exit the process if the database connection fails
  } else {
    console.log('Worker.js successfully connected to the database');
    release();
  }
});

// Middleware to verify JWT token (from auth.js)
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
    req.user = decoded; // Attach decoded token data (userid, email, role) to req.user
    next();
  } catch (err) {
    console.error('Token verification error in worker.js:', err.message);
    return res.status(403).json({ message: 'Invalid or expired token' });
  }
};

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
    const workerId = parseInt(req.user.userid, 10); // Use userid from JWT token
    if (isNaN(workerId)) {
      return res.status(400).json({ error: 'Invalid worker ID in token' });
    }

    const result = await pool.query(
      `SELECT t.taskid, g.wastetype, g.location, t.status, t.progress 
       FROM taskrequests t 
       JOIN garbagereports g ON t.reportid = g.reportid 
       WHERE t.assignedworkerid = $1 AND t.status != 'completed'`,
      [workerId]
    );

    // Format the response to include task details
    const assignedWorks = result.rows.map(row => ({
      taskId: row.taskid.toString(),
      title: row.wastetype,
      location: row.location, // Note: This is a geography type; frontend may need to parse it
      status: row.status,
      progress: row.progress,
    }));

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

    // Ensure the task belongs to the worker
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

    // Validate progress and status
    const progressFloat = parseFloat(progress);
    if (isNaN(progressFloat) || progressFloat < 0 || progressFloat > 1) {
      return res.status(400).json({ error: 'Progress must be a number between 0 and 1' });
    }

    const validStatuses = ['pending', 'assigned', 'in-progress', 'completed', 'failed'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
    }

    // Ensure the task belongs to the worker
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

// ... (existing imports and code from worker.js)

router.get('/task-route/:taskid', authenticateToken, checkWorkerRole, async (req, res) => {
  const taskId = parseInt(req.params.taskid, 10);
  const workerId = req.user.userid; // From JWT token

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

    // Parse the route from the jsonb field
    const routeData = task.route || { start: {}, end: {}, waypoints: [] };
    const routePoints = [];

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

    // Parse the report location (from garbagereports)
    const reportLocation = task.report_location;
    const locationMatch = reportLocation.match(/POINT\(([^ ]+) ([^)]+)\)/);
    const collectionPoint = locationMatch
      ? {
          lat: parseFloat(locationMatch[2]), // Latitude
          lng: parseFloat(locationMatch[1]), // Longitude
        }
      : null;

    res.status(200).json({
      taskid: task.taskid,
      reportid: task.reportid,
      status: task.status,
      route: routePoints,
      locations: collectionPoint ? [collectionPoint] : [],
      wastetype: task.wastetype,
    });
  } catch (error) {
    console.error('Error fetching task route:', error.message, error.stack);
    res.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

module.exports = router;