const express = require('express');
const { Pool } = require('pg');
const multer = require('multer');
const { createClient } = require('@supabase/supabase-js');

const collectionRequestRouter = express.Router();

// Initialize Supabase client for image storage
const supabase = createClient(
  'https://hrzroqrgkvzhomsosqzl.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhyenJvcXJna3Z6aG9tc29zcXpsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE5MjQ0NDQsImV4cCI6MjA1NzUwMDQ0NH0.qBDNsN0DvMKZ8JBAmoh2DsN8WW74uj2hZZuG_-gxF4g' // Replace with your Supabase anon key
);

// Configure PostgreSQL connection
const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/WasteManagementDB',
  ssl: { rejectUnauthorized: false },
});

// Configure multer for image uploads
const storage = multer.memoryStorage();
const upload = multer({ storage: storage });

// Utility function to calculate distance between two points using the Haversine formula
function calculateDistance(point1, point2) {
  const R = 6371; // Earth's radius in km
  const dLat = ((point2.lat - point1.lat) * Math.PI) / 180;
  const dLon = ((point2.lng - point1.lng) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((point1.lat * Math.PI) / 180) *
      Math.cos((point2.lat * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distance in km
}

// Utility function to parse GEOGRAPHY POINT data from PostgreSQL
function parseGeographyPoint(point) {
  if (!point) return null;
  const matches = point.match(/POINT\(([^ ]+) ([^)]+)\)/);
  if (!matches) return null;
  return {
    lng: parseFloat(matches[1]),
    lat: parseFloat(matches[2]),
  };
}

// Compute shortest route using a nearest-neighbor algorithm
function computeShortestRoute(locations, workerLocation) {
  const route = [{ id: 0, lat: workerLocation.lat, lng: workerLocation.lng }];
  const unvisited = locations.map(loc => ({ ...loc }));
  let currentPos = { lat: workerLocation.lat, lng: workerLocation.lng };

  while (unvisited.length > 0) {
    let nearestIdx = 0;
    let minDistance = calculateDistance(currentPos, unvisited[0].location);

    for (let i = 1; i < unvisited.length; i++) {
      const distance = calculateDistance(currentPos, unvisited[i].location);
      if (distance < minDistance) {
        minDistance = distance;
        nearestIdx = i;
      }
    }

    const nearest = unvisited.splice(nearestIdx, 1)[0];
    route.push({
      id: nearest.id,
      lat: nearest.location.lat,
      lng: nearest.location.lng,
    });
    currentPos = nearest.location;
  }

  return route;
}

// POST /report - Submit a new waste report
collectionRequestRouter.post('/report', upload.single('image'), async (req, res) => {
  const { userId, latitude, longitude, wasteType } = req.body;
  const image = req.file;

  if (!userId || !latitude || !longitude || !wasteType) {
    return res.status(400).json({ message: 'User ID, latitude, longitude, and waste type are required' });
  }

  if (wasteType === 'public' && !image) {
    return res.status(400).json({ message: 'Image is required for public waste reports' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    let imageUrl = null;
    if (image) {
      const { data, error } = await supabase.storage
        .from('waste-images')
        .upload(`public/${Date.now()}_${image.originalname}`, image.buffer, {
          contentType: image.mimetype,
        });

      if (error) throw new Error('Failed to upload image to Supabase Storage: ' + error.message);

      const { data: publicUrlData } = supabase.storage
        .from('waste-images')
        .getPublicUrl(data.path);
      imageUrl = publicUrlData.publicUrl;
    }

    const initialStatus = wasteType === 'public' ? 'awaiting_approval' : 'pending';

    const reportResult = await client.query(
      'INSERT INTO GarbageReports (userID, location, wasteType, imageUrl, status) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326), $4, $5, $6) RETURNING reportID',
      [userId, longitude, latitude, wasteType, imageUrl, initialStatus]
    );

    const reportId = reportResult.rows[0].reportID;

    if (wasteType === 'public') {
      const officialResult = await client.query('SELECT userID FROM Users WHERE role = $1 LIMIT 1', ['official']);
      if (officialResult.rows.length === 0) {
        throw new Error('No public official found to assign the report');
      }
      const officialId = officialResult.rows[0].userID;

      await client.query(
        'INSERT INTO PublicOfficialApprovals (reportID, officialID, status) VALUES ($1, $2, $3)',
        [reportId, officialId, 'pending']
      );
    }

    await client.query('COMMIT');
    res.status(201).json({ message: 'Waste report submitted successfully', reportId });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error submitting waste report:', error.message);
    res.status(500).json({ message: error.message || 'Server error submitting waste report' });
  } finally {
    client.release();
  }
});

// POST /worker/update-location - Update worker's location and calculate route progress
collectionRequestRouter.post('/worker/update-location', async (req, res) => {
  const { workerId, latitude, longitude } = req.body;
  if (!workerId || !latitude || !longitude) {
    return res.status(400).json({ message: 'Worker ID, latitude, and longitude are required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Update worker's location
    await client.query(
      'UPDATE Users SET location = ST_SetSRID(ST_MakePoint($1, $2), 4326) WHERE userID = $3 AND role = $4',
      [longitude, latitude, workerId, 'worker']
    );

    // Fetch tasks assigned to the worker
    const tasksResult = await client.query(`
      SELECT taskID, route, reportID
      FROM TaskRequests
      WHERE assignedWorkerID = $1 AND status = $2
    `, [workerId, 'in-progress']);

    const workerLocation = { lat: latitude, lng: longitude };

    for (const task of tasksResult.rows) {
      const route = task.route || [];
      if (route.length < 2) continue;

      // Calculate total route distance
      let totalDistance = 0;
      for (let i = 0; i < route.length - 1; i++) {
        totalDistance += calculateDistance(route[i], route[i + 1]);
      }

      // Find the closest point on the route to the worker's current location
      let closestPointIndex = 0;
      let minDistance = Infinity;
      for (let i = 0; i < route.length; i++) {
        const distance = calculateDistance(workerLocation, route[i]);
        if (distance < minDistance) {
          minDistance = distance;
          closestPointIndex = i;
        }
      }

      // Calculate distance traveled along the route up to the closest point
      let distanceTraveled = 0;
      for (let i = 0; i < closestPointIndex; i++) {
        distanceTraveled += calculateDistance(route[i], route[i + 1]);
      }
      // Add the distance from the closest point to the worker's current location
      distanceTraveled += minDistance;

      // Calculate progress as a percentage of the total route distance
      const progress = totalDistance > 0
        ? (distanceTraveled / totalDistance) * 100
        : 0;

      await client.query(
        'UPDATE TaskRequests SET progress = $1 WHERE taskID = $2',
        [Math.min(Math.max(progress, 0), 100), task.taskID]
      );
    }

    await client.query('COMMIT');
    res.status(200).json({ message: 'Location and progress updated' });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error updating worker location:', error.message);
    res.status(500).json({ message: error.message || 'Server error updating worker location' });
  } finally {
    client.release();
  }
});

// GET /worker/reports - Fetch garbage reports assigned to a worker
collectionRequestRouter.get('/worker/reports', async (req, res) => {
  const workerId = req.query.workerId;
  if (!workerId) {
    return res.status(400).json({ message: 'Worker ID is required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const workerResult = await client.query('SELECT location FROM Users WHERE userID = $1 AND role = $2', [workerId, 'worker']);
    if (workerResult.rows.length === 0) {
      throw new Error('Worker not found');
    }
    if (!workerResult.rows[0].location) {
      throw new Error('Worker location not set. Please update your location.');
    }
    const workerLocation = parseGeographyPoint(workerResult.rows[0].location);

    const reportsResult = await client.query(`
      SELECT gr.reportID, gr.location, gr.wasteType, gr.imageUrl, gr.status, tr.taskID
      FROM GarbageReports gr
      LEFT JOIN TaskRequests tr ON gr.reportID = tr.reportID
      WHERE tr.assignedWorkerID = $1 AND gr.status IN ('pending', 'assigned')
    `, [workerId]);

    if (reportsResult.rows.length === 0) {
      return res.status(200).json({ message: 'No reports assigned to this worker', locations: [], route: [] });
    }

    const locations = reportsResult.rows.map(row => ({
      id: row.reportID,
      location: parseGeographyPoint(row.location),
      wasteType: row.wasteType,
      imageUrl: row.imageUrl,
    }));

    const route = computeShortestRoute(locations, workerLocation);

    for (const loc of route) {
      if (loc.id !== 0) {
        await client.query(
          'UPDATE TaskRequests SET route = $1 WHERE reportID = $2',
          [JSON.stringify(route.map(r => ({ lat: r.lat, lng: r.lng }))), loc.id]
        );
      }
    }

    await client.query('COMMIT');
    res.status(200).json({
      locations: locations,
      route: route,
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error fetching garbage reports:', error.message);
    res.status(500).json({ message: error.message || 'Server error fetching garbage reports' });
  } finally {
    client.release();
  }
});

// GET /user/progress - Fetch progress of garbage reports for a user
collectionRequestRouter.get('/user/progress', async (req, res) => {
  const userId = req.query.userId;
  if (!userId) {
    return res.status(400).json({ message: 'User ID is required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const result = await client.query(`
      SELECT gr.reportID, tr.taskID, tr.progress, tr.route, tr.startTime,
             u.location as worker_location, u.name as worker_name
      FROM GarbageReports gr
      LEFT JOIN TaskRequests tr ON gr.reportID = tr.reportID
      LEFT JOIN Users u ON tr.assignedWorkerID = u.userID
      WHERE gr.userID = $1 AND gr.status IN ('pending', 'assigned')
    `, [userId]);

    if (result.rows.length === 0) {
      return res.status(200).json({ message: 'No active garbage reports found for this user', reports: [] });
    }

    const reports = result.rows.map(row => {
      // Calculate ETA (simplified: assumes constant speed of 30 km/h)
      const progress = row.progress || 0.0;
      const route = row.route || [];
      if (route.length < 2) {
        return {
          reportID: row.reportID,
          progress: progress,
          route: route,
          workerLocation: parseGeographyPoint(row.worker_location),
          workerName: row.worker_name,
          eta: 'N/A',
        };
      }

      const totalDistance = route.reduce((acc, point, idx) => {
        if (idx === 0) return acc;
        return acc + calculateDistance(route[idx - 1], point);
      }, 0);

      const remainingDistance = totalDistance * (1 - progress / 100);
      const speedKmPerHour = 30; // Assume 30 km/h
      const etaMinutes = (remainingDistance / speedKmPerHour) * 60;

      return {
        reportID: row.reportID,
        progress: progress,
        route: route,
        workerLocation: parseGeographyPoint(row.worker_location),
        workerName: row.worker_name,
        eta: etaMinutes > 0 ? `${Math.round(etaMinutes)} minutes` : 'Arriving soon',
      };
    });

    await client.query('COMMIT');
    res.status(200).json(reports);
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error fetching progress:', error.message);
    res.status(500).json({ message: error.message || 'Server error fetching progress' });
  } finally {
    client.release();
  }
});

module.exports = collectionRequestRouter;