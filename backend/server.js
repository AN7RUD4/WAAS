const express = require('express');
const authRouter = require('./routes/auth');
const profileRouter = require('./routes/profile');
const userRouter = require('./routes/user');
const workerRouter = require('./routes/worker'); 
const cors = require('cors');
const cron = require('node-cron');

const app = express();
const port = process.env.PORT || 5000;

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cors());

const fs = require('fs');
if (!fs.existsSync('uploads')) {
  fs.mkdirSync('uploads');
}

// Root route for testing
app.get('/', (req, res) => {
  res.json({ message: 'Server is running' });
});

// Routes
app.use('/api', authRouter);
app.use('/api/profile', profileRouter);
app.use('/api/user', userRouter);
app.use('/api/worker', workerRouter); 

async function getAdminToken() {
  try {
    // If you have a stored token that's still valid, use it
    if (process.env.ADMIN_JWT_TOKEN) {
      try {
        jwt.verify(process.env.ADMIN_JWT_TOKEN, process.env.JWT_SECRET || 'passwordKey');
        return process.env.ADMIN_JWT_TOKEN;
      } catch (e) {
        // Token expired, need to get a new one
      }
    }

    // Get new token by logging in
    const response = await axios.post(
      `${process.env.API_BASE_URL}/admin-login`,
      {
        username: process.env.ADMIN_USERNAME,
        password: process.env.ADMIN_PASSWORD
      }
    );

    // Store the new token in memory (or in a secure storage for production)
    process.env.ADMIN_JWT_TOKEN = response.data.token;
    return response.data.token;
  } catch (error) {
    console.error('Failed to get admin token:', error.message);
    return null;
  }
}

// In worker mobile app (Flutter/React Native)
async function sendLocationUpdate() {
  // Get current location
  const location = await getCurrentPosition(); 
  
  // Send to server
  await axios.post(`${API_URL}/update-worker-location`, {
    userId: currentUser.id,
    lat: location.latitude,
    lng: location.longitude
  });
}

// Run every 15 minutes when app is active
setInterval(sendLocationUpdate, 15 * 60 * 1000);

// Schedule to run every 2 hours
cron.schedule('0 */2 * * *', async () => {
  try {
    const adminJwtToken = await getAdminToken();
    sendLocationUpdate();
    
    if (!adminJwtToken) {
      throw new Error('Admin JWT token not available');
    }

    const response = await axios.post(
      `${process.env.API_BASE_URL_WORKER}/worker/group-and-assign-reports`,
      {}, // Empty request body
      {
        headers: { 
          Authorization: `Bearer ${adminJwtToken}`,
          'Content-Type': 'application/json'
        },
        timeout: 30000 // 30-second timeout
      }
    );

    console.log('Scheduled assignment completed:', {
      status: response.status,
      data: response.data
    });
    
  } catch (error) {
    console.error('Scheduled assignment failed:', {
      time: new Date().toISOString(),
      error: error.response?.data || error.message,
      stack: error.stack
    });
  }
}, {
  scheduled: true,
  timezone: "Asia/Kolkata" // Using IANA timezone for India
});

console.log('Cron job scheduled to run every 2 hours for report assignments');

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ message: 'Internal Server Error' });
});

// Start server
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});

module.exports = app;