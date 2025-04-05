const express = require('express');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const multer = require('multer');
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const userRouter = express.Router();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

// Authentication middleware
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ message: 'Authentication required' });

  jwt.verify(token, process.env.JWT_SECRET || 'passwordKey', (err, user) => {
    if (err) return res.status(403).json({ message: 'Invalid token' });
    req.user = user;
    next();
  });
};

// Configure storage for uploaded files
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = 'uploads/';
    // Create uploads directory if it doesn't exist
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // Create a unique filename
    cb(null, Date.now() + path.extname(file.originalname));
  }
});

// Initialize multer upload middleware
const upload = multer({ 
  storage: storage,
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB file size limit
  },
  fileFilter: (req, file, cb) => {
    // Accept images only
    if (!file.originalname.match(/\.(jpg|jpeg|png|gif)$/)) {
      return cb(new Error('Only image files are allowed!'), false);
    }
    cb(null, true);
  }
});

// Waste detection endpoint
userRouter.post('/detect-waste', authenticateToken, upload.single('image'), async (req, res) => {
  let filePath;
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image provided' });
    }

    filePath = req.file.path;
    console.log('Processing image:', filePath);

    // Convert image to base64
    const imageBuffer = await sharp(filePath)
      .resize(640, 640) // Resize to common inference size
      .toBuffer();
    const imageBase64 = imageBuffer.toString('base64');

    // Call both Roboflow APIs in parallel
    const [detectionResponse, bgRemovalResponse] = await Promise.all([
      fetch('https://detect.roboflow.com/infer/workflows/anirudh-anilkumar-go0ru/detect-and-classify', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          api_key: process.env.ROBOFLOW_API_KEY,
          inputs: {
            "image": {"type": "base64", "value": imageBase64}
          }
        })
      }),
      fetch('https://detect.roboflow.com/infer/workflows/anirudh-anilkumar-go0ru/background-removal', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          api_key: process.env.ROBOFLOW_API_KEY,
          inputs: {
            "image": {"type": "base64", "value": imageBase64}
          }
        })
      })
    ]);

    if (!detectionResponse.ok || !bgRemovalResponse.ok) {
      throw new Error(`Roboflow API error: ${detectionResponse.statusText || bgRemovalResponse.statusText}`);
    }

    const detectionResult = await detectionResponse.json();
    const bgRemovalResult = await bgRemovalResponse.json();
    console.log('Roboflow responses:', { detectionResult, bgRemovalResult });

    // Process results
    // Process results more robustly
const wasteResult = {
  hasWaste: detectionResult.outputs?.some(output => 
    output.predictions?.some(pred => 
      pred.class === 'waste-waste' && pred.confidence > 0.5
    )
  ),
  predictions: detectionResult.outputs?.[0]?.predictions || [],
  backgroundRemoved: bgRemovalResult.outputs?.[0]?.image || null
};

// Add detailed class information
if (wasteResult.predictions.length > 0) {
  wasteResult.detailedResults = wasteResult.predictions.map(pred => ({
    class: pred.class,
    confidence: pred.confidence,
    box: pred.bbox // if available
  }));
}

    res.json(wasteResult);
  } catch (error) {
    console.error('Detection error:', error);
    res.status(500).json({ error: 'Detection failed', details: error.message });
  } finally {
    // Cleanup uploaded file
    if (filePath) {
      fs.unlink(filePath, (err) => {
        if (err) console.error('Failed to delete uploaded file:', err);
      });
    }
  }
});
//bin Fill endpoint
userRouter.post('/bin-fill', authenticateToken, async (req, res) => {
  try {
    console.log('Received bin-fill request:', req.body);
    const { location, fillLevel } = req.body;
    if (!location) {
      return res.status(400).json({ message: 'Location is required' });
    }
    if (!fillLevel || ![80, 100].includes(Number(fillLevel))) {
      return res.status(400).json({ message: 'Fill level must be 80 or 100' });
    }
    const [lat, long] = location.split(',').map(Number);
    if (isNaN(lat) || isNaN(long)) {
      throw new Error('Invalid location format. Expected: "lat,long"');
    }

    const result = await pool.query(
      `INSERT INTO garbagereports (userid, location, wastetype, comments, datetime) 
       VALUES ($1, ST_GeomFromText('POINT(${long} ${lat})', 4326), $2, $3, NOW()) 
       RETURNING reportid, ST_AsText(location) as location`,
      [req.user.userid, 'home', `Bin fill level: ${fillLevel}%`]
    );

    console.log('Bin fill report submitted:', result.rows[0]);
    res.status(201).json({
      message: 'Bin fill report submitted successfully',
      report: {
        id: result.rows[0].reportid,
        location: result.rows[0].location.replace('POINT(', '').replace(')', ''),
      },
    });
  } catch (error) {
    console.error('Bin fill report error:', error);
    res.status(500).json({ message: error.message || 'Server error submitting bin fill report' });
  }
});

// Report Public Waste endpoint
userRouter.post('/report-waste', authenticateToken, upload.single('image'), async (req, res) => {
  const client = await pool.connect();
  try {
    console.log('Received report-waste request:', req.body);
    await client.query('BEGIN');
    const { location } = req.body;
    if (!location || !req.file) {
      console.log('Validation failed: Location and image are required');
      return res.status(400).json({ message: 'Location and image are required' });
    }
    const imageUrl = req.file.path;
    const [lat, long] = location.split(',').map(Number);
    if (isNaN(lat) || isNaN(long)) {
      throw new Error('Invalid location format. Expected: "lat,long"');
    }
    const result = await client.query(
      `INSERT INTO garbagereports (userid, location, wastetype, imageurl, datetime) 
       VALUES ($1, ST_GeomFromText('POINT(${long} ${lat})', 4326), $2, $3, NOW()) 
       RETURNING reportid, ST_AsText(location) as location, imageurl`,
      [req.user.userid, 'public', imageUrl, 'pending']
    );
    await client.query('COMMIT');
    console.log('Waste report submitted:', result.rows[0]);
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

// Collection Requests endpoint
userRouter.get('/collection-requests', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  try {
    console.log('Fetching collection requests for user:', req.user.userid);
    await client.query('BEGIN');
    const garbageReports = await client.query(
      `SELECT reportid, ST_AsText(location) as location, imageurl, datetime, wastetype, comments 
       FROM garbagereports WHERE userid = $1 ORDER BY datetime DESC`,
      [req.user.userid]
    );
    await client.query('COMMIT');
    console.log('Fetched garbage reports:', garbageReports.rows);
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
