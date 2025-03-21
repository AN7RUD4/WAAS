const express = require('express');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const multer = require('multer');

const userRouter = express.Router();

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

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/'),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});
const upload = multer({ storage: storage });

// Bin Fill endpoint (Remove availableTime)
userRouter.post('/bin-fill', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { location } = req.body;
    if (!location) return res.status(400).json({ message: 'Location is required' }); // Removed availableTime validation
    const [lat, long] = location.split(',').map(Number);
    if (isNaN(lat) || isNaN(long)) throw new Error('Invalid location format. Expected: "lat,long"');
    const result = await client.query(
      `INSERT INTO collectionrequests (userid, location, status, datetime) 
       VALUES ($1, ST_GeomFromText('POINT(${long} ${lat})', 4326), $2, NOW()) 
       RETURNING requestid, ST_AsText(location) as location, status`, // Removed availabletime
      [req.user.userid, 'pending']
    );
    await client.query('COMMIT');
    res.status(201).json({
      message: 'Collection request submitted successfully',
      request: {
        id: result.rows[0].requestid,
        location: result.rows[0].location.replace('POINT(', '').replace(')', '') || result.rows[0].location,
        status: result.rows[0].status,
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Collection request error:', error);
    res.status(500).json({ message: error.message || 'Server error submitting collection request' });
  } finally {
    client.release();
  }
});

// Report Waste endpoint (unchanged)
userRouter.post('/report-waste', authenticateToken, upload.single('image'), async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { location } = req.body;
    if (!location || !req.file) return res.status(400).json({ message: 'Location and image are required' });
    const imageUrl = req.file.path;
    const [lat, long] = location.split(',').map(Number);
    if (isNaN(lat) || isNaN(long)) throw new Error('Invalid location format. Expected: "lat,long"');
    const result = await client.query(
      `INSERT INTO garbagereports (userid, location, imageurl, status, datetime) 
       VALUES ($1, ST_GeomFromText('POINT(${long} ${lat})', 4326), $2, $3, NOW()) 
       RETURNING reportid, ST_AsText(location) as location, imageurl`,
      [req.user.userid, imageUrl, 'pending']
    );
    await client.query('COMMIT');
    res.status(201).json({
      message: 'Waste report submitted successfully',
      report: {
        id: result.rows[0].reportid,
        location: result.rows[0].location.replace('POINT(', '').replace(')', '') || result.rows[0].location,
        imageUrl: result.rows[0].imageurl
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Waste report error:', error);
    res.status(500).json({ message: error.message || 'Server error submitting waste report' });
  } finally {
    client.release();
  }
});

// Collection Requests endpoint (Remove availabletime)
userRouter.get('/collection-requests', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const garbageReports = await client.query(
      `SELECT reportid, ST_AsText(location) as location, imageurl, status, datetime 
       FROM garbagereports WHERE userid = $1 ORDER BY datetime DESC`,
      [req.user.userid]
    );
    await client.query('COMMIT');
    res.json({
      garbageReports: garbageReports.rows.map(row => ({
        ...row,
        location: row.location.replace('POINT(', '').replace(')', '') || row.location
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

userRouter.use((req, res) => res.status(404).json({ message: 'Route not found' }));

module.exports = userRouter;