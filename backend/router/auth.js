const express = require("express");
const router = express.Router();
const bcryptjs = require("bcryptjs");
const jwt = require("jsonwebtoken");

router.post()

// Signup endpoint
authRouter.post("/api/Signup", async (req, res) => {
    try {
        const { name, username, password } = req.body;

        // Check if the user already exists
        const existingUser = await pool.query(
            'SELECT * FROM "User" WHERE name = $1',
            [username]
        );

        if (existingUser.rows.length > 0) {
            return res.status(400).json({ message: "User Already Exists" });
        }

        // Hash the password
        const hashed = await bcryptjs.hash(password, 8);

        // Insert the new user into the database
        const newUser = await pool.query(
            'INSERT INTO "User" (userID, name, password) VALUES ($1, $2, $3) RETURNING *',
            [name, username, hashed]
        );

        res.json(newUser.rows[0]);
    } catch (e) {
        res.status(500).json({ message: "Server Error" });
    }
});

// Login endpoint
authRouter.post("/api/Login", async (req, res) => {
    try {
        const { username, password } = req.body;

        // Find the user by username
        const user = await pool.query(
            'SELECT * FROM "User" WHERE name = $1',
            [username]
        );

        if (user.rows.length === 0) {
            return res.status(400).json({ message: "User Does not Exist" });
        }

        // Compare passwords
        const match = await bcryptjs.compare(password, user.password);

        if (!match) {
            return res.status(400).json({ message: "Incorrect Password" });
        }

        // Generate JWT token
        const token = jwt.sign({ id: user.rows[0].id }, "passwordKey");
        const role = user.rows[0].role;
        const image = user.rows[0].img;

        res.json({ role, token, image, ...user.rows[0] });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Update password endpoint
authRouter.post("/api/UpdatePass", async (req, res) => {
    try {
        const { username, password, newPass } = req.body;

        // Find the user by username
        const user = await pool.query(
            'SELECT * FROM "User" WHERE name = $1',
            [username]
        );

        if (user.rows.length === 0) {
            return res.status(400).json({ message: "User Does not Exist" });
        }

        // Compare passwords
        const match = await bcryptjs.compare(password, user.rows[0].password);

        if (!match) {
            return res.status(400).json({ message: "Incorrect Password" });
        }

        // Hash the new password
        const hashedNewPass = await bcryptjs.hash(newPass, 10);

        // Update the user's password
        await pool.query(
            'UPDATE "User" SET password = $1 WHERE name = $2',
            [hashedNewPass, username]
        );

        res.status(200).json({ message: "Password Updated Successfully" });
    } catch (e) {
        res.status(500).json({ message: "Server Error" + e });
    }
});

// Update FCM token endpoint
authRouter.post("/api/:userId/fetchToken", async (req, res) => {
    try {
        const userId = req.params.userId;
        const { fcm } = req.body;

        // Find the user by ID
        const user = await pool.query(
            'SELECT * FROM "User" WHERE userID = $1',
            [userId]
        );

        if (user.rows.length === 0) {
            return res.status(400).json({ message: "User Does not Exist" });
        }

        // Update the FCM token
        await pool.query(
            'UPDATE "User" SET fcmtoken = $1 WHERE userID = $2',
            [fcm, userId]
        );

        res.status(200).json({ message: "FCM Token Updated Successfully" });
    } catch (e) {
        res.status(500).json({ message: "Server Error" + e });
    }
});

module.exports = authRouter;