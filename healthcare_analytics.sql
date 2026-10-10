-- =====================================================================
-- MediCare Hospital — Patient Analytics & Readmission Prediction
-- MySQL script (cmd/terminal, no Workbench)
--
-- Run this FIRST with the full path to mysql.exe:
--   "C:\Program Files\MySQL\MySQL Server 9.7\bin\mysql.exe" --local-infile=1 -u root -p < healthcare_analytics.sql
-- Then run the Python notebook, which adds the readmission_risk table on top.
-- =====================================================================

SET GLOBAL local_infile = 1;

CREATE DATABASE IF NOT EXISTS healthcare_analytics_db;
USE healthcare_analytics_db;

-- ---------------------------------------------------------------------
-- 1. TABLES — matching the schema and constraints given in the brief
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS vitals;
DROP TABLE IF EXISTS treatments;
DROP TABLE IF EXISTS admissions;
DROP TABLE IF EXISTS patients;
DROP TABLE IF EXISTS doctors;

CREATE TABLE patients (
    patient_id          INT PRIMARY KEY,
    first_name          VARCHAR(50) NOT NULL,
    last_name           VARCHAR(50) NOT NULL,
    dob                 DATE NOT NULL,
    gender              VARCHAR(10) NOT NULL,
    contact_no          VARCHAR(15) NOT NULL,
    address             VARCHAR(255),
    chronic_conditions  VARCHAR(255)
);

CREATE TABLE doctors (
    doctor_id       INT PRIMARY KEY,
    first_name      VARCHAR(50) NOT NULL,
    last_name       VARCHAR(50) NOT NULL,
    specialization  VARCHAR(255) NOT NULL,
    contact_no      VARCHAR(15) NOT NULL
);

CREATE TABLE admissions (
    admission_id    INT PRIMARY KEY,
    patient_id      INT NOT NULL,
    admission_date  DATE NOT NULL,
    discharge_date  DATE,                      -- NULL = still admitted
    diagnosis       VARCHAR(255) NOT NULL,
    doctor_id       INT,
    room_no         VARCHAR(10),
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
);

CREATE TABLE vitals (
    vital_id        INT PRIMARY KEY,
    admission_id    INT NOT NULL,
    recorded_time   DATETIME NOT NULL,
    heart_rate      INT NOT NULL,
    blood_pressure  VARCHAR(10) NOT NULL,
    oxygen_level    INT NOT NULL,
    temperature     DECIMAL(5,2) NOT NULL,
    FOREIGN KEY (admission_id) REFERENCES admissions(admission_id)
);

CREATE TABLE treatments (
    treatment_id    INT PRIMARY KEY,
    admission_id    INT NOT NULL,
    treatment_date  DATE NOT NULL,
    procedure_name  VARCHAR(255),    -- renamed from "procedure", a reserved-adjacent word best avoided as a column name
    medication      VARCHAR(255) NOT NULL,
    dosage          VARCHAR(50),
    FOREIGN KEY (admission_id) REFERENCES admissions(admission_id)
);

-- readmission_risk is intentionally NOT created here - it doesn't exist until the
-- Python notebook trains the model and writes it with to_sql()

-- ---------------------------------------------------------------------
-- 2. LOAD THE CSV FILES — update these paths to your actual data folder
-- ---------------------------------------------------------------------

LOAD DATA LOCAL INFILE 'C:/Users/aviksomya.ext/OneDrive - Deloitte (O365D)/Desktop/WEEK 4 cs2/patients.csv'
INTO TABLE patients
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'C:/Users/aviksomya.ext/OneDrive - Deloitte (O365D)/Desktop/WEEK 4 cs2/doctors.csv'
INTO TABLE doctors
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'C:/Users/aviksomya.ext/OneDrive - Deloitte (O365D)/Desktop/WEEK 4 cs2/admissions.csv'
INTO TABLE admissions
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(admission_id, patient_id, admission_date, @discharge_date, diagnosis, doctor_id, room_no)
SET discharge_date = NULLIF(@discharge_date, '');   -- blank discharge_date becomes a real NULL, not an empty string

LOAD DATA LOCAL INFILE 'C:/Users/aviksomya.ext/OneDrive - Deloitte (O365D)/Desktop/WEEK 4 cs2/vitals.csv'
INTO TABLE vitals
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE 'C:/Users/aviksomya.ext/OneDrive - Deloitte (O365D)/Desktop/WEEK 4 cs2/treatments.csv'
INTO TABLE treatments
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'patients' AS tbl, COUNT(*) AS rows_loaded FROM patients
UNION ALL SELECT 'doctors', COUNT(*) FROM doctors
UNION ALL SELECT 'admissions', COUNT(*) FROM admissions
UNION ALL SELECT 'vitals', COUNT(*) FROM vitals
UNION ALL SELECT 'treatments', COUNT(*) FROM treatments;

-- ---------------------------------------------------------------------
-- 3. DATA QUALITY VALIDATION CHECKS
-- ---------------------------------------------------------------------

-- missing values
SELECT
    SUM(dob IS NULL) AS missing_dob,
    SUM(gender IS NULL) AS missing_gender,
    SUM(chronic_conditions IS NULL) AS missing_chronic_conditions
FROM patients;

-- admissions with no discharge_date = still admitted (not necessarily a data error,
-- but worth knowing how many before building reports that assume every stay has ended)
SELECT COUNT(*) AS still_admitted FROM admissions WHERE discharge_date IS NULL;

-- duplicate key checks
SELECT patient_id, COUNT(*) FROM patients GROUP BY patient_id HAVING COUNT(*) > 1;
SELECT admission_id, COUNT(*) FROM admissions GROUP BY admission_id HAVING COUNT(*) > 1;

-- range checks on vitals
SELECT COUNT(*) AS bad_heart_rate FROM vitals WHERE heart_rate < 30 OR heart_rate > 220;
SELECT COUNT(*) AS bad_oxygen FROM vitals WHERE oxygen_level < 50 OR oxygen_level > 100;
SELECT COUNT(*) AS bad_temperature FROM vitals WHERE temperature < 90 OR temperature > 110;

-- referential integrity
SELECT COUNT(*) AS orphan_admissions FROM admissions a
LEFT JOIN patients p ON p.patient_id = a.patient_id WHERE p.patient_id IS NULL;

SELECT COUNT(*) AS orphan_vitals FROM vitals v
LEFT JOIN admissions a ON a.admission_id = v.admission_id WHERE a.admission_id IS NULL;

-- vitals or treatments dated outside their own admission's stay window - a known
-- data quality issue in this sample data, flagged here rather than silently ignored
SELECT COUNT(*) AS vitals_outside_stay
FROM vitals v
JOIN admissions a ON a.admission_id = v.admission_id
WHERE DATE(v.recorded_time) < a.admission_date
   OR (a.discharge_date IS NOT NULL AND DATE(v.recorded_time) > a.discharge_date);

SELECT COUNT(*) AS treatments_outside_stay
FROM treatments t
JOIN admissions a ON a.admission_id = t.admission_id
WHERE t.treatment_date < a.admission_date
   OR (a.discharge_date IS NOT NULL AND t.treatment_date > a.discharge_date);

-- ---------------------------------------------------------------------
-- 4. REPORTING QUERIES 
-- ---------------------------------------------------------------------

-- 4.1 Hospital Admission Trends — daily admissions and discharges
SELECT admission_date, COUNT(*) AS admissions_count
FROM admissions
GROUP BY admission_date
ORDER BY admission_date;

SELECT discharge_date, COUNT(*) AS discharges_count
FROM admissions
WHERE discharge_date IS NOT NULL
GROUP BY discharge_date
ORDER BY discharge_date;

-- admissions by diagnosis - which conditions show up most
SELECT diagnosis, COUNT(*) AS admission_count
FROM admissions
GROUP BY diagnosis
ORDER BY admission_count DESC;

-- 4.2 High-Risk Patient Prediction — this needs readmission_risk, which only exists
-- after the Python notebook has run. Run this after that step.
SELECT
    r.risk_level,
    COUNT(*) AS patient_count,
    ROUND(AVG(r.risk_score), 2) AS avg_risk_score
FROM readmission_risk r
GROUP BY r.risk_level
ORDER BY avg_risk_score DESC;

SELECT
    p.patient_id, p.first_name, p.last_name, a.diagnosis, r.risk_score, r.risk_level
FROM readmission_risk r
JOIN admissions a ON a.admission_id = r.admission_id
JOIN patients p ON p.patient_id = a.patient_id
WHERE r.risk_level = 'High'
ORDER BY r.risk_score DESC;

-- 4.3 Vitals Monitoring Dashboard — abnormal readings worth a closer look
SELECT
    a.admission_id, p.first_name, p.last_name, v.recorded_time,
    v.heart_rate, v.oxygen_level, v.temperature
FROM vitals v
JOIN admissions a ON a.admission_id = v.admission_id
JOIN patients p ON p.patient_id = a.patient_id
WHERE v.heart_rate < 60 OR v.heart_rate > 100
   OR v.oxygen_level < 92
   OR v.temperature > 100.4
ORDER BY v.recorded_time DESC;

-- 4.4 Readmission Rate Analysis — by diagnosis and by attending doctor
-- (needs readmission_risk's admission_id list of discharged admissions, but the
-- readmission flag itself was computed in Python and is visible via that table's
-- presence; this view approximates it directly from admissions by diagnosis instead)
SELECT
    doc.specialization,
    COUNT(*) AS total_admissions,
    SUM(CASE WHEN a.discharge_date IS NULL THEN 1 ELSE 0 END) AS still_admitted
FROM admissions a
JOIN doctors doc ON doc.doctor_id = a.doctor_id
GROUP BY doc.specialization
ORDER BY total_admissions DESC;

-- 4.5 Post-Discharge Follow-Up Tracker — recently discharged patients who haven't
-- been flagged with a follow-up prediction yet (useful once readmission_risk exists)
SELECT
    p.patient_id, p.first_name, p.last_name, a.discharge_date, a.diagnosis
FROM admissions a
JOIN patients p ON p.patient_id = a.patient_id
LEFT JOIN readmission_risk r ON r.admission_id = a.admission_id
WHERE a.discharge_date IS NOT NULL
  AND a.discharge_date >= DATE_SUB((SELECT MAX(discharge_date) FROM admissions), INTERVAL 14 DAY)
ORDER BY a.discharge_date DESC;
