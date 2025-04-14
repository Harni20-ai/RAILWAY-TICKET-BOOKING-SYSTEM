-- Create the database
CREATE DATABASE railway_booking_system;
USE railway_booking_system;

-- Users table
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL
) ENGINE=InnoDB;

-- Stations table
CREATE TABLE stations (
    station_code VARCHAR(10) PRIMARY KEY,
    station_name VARCHAR(100) NOT NULL,
    city VARCHAR(50) NOT NULL,
    state VARCHAR(50) NOT NULL
) ENGINE=InnoDB;

-- Trains table
CREATE TABLE trains (
    train_id VARCHAR(10) PRIMARY KEY,
    train_name VARCHAR(100) NOT NULL,
    source_station VARCHAR(10) NOT NULL,
    destination_station VARCHAR(10) NOT NULL,
    departure_time TIME NOT NULL,
    arrival_time TIME NOT NULL,
    days_available VARCHAR(50) NOT NULL,
    FOREIGN KEY (source_station) REFERENCES stations(station_code),
    FOREIGN KEY (destination_station) REFERENCES stations(station_code)
) ENGINE=InnoDB;

-- Train classes table
CREATE TABLE train_classes (
    class_id VARCHAR(5) PRIMARY KEY,
    class_name VARCHAR(50) NOT NULL,
    description VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

-- Train fare table
CREATE TABLE train_fare (
    fare_id INT AUTO_INCREMENT PRIMARY KEY,
    train_id VARCHAR(10) NOT NULL,
    class_id VARCHAR(5) NOT NULL,
    fare DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (train_id) REFERENCES trains(train_id),
    FOREIGN KEY (class_id) REFERENCES train_classes(class_id),
    UNIQUE KEY (train_id, class_id)
) ENGINE=InnoDB;

-- Bookings table
CREATE TABLE bookings (
    pnr_number VARCHAR(15) PRIMARY KEY,
    user_id INT NOT NULL,
    train_id VARCHAR(10) NOT NULL,
    journey_date DATE NOT NULL,
    booking_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_fare DECIMAL(10,2) NOT NULL,
    status ENUM('CONFIRMED', 'CANCELLED', 'WAITING') DEFAULT 'CONFIRMED',
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (train_id) REFERENCES trains(train_id)
) ENGINE=InnoDB;

-- Passengers table
CREATE TABLE passengers (
    passenger_id INT AUTO_INCREMENT PRIMARY KEY,
    pnr_number VARCHAR(15) NOT NULL,
    name VARCHAR(100) NOT NULL,
    age INT NOT NULL,
    gender ENUM('Male', 'Female', 'Other', 'Prefer not to say') NOT NULL,
    title ENUM('Mr.', 'Ms.', 'Mrs.', 'Dr.', 'Prof.') NOT NULL,
    travel_class VARCHAR(5) NOT NULL,
    seat_number VARCHAR(10) NULL,
    FOREIGN KEY (pnr_number) REFERENCES bookings(pnr_number),
    FOREIGN KEY (travel_class) REFERENCES train_classes(class_id)
) ENGINE=InnoDB;

-- Cancellations table
CREATE TABLE cancellations (
    cancellation_id INT AUTO_INCREMENT PRIMARY KEY,
    pnr_number VARCHAR(15) NOT NULL,
    cancellation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    refund_amount DECIMAL(10,2) NOT NULL,
    reason VARCHAR(255) NULL,
    FOREIGN KEY (pnr_number) REFERENCES bookings(pnr_number)
) ENGINE=InnoDB;

-- View 1: Available trains between stations
CREATE VIEW available_trains AS
SELECT 
    t.train_id, 
    t.train_name, 
    s1.station_name AS source_station, 
    s2.station_name AS destination_station,
    t.departure_time,
    t.arrival_time
FROM 
    trains t
JOIN 
    stations s1 ON t.source_station = s1.station_code
JOIN 
    stations s2 ON t.destination_station = s2.station_code
WHERE 
    t.status = 'ACTIVE';
ALTER TABLE trains ADD COLUMN status VARCHAR(20) DEFAULT 'ACTIVE';

-- View 2: User booking history
CREATE VIEW user_booking_history AS
SELECT 
    u.username,
    b.pnr_number,
    t.train_name,
    b.journey_date,
    b.booking_date,
    b.total_fare,
    b.status,
    COUNT(p.passenger_id) AS passenger_count
FROM 
    bookings b
JOIN 
    users u ON b.user_id = u.user_id
JOIN 
    trains t ON b.train_id = t.train_id
LEFT JOIN 
    passengers p ON b.pnr_number = p.pnr_number
GROUP BY 
    b.pnr_number;

-- View 3: Train fare details
CREATE VIEW train_fare_details AS
SELECT 
    t.train_id,
    t.train_name,
    tc.class_id,
    tc.class_name,
    tf.fare
FROM 
    train_fare tf
JOIN 
    trains t ON tf.train_id = t.train_id
JOIN 
    train_classes tc ON tf.class_id = tc.class_id;

-- Procedure 1: Book a ticket
DELIMITER //
CREATE PROCEDURE book_ticket(
    IN p_username VARCHAR(50),
    IN p_train_id VARCHAR(10),
    IN p_journey_date DATE,
    IN p_passenger_name VARCHAR(100),
    IN p_passenger_age INT,
    IN p_passenger_gender ENUM('Male', 'Female', 'Other', 'Prefer not to say'),
    IN p_passenger_title ENUM('Mr.', 'Ms.', 'Mrs.', 'Dr.', 'Prof.'),
    IN p_travel_class VARCHAR(5),
    OUT p_pnr_number VARCHAR(15),
    OUT p_status VARCHAR(20),
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE v_user_id INT;
    DECLARE v_fare DECIMAL(10,2);
    DECLARE v_pnr VARCHAR(15);
    
    -- Start transaction
    START TRANSACTION;
    
    -- Get user ID
    SELECT user_id INTO v_user_id FROM users WHERE username = p_username;
    
    IF v_user_id IS NULL THEN
        SET p_status = 'FAILURE';
        SET p_message = 'User not found';
        ROLLBACK;
    ELSE
        -- Get fare for the selected class
        SELECT fare INTO v_fare FROM train_fare 
        WHERE train_id = p_train_id AND class_id = p_travel_class;
        
        IF v_fare IS NULL THEN
            SET p_status = 'FAILURE';
            SET p_message = 'Fare not found for selected class';
            ROLLBACK;
        ELSE
            -- Generate PNR number
            SET v_pnr = CONCAT(
                SUBSTRING(p_train_id, 1, 3),
                DATE_FORMAT(p_journey_date, '%d%m'),
                FLOOR(RAND() * 9000) + 1000
            );
            
            -- Create booking
            INSERT INTO bookings (pnr_number, user_id, train_id, journey_date, total_fare)
            VALUES (v_pnr, v_user_id, p_train_id, p_journey_date, v_fare);
            
            -- Add passenger
            INSERT INTO passengers (pnr_number, name, age, gender, title, travel_class)
            VALUES (v_pnr, p_passenger_name, p_passenger_age, p_passenger_gender, p_passenger_title, p_travel_class);
            
            SET p_pnr_number = v_pnr;
            SET p_status = 'SUCCESS';
            SET p_message = 'Ticket booked successfully';
            
            COMMIT;
        END IF;
    END IF;
END //
DELIMITER ;

-- Procedure 2: Cancel a ticket
DELIMITER //

CREATE PROCEDURE cancel_ticket(
    IN p_pnr_number VARCHAR(15),
    IN p_reason VARCHAR(255),
    OUT p_status VARCHAR(20),
    OUT p_message VARCHAR(255),
    OUT p_refund_amount DECIMAL(10,2)
)
BEGIN
    DECLARE v_booking_status VARCHAR(20);
    DECLARE v_total_fare DECIMAL(10,2);
    DECLARE v_journey_date DATE;
    DECLARE v_days_diff INT DEFAULT 0;
    
    -- Start transaction
    START TRANSACTION;
    
    -- Get booking details
    SELECT status, total_fare, journey_date 
    INTO v_booking_status, v_total_fare, v_journey_date
    FROM bookings 
    WHERE pnr_number = p_pnr_number;
    
    IF v_booking_status IS NULL THEN
        SET p_status = 'FAILURE';
        SET p_message = 'Booking not found';
        SET p_refund_amount = 0.00;
        ROLLBACK;
    ELSEIF v_booking_status = 'CANCELLED' THEN
        SET p_status = 'FAILURE';
        SET p_message = 'Booking already cancelled';
        SET p_refund_amount = 0.00;
        ROLLBACK;
    ELSE
        -- Calculate days difference
        SET v_days_diff = DATEDIFF(v_journey_date, CURDATE());
        
        -- Calculate refund amount based on cancellation policy
        IF v_days_diff > 30 THEN
            SET p_refund_amount = ROUND(v_total_fare * 0.9, 2); -- 90% refund
        ELSEIF v_days_diff > 15 THEN
            SET p_refund_amount = ROUND(v_total_fare * 0.75, 2); -- 75% refund
        ELSEIF v_days_diff > 7 THEN
            SET p_refund_amount = ROUND(v_total_fare * 0.5, 2); -- 50% refund
        ELSE
            SET p_refund_amount = 0.00; -- No refund
        END IF;
        
        -- Update booking status
        UPDATE bookings SET status = 'CANCELLED' WHERE pnr_number = p_pnr_number;
        
        -- Record cancellation
        INSERT INTO cancellations (pnr_number, refund_amount, reason)
        VALUES (p_pnr_number, p_refund_amount, p_reason);
        
        SET p_status = 'SUCCESS';
        SET p_message = CONCAT('Ticket cancelled successfully. Refund amount: ₹', FORMAT(p_refund_amount, 2));
        
        COMMIT;
    END IF;
END //

DELIMITER ;

-- Procedure 3: User authentication
DELIMITER //

CREATE PROCEDURE authenticate_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    OUT p_success TINYINT(1),  -- Changed from BOOLEAN to TINYINT(1) for better compatibility
    OUT p_message VARCHAR(255),
    OUT p_user_data TEXT       -- Changed from JSON to TEXT for wider compatibility
)
BEGIN
    DECLARE v_user_id INT DEFAULT 0;
    DECLARE v_username VARCHAR(50) DEFAULT '';
    DECLARE v_email VARCHAR(100) DEFAULT '';
    
    -- Initialize output parameters
    SET p_success = 0;
    SET p_message = '';
    SET p_user_data = NULL;
    
    -- Find matching user
    SELECT user_id, username, email 
    INTO v_user_id, v_username, v_email
    FROM users 
    WHERE username = p_username AND password = p_password
    LIMIT 1;
    
    IF v_user_id > 0 THEN
        -- Update last login
        UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE user_id = v_user_id;
        
        SET p_success = 1;  -- Using 1 for TRUE
        SET p_message = 'Login successful';
        
        -- Create JSON-like string manually for compatibility
        SET p_user_data = CONCAT(
            '{"user_id":', v_user_id,
            ',"username":"', v_username,
            '","email":"', v_email, '"}'
        );
    ELSE
        SET p_success = 0;  -- Using 0 for FALSE
        SET p_message = 'Invalid username or password';
    END IF;
END //

DELIMITER ;

-- Trigger 1: Validate passenger age before booking

DELIMITER //

CREATE TRIGGER validate_passenger_age
BEFORE INSERT ON passengers
FOR EACH ROW
BEGIN
    IF NEW.age < 1 THEN
        -- For MySQL 9.2 compatibility, we use the older SIGNAL syntax
        CALL raise_application_error(-20001, 'Passenger age must be at least 1 year');
    END IF;
END//
DELIMITER ;

-- Trigger 2: Update booking status when all passengers are cancelled

DELIMITER //

CREATE TRIGGER update_booking_status
AFTER INSERT ON cancellations
FOR EACH ROW
BEGIN
    DECLARE v_passenger_count INT DEFAULT 0;
    DECLARE v_cancelled_count INT DEFAULT 0;
    
    -- Count total passengers for this booking
    SELECT COUNT(*) INTO v_passenger_count
    FROM passengers
    WHERE pnr_number = NEW.pnr_number;
    
    -- Count cancelled passengers (if any)
    SELECT COUNT(*) INTO v_cancelled_count
    FROM passengers p, bookings b
    WHERE p.pnr_number = b.pnr_number
    AND p.pnr_number = NEW.pnr_number
    AND b.status = 'CANCELLED';
    
    -- If all passengers are cancelled, update booking status
    IF v_passenger_count = v_cancelled_count AND v_passenger_count > 0 THEN
        UPDATE bookings 
        SET status = 'CANCELLED' 
        WHERE pnr_number = NEW.pnr_number;
    END IF;
END//

DELIMITER ;

-- Trigger 3: Log user registration
DELIMITER //
DELIMITER //

CREATE TRIGGER log_user_registration
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    -- Ensure the log table exists (safe execution)
    IF EXISTS (SELECT 1 FROM information_schema.tables 
              WHERE table_schema = DATABASE() 
              AND table_name = 'user_activity_log') THEN
                
        INSERT INTO user_activity_log 
        (user_id, activity_type, activity_details, activity_date)
        VALUES (
            NEW.user_id, 
            'REGISTRATION', 
            CONCAT('User ', NEW.username, ' registered'),
            NOW()
        );
    END IF;
END//

DELIMITER ; //
DELIMITER ;

-- Transaction 1: User registration with validation
DELIMITER //
CREATE PROCEDURE register_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_email VARCHAR(100),
    OUT p_status VARCHAR(20),
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE v_user_exists INT;
    
    -- Start transaction
    START TRANSACTION;
    
    -- Check if username exists
    SELECT COUNT(*) INTO v_user_exists FROM users WHERE username = p_username;
    
    IF v_user_exists > 0 THEN
        SET p_status = 'FAILURE';
        SET p_message = 'Username already exists';
        ROLLBACK;
    ELSE
        -- Check if email exists
        SELECT COUNT(*) INTO v_user_exists FROM users WHERE email = p_email;
        
        IF v_user_exists > 0 THEN
            SET p_status = 'FAILURE';
            SET p_message = 'Email already registered';
            ROLLBACK;
        ELSE
            -- Insert new user
            INSERT INTO users (username, password, email)
            VALUES (p_username, p_password, p_email);
            
            SET p_status = 'SUCCESS';
            SET p_message = 'User registered successfully';
            
            COMMIT;
        END IF;
    END IF;
END //
DELIMITER ;

-- Transaction 2: Update train fare with validation
DELIMITER //
CREATE PROCEDURE update_train_fare(
    IN p_train_id VARCHAR(10),
    IN p_class_id VARCHAR(5),
    IN p_new_fare DECIMAL(10,2),
    OUT p_status VARCHAR(20),
    OUT p_message VARCHAR(255)
)
BEGIN
    DECLARE v_fare_exists INT;
    
    -- Start transaction
    START TRANSACTION;
    
    -- Check if fare exists
    SELECT COUNT(*) INTO v_fare_exists 
    FROM train_fare 
    WHERE train_id = p_train_id AND class_id = p_class_id;
    
    IF v_fare_exists = 0 THEN
        SET p_status = 'FAILURE';
        SET p_message = 'Fare combination not found';
        ROLLBACK;
    ELSEIF p_new_fare <= 0 THEN
        SET p_status = 'FAILURE';
        SET p_message = 'Fare must be greater than 0';
        ROLLBACK;
    ELSE
        -- Update fare
        UPDATE train_fare 
        SET fare = p_new_fare 
        WHERE train_id = p_train_id AND class_id = p_class_id;
        
        SET p_status = 'SUCCESS';
        SET p_message = 'Fare updated successfully';
        
        COMMIT;
    END IF;
END //
DELIMITER ;

-- Transaction 3: Bulk insert stations with validation
DELIMITER //
CREATE PROCEDURE bulk_insert_stations(
    IN p_stations JSON,
    OUT p_status VARCHAR(20),
    OUT p_message VARCHAR(255),
    OUT p_inserted_count INT,
    OUT p_skipped_count INT
)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE v_station_count INT;
    DECLARE v_station_code VARCHAR(10);
    DECLARE v_station_name VARCHAR(100);
    DECLARE v_city VARCHAR(50);
    DECLARE v_state VARCHAR(50);
    DECLARE v_exists INT;
    
    SET p_inserted_count = 0;
    SET p_skipped_count = 0;
    
    -- Get the number of stations in the JSON array
    SET v_station_count = JSON_LENGTH(p_stations);
    
    -- Start transaction
    START TRANSACTION;
    
    -- Loop through each station
    WHILE i < v_station_count DO
        -- Extract station data from JSON
        SET v_station_code = JSON_UNQUOTE(JSON_EXTRACT(p_stations, CONCAT('$[', i, '].station_code')));
        SET v_station_name = JSON_UNQUOTE(JSON_EXTRACT(p_stations, CONCAT('$[', i, '].station_name')));
        SET v_city = JSON_UNQUOTE(JSON_EXTRACT(p_stations, CONCAT('$[', i, '].city')));
        SET v_state = JSON_UNQUOTE(JSON_EXTRACT(p_stations, CONCAT('$[', i, '].state')));
        
        -- Check if station already exists
        SELECT COUNT(*) INTO v_exists FROM stations WHERE station_code = v_station_code;
        
        IF v_exists = 0 THEN
            -- Insert new station
            INSERT INTO stations (station_code, station_name, city, state)
            VALUES (v_station_code, v_station_name, v_city, v_state);
            
            SET p_inserted_count = p_inserted_count + 1;
        ELSE
            SET p_skipped_count = p_skipped_count + 1;
        END IF;
        
        SET i = i + 1;
    END WHILE;
    
    SET p_status = 'SUCCESS';
    SET p_message = CONCAT('Bulk insert completed. Inserted: ', p_inserted_count, ', Skipped: ', p_skipped_count);
    
    COMMIT;
END //
DELIMITER ;

-- Insert stations
INSERT INTO stations (station_code, station_name, city, state) VALUES
('SBC', 'Bengaluru City Jn', 'Bengaluru', 'Karnataka'),
('MYS', 'Mysuru Jn', 'Mysuru', 'Karnataka'),
('UBL', 'Hubballi Jn', 'Hubballi', 'Karnataka'),
('BCT', 'Mumbai Central', 'Mumbai', 'Maharashtra'),
('PUNE', 'Pune Jn', 'Pune', 'Maharashtra'),
('NGP', 'Nagpur Jn', 'Nagpur', 'Maharashtra'),
('NDLS', 'New Delhi', 'Delhi', 'Delhi'),
('LKO', 'Lucknow Charbagh NR', 'Lucknow', 'Uttar Pradesh'),
('CNB', 'Kanpur Central', 'Kanpur', 'Uttar Pradesh'),
('MAS', 'MGR Chennai Central', 'Chennai', 'Tamil Nadu'),
('MDU', 'Madurai Jn', 'Madurai', 'Tamil Nadu'),
('TPJ', 'Tiruchchirappalli Jn', 'Tiruchirappalli', 'Tamil Nadu'),
('HWH', 'Howrah Jn', 'Kolkata', 'West Bengal'),
('SDAH', 'Sealdah', 'Kolkata', 'West Bengal'),
('KGP', 'Kharagpur Jn', 'Kharagpur', 'West Bengal');

-- Insert train classes
INSERT INTO train_classes (class_id, class_name, description) VALUES
('EC', 'Executive Chair Car', 'Premium AC seating with extra legroom'),
('CC', 'AC Chair Car', 'Air-conditioned seating'),
('1A', 'First Class AC', 'Most premium AC accommodation with lockable doors'),
('2A', 'AC Two-Tier', 'AC sleeper with curtains and bedding'),
('3A', 'AC Three-Tier', 'AC sleeper with open berths'),
('SL', 'Sleeper Class', 'Non-AC sleeper with open berths'),
('2S', 'Second Sitting', 'Basic non-AC seating');

-- Insert trains
-- Disable foreign key checks temporarily (if absolutely necessary)
SET FOREIGN_KEY_CHECKS = 0;

INSERT INTO trains (train_id, train_name, source_station, destination_station, departure_time, arrival_time, days_available) VALUES
('12007', 'Chennai Central Shatabdi Express', 'MAS', 'SBC', '06:00:00', '11:00:00', '1,3,5'),
('12609', 'MGR Chennai Central SF Express', 'MAS', 'NDLS', '20:30:00', '05:30:00', 'Daily'),
('12658', 'KSR Bengaluru - Chennai Mail', 'SBC', 'MAS', '22:30:00', '06:30:00', 'Daily'),
('12696', 'Chennai SF Express', 'MAS', 'HWH', '08:00:00', '10:00:00', '2,4,6'),
('12001', 'New Delhi - Bhopal Habibganj Shatabdi Express', 'NDLS', 'BPL', '06:00:00', '11:30:00', 'Daily'),
('22691', 'Bengaluru - Hazrat Nizamuddin Rajdhani Express', 'SBC', 'NZM', '20:00:00', '05:30:00', '2,5');

-- Re-enable foreign key checks
SET FOREIGN_KEY_CHECKS = 1;

-- Insert train fares
INSERT INTO train_fare (train_id, class_id, fare) VALUES
('12007', 'EC', 1500),
('12007', 'CC', 900),
('12609', '1A', 2200),
('12609', '2A', 1300),
('12609', '3A', 950),
('12609', 'SL', 350),
('12658', '2A', 1200),
('12658', '3A', 850),
('12658', 'SL', 300),
('12658', '2S', 200),
('12696', '2A', 1250),
('12696', '3A', 900),
('12696', 'SL', 320),
('12001', 'EC', 1600),
('12001', 'CC', 950),
('22691', '1A', 2500),
('22691', '2A', 1500),
('22691', '3A', 1100);
INSERT INTO train_fare (train_id, class_id, fare)
VALUES ('22691', '2A', 1500)
ON DUPLICATE KEY UPDATE fare = 1500;