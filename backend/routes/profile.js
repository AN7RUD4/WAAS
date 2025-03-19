const express = require('express');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');

const profileRouter = express.Router();

const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
  ssl: { rejectUnauthorized: false },
});

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) {
    return res.status(401).json({ message: 'Authentication required' });
  }
  jwt.verify(token, process.env.JWT_SECRET || 'passwordKey', (err, user) => {
    if (err) return res.status(403).json({ message: 'Invalid token' });
    req.user = user;
    next();
  });
};

// Get user profile
profileRouter.get('/profile', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const user = await client.query(
      'SELECT userid, name, email FROM users WHERE userid = $1',
      [req.user.userid]
    );
    if (user.rows.length === 0) {
      throw new Error('User not found');
    }
    await client.query('COMMIT');
    res.status(200).json({
      user: {
        userid: user.rows[0].userid,
        name: user.rows[0].name,
        email: user.rows[0].email,
      },
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Profile fetch error:', error.message);
    res.status(500).json({ message: error.message || 'Server error fetching profile' });
  } finally {
    client.release();
  }
});

module.exports = profileRouter;