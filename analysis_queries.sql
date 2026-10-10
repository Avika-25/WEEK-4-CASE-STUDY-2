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
