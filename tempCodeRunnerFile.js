app.post('/signup', (req, res) => {
    const { name, email, password } = req.body;

    // Validate input
    if (!email || !password || !name) {
        return res.status(400).json({ message: 'Email and password are required' });
    }

    // Check if the email already exists
    const checkEmailQuery = 'SELECT * FROM User WHERE email = ?';
    db.query(checkEmailQuery, [email], (err, results) => {
        if (err) {
            console.error('Database error:', err);
            return res.status(500).json({ message: 'Server error' });
        }

        if (results.length > 0) {
            return res.status(400).json({ message: 'Email already exists' });
        }

        // Hash the password
        const salt = bcrypt.genSaltSync(10);
        const hashedPassword = bcrypt.hashSync(password, salt);

        // Insert the new user into the database
        const insertUserQuery = 'INSERT INTO User (name, email, password) VALUES (?, ?, ?)';
        db.query(insertUserQuery, [name, email, hashedPassword], (err, results) => {
            if (err) {
                console.error('Database error:', err);
                return res.status(500).json({ message: 'Server error' });
            }

            res.status(201).json({ message: 'User registered successfully' });
        });
    });
});
