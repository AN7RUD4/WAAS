const express = require('express');
const { Pool } = require('pg'); // Use pg for PostgreSQL
const bcrypt = require('bcryptjs');
const cors = require('cors');
require('dotenv').config();

const bodyParser = require('body-parser');
const multer = require('multer');
const path = require('path');

const app = express();

app.use(express.json());
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

const port = process.env.PORT || 5000;

// Serve uploaded images statically
app.use('/uploads', express.static('uploads'));

// Initialize PostgreSQL pool
const pool = new Pool({
    connectionString: process.env.DATABASE_URL, // Use your PostgreSQL connection string
    ssl: { rejectUnauthorized: false }, // Required for Render or other cloud services
});

// Test database connection
app.get('/test-db', async (req, res) => {
    try {
        const result = await pool.query('SELECT NOW()');
        res.json({ message: 'Database connected!', time: result.rows[0].now });
    } catch (error) {
        console.error('Database connection error:', error);
        res.status(500).json({ error: 'Database connection failed' });
    }
});

// Login endpoint
app.post('/login', async (req, res) => {
    const { email, password } = req.body;

    // Validate input
    if (!email || !password) {
        return res.status(400).json({ message: 'Email and password are required' });
    }

    try {
        const query = 'SELECT * FROM "User" WHERE email = $1';
        const result = await pool.query(query, [email]);

        if (result.rows.length === 0) {
            return res.status(401).json({ message: 'Invalid email or password' });
        }

        const user = result.rows[0];
        const isMatch = await bcrypt.compare(password, user.password);

        if (!isMatch) {
            return res.status(401).json({ message: 'Invalid password' });
        }

        res.status(200).json({
            message: 'Login successful',
            user: { userID: user.userID, name: user.name, email: user.email },
        });
    } catch (error) {
        console.error('Database error:', error);
        res.status(500).json({ message: 'Server error' });
    }
});

// Signup endpoint
app.post('/signup', async (req, res) => {
    console.log('Signup request received:', req.body);

    const { name, email, password } = req.body;

    // Validate input
    if (!email || !password || !name) {
        console.log('Validation failed: Missing fields');
        return res.status(400).json({ message: 'Email and password are required' });
    }

    try {
        // Check if the email already exists
        const checkEmailQuery = 'SELECT * FROM "User" WHERE email = $1';
        const emailCheckResult = await pool.query(checkEmailQuery, [email]);

        if (emailCheckResult.rows.length > 0) {
            console.log('Email already exists:', email);
            return res.status(400).json({ message: 'Email already exists' });
        }

        // Hash the password
        const salt = bcrypt.genSaltSync(10);
        const hashedPassword = bcrypt.hashSync(password, salt);

        // Insert the new user into the database
        const insertUserQuery = 'INSERT INTO "User" (name, email, password) VALUES ($1, $2, $3) RETURNING *';
        const insertResult = await pool.query(insertUserQuery, [name, email, hashedPassword]);

        console.log('User registered successfully:', email);
        res.status(201).json({ message: 'User registered successfully', user: insertResult.rows[0] });
    } catch (error) {
        console.error('Database error:', error);
        res.status(500).json({ message: 'Server error' });
    }
});

// Fetch assigned tasks for a worker
app.get('/worker/assigned-tasks', async (req, res) => {
    const workerId = req.query.workerId;

    // Validate workerId
    if (!workerId) {
        return res.status(400).json({ message: 'workerId is required' });
    }

    try {
        // Query to fetch assigned tasks
        const query = `
            SELECT 
                wt.taskID,
                wt.garbageLocation AS title,
                wt.status,
                t.garbageLocation,
                '5km' AS distance, -- Placeholder; calculate dynamically if needed
                '15min' AS time    -- Placeholder; calculate dynamically if needed
            FROM WorkerTask wt
            JOIN TaskRequest t ON wt.taskID = t.taskID
            WHERE wt.workerID = $1
        `;

        const result = await pool.query(query, [workerId]);

        // Format results
        const assignedWorks = result.rows.map((row) => ({
            title: row.title,
            distance: row.distance,
            time: row.time,
        }));

        res.status(200).json({
            message: 'Assigned tasks retrieved successfully',
            assignedWorks: assignedWorks,
        });
    } catch (error) {
        console.error('Database error:', error);
        res.status(500).json({ message: 'Server error', error: error.message });
    }
});

// Fetch collection requests
app.get('/collectionrequest', async (req, res) => {
    try {
        const query = 'SELECT * FROM collectionrequest';
        const result = await pool.query(query);
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching data:', error);
        res.status(500).send('Error fetching data');
    }
});

// Configure Image Uploads
const storage = multer.diskStorage({
    destination: './uploads/',
    filename: (req, file, cb) => {
        cb(null, file.fieldname + '-' + Date.now() + path.extname(file.originalname));
    },
});

const upload = multer({ storage });

// Update Profile Information
app.put('/updateProfile', async (req, res) => {
    const { userID, name, email } = req.body;

    try {
        const query = 'UPDATE "User" SET name = $1, email = $2 WHERE userID = $3';
        await pool.query(query, [name, email, userID]);
        res.json({ message: 'Profile updated successfully' });
    } catch (error) {
        console.error('Database error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Change Password
app.put('/changePassword', async (req, res) => {
    const { userID, newPassword } = req.body;

    try {
        const hashedPassword = await bcrypt.hash(newPassword, 10);
        const query = 'UPDATE "User" SET password = $1 WHERE userID = $2';
        await pool.query(query, [hashedPassword, userID]);
        res.json({ message: 'Password updated successfully' });
    } catch (error) {
        console.error('Database error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Upload Profile Picture
app.post('/uploadProfilePicture', upload.single('profilePic'), async (req, res) => {
    const { userID } = req.body;
    const profilePicUrl = `http://localhost:3000/uploads/${req.file.filename}`;

    try {
        const query = 'UPDATE "User" SET profile_picture = $1 WHERE userID = $2';
        await pool.query(query, [profilePicUrl, userID]);
        res.json({ message: 'Profile picture updated successfully', profilePicUrl });
    } catch (error) {
        console.error('Database error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Start the server
app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});