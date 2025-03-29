const express = require('express');
const authRouter = require('./routes/auth');
const profileRouter = require('./routes/profile');
const userRouter = require('./routes/user');
const workerRouter = require('./routes/worker'); // Uncommented
const cors = require('cors');

const app = express();
const port = process.env.PORT || 5000;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cors());

// Root route for testing
app.get('/', (req, res) => {
  res.json({ message: 'Server is running' });
});

// Routes
app.use('/api', authRouter);
app.use('/api/profile', profileRouter);
app.use('/api/user', userRouter);
app.use('/api/worker', workerRouter); 

const cron = require('node-cron');
const axios = require('axios');

// Schedule to run every hour
cron.schedule('0 * * * *', async () => {
  try {
    const response = await axios.post(
      'http://localhost:3000/api/worker/group-and-assign-reports',
      {},
      { headers: { Authorization: 'Bearer <admin-jwt-token>' } }
    );
    console.log('Scheduled assignment completed:', response.data);
  } catch (error) {
    console.error('Scheduled assignment failed:', error.message);
  }
});

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