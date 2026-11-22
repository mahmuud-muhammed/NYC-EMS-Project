-- Purpose: copy the imported table into bronze and log the basic checks
-- Depends on: 01_setup_schemas_audit.sql
USE NYC_EMS_DW;
GO

-- Remove old versions if you ran an earlier script
DROP TABLE IF EXISTS bronze.EMS_Incident_Raw;
DROP TABLE IF EXISTS bronze.EMS_Incident;
GO

-- Load (can take a minute or two)
SELECT * INTO bronze.EMS_Incident
FROM dbo.ems_incidents_clean;
GO

-- Clear old audit rows so reruns don't duplicate
DELETE FROM audit.DataQualityReport WHERE Table_Name LIKE 'bronze.%';
GO

-- Save the checks in the audit table
INSERT INTO audit.DataQualityReport (Check_Name, Table_Name, Expected_Value, Actual_Value, Check_Status)
SELECT Check_Name, Table_Name, Expected_Value, Actual_Value,
       CASE WHEN Actual_Value = Expected_Value THEN 'PASS' ELSE Fail_Label END
FROM (VALUES
    ('Row count: Python vs bronze', 'bronze.EMS_Incident', CAST(4862291 AS BIGINT),
        (SELECT COUNT_BIG(*) FROM bronze.EMS_Incident), 'FAIL'),
    ('Row count: dbo vs bronze', 'bronze.EMS_Incident',
        (SELECT COUNT_BIG(*) FROM dbo.ems_incidents_clean),
        (SELECT COUNT_BIG(*) FROM bronze.EMS_Incident), 'FAIL'),
    ('NULL incident_id', 'bronze.EMS_Incident', CAST(0 AS BIGINT),
        (SELECT COUNT_BIG(*) FROM bronze.EMS_Incident WHERE incident_id IS NULL), 'FAIL'),
    ('Duplicate incident_id', 'bronze.EMS_Incident', CAST(0 AS BIGINT),
        (SELECT COUNT_BIG(*) - COUNT(DISTINCT incident_id) FROM bronze.EMS_Incident), 'REVIEW')
) AS t(Check_Name, Table_Name, Expected_Value, Actual_Value, Fail_Label);
GO

-- Show the report (take a screenshot of this)
SELECT * FROM audit.DataQualityReport ORDER BY Check_ID;