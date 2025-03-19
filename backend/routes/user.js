const express = require('express');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const router = express.Router();
const multer = require('multer');

// Database configuration
const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
  ssl: { rejectUnauthorized: false },
});

// Middleware to verify JWT token
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) {
    return res.status(401).json({ message: 'Authentication required' });
  }

  jwt.verify(token, process.env.JWT_SECRET || 'passwordKey', (err, user) => {
    if (err) {
      return res.status(403).json({ message: 'Invalid token' });
    }
    req.user = user;
    next();
  });
};

// Configure multer for image uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, 'uploads/');
  },
  filename: (req, file, cb) => {
    cb(null, `${Date.now()}-${file.originalname}`);
  },
});
const upload = multer({ storage: storage });

// Bin Fill Report endpoint (updated to CollectionRequests)
router.post('/bin-fill', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { location, availableTime } = req.body;
    if (!location || !availableTime) {
      return res.status(400).json({ message: 'Location and available time are required' });
    }

    // Convert location to PostGIS point format
    const [lat, long] = location.split(',').map(Number);
    if (isNaN(lat) || isNaN(long)) {
      throw new Error('Invalid location format. Expected: "lat,long"');
    }

    const result = await client.query(
      `INSERT INTO collectionrequests 
       (userid, location, status, datetime, availabletime) 
       VALUES ($1, ST_GeomFromText('POINT(${long} ${lat})', 4326), $2, NOW(), $3) 
       RETURNING requestid, ST_AsText(location) as location, status, availabletime`,
      [req.user.userid, 'pending', availableTime]
    );

    await client.query('COMMIT');

    res.status(201).json({
      message: 'Collection request submitted successfully',
      request: {
        id: result.rows[0].requestid,
        location: result.rows[0].location.replace('POINT(', '').replace(')', ''),
        status: result.rows[0].status,
        availableTime: result.rows[0].availabletime
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Collection request error:', error);
    res.status(500).json({ message: 'Server error submitting collection request' });
  } finally {
    client.release();
  }
});

// Public Waste Report endpoint (updated to GarbageReports)
router.post('/report-waste', authenticateToken, upload.single('image'), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { location } = req.body;
    if (!location || !req.file) {
      return res.status(400).json({ message: 'Location and image are required' });
    }

    const imageUrl = req.file.path;
    const [lat, long] = location.split(',').map(Number);
    if (isNaN(lat) || isNaN(long)) {
      throw new Error('Invalid location format. Expected: "lat,long"');
    }

    const result = await client.query(
      `INSERT INTO garbagereports 
       (userid, location, imageurl, status, datetime) 
       VALUES ($1, ST_GeomFromText('POINT(${long} ${lat})', 4326), $2, $3, NOW()) 
       RETURNING reportid, ST_AsText(location) as location, imageurl`,
      [req.user.userid, imageUrl, 'pending']
    );

    await client.query('COMMIT');

    res.status(201).json({
      message: 'Waste report submitted successfully',
      report: {
        id: result.rows[0].reportid,
        location: result.rows[0].location.replace('POINT(', '').replace(')', ''),
        imageUrl: result.rows[0].imageurl
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Waste report error:', error);
    res.status(500).json({ message: 'Server error submitting waste report' });
  } finally {
    client.release();
  }
});

// View Collection Requests endpoint (updated for new schema)
router.get('/collection-requests', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const collectionRequests = await client.query(
      `SELECT requestid, 
              ST_AsText(location) as location, 
              status, 
              datetime,
              availabletime 
       FROM collectionrequests 
       WHERE userid = $1 
       ORDER BY datetime DESC`,
      [req.user.userid]
    );

    const garbageReports = await client.query(
      `SELECT reportid, 
              ST_AsText(location) as location, 
              imageurl, 
              status, 
              datetime 
       FROM garbagereports 
       WHERE userid = $1 
       ORDER BY datetime DESC`,
      [req.user.userid]
    );

    await client.query('COMMIT');

    res.json({
      collectionRequests: collectionRequests.rows.map(row => ({
        ...row,
        location: row.location.replace('POINT(', '').replace(')', '')
      })),
      garbageReports: garbageReports.rows.map(row => ({
        ...row,
        location: row.location.replace('POINT(', '').replace(')', '')
      }))
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Collection requests error:', error);
    res.status(500).json({ message: 'Server error fetching collection requests' });
  } finally {
    client.release();
  }
});

// CORS configuration
router.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  next();
});

module.exports = router;