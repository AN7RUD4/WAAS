require('dotenv').config();
const express = require('express');
const { createClient } = require('@supabase/supabase-js');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

// Supabase Client Setup
const SUPABASE_URL = 'https://your-supabase-url';
const SUPABASE_KEY = 'your-supabase-key';
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

// JWT Secret Key
const JWT_SECRET = 'your_jwt_secret';

/** Worker Signup */
app.post('/worker/signup', async (req, res) => {
    const { name, email, password } = req.body;
    
    const hashedPassword = await bcrypt.hash(password, 10);
    const { data, error } = await supabase.from('Users').insert([{ 
        name, email, password: hashedPassword, role: 'worker', status: 'available'
    }]);
    
    if (error) return res.status(400).json({ error: error.message });
    res.json({ message: 'Worker registered successfully!' });
});

/** Worker Login */
app.post('/worker/login', async (req, res) => {
    const { email, password } = req.body;
    
    const { data: user, error } = await supabase.from('Users').select('*').eq('email', email).single();
    if (error || !user) return res.status(400).json({ error: 'Invalid credentials' });
    
    const isValid = await bcrypt.compare(password, user.password);
    if (!isValid) return res.status(401).json({ error: 'Incorrect password' });
    
    const token = jwt.sign({ userID: user.userID, role: user.role }, JWT_SECRET, { expiresIn: '1d' });
    res.json({ token, workerID: user.userID });
});

/** Get Assigned Tasks */
app.get('/worker/tasks/:workerID', async (req, res) => {
    const { workerID } = req.params;
    
    const { data, error } = await supabase.from('TaskRequests').select('*').eq('assignedWorkerID', workerID);
    if (error) return res.status(400).json({ error: error.message });
    
    res.json({ tasks: data });
});

/** Update Task Status */
app.patch('/worker/task/update', async (req, res) => {
    const { taskID, status } = req.body;
    
    const { data, error } = await supabase.from('TaskRequests').update({ status }).eq('taskID', taskID);
    if (error) return res.status(400).json({ error: error.message });
    
    res.json({ message: 'Task status updated successfully!' });
});

/** Fetch Nearby Reports */
app.get('/worker/reports/nearby', async (req, res) => {
    const { latitude, longitude } = req.query;
    
    const { data, error } = await supabase.rpc('get_nearby_reports', { lat: latitude, lon: longitude });
    if (error) return res.status(400).json({ error: error.message });
    
    res.json({ reports: data });
});

/** Update Live Location */
app.patch('/worker/location/update', async (req, res) => {
    const { workerID, latitude, longitude } = req.body;
    
    const { data, error } = await supabase.from('Users').update({ location: SRID=4326; POINT(${longitude} ${latitude}) }).eq('userID', workerID);
    if (error) return res.status(400).json({ error: error.message });
    
    res.json({ message: 'Location updated successfully!' });
});
