-- Purpose: profile bronze data to decide Silver rules
USE NYC_EMS_DW;
GO

-- 1) Date range
SELECT MIN(incident_datetime) AS first_date, MAX(incident_datetime) AS last_date
FROM bronze.EMS_Incident;

-- 2) Null counts
SELECT
    COUNT(*) - COUNT(incident_datetime)           AS null_datetime,
    COUNT(*) - COUNT(incident_response_seconds)   AS null_response,
    COUNT(*) - COUNT(dispatch_response_seconds)   AS null_dispatch,
    COUNT(*) - COUNT(incident_travel_seconds)     AS null_travel,
    COUNT(*) - COUNT(borough)                     AS null_borough,
    COUNT(*) - COUNT(incident_dispatch_area)      AS null_area,
    COUNT(*) - COUNT(zipcode)                     AS null_zip,
    COUNT(*) - COUNT(incident_disposition_code)   AS null_dispo
FROM bronze.EMS_Incident;

-- 3) Response time check
SELECT MIN(incident_response_seconds) AS min_sec,
       MAX(incident_response_seconds) AS max_sec,
       COUNT(CASE WHEN incident_response_seconds < 0 THEN 1 END) AS negative_values
FROM bronze.EMS_Incident;

-- 4) Valid flag and zero response counts
SELECT is_valid_incident_response, is_zero_response, COUNT(*) AS n
FROM bronze.EMS_Incident
GROUP BY is_valid_incident_response, is_zero_response;

-- 5) Borough and is_transfer values
SELECT borough, COUNT(*) AS n FROM bronze.EMS_Incident GROUP BY borough ORDER BY n DESC;
SELECT is_transfer, COUNT(*) AS n FROM bronze.EMS_Incident GROUP BY is_transfer;

-- 6) Dispatch areas
SELECT incident_dispatch_area, COUNT(*) AS n
FROM bronze.EMS_Incident GROUP BY incident_dispatch_area ORDER BY n DESC;

-- 7) Disposition codes
SELECT incident_disposition_code, COUNT(*) AS n
FROM bronze.EMS_Incident GROUP BY incident_disposition_code ORDER BY n DESC;

-- 8) Timestamps out of order
SELECT COUNT(CASE WHEN first_assignment_datetime < incident_datetime THEN 1 END) AS assign_before_incident,
       COUNT(CASE WHEN incident_close_datetime < incident_datetime THEN 1 END)  AS close_before_incident
FROM bronze.EMS_Incident;