// routes/auth.js
const express = require('express');
const { Pool } = require('pg');
const bcryptjs = require('bcryptjs');
const jwt = require('jsonwebtoken');
const router = express.Router();

// Database configuration (Updated to WasteManagementDB)
const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/WasteManagementDB',
  ssl: { rejectUnauthorized: false },
});

// Input validation middleware
const validateSignup = (req, res, next) => {
  const { name, email, password } = req.body;
  if (!name || !email || !password) {
    return res.status(400).json({ message: 'All fields are required' });
  }
  if (!/\S+@\S+\.\S+/.test(email)) {
    return res.status(400).json({ message: 'Invalid email format' });
  }
  next();
};

// Signup endpoint
router.post('/signup', validateSignup, async (req, res) => {
  try {
    const { name, email, password } = req.body;

    // Check if user exists
    const existingUser = await pool.query(
      'SELECT * FROM users WHERE email = $1',
      [email]
    );

    if (existingUser.rows.length > 0) {
      return res.status(400).json({ message: 'Email already exists' });
    }

    // Hash password
    const hashedPassword = await bcryptjs.hash(password, 10);

    // Insert new user (role is required, set to 'user'; location and status are optional)
    const newUser = await pool.query(
      'INSERT INTO users (name, email, password, role) VALUES ($1, $2, $3, $4) RETURNING userID, name, email',
      [name, email, hashedPassword, 'user'] // Default role as 'user'
    );

    res.status(201).json({
      message: 'User created successfully',
      user: {
        id: newUser.rows[0].userID, // Use userID instead of id
        name: newUser.rows[0].name,
        email: newUser.rows[0].email
      }
    });
  } catch (error) {
    console.error('Signup error:', error);
    res.status(500).json({ message: 'Server error during signup' });
  }
});

// Login endpoint
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    const user = await pool.query(
      'SELECT * FROM users WHERE email = $1',
      [email]
    );

    if (user.rows.length === 0) {
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    const isMatch = await bcryptjs.compare(password, user.rows[0].password);
    if (!isMatch) {
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { id: user.rows[0].userID }, // Use userID instead of id
      process.env.JWT_SECRET || 'passwordKey',
      { expiresIn: '1h' }
    );
    res.json({
      token,
      user: {
        id: user.rows[0].userID, // Use userID
        name: user.rows[0].name,
        email: user.rows[0].email
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ message: 'Server error during login' });
  }
});

module.exports = router;