const express = require('express');
const { Pool } = require('pg');
const jwt = require('jsonwebtoken');
const multer = require('multer');
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
    // 1. Process with sharp consistently
    const { data, info } = await sharp(filePath)
      .resize(224, 224)
      .removeAlpha()
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });

    // 2. Validate buffer
    const expectedLength = 224 * 224 * 3;
    if (data.length !== expectedLength) {
      throw new Error(`Invalid buffer length: ${data.length}, expected ${expectedLength}`);
    }

    // 3. Create normalized tensor
    const pixels = new Float32Array(expectedLength);
    for (let i = 0; i < data.length; i++) {
      pixels[i] = (data[i] / 127.5) - 1.0; // Consistent [-1, 1] normalization
    }

    // 4. Create and verify tensor
    const tensor = tf.tensor4d(pixels, [1, 224, 224, 3]);
    console.log('Tensor shape:', tensor.shape);
    
    return tensor;
  } catch (error) {
    console.error('Image processing failed:', error);
    throw new Error(`Image processing failed: ${error.message}`);
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
  const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/bmp', 'application/octet-stream'];
  console.log('File MIME type:', file.mimetype);
  if (allowedTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type. Only JPEG, PNG, GIF, BMP, and generic binary streams are allowed.'), false);
  }
};

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
    const wasteResult = {
      hasWaste: detectionResult.predictions && detectionResult.predictions.length > 0,
      confidence: detectionResult.predictions?.[0]?.confidence || 0,
      label: detectionResult.predictions?.[0]?.class || '',
      predictions: detectionResult.predictions || [],
      backgroundRemoved: bgRemovalResult?.outputs?.[0]?.image || null // Base64 of bg removed image
    };

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
