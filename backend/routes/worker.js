require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

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

        res.json({ assignedWorks: result.rows });
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

        res.json({ completedWorks: result.rows });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: 'Internal Server Error' });
    }
});