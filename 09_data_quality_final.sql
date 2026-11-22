-- Purpose: final data quality report across all layers
-- Depends on: 08_views.sql
USE NYC_EMS_DW;
GO

DELETE FROM audit.DataQualityReport WHERE Check_Name LIKE 'FINAL:%';
GO

INSERT INTO audit.DataQualityReport (Check_Name, Table_Name, Expected_Value, Actual_Value, Check_Status, Notes)
SELECT Check_Name, Table_Name, Expected_Value, Actual_Value,
       CASE WHEN Actual_Value = Expected_Value THEN 'PASS' ELSE Fail_Label END, Notes
FROM (VALUES
 -- Row counts across layers (all should equal the source count)
 ('FINAL: source (dbo) rows',        'dbo.ems_incidents_clean', CAST(4862291 AS BIGINT), (SELECT COUNT_BIG(*) FROM dbo.ems_incidents_clean), 'FAIL', 'Python count from the brief'),
 ('FINAL: bronze rows',              'bronze.EMS_Incident',     CAST(4862291 AS BIGINT), (SELECT COUNT_BIG(*) FROM bronze.EMS_Incident),     'FAIL', NULL),
 ('FINAL: silver rows',              'silver.EMS_Incident',     CAST(4862291 AS BIGINT), (SELECT COUNT_BIG(*) FROM silver.EMS_Incident),     'FAIL', NULL),
 ('FINAL: gold fact rows',           'gold.FactEMSIncident',    CAST(4862291 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident),    'FAIL', NULL),
 -- Duplicates and keys
 ('FINAL: duplicate incident IDs',   'gold.FactEMSIncident',    CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) - COUNT_BIG(DISTINCT Incident_ID) FROM gold.FactEMSIncident), 'FAIL', NULL),
 ('FINAL: unmatched dimension keys', 'gold.FactEMSIncident',    CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident f
        WHERE NOT EXISTS (SELECT 1 FROM gold.DimDate d WHERE d.Date_Key = f.Date_Key)
           OR NOT EXISTS (SELECT 1 FROM gold.DimTime t WHERE t.Time_Key = f.Time_Key)
           OR NOT EXISTS (SELECT 1 FROM gold.DimLocation l WHERE l.Location_Key = f.Location_Key)
           OR NOT EXISTS (SELECT 1 FROM gold.DimCallType c WHERE c.CallType_Key = f.CallType_Key)
           OR NOT EXISTS (SELECT 1 FROM gold.DimSeverity s WHERE s.Severity_Key = f.Severity_Key)
           OR NOT EXISTS (SELECT 1 FROM gold.DimDisposition p WHERE p.Disposition_Key = f.Disposition_Key)), 'FAIL', NULL),
 -- Response time checks
 ('FINAL: negative response times',  'gold.FactEMSIncident',    CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident WHERE Incident_Response_Seconds < 0), 'FAIL', NULL),
 ('FINAL: negative dispatch times',  'gold.FactEMSIncident',    CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident WHERE Dispatch_Response_Seconds < 0), 'FAIL', NULL),
 ('FINAL: negative travel times',    'gold.FactEMSIncident',    CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident WHERE Travel_Time_Seconds < 0), 'FAIL', NULL),
 ('FINAL: valid flag but no response time', 'gold.FactEMSIncident', CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident WHERE Valid_Incident_Response = 1 AND Incident_Response_Seconds IS NULL), 'FAIL', NULL),
 ('FINAL: responses over 24 hours (kept)', 'gold.FactEMSIncident', CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident WHERE Incident_Response_Seconds > 86400), 'REVIEW', 'Extreme values are kept, not deleted'),
 -- Important columns
 ('FINAL: NULL incident_datetime',   'gold.FactEMSIncident',    CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident WHERE Incident_DateTime IS NULL), 'FAIL', NULL),
 ('FINAL: missing severity (-1)',    'gold.DimSeverity',        CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.DimSeverity WHERE Initial_Severity_Level = -1 OR Final_Severity_Level = -1), 'REVIEW', NULL),
 ('FINAL: disposition codes without a description', 'gold.DimDisposition', CAST(0 AS BIGINT), (SELECT COUNT_BIG(*) FROM gold.DimDisposition WHERE Disposition_Description IS NULL), 'REVIEW', 'Official descriptions not available')
) AS t(Check_Name, Table_Name, Expected_Value, Actual_Value, Fail_Label, Notes);
GO

-- Final report (screenshot this)
SELECT Check_ID, Check_Name, Table_Name, Expected_Value, Actual_Value, Difference, Check_Status, Notes
FROM audit.DataQualityReport
WHERE Check_Name LIKE 'FINAL:%'
ORDER BY Check_ID;
GO

-- Summary of statuses
SELECT Check_Status, COUNT(*) AS n FROM audit.DataQualityReport GROUP BY Check_Status;
GO