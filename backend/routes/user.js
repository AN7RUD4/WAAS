const express = require('express');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const multer = require('multer');

// Imports for AI
const tf = process.env.NODE_ENV === 'production' ? require('@tensorflow/tfjs-node') : require('@tensorflow/tfjs');
const mobilenet = require('@tensorflow-models/mobilenet');
const sharp = require('sharp');
const fs = require('fs');

const userRouter = express.Router();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) {
    console.log('Authentication failed: No token provided');
    return res.status(401).json({ message: 'Authentication required' });
  }
  jwt.verify(token, process.env.JWT_SECRET || 'passwordKey', (err, user) => {
    if (err) {
      console.log('Authentication failed: Invalid token', err);
      return res.status(403).json({ message: 'Invalid token' });
    }
    req.user = user;
    console.log('Authenticated user:', user);
    next();
  });
};

// Configure multer with file filter to accept only images
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/'),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});
const fileFilter = (req, file, cb) => {
  const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/bmp'];
  console.log('File MIME type:', file.mimetype); // Log the MIME type
  if (allowedTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type. Only JPEG, PNG, GIF, and BMP are allowed.'), false);
  }
};
const upload = multer({ storage: storage, fileFilter: fileFilter });

// Load MobileNet model at startup
let wasteModel;
(async () => {
  try {
    wasteModel = await mobilenet.load({ version: 2, alpha: 1.0 });
    console.log('MobileNet model loaded for waste detection');
  } catch (error) {
    console.error('Error loading MobileNet:', error);
  }
})();

// Waste detection endpoint
userRouter.post('/detect-waste', authenticateToken, upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      console.log('No image provided in request');
      return res.status(400).json({ error: 'No image provided' });
    }

    if (!wasteModel) {
      console.log('AI model not loaded');
      return res.status(500).json({ error: 'AI model not loaded. Please try again later.' });
    }

    console.log('Uploaded file:', {
      path: req.file.path,
      mimetype: req.file.mimetype,
      size: req.file.size,
    });

    // Read the raw file to verify it exists and is readable
    let rawImageBuffer;
    try {
      rawImageBuffer = fs.readFileSync(req.file.path);
      console.log('Raw file buffer length:', rawImageBuffer.length);
    } catch (readError) {
      console.error('Failed to read uploaded file:', readError);
      return res.status(500).json({ error: 'Failed to read uploaded file', details: readError.message });
    }

    // Preprocess the image to 224x224 (MobileNet requirement)
    // Preprocess the converted image to 224x224
    let imageBuffer;
    if (process.env.NODE_ENV === 'production') {
      imageBuffer = await sharp(convertedPath)
        .resize(224, 224)
        .normalize() // Enhance contrast
        .jpeg()
        .toBuffer();

      console.log('Processed image buffer length:', imageBuffer.length);
    } else {
      imageBuffer = await sharp(convertedPath)
        .resize(224, 224)
        .normalize() // Enhance contrast
        .toFormat('jpeg')
        .raw()
        .toBuffer();

      console.log('Processed image buffer length:', imageBuffer.length);
    }

    // Validate the image buffer
    if (!imageBuffer || imageBuffer.length < 1000) {
      console.error('Image buffer is too small or invalid:', imageBuffer.length);
      return res.status(500).json({ error: 'Processed image buffer is invalid or too small' });
    }

    // Convert to tensor
    let tensor;
    try {
      tensor = tf.node.decodeImage(imageBuffer, 3) // Use tfjs-node to decode JPEG buffer
        .toFloat()
        .div(tf.scalar(255)) // Normalize to [0, 1] range
        .expandDims();
      console.log('Tensor shape:', tensor.shape);

      // Log a sample of the tensor to verify its content
      const tensorSample = tensor.slice([0, 0, 0, 0], [1, 5, 5, 3]).dataSync();
      console.log('Tensor sample (first 5x5 pixels):', Array.from(tensorSample).slice(0, 25));
    } catch (tensorError) {
      console.error('Tensor creation failed:', tensorError);
      return res.status(500).json({ error: 'Failed to create tensor', details: tensorError.message });
    }

    // Predict using MobileNet
    let predictions;
    try {
      predictions = await wasteModel.classify(tensor);
      console.log('Raw predictions:', predictions);
    } catch (predictError) {
      console.error('Prediction failed:', predictError);
      tf.dispose(tensor);
      return res.status(500).json({ error: 'Prediction failed', details: predictError.message });
    }

    tf.dispose(tensor); // Free memory

    // Expanded waste-related labels
    const wasteLabels = [
      'trash', 'plastic', 'bottle', 'cardboard', 'paper', 'waste', 'garbage', 'rubbish',
      'container', 'wrapper', 'can', 'glass', 'metal', 'organic', 'recyclable', 'debris',
      'litter', 'dump', 'scrap', 'refuse', 'bin', 'bag', 'compost', 'pollution', 'junk',
      'box', 'cardboard box', 'plastic bag', 'trash bag', 'heap', 'pile', 'mess', 'clutter',
      'waste material', 'recyclables', 'garbage bag', 'rubble', 'detritus'
    ];

    // Check for waste with a confidence threshold
    const confidenceThreshold = 0.3; // Adjust as needed
    let hasWaste = false;
    let highestWasteConfidence = 0;
    let detectedWasteLabel = null;

    for (const pred of predictions) {
      const classNameLower = pred.className.toLowerCase();
      const isWaste = wasteLabels.some(label => classNameLower.includes(label));
      if (isWaste && pred.probability >= confidenceThreshold) {
        hasWaste = true;
        if (pred.probability > highestWasteConfidence) {
          highestWasteConfidence = pred.probability;
          detectedWasteLabel = pred.className;
        }
      }
    }

    // Log detection result
    if (hasWaste) {
      console.log(`Waste detected: ${detectedWasteLabel} (confidence: ${highestWasteConfidence})`);
    } else {
      console.log('No waste detected. Top predictions:', predictions.slice(0, 5));
    }

    // Clean up uploaded file
    fs.unlink(req.file.path, (err) => {
      if (err) console.error('Failed to delete uploaded file:', err);
    });

    // Respond with detailed result
    res.status(200).json({
      hasWaste: hasWaste,
      confidence: hasWaste ? highestWasteConfidence : null,
      detectedLabel: hasWaste ? detectedWasteLabel : null,
      topPredictions: predictions.slice(0, 5), // Top 5 predictions for debugging
    });
  } catch (error) {
    console.error('Error in /detect-waste:', error.message, error.stack);
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlink(req.file.path, (err) => {
        if (err) console.error('Failed to delete uploaded file on error:', err);
      });
    }
    res.status(500).json({ error: 'Failed to process image', details: error.message });
  }
});

// Bin Fill endpoint
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