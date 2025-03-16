const express = require('express');
const { Pool } = require('pg');
const authRouter =require('./routes/auth')

const app = express();

const port = process.env.PORT || 5000;

// Initialize PostgreSQL pool
const pool = new Pool({
    connectionString: 'postgresql://postgres.hrzroqrgkvzhomsosqzl:7H.6k2wS*F$q2zY@aws-0-ap-south-1.pooler.supabase.com:6543/postgres', 
    ssl: { rejectUnauthorized: false }, 
});

app.use(authRouter);

// Test database connection
app.get('/test-db', async (req, res) => {
    try {
        const result = await pool.query('SELECT NOW()');
        res.json({ message: 'Database connected!', time: result.rows[0].now });
    } catch (error) {
        console.error('Database connection error:', error);
        res.status(500).json({ error: 'Database connection failed' });
    }
});