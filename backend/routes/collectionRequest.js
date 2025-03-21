const express = require('express');
const { Pool } = require('pg');
const haversine = require('haversine-distance');

const collectionRequestRouter = express.Router();

const pool = new Pool({
  connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres',
  ssl: { rejectUnauthorized: false },
});

// Helper function to parse location string into lat/lng
const parseLocation = (location) => {
  const [lat, lng] = location.split(',').map(coord => parseFloat(coord.trim()));
  if (!lat || !lng) throw new Error(`Invalid location format: ${location}`);
  return { lat, lng };
};

// Helper function to calculate Haversine distance between two points
const calculateDistance = (point1, point2) => {
  return haversine(
    { lat: point1.lat, lng: point1.lng },
    { lat: point2.lat, lng: point2.lng }
  ) / 1000; // Convert to kilometers
};

// Nearest-neighbor algorithm to compute the shortest route
const computeShortestRoute = (locations) => {
  if (locations.length <= 1) return locations;

  const unvisited = [...locations];
  const route = [unvisited.shift()]; // Start with the first location

  while (unvisited.length > 0) {
    let lastPoint = route[route.length - 1];
    let nearestIndex = 0;
    let nearestDistance = Infinity;

    // Find the nearest unvisited location
    for (let i = 0; i < unvisited.length; i++) {
      const distance = calculateDistance(lastPoint, unvisited[i]);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    // Add the nearest location to the route and remove it from unvisited
    route.push(unvisited[nearestIndex]);
    unvisited.splice(nearestIndex, 1);
  }

  return route;
};

// Get collection requests and compute the shortest route
collectionRequestRouter.get('/route', async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Fetch collection requests
    const result = await client.query('SELECT * FROM collectionrequests WHERE status = $1', ['pending']);
    const locations = result.rows.map(row => ({
      id: row.id,
      location: row.location,
    }));

    // Parse locations into lat/lng
    const parsedLocations = locations.map(loc => ({
      ...loc,
      ...parseLocation(loc.location),
    }));

    // Compute the shortest route
    const route = computeShortestRoute(parsedLocations);

    await client.query('COMMIT');
    res.status(200).json({
      locations: locations, // All locations for markers
      route: route, // Optimized route for polyline
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error fetching collection requests:', error.message);
    res.status(500).json({ message: error.message || 'Server error fetching collection requests' });
  } finally {
    client.release();
  }
});

module.exports = collectionRequestRouter;