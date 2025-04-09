const express = require('express');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const bcryptjs = require('bcryptjs');

const profileRouter = express.Router();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  console.log('Received token:', token);
  if (!token) {
    console.log('No token provided');
    return res.status(401).json({ message: 'Authentication required' });
  }
  jwt.verify(token, process.env.JWT_SECRET || 'passwordKey', (err, user) => {
    if (err) {
      console.log('Token verification failed:', err.message);
      return res.status(403).json({ message: 'Invalid token' });
    }
    console.log('Token verified, user:', user);
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
      'SELECT userid, name, email, address, phone, role FROM users WHERE userid = $1',
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
        address: user.rows[0].address || 'Not provided',
        phone: user.rows[0].phone || 'Not provided',
        role: user.rows[0].role
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

// Update user profile (name, email, address, phone)
profileRouter.put('/profile', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { name, email, address, phone } = req.body;

    // Input validation
    if (!name || !email || !address || !phone) {
      throw new Error('Name, email, address, and phone are required');
    }
    if (!/\S+@\S+\.\S+/.test(email)) {
      throw new Error('Invalid email format');
    }
    // Basic phone validation (e.g., 10-12 digits with optional country code)
    if (!/^\+?[\d]{10,12}$/.test(phone)) {
      throw new Error('Invalid phone number format (e.g., +1234567890 or 1234567890)');
    }

    // Check if the email is already in use by another user
    const emailCheck = await client.query(
      'SELECT * FROM users WHERE email = $1 AND userid != $2',
      [email, req.user.userid]
    );
    if (emailCheck.rows.length > 0) {
      throw new Error('Email already in use by another user');
    }

    // Update the user's name, email, address, and phone
    const updatedUser = await client.query(
      'UPDATE users SET name = $1, email = $2, address = $3, phone = $4 WHERE userid = $5 RETURNING userid, name, email, address, phone, role',
      [name, email, address, phone, req.user.userid]
    );

    if (updatedUser.rows.length === 0) {
      throw new Error('User not found');
    }

    // Generate a new token with the updated user data
    const newToken = jwt.sign(
      {
        userid: updatedUser.rows[0].userid,
        name: updatedUser.rows[0].name,
        email: updatedUser.rows[0].email,
        address: updatedUser.rows[0].address,
        phone: updatedUser.rows[0].phone,
        role: updatedUser.rows[0].role,
      },
      process.env.JWT_SECRET || 'passwordKey',
      { expiresIn: '1h' }
    );

    await client.query('COMMIT');
    res.status(200).json({
      message: 'Profile updated successfully',
      user: {
        userid: updatedUser.rows[0].userid,
        name: updatedUser.rows[0].name,
        email: updatedUser.rows[0].email,
        address: updatedUser.rows[0].address,
        phone: updatedUser.rows[0].phone,
        role: updatedUser.rows[0].role,
      },
      token: newToken,
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Profile update error:', error.message);
    res.status(500).json({ message: error.message || 'Server error updating profile' });
  } finally {
    client.release();
  }
});

// Change user password
profileRouter.put('/change-password', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { newPassword } = req.body;

    // Input validation
    if (!newPassword) {
      throw new Error('New password is required');
    }
    if (newPassword.length < 8 || !/(?=.*[A-Z])(?=.*[0-9])/.test(newPassword)) {
      throw new Error('Password must be at least 8 characters with one uppercase letter and one number');
    }

    // Hash the new password
    const hashedPassword = await bcryptjs.hash(newPassword, 10);

    // Update the user's password
    const updatedUser = await client.query(
      'UPDATE users SET password = $1 WHERE userid = $2 RETURNING userid',
      [hashedPassword, req.user.userid]
    );

    if (updatedUser.rows.length === 0) {
      throw new Error('User not found');
    }

    // Fetch the updated user data to include in the new token
    const userData = await client.query(
      'SELECT userid, name, email, address, phone FROM users WHERE userid = $1',
      [req.user.userid]
    );

    // Generate a new token
    const newToken = jwt.sign(
      {
        userid: userData.rows[0].userid,
        name: userData.rows[0].name,
        email: userData.rows[0].email,
        address: userData.rows[0].address,
        phone: userData.rows[0].phone,
      },
      process.env.JWT_SECRET || 'passwordKey',
      { expiresIn: '1h' }
    );

    await client.query('COMMIT');
    res.status(200).json({
      message: 'Password changed successfully',
      token: newToken,
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Change password error:', error.message);
    res.status(500).json({ message: error.message || 'Server error changing password' });
  } finally {
    client.release();
  }
});

// Add this route to your router file
profileRouter.put('/update-status', authenticateToken, async (req, res) => {
  try {
      const { status } = req.body;
      const { userid } = req.user;
      if (!['available', 'busy'].includes(status)) {
          return res.status(400).json({ error: 'Invalid status value' });
      }
      const result = await pool.query(
          `UPDATE users SET status = $1 WHERE userid = $2 RETURNING status`,
          [status, userid]
      );
      if (result.rowCount === 0) {
          return res.status(404).json({ error: 'User not found' });
      }
      console.log(`User ${userid} status updated to: ${status}`);
      res.status(200).json({ message: `Status updated to: ${status}` });
  } catch (error) {
      console.error('Status update error:', error);
      res.status(500).json({ error: 'Failed to update status', details: error.message });
  }
});

module.exports = profileRouter;