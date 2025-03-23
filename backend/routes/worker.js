require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT,
});

// Fetch Assigned Tasks for Worker
app.get('/worker/assigned-tasks', async (req, res) => {
  try {
    const { workerId } = req.query;
    if (!workerId) return res.status(400).json({ error: 'Worker ID is required' });

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
      title: row.wastetype, // Use wastetype as the title
      location: row.location, // This will be used to calculate distance/time on the frontend or map
      status: row.status,
      progress: row.progress,
    }));

    res.json({ assignedWorks });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

// Fetch Task Route for Map (used by pickup_map.dart)
app.get('/task/route', async (req, res) => {
  try {
    const { taskId } = req.query;
    if (!taskId) return res.status(400).json({ error: 'Task ID is required' });

    const result = await pool.query(
      `SELECT route 
       FROM taskrequests 
       WHERE taskid = $1`,
      [taskId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Task not found' });
    }

    const route = result.rows[0].route;
    if (!route) {
      return res.status(404).json({ error: 'No route data available for this task' });
    }

    // Assuming map.js calculates the shortest path and returns it
    // For now, we'll return the raw route data (start, end, waypoints)
    res.json({ route });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

// Update Task Progress
app.patch('/worker/update-progress', async (req, res) => {
  try {
    const { taskId, progress, status } = req.body;
    if (!taskId || progress === undefined || !status) {
      return res.status(400).json({ error: 'Task ID, progress, and status are required' });
    }

    await pool.query(
      'UPDATE taskrequests SET progress = $1, status = $2 WHERE taskid = $3',
      [progress, status, taskId]
    );

    res.json({ message: 'Task updated successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});

// Fetch Completed Tasks
app.get('/worker/completed-tasks', async (req, res) => {
  try {
    const { workerId } = req.query;
    if (!workerId) return res.status(400).json({ error: 'Worker ID is required' });

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
      endTime: row.endtime,
    }));

    res.json({ completedWorks });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
});
