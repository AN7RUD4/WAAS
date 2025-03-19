// routes/waste.js
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
    cb(null, Date.now() + '-' + file.originalname);
  }
});
const upload = multer({ storage: storage });

// Bin Fill Report endpoint (updated to CollectionRequests)
router.post('/bin-fill', authenticateToken, async (req, res) => {
  try {
    const { location, availableTime } = req.body; // Removed fillLevel as it's not in schema
    
    if (!location || !availableTime) {
      return res.status(400).json({ message: 'Location and available time are required' });
    }

    // Convert location to PostGIS point format if it's in lat,long format
    const [lat, long] = location.split(',').map(Number);
    const locationPoint = POINT($long, $lat);

    const result = await pool.query(
      `INSERT INTO collectionrequests 
       (userid, location, status, datetime) 
       VALUES ($1, ST_GeomFromText($2, 4326), $3, NOW()) 
       RETURNING requestID, location, status`,
      [req.userid, locationPoint, 'pending']
    );

    res.status(201).json({
      message: 'Collection request submitted successfully',
      request: {
        id: result.rows[0].requestid,
        location: result.rows[0].location,
        status: result.rows[0].status
      }
    });
  } catch (error) {
    console.error('Collection request error:', error);
    res.status(500).json({ message: 'Server error submitting collection request' });
  }
});

// Public Waste Report endpoint (updated to GarbageReports)
router.post('/report-waste', authenticateToken, upload.single('image'), async (req, res) => {
  try {
    const { location } = req.body;
    
    if (!location || !req.file) {
      return res.status(400).json({ message: 'Location and image are required' });
    }

    const imageUrl = req.file.path;
    const [lat, long] = location.split(',').map(Number);
    const locationPoint = POINT($long , $lat);

    const result = await pool.query(
      `INSERT INTO garbagereports 
       (userid, location, imageUrl, status, dateTime) 
       VALUES ($1, ST_GeomFromText($2, 4326), $3, $4, NOW()) 
       RETURNING reportid, location, imageurl`,
      [req.userid, locationPoint, imageUrl, 'pending']
    );

    res.status(201).json({
      message: 'Waste report submitted successfully',
      report: {
        id: result.rows[0].reportid,
        location: result.rows[0].location,
        imageUrl: result.rows[0].imageurl
      }
    });
  } catch (error) {
    console.error('Waste report error:', error);
    res.status(500).json({ message: 'Server error submitting waste report' });
  }
});

// View Collection Requests endpoint (updated for new schema)
router.get('/collection-requests', authenticateToken, async (req, res) => {
  try {
    const collectionRequests = await pool.query(
      `SELECT requestid, 
              ST_AsText(location) as location, 
              status, 
              dateTime 
       FROM collectionrequests 
       WHERE userid = $1 
       ORDER BY datetime DESC`,
      [req.userid]
    );

    const garbageReports = await pool.query(
      `SELECT reportID, 
              ST_AsText(location) as location, 
              imageUrl, 
              status, 
              dateTime 
       FROM GarbageReports 
       WHERE userID = $1 
       ORDER BY dateTime DESC`,
      [req.user.id]
    );

    res.json({
      collectionRequests: collectionRequests.rows.map(row => ({
        ...row,
        location: row.location.replace('POINT(', '').replace(')', '') // Convert POINT(x y) to "x,y"
      })),
      garbageReports: garbageReports.rows.map(row => ({
        ...row,
        location: row.location.replace('POINT(', '').replace(')', '')
      }))
    });
  } catch (error) {
    console.error('Collection requests error:', error);
    res.status(500).json({ message: 'Server error fetching collection requests' });
  }
});

module.exports=router;
