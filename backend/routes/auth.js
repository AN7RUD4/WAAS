const express = require('express');
const { Pool } = require('pg');
const bcryptjs = require('bcryptjs');
const jwt = require('jsonwebtoken');
const router = express.Router();

const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
  ssl: { rejectUnauthorized: false },
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
    req.user = decoded; // Store decoded user data
    next();
  } catch (err) {
    return res.status(403).json({ message: 'Invalid or expired token' });
  }
};

// Input validation middleware for signup
const validateSignup = (req, res, next) => {
  const { name, email, password } = req.body;
  if (!name || !email || !password) {
    return res.status(400).json({ message: 'All fields are required' });
  }
  if (!/\S+@\S+\.\S+/.test(email)) {
    return res.status(400).json({ message: 'Invalid email format' });
  }
  if (password.length < 8 || !/(?=.*[A-Z])(?=.*[0-9])/.test(password)) {
    return res.status(400).json({ message: 'Password must be at least 8 characters with one uppercase and one number' });
  }
  next();
};

// Input validation middleware for login
const validateLogin = (req, res, next) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ message: 'Email and password are required' });
  }
  if (!/\S+@\S+\.\S+/.test(email)) {
    return res.status(400).json({ message: 'Invalid email format' });
  }
  next();
};

// Signup endpoint
router.post('/signup', validateSignup, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { name, email, password } = req.body;

    // Check if user exists
    const existingUser = await client.query(
      'SELECT * FROM users WHERE email = $1',
      [email]
    );

    if (existingUser.rows.length > 0) {
      throw new Error('Email already exists');
    }

    const hashedPassword = await bcryptjs.hash(password, 10);

    const newUser = await client.query(
      'INSERT INTO users (name, email, password, role) VALUES ($1, $2, $3, $4) RETURNING userID, name, email',
      [name, email, hashedPassword, 'user']
    );

    await client.query('COMMIT');

    res.status(201).json({
      message: 'User created successfully',
      user: {
        userID: newUser.rows[0].userID,
        name: newUser.rows[0].name,
        email: newUser.rows[0].email
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Signup error:', error.message);
    res.status(500).json({ message: error.message || 'Server error during signup' });
  } finally {
    client.release();
  }
});

// Login endpoint
router.post('/login', validateLogin, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { email, password } = req.body;

    const userResult = await client.query(
      'SELECT userID, name, email, password FROM users WHERE email = $1',
      [email]
    );

    if (userResult.rows.length === 0) {
      throw new Error('Invalid credentials');
    }

    const user = userResult.rows[0];
    const isMatch = await bcryptjs.compare(password, user.password);
    if (!isMatch) {
      throw new Error('Invalid credentials');
    }

    const token = jwt.sign(
      { userID: user.userID, email: user.email }, // Use userID instead of id
      process.env.JWT_SECRET || 'passwordKey',
      { expiresIn: '1h' }
    );

    await client.query('COMMIT');

    res.json({
      message: 'Login successful',
      token,
      user: {
        userID: user.userID,
        name: user.name,
        email: user.email
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Login error:', error.message);
    res.status(400).json({ message: error.message || 'Server error during login' });
  } finally {
    client.release();
  }
});

// Profile endpoint (protected by JWT)
router.get('/profile/:userID', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { userID } = req.params;
    const user = await client.query(
      'SELECT userID, name, email FROM users WHERE userID = $1',
      [userID]
    );

    if (user.rows.length === 0) {
      throw new Error('User not found');
    }

    await client.query('COMMIT');

    res.status(200).json({
      user: {
        userID: user.rows[0].userID,
        name: user.rows[0].name,
        email: user.rows[0].email
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Profile fetch error:', error.message);
    res.status(500).json({ message: error.message || 'Server error fetching profile' });
  } finally {
    client.release();
  }
});

// Add CORS configuration
router.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*'); // Adjust for production (e.g., specific origin)
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  next();
});

module.exports = router;