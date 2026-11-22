-- Purpose: build silver.EMS_Incident from bronze (no rows deleted)
-- Depends on: 02_bronze_load_and_checks.sql
USE NYC_EMS_DW;
GO

DROP TABLE IF EXISTS silver.EMS_Incident;
GO

SELECT
    incident_id,
    incident_datetime,
    TRIM(initial_call_type)                      AS initial_call_type,
    initial_severity_level,
    TRIM(final_call_type)                        AS final_call_type,
    final_severity_level,
    first_assignment_datetime,
    is_valid_dispatch_response,
    dispatch_response_seconds,
    first_activation_datetime,
    first_on_scene_datetime,
    is_valid_incident_response,
    incident_response_seconds,
    incident_travel_seconds,
    first_to_hosp_datetime,
    first_hosp_arrival_datetime,
    incident_close_datetime,
    is_held,
    UPPER(TRIM(incident_disposition_code))       AS incident_disposition_code,
    UPPER(TRIM(borough))                         AS borough,
    UPPER(TRIM(incident_dispatch_area))          AS incident_dispatch_area,
    ISNULL(TRIM(zipcode), 'Unknown')             AS zipcode,
    police_precinct,
    city_council_district,
    community_district,
    community_school_district,
    congressional_district,
    is_reopened,
    is_special_event,
    is_standby,
    CASE WHEN is_transfer = 'True' THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS is_transfer,
    is_zero_response,
    CASE WHEN first_assignment_datetime < incident_datetime
           OR incident_close_datetime  < incident_datetime
         THEN 1 ELSE 0 END                       AS has_time_issue
INTO silver.EMS_Incident
FROM bronze.EMS_Incident;
GO

-- Log the checks
DELETE FROM audit.DataQualityReport WHERE Table_Name LIKE 'silver.%';
GO

INSERT INTO audit.DataQualityReport (Check_Name, Table_Name, Expected_Value, Actual_Value, Check_Status)
SELECT Check_Name, Table_Name, Expected_Value, Actual_Value,
       CASE WHEN Actual_Value = Expected_Value THEN 'PASS' ELSE Fail_Label END
FROM (VALUES
    ('Row count: bronze vs silver', 'silver.EMS_Incident',
        (SELECT COUNT_BIG(*) FROM bronze.EMS_Incident),
        (SELECT COUNT_BIG(*) FROM silver.EMS_Incident), 'FAIL'),
    ('Invalid incident response (flag = 0)', 'silver.EMS_Incident', 0,
        (SELECT COUNT_BIG(*) FROM silver.EMS_Incident WHERE is_valid_incident_response = 0), 'REVIEW'),
    ('Zero-second responses', 'silver.EMS_Incident', 0,
        (SELECT COUNT_BIG(*) FROM silver.EMS_Incident WHERE is_zero_response = 1), 'REVIEW'),
    ('Timestamps out of order', 'silver.EMS_Incident', 0,
        (SELECT COUNT_BIG(*) FROM silver.EMS_Incident WHERE has_time_issue = 1), 'REVIEW'),
    ('Unknown borough', 'silver.EMS_Incident', 0,
        (SELECT COUNT_BIG(*) FROM silver.EMS_Incident WHERE borough = 'UNKNOWN'), 'REVIEW'),
    ('Missing zipcode', 'silver.EMS_Incident', 0,
        (SELECT COUNT_BIG(*) FROM silver.EMS_Incident WHERE zipcode = 'Unknown'), 'REVIEW')
) AS t(Check_Name, Table_Name, Expected_Value, Actual_Value, Fail_Label);
GO

SELECT * FROM audit.DataQualityReport ORDER BY Check_ID;