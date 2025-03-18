const express = require('express');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const router = express.Router();

// Database configuration
const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
  ssl: { rejectUnauthorized: false },
});

// Middleware to verify JWT token
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer <token>

  if (!token) {
    return res.status(401).json({ message: 'Authentication token required' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded; // Store decoded user data in request
    next();
  } catch (err) {
    return res.status(403).json({ message: 'Invalid or expired token' });
  }
};

// Input validation middleware for profile update
const validateProfileUpdate = (req, res, next) => {
  const { name, email } = req.body;

  if (!name || name.trim().length < 2) {
    return res.status(400).json({ message: 'Name must be at least 2 characters long' });
  }

  if (!email || !/\S+@\S+\.\S+/.test(email)) {
    return res.status(400).json({ message: 'Invalid email format' });
  }

  next();
};

// Input validation middleware for password change
const validatePasswordChange = (req, res, next) => {
  const { newPassword } = req.body;

  if (!newPassword || newPassword.length < 8) {
    return res.status(400).json({ message: 'Password must be at least 8 characters long' });
  }

  if (!/[A-Z]/.test(newPassword) || !/[0-9]/.test(newPassword)) {
    return res.status(400).json({ message: 'Password must contain at least one uppercase letter and one number' });
  }

  next();
};

// Update Name and Email
router.put('/updateProfile', authenticateToken, validateProfileUpdate, async (req, res) => {
  const client = await pool.connect();
  try {
    const { name, email } = req.body;
    const userID = req.user.id; // From JWT token

    await client.query('BEGIN'); // Start transaction

    // Check if email is already taken by another user
    const emailCheck = await client.query(
      'SELECT userID FROM users WHERE email = $1 AND userid != $2',
      [email, userID]
    );
    if (emailCheck.rows.length > 0) {
      throw new Error('Email already in use by another user');
    }

    const query = 'UPDATE users SET name = $1, email = $2 WHERE userid = $3 RETURNING userid, name, email';
    const result = await client.query(query, [name, email, userID]);

    if (result.rows.length === 0) {
      throw new Error('User not found');
    }

    await client.query('COMMIT'); // Commit transaction

    res.status(200).json({
      message: 'Profile updated successfully',
      user: {
        id: result.rows[0].userID,
        name: result.rows[0].name,
        email: result.rows[0].email,
      },
    });
  } catch (err) {
    await client.query('ROLLBACK'); // Rollback on error
    console.error('Error updating profile:', err);
    res.status(500).json({ message: err.message || 'Server error updating profile' });
  } finally {
    client.release();
  }
});

// Update Password
router.put('/changePassword', authenticateToken, validatePasswordChange, async (req, res) => {
  const client = await pool.connect();
  try {
    const { newPassword } = req.body;
    const userID = req.user.id; // From JWT token

    await client.query('BEGIN'); // Start transaction

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    const query = 'UPDATE users SET password = $1 WHERE userid = $2 RETURNING userid';
    const result = await client.query(query, [hashedPassword, userID]);

    if (result.rows.length === 0) {
      throw new Error('User not found');
    }

    await client.query('COMMIT'); // Commit transaction

    res.status(200).json({ message: 'Password updated successfully' });
  } catch (err) {
    await client.query('ROLLBACK'); // Rollback on error
    console.error('Error updating password:', err);
    res.status(500).json({ message: err.message || 'Server error updating password' });
  } finally {
    client.release();
  }
});

module.exports = router;