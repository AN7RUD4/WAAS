const express = require('express');
const mysql = require('mysql2');
const bcrypt = require('bcryptjs');
const cors = require('cors');
require('dotenv').config();

const bodyParser = require("body-parser");
const multer = require("multer");
const path = require("path");

const app = express();

app.use(express.json());
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

const { Pool } = require('pg');
const port = process.env.PORT || 5000;

// Serve uploaded images statically
app.use("/uploads", express.static("uploads"));


const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }  
});


app.get('/test-db', async (req, res) => {
    try {
        const result = await pool.query('SELECT NOW()');
        res.json({ message: 'Database connected!', time: result.rows[0].now });
    } catch (error) {
        console.error('Database connection error:', error);
        res.status(500).json({ error: 'Database connection failed' });
    }
});


app.post('/login', (req, res) => {
    const { email, password } = req.body;

    // Validate input
    if (!email || !password) {
        return res.status(400).json({ message: 'Email and password are required' });
    }

    const query = 'SELECT * FROM User WHERE email = ?';
    db.query(query, [email], (err, results) => {
        if (err) {
            console.error('Database error:', err);
            return res.status(500).json({ message: 'Server error' });
        }

        if (results.length === 0) {
            return res.status(401).json({ message: 'Invalid email or password' });
        }

        const user = results[0];

        bcrypt.compare(password, user.password, (err, isMatch) => {
            if (err) {
                console.error('Bcrypt error:', err);
                return res.status(500).json({ message: 'Server error' });
            }

            if (!isMatch) {
                return res.status(401).json({ message: 'Invalid password' });
            }

            res.status(200).json({
                message: 'Login successful',
                user: { userID: user.userID, name: user.name, email: user.email }
            });
        });
    });
});

// Signup endpoint
app.post('/signup', (req, res) => {
    const { name, email, password } = req.body;

    // Validate input
    if (!email || !password || !name) {
        return res.status(400).json({ message: 'Email and password are required' });
    }

    // Check if the email already exists
    const checkEmailQuery = 'SELECT * FROM User WHERE email = ?';
    db.query(checkEmailQuery, [email], (err, results) => {
        if (err) {
            console.error('Database error:', err);
            return res.status(500).json({ message: 'Server error' });
        }

        if (results.length > 0) {
            return res.status(400).json({ message: 'Email already exists' });
        }

        // Hash the password
        const salt = bcrypt.genSaltSync(10);
        const hashedPassword = bcrypt.hashSync(password, salt);

        // Insert the new user into the database
        const insertUserQuery = 'INSERT INTO User (name, email, password) VALUES (?, ?, ?)';
        db.query(insertUserQuery, [name, email, hashedPassword], (err, results) => {
            if (err) {
                console.error('Database error:', err);
                return res.status(500).json({ message: 'Server error' });
            }

            res.status(201).json({ message: 'User registered successfully' });
        });
    });
});

// Fetch assigned tasks for a worker
app.get('/worker/assigned-tasks', (req, res) => {
    const workerId = req.query.workerId;

    // Validate workerId
    if (!workerId) {
        return res.status(400).json({ message: 'workerId is required' });
    }

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
        WHERE wt.workerID = ?
    `;

    db.query(query, [workerId], (err, results) => {
        if (err) {
            console.error('Database error:', err);
            return res.status(500).json({ message: 'Server error', error: err.message });
        }

        // Format results
        const assignedWorks = results.map(row => ({
            title: row.title,
            distance: row.distance,
            time: row.time
        }));

        res.status(200).json({
            message: 'Assigned tasks retrieved successfully',
            assignedWorks: assignedWorks
        });
    });
});

app.get('/collectionrequest', (req, res) => {
    const query = 'SELECT * FROM collectionrequest';
    db.query(query, (err, results) => {
      if (err) {
        console.error('Error fetching data:', err);
        res.status(500).send('Error fetching data');
        return;
      }
      res.json(results);
    });
});

//PROFILE
// Configure Image Uploads
const storage = multer.diskStorage({
  destination: "./uploads/",
  filename: (req, file, cb) => {
    cb(null, file.fieldname + "-" + Date.now() + path.extname(file.originalname));
  },
});

const upload = multer({ storage });

// Update Profile Information
app.put("/updateProfile", (req, res) => {
  const { userID, name, email } = req.body;
  const sql = "UPDATE User SET name=?, email=? WHERE userID=?";
  db.query(sql, [name, email, userID], (err, result) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ message: "Profile updated successfully" });
  });
});

// Change Password
app.put("/changePassword", async (req, res) => {
  const { userID, newPassword } = req.body;
  const hashedPassword = await bcrypt.hash(newPassword, 10);
  const sql = "UPDATE User SET password=? WHERE userID=?";
  db.query(sql, [hashedPassword, userID], (err, result) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ message: "Password updated successfully" });
  });
});

// Upload Profile Picture
app.post("/uploadProfilePicture", upload.single("profilePic"), (req, res) => {
  const { userID } = req.body;
  const profilePicUrl = 'http://localhost:3000/uploads/${req.file.filename}';

  const sql = "UPDATE User SET profile_picture=? WHERE userID=?";
  db.query(sql, [profilePicUrl, userID], (err, result) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ message: "Profile picture updated successfully", profilePicUrl });
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
