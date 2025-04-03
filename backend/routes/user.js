// const express = require('express');
// const { Pool } = require('pg');
// const jwt = require('jsonwebtoken');
// const multer = require('multer');

// //imports for ai
// const tf = require('@tensorflow/tfjs-node');
// const mobilenet = require('@tensorflow-models/mobilenet');
// const sharp = require('sharp');
// const fs = require('fs');

// const userRouter = express.Router();

// const pool = new Pool({
//   connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
//   ssl: { rejectUnauthorized: false },
// });

// const authenticateToken = (req, res, next) => {
//   const authHeader = req.headers['authorization'];
//   const token = authHeader && authHeader.split(' ')[1];
//   if (!token) {
//     console.log('Authentication failed: No token provided');
//     return res.status(401).json({ message: 'Authentication required' });
//   }
//   jwt.verify(token, process.env.JWT_SECRET || 'passwordKey', (err, user) => {
//     if (err) {
//       console.log('Authentication failed: Invalid token', err);
//       return res.status(403).json({ message: 'Invalid token' });
//     }
//     req.user = user;
//     console.log('Authenticated user:', user);
//     next();
//   });
// };

// const storage = multer.diskStorage({
//   destination: (req, file, cb) => cb(null, 'uploads/'),
//   filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
// });
// const upload = multer({ storage: storage });

// // Load MobileNet model at startup
// let wasteModel;
// (async () => {
//     try {
//         wasteModel = await mobilenet.load({ version: 2, alpha: 1.0 });
//         console.log('MobileNet model loaded for waste detection');
//     } catch (error) {
//         console.error('Error loading MobileNet:', error);
//     }
// })();

// router.post('/detect-waste', authenticateToken, upload.single('image'), async (req, res) => {
//   try {
//       if (!req.file) {
//           return res.status(400).json({ error: 'No image provided' });
//       }

//       // Preprocess the image to 224x224 (MobileNet requirement)
//       const imageBuffer = await sharp(req.file.path)
//           .resize(224, 224)
//           .toFormat('jpeg')
//           .toBuffer();

//       // Convert to tensor
//       const tensor = tf.node.decodeImage(imageBuffer, 3) // 3 channels (RGB)
//           .toFloat()
//           .div(tf.scalar(127.5))
//           .sub(tf.scalar(1)) // Normalize to [-1, 1]
//           .expandDims(); // Add batch dimension

//       // Predict
//       const predictions = await wasteModel.classify(tensor);
//       tf.dispose(tensor); // Free memory

//       // Define waste-related labels
//       const wasteLabels = ['trash', 'plastic', 'bottle', 'cardboard', 'paper', 'waste', 'garbage', 'rubbish'];
//       const hasWaste = predictions.some(pred => 
//           wasteLabels.some(label => pred.className.toLowerCase().includes(label))
//       );

//       // Clean up uploaded file
//       fs.unlinkSync(req.file.path);

//       // Respond with result
//       res.status(200).json({
//           hasWaste: hasWaste,
//           confidence: hasWaste ? predictions[0].probability : null,
//           topPredictions: predictions.slice(0, 3) // For debugging
//       });
//   } catch (error) {
//       console.error('Error in /detect-waste:', error.message, error.stack);
//       res.status(500).json({ error: 'Failed to process image', details: error.message });
//   }
// });

// // Bin Fill endpoint
// userRouter.post('/bin-fill', authenticateToken, async (req, res) => {
//   try {
//     console.log('Received bin-fill request:', req.body);
//     const { location, fillLevel } = req.body;
//     if (!location) {
//       return res.status(400).json({ message: 'Location is required' });
//     }
//     if (!fillLevel || ![80, 100].includes(Number(fillLevel))) {
//       return res.status(400).json({ message: 'Fill level must be 80 or 100' });
//     }
//     const [lat, long] = location.split(',').map(Number);
//     if (isNaN(lat) || isNaN(long)) {
//       throw new Error('Invalid location format. Expected: "lat,long"');
//     }

//     const result = await pool.query(
//       `INSERT INTO garbagereports (userid, location, wastetype, comments, datetime) 
//        VALUES ($1, ST_GeomFromText('POINT(${long} ${lat})', 4326), $2, $3, NOW()) 
//        RETURNING reportid, ST_AsText(location) as location`,
//       [req.user.userid, 'home', `Bin fill level: ${fillLevel}%`]
//     );

//     console.log('Bin fill report submitted:', result.rows[0]);
//     res.status(201).json({
//       message: 'Bin fill report submitted successfully',
//       report: {
//         id: result.rows[0].reportid,
//         location: result.rows[0].location.replace('POINT(', '').replace(')', ''),
//       },
//     });
//   } catch (error) {
//     console.error('Bin fill report error:', error);
//     res.status(500).json({ message: error.message || 'Server error submitting bin fill report' });
//   }
// });

// // Report Public Waste endpoint
// userRouter.post('/report-waste', authenticateToken, upload.single('image'), async (req, res) => {
//   const client = await pool.connect();
//   try {
//     console.log('Received report-waste request:', req.body);
//     await client.query('BEGIN');
//     const { location } = req.body;
//     if (!location || !req.file) {
//       console.log('Validation failed: Location and image are required');
//       return res.status(400).json({ message: 'Location and image are required' });
//     }
//     const imageUrl = req.file.path;
//     const [lat, long] = location.split(',').map(Number);
//     if (isNaN(lat) || isNaN(long)) {
//       throw new Error('Invalid location format. Expected: "lat,long"');
//     }
//     const result = await client.query(
//       `INSERT INTO garbagereports (userid, location, wastetype, imageurl, datetime) 
//        VALUES ($1, ST_GeomFromText('POINT(${long} ${lat})', 4326), $2, $3, NOW()) 
//        RETURNING reportid, ST_AsText(location) as location, imageurl`,
//       [req.user.userid, 'public', imageUrl, 'pending']
//     );
//     await client.query('COMMIT');
//     console.log('Waste report submitted:', result.rows[0]);
//     res.status(201).json({
//       message: 'Waste report submitted successfully',
//       report: {
//         id: result.rows[0].reportid,
//         location: result.rows[0].location.replace('POINT(', '').replace(')', '') || result.rows[0].location,
//         imageUrl: result.rows[0].imageurl
//       }
//     });
//   } catch (error) {
//     await client.query('ROLLBACK');
//     console.error('Waste report error:', error);
//     res.status(500).json({ message: error.message || 'Server error submitting waste report' });
//   } finally {
//     client.release();
//   }
// });

// // Collection Requests endpoint
// userRouter.get('/collection-requests', authenticateToken, async (req, res) => {
//   const client = await pool.connect();
//   try {
//     console.log('Fetching collection requests for user:', req.user.userid);
//     await client.query('BEGIN');
//     const garbageReports = await client.query(
//       `SELECT reportid, ST_AsText(location) as location, imageurl, datetime, wastetype, comments 
//        FROM garbagereports WHERE userid = $1 ORDER BY datetime DESC`,
//       [req.user.userid]
//     );
//     await client.query('COMMIT');
//     console.log('Fetched garbage reports:', garbageReports.rows);
//     res.json({
//       garbageReports: garbageReports.rows.map(row => ({
//         ...row,
//         location: row.location.replace('POINT(', '').replace(')', '') || row.location
//       }))
//     });
//   } catch (error) {
//     await client.query('ROLLBACK');
//     console.error('Collection requests error:', error);
//     res.status(500).json({ message: 'Server error fetching collection requests' });
//   } finally {
//     client.release();
//   }
// });

// userRouter.use((req, res) => res.status(404).json({ message: 'Route not found' }));

// module.exports = userRouter;

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

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, 'uploads/'),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});
const upload = multer({ storage: storage });

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