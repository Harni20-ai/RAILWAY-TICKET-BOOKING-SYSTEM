require('dotenv').config();
const express = require('express');
const mysql = require('mysql2/promise');
const bodyParser = require('body-parser');
const cors = require('cors');
const bcrypt = require('bcrypt');
const saltRounds = 10;

const app = express();

// Enhanced CORS configuration
//app.use(cors({
    //origin: process.env.FRONTEND_URL || 'http://localhost:3001',
    //methods: ['GET', 'POST', 'PUT', 'DELETE'],
    //allowedHeaders: ['Content-Type', 'Authorization']
//}));
app.use(cors());
app.use(bodyParser.json());

// Secure database connection with environment variables
const pool = mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || 'Harni*01',
    database: process.env.DB_NAME || 'railway_booking_system',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
    connectTimeout: 10000,
    timezone: '+00:00'
});

// Station mapping with validation
const validateStation = (stationName) => {
    const stationCodes = {
        'Bengaluru City Jn': 'SBC',
        'Hazrat Nizamuddin': 'NZM',
        'New Delhi': 'NDLS',
        'Mumbai Central': 'BCT',
        'Chennai Central': 'MAS'
    };
    return stationCodes[stationName] || null;
};

// Train route validation
const validateTrainRoute = (trainId, fromCode, toCode) => {
    const validTrainRoutes = {
        '22691': { from: 'SBC', to: 'NZM' },
        '12609': { from: 'MAS', to: 'NDLS' },
        '12658': { from: 'SBC', to: 'MAS' }
    };
    const route = validTrainRoutes[trainId];
    return route && route.from === fromCode && route.to === toCode;
};

// Fare validation with database fallback
const getFare = async (connection, trainId, travelClass) => {
    try {
        // First try database
        const [fareRows] = await connection.query(
            'SELECT fare FROM train_fare WHERE train_id = ? AND class_id = ?',
            [trainId, travelClass]
        );
        
        if (fareRows.length > 0) return fareRows[0].fare;
        
        // Fallback to hardcoded fares
        const hardcodedFares = {
            '22691': { '1A': 2500, '2A': 1500, '3A': 1100 },
            '12609': { '1A': 2200, '2A': 1300, '3A': 950 },
            '12658': { '2A': 1200, '3A': 850 }
        };
        
        return hardcodedFares[trainId]?.[travelClass] || null;
    } catch (error) {
        console.error('Fare lookup error:', error);
        return null;
    }
};

// Secure PNR generation with collision check
const generateUniquePNR = async (connection, trainId, journeyDate) => {
    let pnr, exists;
    do {
        const datePart = new Date(journeyDate).toISOString().slice(8, 10) + 
                        new Date(journeyDate).toISOString().slice(5, 7);
        const randomPart = Math.floor(1000 + Math.random() * 9000);
        pnr = trainId.slice(0, 3) + datePart + randomPart;
        
        [exists] = await connection.query(
            'SELECT 1 FROM bookings WHERE pnr_number = ? LIMIT 1',
            [pnr]
        );
    } while (exists.length > 0);
    
    return pnr;
};

// Enhanced booking validation
const validateBookingData = (data) => {
    const requiredFields = [
        'username', 'train_id', 'travel_class', 
        'journey_date', 'from_station', 'to_station',
        'passenger_name', 'passenger_age', 'passenger_gender'
    ];
    
    const missingFields = requiredFields.filter(field => !data[field]);
    if (missingFields.length > 0) {
        return { valid: false, message: `Missing required fields: ${missingFields.join(', ')}` };
    }
    
    if (isNaN(data.passenger_age) || data.passenger_age < 1 || data.passenger_age > 120) {
        return { valid: false, message: 'Invalid passenger age (1-120)' };
    }
    
    return { valid: true };
};

// Secure booking endpoint
app.post('/book', async (req, res) => {
    console.log('Booking request received:', JSON.stringify(req.body, null, 2));
    
    const validation = validateBookingData(req.body);
    if (!validation.valid) {
        return res.status(400).json({ 
            success: false, 
            message: validation.message 
        });
    }

    let connection;
    try {
        connection = await pool.getConnection();
        await connection.beginTransaction();
        connection.config.queryTimeout = 10000; // 10s timeout

        // Get user ID with parameterized query
        const [userRows] = await connection.query(
            'SELECT user_id FROM users WHERE username = ? LIMIT 1',
            [req.body.username]
        );
        
        if (userRows.length === 0) {
            throw new Error('User not found');
        }
        
        const user_id = userRows[0].user_id;
        const fromCode = validateStation(req.body.from_station);
        const toCode = validateStation(req.body.to_station);
        
        if (!fromCode || !toCode) {
            throw new Error('Invalid station selection');
        }

        if (!validateTrainRoute(req.body.train_id, fromCode, toCode)) {
            const [trainDetails] = await connection.query(
                'SELECT train_name FROM trains WHERE train_id = ? LIMIT 1',
                [req.body.train_id]
            );
            throw new Error(
                `${trainDetails[0]?.train_name || 'Selected train'} only runs between ` +
                `${validTrainRoutes[req.body.train_id]?.from} and ` +
                `${validTrainRoutes[req.body.train_id]?.to}`
            );
        }

        // Get fare with proper validation
        const fare = await getFare(connection, req.body.train_id, req.body.travel_class);
        if (!fare) {
            throw new Error(`Fare not found for ${req.body.train_id} ${req.body.travel_class}`);
        }

        // Generate unique PNR
        const pnr = await generateUniquePNR(connection, req.body.train_id, req.body.journey_date);
        
        // Create booking
        await connection.query(
            'INSERT INTO bookings (pnr_number, user_id, train_id, journey_date, total_fare) VALUES (?, ?, ?, ?, ?)',
            [pnr, user_id, req.body.train_id, req.body.journey_date, fare]
        );
        
        // Add passenger
        await connection.query(
            'INSERT INTO passengers (pnr_number, name, age, gender, title, travel_class) VALUES (?, ?, ?, ?, ?, ?)',
            [
                pnr, 
                req.body.passenger_name, 
                req.body.passenger_age, 
                req.body.passenger_gender, 
                req.body.passenger_title || 'Mr.', 
                req.body.travel_class
            ]
        );
        
        await connection.commit();
        
        res.json({ 
            success: true, 
            pnr_number: pnr,
            total_fare: fare,
            message: 'Ticket booked successfully'
        });

    } catch (error) {
        if (connection) {
            await connection.rollback();
            connection.release();
        }
        console.error('Booking error:', error);
        res.status(400).json({ 
            success: false, 
            message: error.message || 'Booking failed'
        });
    } finally {
        if (connection) connection.release();
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.status(200).json({ 
        status: 'OK', 
        timestamp: new Date().toISOString() 
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Server error:', err);
    res.status(500).json({ 
        success: false, 
        message: 'Internal server error' 
    });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Database: ${process.env.DB_NAME || 'railway_booking_system'}`);
});
