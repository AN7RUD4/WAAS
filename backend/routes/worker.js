require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const munkres = require('munkres').default;
const twilio = require('twilio');

const router = express.Router();
router.use(cors());
router.use(express.json());

// Initialize Twilio client
const twilioClient = new twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
});

// Database connection check
pool.connect((err, client, release) => {
    if (err) {
        console.error('Database connection error:', err.stack);
        process.exit(1);
    } else {
        console.log('Worker service connected to database');
        release();
    }
});

// Authentication middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader?.split(' ')[1];
    if (!token) return res.status(401).json({ message: 'Authentication token required' });

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET || 'passwordKey');
        if (!decoded.userid || !decoded.role) {
            return res.status(403).json({ message: 'Invalid token: Missing userid or role' });
        }
        req.user = decoded;
        next();
    } catch (err) {
        console.error('Token verification error:', err.message);
        return res.status(403).json({ message: 'Invalid or expired token' });
    }
};

// Middleware to check if user is a worker or admin
const checkWorkerOrAdminRole = (req, res, next) => {
    const { role } = req.user; // Assuming req.user is set by authenticateToken middleware
    if (role === 'worker' || role === 'admin') {
        return next();
    }
    return res.status(403).json({ error: 'Access denied: Worker or Admin role required' });
};

// Haversine distance function
function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371; // Earth radius in km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

// // Enhanced and fixed K-Means clustering
// function kmeansClustering(points, k) {
//     if (!points || !Array.isArray(points) || points.length === 0) {
//         console.error('Invalid or empty points array');
//         return [];
//     }

//     k = Math.min(Math.max(1, k), points.length);
//     if (k <= 1) return [points];

//     const clusters = Array.from({ length: k }, () => []);
//     points.sort((a, b) => {
//         const severityOrder = { high: 3, medium: 2, low: 1 };
//         return (severityOrder[b.severity] || 1) - (severityOrder[a.severity] || 1);
//     });

//     try {
//         const data = points.map(p => [p.lat, p.lng]);
//         const centroids = [];
//         for (let i = 0; i < k; i++) {
//             centroids.push(data[i % data.length]);
//         }

//         let changed = true;
//         let iterations = 0;
//         const maxIterations = 100;

//         while (changed && iterations < maxIterations) {
//             iterations++;
//             changed = false;
//             clusters.forEach(cluster => cluster.length = 0);

//             points.forEach(point => {
//                 const pointCoords = [point.lat, point.lng];
//                 let minDistance = Infinity;
//                 let closestIdx = 0;

//                 centroids.forEach((centroid, i) => {
//                     const dist = haversineDistance(
//                         pointCoords[0], pointCoords[1],
//                         centroid[0], centroid[1]
//                     );
//                     if (dist < minDistance) {
//                         minDistance = dist;
//                         closestIdx = i;
//                     }
//                 });

//                 clusters[closestIdx].push(point);
//             });

//             centroids.forEach((centroid, i) => {
//                 if (clusters[i].length > 0) {
//                     const newLat = clusters[i].reduce((sum, p) => sum + p.lat, 0) / clusters[i].length;
//                     const newLng = clusters[i].reduce((sum, p) => sum + p.lng, 0) / clusters[i].length;
//                     if (haversineDistance(centroid[0], centroid[1], newLat, newLng) > 0.01) {
//                         changed = true;
//                     }
//                     centroid[0] = newLat;
//                     centroid[1] = newLng;
//                 }
//             });
//         }

//         // Print clustering results
//         console.log('=== Clustering Results ===');
//         console.log(`Number of clusters: ${clusters.length}`);
//         clusters.forEach((cluster, index) => {
//             console.log(`Cluster ${index + 1}: ${cluster.length} points`);
//             console.log('Points:', cluster.map(p => ({
//                 reportid: p.reportid,
//                 lat: p.lat,
//                 lng: p.lng,
//                 severity: p.severity
//             })));
//         });

//         return clusters.filter(c => c.length > 0);
//     } catch (error) {
//         console.error('Clustering error:', error);
//         return points.map(p => [p]);
//     }
// }


// // Worker assignment with skill matching
// async function assignWorkersToClusters(clusters, workers) {
//     if (!clusters.length || !workers.length) return [];

//     const costMatrix = clusters.map(cluster => {
//         const centroid = {
//             lat: cluster.reduce((sum, p) => sum + p.lat, 0) / cluster.length,
//             lng: cluster.reduce((sum, p) => sum + p.lng, 0) / cluster.length
//         };

//         return workers.map(worker => {
//             return haversineDistance(worker.lat, worker.lng, centroid.lat, centroid.lng);
//         });
//     });

//     // Apply Hungarian algorithm
//     const assignments = munkres(costMatrix);
//     const results = [];
//     const assignedWorkers = new Set();

//     assignments.forEach(([clusterIdx, workerIdx]) => {
//         if (clusterIdx < clusters.length && workerIdx < workers.length && !assignedWorkers.has(workerIdx)) {
//             results.push({
//                 cluster: clusters[clusterIdx],
//                 worker: workers[workerIdx],
//                 distance: costMatrix[clusterIdx][workerIdx]
//             });
//             assignedWorkers.add(workerIdx);
//         }
//     });

//     return results.sort((a, b) => a.distance - b.distance);
// }


// Enhanced K-Means clustering with distance and size constraints
function kmeansClustering(points, k) {
    if (!points || !Array.isArray(points) || points.length === 0) {
        console.error('Invalid or empty points array');
        return [];
    }

    k = Math.min(Math.max(1, k), points.length);
    if (k <= 1) return [points];

    const clusters = Array.from({ length: k }, () => []);
    points.sort((a, b) => (a.wastetype === 'hazardous' ? -1 : b.wastetype === 'hazardous' ? 1 : 0));

    try {
        const data = points.map(p => [p.lat, p.lng]);
        const centroids = [];
        for (let i = 0; i < k; i++) centroids.push(data[i % data.length]); // Simple init (could use K-Means++ if time allows)

        let changed = true;
        let iterations = 0;
        const maxIterations = 100;

        while (changed && iterations < maxIterations) {
            iterations++;
            changed = false;
            clusters.forEach(cluster => cluster.length = 0);

            points.forEach(point => {
                const pointCoords = [point.lat, point.lng];
                let minDistance = Infinity;
                let closestIdx = 0;
                centroids.forEach((centroid, i) => {
                    const dist = haversineDistance(pointCoords[0], pointCoords[1], centroid[0], centroid[1]);
                    if (dist < minDistance) {
                        minDistance = dist;
                        closestIdx = i;
                    }
                });
                clusters[closestIdx].push(point);
            });

            centroids.forEach((centroid, i) => {
                if (clusters[i].length > 0) {
                    const newLat = clusters[i].reduce((sum, p) => sum + p.lat, 0) / clusters[i].length;
                    const newLng = clusters[i].reduce((sum, p) => sum + p.lng, 0) / clusters[i].length;
                    if (haversineDistance(centroid[0], centroid[1], newLat, newLng) > 0.01) changed = true;
                    centroid[0] = newLat;
                    centroid[1] = newLng;
                }
            });
        }

        // Refine clusters: split if > 1 km diameter or > 15 reports
        const maxDiameter = 1; // 1 km
        const maxReports = 15;
        const refinedClusters = [];
        clusters.forEach(cluster => {
            if (cluster.length > maxReports || calculateClusterDiameter(cluster) > maxDiameter) {
                const subK = Math.ceil(cluster.length / maxReports);
                const subClusters = kmeansClustering(cluster, subK); // Recursive split
                refinedClusters.push(...subClusters);
            } else {
                refinedClusters.push(cluster);
            }
        });

        console.log('=== Clustering Results ===');
        refinedClusters.forEach((c, i) => {
            console.log('Cluster ${i + 1}: ${c.length} reports, Diameter: ${calculateClusterDiameter(c).toFixed(2)} km');
        });
        return refinedClusters.filter(c => c.length > 0);
    } catch (error) {
        console.error('Clustering error:', error);
        return points.map(p => [p]);
    }
}

// Updated group-and-assign-reports endpoint with 20km radius constraint
router.post('/group-and-assign-reports', authenticateToken, async (req, res) => {
    try {
        // 1. Verify worker location exists
        const workerCheck = await pool.query(
            `SELECT ST_X(location::geometry) as lng, ST_Y(location::geometry) as lat 
             FROM users WHERE userid = $1`,
            [req.user.userid]
        );
        
        if (workerCheck.rows.length === 0 || !workerCheck.rows[0].lat) {
            return res.status(400).json({ error: 'Worker location not set' });
        }

        const workerLocation = {
            lat: workerCheck.rows[0].lat,
            lng: workerCheck.rows[0].lng
        };

        // 2. Get all not-collected reports within strict 20km radius
        const maxDistance = 20; // Hard-coded 20km radius
        const reportsResult = await pool.query(`
            SELECT 
                r.reportid, 
                r.wastetype,
                ST_X(r.location::geometry) AS lng,
                ST_Y(r.location::geometry) AS lat,
                ST_Distance(
                    r.location::geography, 
                    (SELECT location FROM users WHERE userid = $1)::geography
                ) / 1000 AS distance_km
            FROM garbagereports r
            WHERE r.status = 'not-collected'
            AND ST_DWithin(
                r.location::geography, 
                (SELECT location FROM users WHERE userid = $1)::geography,
                $2 * 1000  -- 20km in meters
            )
            ORDER BY distance_km ASC
            LIMIT 100`, 
            [req.user.userid, maxDistance]
        );

        // 3. Filter and validate reports
        const reports = reportsResult.rows.filter(report => 
            report.distance_km <= maxDistance && 
            isValidCoordinate(report.lat, report.lng)
        );

        if (reports.length === 0) {
            return res.json({ message: 'No reports within 20km radius to cluster' });
        }

        // 4. Cluster reports with distance constraints
        const clusterCount = Math.min(
            Math.ceil(reports.length / 3), // Max 3 reports per cluster
            5 // Max 5 clusters per worker
        );

        const clusters = kmeansClustering(reports, clusterCount, {
            maxDistanceFromWorker: maxDistance,
            workerLocation: workerLocation
        });

        // 5. Filter clusters to ensure all points are within 20km
        const validClusters = clusters.filter(cluster => 
            cluster.every(report => report.distance_km <= maxDistance)
        );

        if (validClusters.length === 0) {
            return res.json({ message: 'No valid clusters within 20km radius' });
        }

        // 6. Assign clusters to current worker
        const assignments = validClusters.map(cluster => ({
            cluster,
            worker: {
                userid: req.user.userid,
                ...workerLocation
            },
            distance: 0 // Since we're assigning to current worker
        }));

        // 7. Create tasks with optimized routes
        const results = [];
        for (const { cluster } of assignments) {
            const route = solveTSP(cluster, workerLocation);

            // Final validation - ensure all points in route are within 20km
            if (route.waypoints.some(point => 
                haversineDistance(
                    workerLocation.lat, workerLocation.lng,
                    point.lat, point.lng
                ) > maxDistance
            )) {
                continue; // Skip this cluster if any point is beyond 20km
            }

            const taskResult = await pool.query(`
                INSERT INTO taskrequests (
                    reportids,
                    assignedworkerid,
                    status,
                    starttime,
                    route,
                    estimated_distance
                ) VALUES (
                    $1, $2, 'assigned', NOW(), $3, $4
                ) RETURNING taskid`,
                [
                    cluster.map(r => r.reportid),
                    req.user.userid,
                    route,
                    route.totalDistance
                ]
            );

            results.push({
                taskId: taskResult.rows[0].taskid,
                reportCount: cluster.length,
                distance: route.totalDistance,
                maxDistanceInCluster: Math.max(...cluster.map(r => r.distance_km))
            });
        }

        if (results.length === 0) {
            return res.json({ message: 'No valid tasks created within 20km radius' });
        }

        res.json({ 
            success: true, 
            assignments: results,
            workerLocation: workerLocation,
            maxDistance: maxDistance
        });
    } catch (error) {
        console.error('Assignment error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Updated K-Means clustering without hazardous priority
function kmeansClustering(points, k, options = {}) {
    if (!points || !Array.isArray(points) || points.length === 0) {
        return [];
    }

    k = Math.min(Math.max(1, k), points.length);
    if (k <= 1) return [points];

    const clusters = Array.from({ length: k }, () => []);
    
    try {
        const data = points.map(p => [p.lat, p.lng]);
        const centroids = [];
        
        // Initialize centroids within max distance if constraint exists
        if (options.maxDistanceFromWorker && options.workerLocation) {
            const validPoints = points.filter(p => 
                haversineDistance(
                    options.workerLocation.lat, options.workerLocation.lng,
                    p.lat, p.lng
                ) <= options.maxDistanceFromWorker
            );
            
            for (let i = 0; i < k; i++) {
                centroids.push(validPoints[i % validPoints.length] 
                    ? [validPoints[i % validPoints.length].lat, validPoints[i % validPoints.length].lng]
                    : data[i % data.length]
                );
            }
        } else {
            for (let i = 0; i < k; i++) {
                centroids.push(data[i % data.length]);
            }
        }

        let changed = true;
        let iterations = 0;
        const maxIterations = 100;

        while (changed && iterations < maxIterations) {
            iterations++;
            changed = false;
            clusters.forEach(cluster => cluster.length = 0);

            points.forEach(point => {
                const pointCoords = [point.lat, point.lng];
                let minDistance = Infinity;
                let closestIdx = 0;

                centroids.forEach((centroid, i) => {
                    // Skip if this would exceed distance constraint
                    if (options.maxDistanceFromWorker && options.workerLocation) {
                        const clusterDistance = haversineDistance(
                            options.workerLocation.lat, options.workerLocation.lng,
                            centroid[0], centroid[1]
                        );
                        if (clusterDistance > options.maxDistanceFromWorker) return;
                    }

                    const dist = haversineDistance(
                        pointCoords[0], pointCoords[1],
                        centroid[0], centroid[1]
                    );
                    if (dist < minDistance) {
                        minDistance = dist;
                        closestIdx = i;
                    }
                });

                clusters[closestIdx].push(point);
            });

            // Update centroids
            centroids.forEach((centroid, i) => {
                if (clusters[i].length > 0) {
                    const newLat = clusters[i].reduce((sum, p) => sum + p.lat, 0) / clusters[i].length;
                    const newLng = clusters[i].reduce((sum, p) => sum + p.lng, 0) / clusters[i].length;
                    
                    if (haversineDistance(centroid[0], centroid[1], newLat, newLng) > 0.01) {
                        changed = true;
                    }
                    
                    // Ensure new centroid is within max distance
                    if (!options.maxDistanceFromWorker || !options.workerLocation || 
                        haversineDistance(
                            options.workerLocation.lat, options.workerLocation.lng,
                            newLat, newLng
                        ) <= options.maxDistanceFromWorker) {
                        centroid[0] = newLat;
                        centroid[1] = newLng;
                    }
                }
            });
        }

        return clusters.filter(c => c.length > 0);
    } catch (error) {
        console.error('Clustering error:', error);
        return [points]; // Fallback to single cluster
    }
}

// Helper function to validate coordinates
function isValidCoordinate(lat, lng) {
    return lat !== null && lng !== null && 
           !isNaN(lat) && !isNaN(lng) &&
           lat >= -90 && lat <= 90 &&
           lng >= -180 && lng <= 180;
}

// Enhanced TSP solver with priority stops
function solveTSP(points, worker) {
    if (!points.length) {
        return {
            start: { lat: worker.lat, lng: worker.lng },
            waypoints: [],
            end: { lat: worker.lat, lng: worker.lng },
            totalDistance: 0
        };
    }

    // Sort hazardous waste first
    const sortedPoints = [...points].sort((a, b) => {
        if (a.wastetype === 'hazardous' && b.wastetype !== 'hazardous') return -1;
        if (b.wastetype === 'hazardous' && a.wastetype !== 'hazardous') return 1;
        return 0;
    });

    const allPoints = [{ lat: worker.lat, lng: worker.lng }, ...sortedPoints];
    const n = allPoints.length;
    const distMatrix = Array(n).fill().map(() => Array(n).fill(0));

    // Build distance matrix
    for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
            if (i !== j) {
                distMatrix[i][j] = haversineDistance(
                    allPoints[i].lat, allPoints[i].lng,
                    allPoints[j].lat, allPoints[j].lng
                );
            }
        }
    }

    // Nearest neighbor algorithm
    const visited = new Set([0]);
    const route = [0];
    let current = 0;
    let totalDistance = 0;

    while (visited.size < n) {
        let next = -1;
        let minDist = Infinity;
        
        for (let i = 0; i < n; i++) {
            if (!visited.has(i) && distMatrix[current][i] < minDist) {
                minDist = distMatrix[current][i];
                next = i;
            }
        }
        
        if (next === -1) break;
        
        route.push(next);
        visited.add(next);
        totalDistance += minDist;
        current = next;
    }

    // Return to start
    totalDistance += distMatrix[current][0];
    route.push(0);

    return {
        start: { lat: allPoints[0].lat, lng: allPoints[0].lng },
        waypoints: route.slice(1, -1).map(idx => ({
            reportid: idx > 0 ? points[idx-1].reportid : null,
            lat: allPoints[idx].lat,
            lng: allPoints[idx].lng,
            wastetype: idx > 0 ? points[idx-1].wastetype : null
        })),
        end: { lat: allPoints[0].lat, lng: allPoints[0].lng },
        totalDistance
    };
}

router.get('/location', authenticateToken, async (req, res) => {
    try {
      const userId = req.query.userId || req.user.userid;
      
      const result = await pool.query(`
        SELECT 
          userid,
          ST_X(location::geometry) AS lng,
          ST_Y(location::geometry) AS lat,
          last_updated
        FROM users
        WHERE userid = $1
      `, [userId]);
  
      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'User not found' });
      }
  
      res.json(result.rows[0]);
    } catch (error) {
      console.error('Location query error:', error);
      res.status(500).json({ error: 'Database error' });
    }
  });
  
// Update worker location
router.post('/update-worker-location', authenticateToken, async (req, res) => {
    try {
      const { userId, lat, lng } = req.body;
      
      console.log(`Updating location for worker ${userId} to (${lat},${lng})`);
  
      // Validate coordinates
      if (!isValidCoordinate(lat, lng)) {
        return res.status(400).json({ error: 'Invalid coordinates' });
      }
  
      // Force update regardless of role (since middleware already verified)
      const result = await pool.query(`
        UPDATE users 
        SET 
          location = ST_SetSRID(ST_MakePoint($1, $2), 4326),
          last_updated = NOW()
        WHERE userid = $3
        RETURNING 
          userid, 
          ST_X(location::geometry) AS lng,
          ST_Y(location::geometry) AS lat
      `, [lng, lat, userId]);
  
      if (result.rows.length === 0) {
        console.error('Worker not found:', userId);
        return res.status(404).json({ error: 'Worker not found' });
      }
  
      const updated = result.rows[0];
      console.log(`✅ Updated worker ${userId} location to (${updated.lat},${updated.lng})`);
      
      res.status(200).json({
        message: 'Location updated',
        location: { lat: updated.lat, lng: updated.lng }
      });
    } catch (error) {
      console.error('Update error:', error);
      res.status(500).json({ 
        error: 'Database update failed',
        details: error.message 
      });
    }
  });
  
  // Helper function
  function isValidCoordinate(lat, lng) {
    return Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  }

router.get('/available-workers-locations', authenticateToken, async (req, res) => {
    try {
        // Optional: Restrict to admin role
        if (req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Admin access required' });
        }

        const result = await pool.query(`
            SELECT 
                userid,
                ST_X(location::geometry) AS lng,
                ST_Y(location::geometry) AS lat
            FROM users
            WHERE role = 'worker' AND status = 'available'
        `);

        const workers = result.rows.map(row => ({
            userId: row.userid,
            lat: row.lat,
            lng: row.lng,
            lastUpdated: row.last_updated
        }));

        res.status(200).json({ workers });
    } catch (error) {
        console.error('Error fetching available workers locations:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Group and assign reports endpoint
router.post('/group-and-assign-reports', authenticateToken, async (req, res) => {
    try {
        // 1. First verify worker location exists
        const workerCheck = await pool.query(
            `SELECT ST_X(location::geometry) as lng, ST_Y(location::geometry) as lat 
             FROM users WHERE userid = $1`,
            [req.user.userid]
        );
        
        if (workerCheck.rows.length === 0 || !workerCheck.rows[0].lat) {
            return res.status(400).json({ error: 'Worker location not set' });
        }

        // 2. Get all not-collected reports within reasonable distance
        const maxDistance = 20; // km
        const reportsResult = await pool.query(`
            SELECT 
                r.reportid, 
                r.wastetype,
                ST_X(r.location::geometry) AS lng,
                ST_Y(r.location::geometry) AS lat,
                r.datetime,
                ST_Distance(
                    r.location::geography, 
                    (SELECT location FROM users WHERE userid = $1)::geography
                ) / 1000 AS distance_km
            FROM garbagereports r
            WHERE r.status = 'not-collected'
            AND ST_DWithin(
                r.location::geography, 
                (SELECT location FROM users WHERE userid = $1)::geography,
                $2 * 1000
            )
            ORDER BY 
                CASE WHEN r.wastetype = 'hazardous' THEN 0 ELSE 1 END,
                distance_km ASC
            LIMIT 100`, 
            [req.user.userid, maxDistance]
        );

        // 3. Cluster reports
        const reports = reportsResult.rows;
        if (reports.length === 0) {
            return res.json({ message: 'No reports to cluster' });
        }

        // Calculate optimal cluster count (max 3 reports per cluster)
        const clusterCount = Math.min(
            Math.ceil(reports.length / 3),
            5 // Max 5 clusters per worker
        );

        const clusters = kmeansClustering(reports, clusterCount);
        
        // 4. Assign to current worker (since this is triggered on login)
        const assignments = clusters.map(cluster => ({
            cluster,
            worker: {
                userid: req.user.userid,
                lat: workerCheck.rows[0].lat,
                lng: workerCheck.rows[0].lng
            },
            distance: 0 // Since we're assigning to current worker
        }));

        // 5. Create tasks
        const results = [];
        for (const { cluster } of assignments) {
            const route = solveTSP(cluster, { 
                lat: workerCheck.rows[0].lat, 
                lng: workerCheck.rows[0].lng 
            });

            const taskResult = await pool.query(`
                INSERT INTO taskrequests (
                    reportids,
                    assignedworkerid,
                    status,
                    starttime,
                    route,
                    estimated_distance
                ) VALUES (
                    $1, $2, 'assigned', NOW(), $3, $4
                ) RETURNING taskid`,
                [
                    cluster.map(r => r.reportid),
                    req.user.userid,
                    route,
                    route.totalDistance
                ]
            );

            results.push({
                taskId: taskResult.rows[0].taskid,
                reportCount: cluster.length,
                distance: route.totalDistance
            });
        }

        res.json({ success: true, assignments: results });
    } catch (error) {
        console.error('Assignment error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Helper functions
function calculateClusterDiameter(cluster) {
    let maxDistance = 0;
    for (let i = 0; i < cluster.length; i++) {
        for (let j = i + 1; j < cluster.length; j++) {
            const dist = haversineDistance(
                cluster[i].lat, cluster[i].lng,
                cluster[j].lat, cluster[j].lng
            );
            maxDistance = Math.max(maxDistance, dist);
        }
    }
    return maxDistance;
}

async function notifyUsers(cluster, taskId) {
    const uniqueUserIds = [...new Set(cluster.map(r => r.userid))];
    
    for (const userId of uniqueUserIds) {
        try {
            const user = await pool.query(`
                SELECT phone FROM users WHERE userid = $1
            `, [userId]);
            
            if (user.rows[0]?.phone) {
                const reports = cluster.filter(r => r.userid === userId);
                const message = `Your reports (${reports.map(r => r.wastetype).join(', ')}) have been assigned. ID: ${taskId}`;
                
                await twilioClient.messages.create({
                    body: message,
                    from: process.env.TWILIO_PHONE_NUMBER,
                    to: user.rows[0].phone
                });
            }
        } catch (error) {
            console.error(`Notification failed for user ${userId}:`, error);
        }
    }
}

// Task progress update endpoint
router.post('/update-task-progress', authenticateToken, async (req, res) => {
    try {
        const { taskId, progress, completedReportIds } = req.body;
        
        await pool.query('BEGIN');
        
        // Update task progress
        await pool.query(`
            UPDATE taskrequests
            SET progress = $1
            WHERE taskid = $2
        `, [progress, taskId]);
        
        // Mark reports as completed
        if (completedReportIds?.length) {
            await pool.query(`
                UPDATE garbagereports
                SET status = 'completed'
                WHERE reportid = ANY($1)
            `, [completedReportIds]);
        }
        
        // Check if task is fully completed
        if (progress >= 100) {
            await pool.query(`
                UPDATE taskrequests
                SET status = 'completed',
                    endtime = NOW()
                WHERE taskid = $1
            `, [taskId]);
            
            // Free up the worker
            await pool.query(`
                UPDATE users
                SET status = 'available'
                WHERE userid = (
                    SELECT assignedworkerid FROM taskrequests WHERE taskid = $1
                )
            `, [taskId]);
        }
        
        await pool.query('COMMIT');
        res.status(200).json({ message: 'Progress updated successfully' });
    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Progress update error:', error);
        res.status(500).json({ error: 'Failed to update progress' });
    }
});

// Fetch Assigned Tasks for Worker
router.get('/assigned-tasks', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const tasksResult = await pool.query(
            `SELECT taskid, reportids, status, starttime, route 
             FROM taskrequests 
             WHERE assignedworkerid = $1 AND status != 'completed'`,
            [workerId]
        );

        if (tasksResult.rows.length === 0) {
            return res.json({ assignedWorks: [] });
        }

        const assignedWorks = [];

        for (const task of tasksResult.rows) {
            const reportsResult = await pool.query(
                `SELECT reportid, wastetype, location 
                 FROM garbagereports 
                 WHERE reportid = ANY($1) 
                 LIMIT 1`,
                [task.reportids]
            );

            if (reportsResult.rows.length > 0) {
                const report = reportsResult.rows[0];
                const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
                const reportLat = locationMatch ? parseFloat(locationMatch[2]) : null;
                const reportLng = locationMatch ? parseFloat(locationMatch[1]) : null;

                const workerLat = 10.235865;
                const workerLng = 76.405676;

                let distance = '0km';
                if (reportLat && reportLng) {
                    distance = (haversineDistance(workerLat, workerLng, reportLat, reportLng)).toFixed(2) + 'km';
                }

                assignedWorks.push({
                    taskId: task.taskid.toString(),
                    title: report.wastetype ?? 'Unknown',
                    reportCount: task.reportids.length,
                    firstLocation: report.location,
                    distance: distance,
                    time: task.starttime ? task.starttime.toISOString() : 'Not Started',
                    status: task.status,
                });
            }
        }

        res.json({ assignedWorks });
    } catch (error) {
        console.error('Error fetching assigned tasks in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Update Task Progress
router.patch('/update-progress', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId, progress, status } = req.body;
        if (!taskId || progress === undefined || !status) {
            return res.status(400).json({ error: 'Task ID, progress, and status are required' });
        }

        const taskIdInt = parseInt(taskId, 10);
        if (isNaN(taskIdInt)) {
            return res.status(400).json({ error: 'Invalid Task ID' });
        }

        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const progressFloat = parseFloat(progress);
        if (isNaN(progressFloat) || progressFloat < 0 || progressFloat > 1) {
            return res.status(400).json({ error: 'Progress must be a number between 0 and 1' });
        }

        const validStatuses = ['pending', 'assigned', 'in-progress', 'completed', 'failed'];
        if (!validStatuses.includes(status)) {
            return res.status(400).json({ error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
        }

        const taskCheck = await pool.query(
            `SELECT 1 FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
            [taskIdInt, workerId]
        );

        if (taskCheck.rows.length === 0) {
            return res.status(403).json({ error: 'Task not assigned to this worker' });
        }

        const updateFields = ['progress = $1', 'status = $2'];
        const updateValues = [progressFloat, status];

        if (status === 'completed') {
            updateFields.push('endtime = NOW()');
        }

        await pool.query(
            `UPDATE taskrequests SET ${updateFields.join(', ')} WHERE taskid = $${updateFields.length + 1}`,
            updateValues.concat([taskIdInt])
        );

        res.json({ message: 'Task updated successfully' });
    } catch (error) {
        console.error('Error updating task progress in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Fetch Completed Tasks
router.get('/completed-tasks', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const tasksResult = await pool.query(
            `SELECT taskid, reportids, endtime 
             FROM taskrequests 
             WHERE assignedworkerid = $1 AND status = 'completed'`,
            [workerId]
        );

        const completedWorks = [];

        for (const task of tasksResult.rows) {
            const reportsResult = await pool.query(
                `SELECT array_agg(DISTINCT wastetype) as wastetypes, COUNT(reportid) as report_count
                 FROM garbagereports 
                 WHERE reportid = ANY($1)`,
                [task.reportids]
            );
            if (reportsResult.rows.length > 0) {
                const report = reportsResult.rows[0];
                completedWorks.push({
                    taskId: task.taskid.toString(),
                    title: report.wastetypes.join(', '),
                    reportCount: report.report_count,
                    endTime: task.endtime ? task.endtime.toISOString() : null,
                });
            }
        }

        res.json({ completedWorks });
    } catch (error) {
        console.error('Error fetching completed tasks in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Start task endpoint
router.post('/start-task', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId } = req.body;
        const workerId = req.user.userid;

        console.log(`Attempting to start task with taskId: ${taskId}, workerId: ${workerId}`);

        const taskCheck = await pool.query(
            `SELECT 1 FROM taskrequests 
             WHERE taskid = $1 AND assignedworkerid = $2 AND status = 'assigned'`,
            [taskId, workerId]
        );
        console.log(`Task check query result: ${JSON.stringify(taskCheck.rows)}`);

        if (taskCheck.rows.length === 0) {
            const taskState = await pool.query(
                `SELECT status FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
                [taskId, workerId]
            );
            console.log(`Task state for taskId ${taskId}: ${JSON.stringify(taskState.rows)}`);
            return res.status(403).json({
                error: 'Task not assigned to this worker or not in assigned state',
                taskState: taskState.rows.length > 0 ? taskState.rows[0].status : 'not found'
            });
        }

        await pool.query(
            `UPDATE taskrequests 
             SET status = 'in-progress', 
                 starttime = NOW()
             WHERE taskid = $1`,
            [taskId]
        );

        console.log(`Task ${taskId} started by worker ${workerId}, status updated to in-progress`);
        res.status(200).json({
            message: 'Task started successfully',
            status: 'in-progress'
        });
    } catch (error) {
        console.error('Error starting task:', error.message, error.stack);
        res.status(500).json({
            error: 'Internal Server Error',
            details: error.message
        });
    }
});

// Mark collected endpoint
router.post('/mark-collected', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId, reportId } = req.body;
        const workerId = req.user.userid;

        // Start a transaction
        await pool.query('BEGIN');

        // 1. First check if the task is assigned to this worker
        const taskCheck = await pool.query(
            `SELECT reportids, status FROM taskrequests 
             WHERE taskid = $1 AND assignedworkerid = $2
             FOR UPDATE`, // Lock the row
            [taskId, workerId]
        );

        if (taskCheck.rows.length === 0) {
            await pool.query('ROLLBACK');
            return res.status(403).json({
                error: 'Task not assigned to this worker'
            });
        }

        // 2. Check if report exists in this task
        const reportIds = taskCheck.rows[0].reportids;
        if (!reportIds.includes(reportId)) {
            await pool.query('ROLLBACK');
            return res.status(404).json({
                error: 'Report not found in this task'
            });
        }

        // 3. Update report status
        await pool.query(
            `UPDATE garbagereports 
             SET status = 'collected' 
             WHERE reportid = $1`,
            [reportId]
        );

        // 4. Check how many reports are left uncollected
        const uncollectedCount = await pool.query(
            `SELECT COUNT(*) FROM garbagereports 
             WHERE reportid = ANY($1) AND status != 'collected'`,
            [reportIds]
        );

        const remaining = parseInt(uncollectedCount.rows[0].count);

        // 5. Update task progress
        const progress = (1 - (remaining / reportIds.length))*100;
        let taskStatus = taskCheck.rows[0].status;

        // If all reports are collected, update task status
        if (remaining === 0) {
            taskStatus = 'completed';
            await pool.query(
                `UPDATE taskrequests 
                 SET status = 'completed', 
                     endtime = NOW(),
                     progress = 1.0
                 WHERE taskid = $1`,
                [taskId]
            );
        } else {
            // Just update progress if not completed
            await pool.query(
                `UPDATE garbagereports 
                 SET status = $1
                 WHERE reportid = $2`,
                ['collected', reportId]
            );
            await pool.query(
                `UPDATE taskrequests 
                 SET progress = $1
                 WHERE taskid = $2`,
                [progress, taskId]
            );
        }

        // Commit the transaction
        await pool.query('COMMIT');

        res.status(200).json({
            message: 'Report marked as collected successfully',
            remainingReports: remaining,
            taskStatus: taskStatus
        });
    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Error marking report as collected:', error);
        res.status(500).json({
            error: 'Internal Server Error',
            details: error.message
        });
    }
});

// Get task route endpoint - updated
router.get('/task-route/:taskid', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    const taskId = parseInt(req.params.taskid, 10);
    const workerId = req.user.userid;

    try {
        // Start transaction
        await pool.query('BEGIN');

        const taskResult = await pool.query(
            `SELECT taskid, reportids, assignedworkerid, status, route, starttime, endtime
             FROM taskrequests
             WHERE taskid = $1 AND assignedworkerid = $2
             FOR UPDATE`,
            [taskId, workerId]
        );

        if (taskResult.rows.length === 0) {
            await pool.query('ROLLBACK');
            return res.status(404).json({ message: 'Task not found or not assigned to this worker' });
        }

        const task = taskResult.rows[0];

        const reportsResult = await pool.query(
            `SELECT reportid, wastetype, ST_AsText(location) AS location, status
             FROM garbagereports 
             WHERE reportid = ANY($1)`,
            [task.reportids]
        );

        // Commit transaction
        await pool.query('COMMIT');

        const collectionPoints = reportsResult.rows.map(report => {
            const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
            return {
                reportid: report.reportid,
                wastetype: report.wastetype,
                lat: locationMatch ? parseFloat(locationMatch[2]) : null,
                lng: locationMatch ? parseFloat(locationMatch[1]) : null,
                status: report.status
            };
        }).filter(point => point.lat !== null && point.lng !== null);

        // Filter out collected reports
        const uncollectedPoints = collectionPoints.filter(p => p.status !== 'collected');

        res.status(200).json({
            taskid: task.taskid,
            reportids: task.reportids,
            status: task.status,
            route: task.route || { start: {}, waypoints: [], end: {} },
            locations: uncollectedPoints,
            wasteTypes: [...new Set(uncollectedPoints.map(p => p.wastetype))],
            workerLocation: { lat: 10.235865, lng: 76.405676 } // Default location
        });
    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Error fetching task route:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// New endpoint to fetch report statuses
router.get('/garbagereports/status', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const reportIds = JSON.parse(req.query.reportIds);
        if (!Array.isArray(reportIds) || reportIds.length === 0) {
            return res.status(400).json({ error: 'Invalid or empty reportIds array' });
        }

        const result = await pool.query(
            `SELECT reportid, status FROM garbagereports WHERE reportid = ANY($1)`,
            [reportIds]
        );

        res.status(200).json(result.rows);
    } catch (error) {
        console.error('Error fetching report statuses:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

module.exports=router