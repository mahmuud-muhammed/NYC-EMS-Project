-- Purpose: create the engineered features as one view on top of the gold star schema
-- Depends on: 05_gold_star_schema.sql
USE NYC_EMS_DW;
GO

---------------------------------------------------------------
-- 1) Peak hours, calculated from the data (top 5 hours by incident count)
--    To change the number of peak hours, change "<= 5" below.
---------------------------------------------------------------
DROP TABLE IF EXISTS gold.PeakHour;
GO
SELECT
    t.[Hour]                                  AS Incident_Hour,
    COUNT(*)                                  AS Total_Incidents,
    RANK() OVER (ORDER BY COUNT(*) DESC)      AS Hour_Rank,
    CASE WHEN RANK() OVER (ORDER BY COUNT(*) DESC) <= 5 THEN 1 ELSE 0 END AS Is_Peak_Hour
INTO gold.PeakHour
FROM gold.FactEMSIncident f
JOIN gold.DimTime t ON t.Time_Key = f.Time_Key
GROUP BY t.[Hour];
GO

---------------------------------------------------------------
-- 2) Feature view (one row per incident)
---------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_EMS_Incident_Features AS
SELECT
    f.Incident_Key,
    f.Incident_ID,

    -- date and time features
    d.[Year]                                  AS Incident_Year,
    d.Month_Number                            AS Incident_Month_Number,
    d.Month_Name                              AS Incident_Month,
    'Q' + CAST(d.[Quarter] AS VARCHAR(1))     AS Incident_Quarter,
    d.Day_Name                                AS Day_Of_Week,
    t.[Hour]                                  AS Incident_Hour,
    d.Is_Weekend,
    t.Time_Period,
    p.Is_Peak_Hour,

    -- response and travel time in minutes (originals stay in seconds)
    f.Dispatch_Response_Seconds,
    f.Incident_Response_Seconds,
    f.Travel_Time_Seconds,
    f.Incident_Response_Seconds / 60.0        AS Response_Time_Minutes,
    f.Dispatch_Response_Seconds / 60.0        AS Dispatch_Time_Minutes,
    f.Travel_Time_Seconds / 60.0              AS Travel_Time_Minutes,
    f.Valid_Incident_Response,
    f.Valid_Dispatch_Response,

    -- response time category (project bands, NOT an official FDNY standard)
    CASE WHEN f.Valid_Incident_Response = 0 OR f.Incident_Response_Seconds IS NULL THEN 'Not valid'
         WHEN f.Incident_Response_Seconds < 300 THEN 'Under 5 min'
         WHEN f.Incident_Response_Seconds < 600 THEN '5 to 10 min'
         WHEN f.Incident_Response_Seconds < 900 THEN '10 to 15 min'
         ELSE 'Over 15 min' END              AS Response_Time_Category,

    -- threshold flag: 1 = valid response over 10 minutes (placeholder until the Team Leader agrees a benchmark)
    CASE WHEN f.Valid_Incident_Response = 1 AND f.Incident_Response_Seconds > 600 THEN 1
         WHEN f.Valid_Incident_Response = 1 THEN 0
         ELSE NULL END                        AS Response_Threshold_Flag,

    -- severity change (NULL if either severity is missing)
    v.Initial_Severity_Level,
    v.Final_Severity_Level,
    CASE WHEN v.Initial_Severity_Level = -1 OR v.Final_Severity_Level = -1 THEN NULL
         WHEN v.Initial_Severity_Level <> v.Final_Severity_Level THEN 1
         ELSE 0 END                           AS Severity_Changed,

    -- incident duration (open to close, in minutes). NULL if close is missing or before the start.
    -- This is NOT ambulance availability time.
    CASE WHEN f.Incident_Close_DateTime >= f.Incident_DateTime
         THEN DATEDIFF(SECOND, f.Incident_DateTime, f.Incident_Close_DateTime) / 60.0
         ELSE NULL END                        AS Incident_Duration_Minutes,

    -- keys and other columns carried over
    f.Date_Key, f.Time_Key, f.Location_Key, f.CallType_Key, f.Severity_Key, f.Disposition_Key,
    f.Is_Zero_Response, f.Has_Time_Issue,
    f.Held_Indicator, f.Reopen_Indicator, f.Special_Event_Indicator,
    f.Standby_Indicator, f.Transfer_Indicator
FROM gold.FactEMSIncident f
JOIN gold.DimDate     d ON d.Date_Key     = f.Date_Key
JOIN gold.DimTime     t ON t.Time_Key     = f.Time_Key
JOIN gold.DimSeverity v ON v.Severity_Key = f.Severity_Key
JOIN gold.PeakHour    p ON p.Incident_Hour = t.[Hour];
GO

---------------------------------------------------------------
-- 3) Check: the view must have the same number of rows as the fact table
---------------------------------------------------------------
DELETE FROM audit.DataQualityReport WHERE Check_Name = 'Row count: fact vs feature view';
GO
INSERT INTO audit.DataQualityReport (Check_Name, Table_Name, Expected_Value, Actual_Value, Check_Status)
SELECT 'Row count: fact vs feature view', 'gold.vw_EMS_Incident_Features',
       (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident),
       (SELECT COUNT_BIG(*) FROM gold.vw_EMS_Incident_Features),
       CASE WHEN (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident)
               = (SELECT COUNT_BIG(*) FROM gold.vw_EMS_Incident_Features) THEN 'PASS' ELSE 'FAIL' END;
GO

SELECT * FROM audit.DataQualityReport ORDER BY Check_ID;
GO

-- Peak hours (screenshot this)
SELECT * FROM gold.PeakHour ORDER BY Hour_Rank;
GO

-- Quick look at the features (screenshot this)
SELECT TOP 10 Incident_ID, Incident_Year, Incident_Month, Incident_Quarter, Day_Of_Week,
       Incident_Hour, Is_Weekend, Time_Period, Is_Peak_Hour,
       Response_Time_Minutes, Travel_Time_Minutes, Response_Time_Category,
       Response_Threshold_Flag, Severity_Changed, Incident_Duration_Minutes
FROM gold.vw_EMS_Incident_Features;
GO