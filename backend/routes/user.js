const express = require('express');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const multer = require('multer');
const tf = process.env.NODE_ENV === 'production' ? require('@tensorflow/tfjs-node') : require('@tensorflow/tfjs');
const mobilenet = require('@tensorflow-models/mobilenet');
const sharp = require('sharp');
const fs = require('fs');

const userRouter = express.Router();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

// Image processing function
const processImage = async (filePath) => {
  try {
    // 1. Read and preprocess with sharp
    const { data, info } = await sharp(filePath)
      .resize(224, 224)
      .removeAlpha()
      .ensureAlpha()  // Explicitly ensure 3 channels
      .raw()
      .toBuffer({ resolveWithObject: true });

    // 2. Verify pixel data
    if (data.length !== 224 * 224 * 3) {
      throw new Error(`Invalid buffer length: ${data.length}, expected ${224 * 224 * 3}`);
    }

    // 3. Convert to normalized Float32 array
    const pixels = new Float32Array(224 * 224 * 3);
    for (let i = 0; i < data.length; i++) {
      pixels[i] = data[i] / 255.0;
      // Debug: Check first few pixels
      if (i < 10) console.log(`Pixel ${i}: ${data[i]} → ${pixels[i]}`);
    }

    return tf.tensor4d(pixels, [1, 224, 224, 3]);
  } catch (error) {
    console.error('Image processing failed:', error);
    throw error;
  }
};

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

// Multer configuration
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/'),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});

const fileFilter = (req, file, cb) => {
  const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/bmp'];
  if (allowedTypes.includes(file.mimetype)) cb(null, true);
  else cb(new Error('Invalid file type'), false);
};

const upload = multer({ storage, fileFilter });

// Load MobileNet model
let wasteModel;
(async () => {
  try {
    wasteModel = await mobilenet.load({ version: 2, alpha: 1.0 });
    console.log('MobileNet model loaded');
  } catch (error) {
    console.error('Error loading MobileNet:', error);
  }
})();

// Waste detection endpoint
userRouter.post('/detect-waste', authenticateToken, upload.single('image'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No image provided' });
    if (!wasteModel) return res.status(500).json({ error: 'AI model not loaded' });

    console.log('Processing image:', req.file.path);

    // Process image using the new function
    const tensor = await processImage(req.file.path);
    console.log('Tensor created with shape:', tensor.shape);

    // Verify tensor content
    const tensorData = await tensor.slice([0, 0, 0, 0], [1, 5, 5, 3]).data();
    console.log('Sample tensor values:', Array.from(tensorData).slice(0, 10));

    // Get predictions
    const predictions = await wasteModel.classify(tensor);
    tf.dispose(tensor);
    console.log('Predictions:', predictions);

    // Waste detection logic
    const wasteLabels = [
      'trash', 'plastic', 'bottle', 'cardboard', 'paper', 'waste', 'garbage',
      'rubbish', 'container', 'wrapper', 'can', 'glass', 'metal', 'organic'
    ];

    const wasteResult = predictions.reduce((result, pred) => {
      const isWaste = wasteLabels.some(label =>
        pred.className.toLowerCase().includes(label)
      );

      if (isWaste && pred.probability > (result.confidence || 0)) {
        return {
          hasWaste: true,
          confidence: pred.probability,
          label: pred.className
        };
      }
      return result;
    }, { hasWaste: false });

    // Cleanup
    fs.unlink(req.file.path, () => { });

    res.json({
      ...wasteResult,
      predictions: predictions.slice(0, 5)
    });

  } catch (error) {
    console.error('Detection error:', error);
    if (req.file) fs.unlink(req.file.path, () => { });
    res.status(500).json({ error: 'Detection failed', details: error.message });
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