-- Purpose: easy analysis queries for demand, response, geography, call types and operations
-- Depends on: 06_feature_engineering.sql
-- Project assumptions (not official FDNY rules):
--   Valid response = source valid flag = 1 AND not a standby incident. Zero-second responses are kept.
--   Threshold = 10 minutes.
USE NYC_EMS_DW;
GO

---------------------------------------------------------------
-- SETUP: two simple views that the queries below use
---------------------------------------------------------------
-- All incidents with location, call type and disposition added
CREATE OR ALTER VIEW gold.vw_EMS_Analysis AS
SELECT f.*,
       l.Borough, l.Dispatch_Area, l.ZIP_Code,
       c.Initial_Call_Type, c.Final_Call_Type,
       d.Disposition_Code
FROM gold.vw_EMS_Incident_Features f
JOIN gold.DimLocation    l ON l.Location_Key    = f.Location_Key
JOIN gold.DimCallType    c ON c.CallType_Key    = f.CallType_Key
JOIN gold.DimDisposition d ON d.Disposition_Key = f.Disposition_Key;
GO

-- Only incidents that count for response-time KPIs
CREATE OR ALTER VIEW gold.vw_EMS_Valid_Response AS
SELECT *
FROM gold.vw_EMS_Analysis
WHERE Valid_Incident_Response = 1
  AND Standby_Indicator = 0
  AND Response_Time_Minutes IS NOT NULL;
GO

-- Log how many incidents are valid for response KPIs
DELETE FROM audit.DataQualityReport WHERE Check_Name = 'Incidents used for response KPIs';
INSERT INTO audit.DataQualityReport (Check_Name, Table_Name, Expected_Value, Actual_Value, Check_Status, Notes)
SELECT 'Incidents used for response KPIs', 'gold.vw_EMS_Valid_Response',
       (SELECT COUNT_BIG(*) FROM gold.vw_EMS_Analysis),
       (SELECT COUNT_BIG(*) FROM gold.vw_EMS_Valid_Response),
       'REVIEW', 'Difference = missing response times + standby incidents';
GO
SELECT * FROM audit.DataQualityReport ORDER BY Check_ID;
GO

---------------------------------------------------------------
-- 1) DEMAND ANALYSIS
---------------------------------------------------------------
-- 1.1 Total incidents
SELECT COUNT(*) AS Total_Incidents FROM gold.vw_EMS_Analysis;

-- 1.2 Incidents per year (2023 = Oct-Dec only, 2026 = Jan-Sep only)
SELECT Incident_Year, COUNT(*) AS Total_Incidents
FROM gold.vw_EMS_Analysis
GROUP BY Incident_Year
ORDER BY Incident_Year;

-- 1.3 Incidents per month
SELECT Incident_Year, Incident_Month_Number, Incident_Month, COUNT(*) AS Total_Incidents
FROM gold.vw_EMS_Analysis
GROUP BY Incident_Year, Incident_Month_Number, Incident_Month
ORDER BY Incident_Year, Incident_Month_Number;

-- 1.4 Incidents per day of week
SELECT Day_Of_Week, COUNT(*) AS Total_Incidents
FROM gold.vw_EMS_Analysis
GROUP BY Day_Of_Week
ORDER BY Total_Incidents DESC;

-- 1.5 Incidents per hour
SELECT Incident_Hour, COUNT(*) AS Total_Incidents
FROM gold.vw_EMS_Analysis
GROUP BY Incident_Hour
ORDER BY Total_Incidents DESC;

-- 1.6 Incidents per borough
SELECT Borough, COUNT(*) AS Total_Incidents
FROM gold.vw_EMS_Analysis
GROUP BY Borough
ORDER BY Total_Incidents DESC;

-- 1.7 Top 10 dispatch areas
SELECT TOP 10 Dispatch_Area, COUNT(*) AS Total_Incidents
FROM gold.vw_EMS_Analysis
GROUP BY Dispatch_Area
ORDER BY Total_Incidents DESC;

---------------------------------------------------------------
-- 2) RESPONSE PERFORMANCE (valid responses only)
---------------------------------------------------------------
-- 2.1 Overall average, median and P90 (minutes)
SELECT TOP 1
    COUNT(*) OVER ()                                                          AS Total_Valid_Responses,
    ROUND(AVG(Response_Time_Minutes) OVER (), 2)                              AS Average_Response_Minutes,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER (), 2) AS Median_Response_Minutes,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER (), 2) AS P90_Response_Minutes
FROM gold.vw_EMS_Valid_Response;

-- 2.2 By borough
SELECT DISTINCT
    Borough,
    COUNT(*) OVER (PARTITION BY Borough)                                      AS Total_Valid_Responses,
    ROUND(AVG(Response_Time_Minutes) OVER (PARTITION BY Borough), 2)          AS Average_Response_Minutes,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER (PARTITION BY Borough), 2) AS Median_Response_Minutes,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER (PARTITION BY Borough), 2) AS P90_Response_Minutes
FROM gold.vw_EMS_Valid_Response
ORDER BY Average_Response_Minutes DESC;

-- 2.3 By hour
SELECT DISTINCT
    Incident_Hour,
    COUNT(*) OVER (PARTITION BY Incident_Hour)                                AS Total_Valid_Responses,
    ROUND(AVG(Response_Time_Minutes) OVER (PARTITION BY Incident_Hour), 2)    AS Average_Response_Minutes,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER (PARTITION BY Incident_Hour), 2) AS Median_Response_Minutes,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER (PARTITION BY Incident_Hour), 2) AS P90_Response_Minutes
FROM gold.vw_EMS_Valid_Response
ORDER BY Incident_Hour;

-- 2.4 Share of responses over 10 minutes, by borough
SELECT Borough,
       COUNT(*)                                          AS Total_Valid_Responses,
       SUM(Response_Threshold_Flag)                      AS Above_Threshold_Count,
       ROUND(100.0 * SUM(Response_Threshold_Flag) / COUNT(*), 2) AS Above_Threshold_Rate
FROM gold.vw_EMS_Valid_Response
GROUP BY Borough
ORDER BY Above_Threshold_Rate DESC;

-- 2.5 Response time categories
SELECT Response_Time_Category, COUNT(*) AS Total_Incidents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS Percent_Of_Valid
FROM gold.vw_EMS_Valid_Response
GROUP BY Response_Time_Category
ORDER BY MIN(Response_Time_Minutes);

---------------------------------------------------------------
-- 3) DEMAND vs RESPONSE
---------------------------------------------------------------
-- 3.1 By borough
WITH demand AS (
    SELECT Borough, COUNT(*) AS Total_Incidents
    FROM gold.vw_EMS_Analysis GROUP BY Borough),
resp AS (
    SELECT DISTINCT Borough,
        ROUND(AVG(Response_Time_Minutes) OVER (PARTITION BY Borough), 2) AS Average_Response_Minutes,
        ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER (PARTITION BY Borough), 2) AS P90_Response_Minutes
    FROM gold.vw_EMS_Valid_Response)
SELECT d.Borough, d.Total_Incidents, r.Average_Response_Minutes, r.P90_Response_Minutes
FROM demand d JOIN resp r ON r.Borough = d.Borough
ORDER BY d.Total_Incidents DESC;

-- 3.2 By hour (does busy mean slower?)
WITH demand AS (
    SELECT Incident_Hour, COUNT(*) AS Total_Incidents
    FROM gold.vw_EMS_Analysis GROUP BY Incident_Hour),
resp AS (
    SELECT DISTINCT Incident_Hour,
        ROUND(AVG(Response_Time_Minutes) OVER (PARTITION BY Incident_Hour), 2) AS Average_Response_Minutes,
        ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER (PARTITION BY Incident_Hour), 2) AS P90_Response_Minutes
    FROM gold.vw_EMS_Valid_Response)
SELECT d.Incident_Hour, d.Total_Incidents, r.Average_Response_Minutes, r.P90_Response_Minutes
FROM demand d JOIN resp r ON r.Incident_Hour = d.Incident_Hour
ORDER BY d.Incident_Hour;

-- 3.3 Top 10 busiest dispatch areas and their response times
SELECT TOP 10
    Dispatch_Area,
    COUNT(*)                                                       AS Total_Incidents,
    ROUND(AVG(CASE WHEN Valid_Incident_Response = 1 AND Standby_Indicator = 0
                   THEN Response_Time_Minutes END), 2)             AS Average_Response_Minutes
FROM gold.vw_EMS_Analysis
GROUP BY Dispatch_Area
ORDER BY Total_Incidents DESC;

---------------------------------------------------------------
-- 4) CALL TYPE AND SEVERITY
---------------------------------------------------------------
-- 4.1 Top 10 initial call types
SELECT TOP 10
    Initial_Call_Type,
    COUNT(*)                                                       AS Total_Incidents,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)             AS Percent_Of_All,
    ROUND(AVG(CASE WHEN Valid_Incident_Response = 1 AND Standby_Indicator = 0
                   THEN Response_Time_Minutes END), 2)             AS Average_Response_Minutes
FROM gold.vw_EMS_Analysis
GROUP BY Initial_Call_Type
ORDER BY Total_Incidents DESC;

-- 4.2 Top 10 final call types
SELECT TOP 10 Final_Call_Type, COUNT(*) AS Total_Incidents
FROM gold.vw_EMS_Analysis
GROUP BY Final_Call_Type
ORDER BY Total_Incidents DESC;

-- 4.3 Incidents by initial severity level
SELECT Initial_Severity_Level,
       COUNT(*)                                                    AS Total_Incidents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS Percent_Of_All,
       ROUND(AVG(CASE WHEN Valid_Incident_Response = 1 AND Standby_Indicator = 0
                      THEN Response_Time_Minutes END), 2)          AS Average_Response_Minutes
FROM gold.vw_EMS_Analysis
GROUP BY Initial_Severity_Level
ORDER BY Initial_Severity_Level;

-- 4.4 How often does severity change between initial and final?
SELECT COUNT(*)                                                    AS Total_Incidents,
       SUM(Severity_Changed)                                       AS Severity_Changed_Count,
       ROUND(100.0 * SUM(Severity_Changed) / COUNT(Severity_Changed), 2) AS Severity_Changed_Percent
FROM gold.vw_EMS_Analysis;

-- 4.5 How often does the call type change?
SELECT COUNT(*) AS Total_Incidents,
       SUM(CASE WHEN Initial_Call_Type <> Final_Call_Type THEN 1 ELSE 0 END) AS Call_Type_Changed_Count,
       ROUND(100.0 * SUM(CASE WHEN Initial_Call_Type <> Final_Call_Type THEN 1 ELSE 0 END) / COUNT(*), 2) AS Call_Type_Changed_Percent
FROM gold.vw_EMS_Analysis;

---------------------------------------------------------------
-- 5) OPERATIONAL ANALYSIS
---------------------------------------------------------------
-- 5.1 Counts of each operational indicator
SELECT COUNT(*)                                  AS Total_Incidents,
       SUM(CAST(Held_Indicator AS INT))          AS Held,
       SUM(CAST(Special_Event_Indicator AS INT)) AS Special_Event,
       SUM(CAST(Transfer_Indicator AS INT))      AS Transfer,
       SUM(CAST(Standby_Indicator AS INT))       AS Standby,
       SUM(CAST(Reopen_Indicator AS INT))        AS Reopened
FROM gold.vw_EMS_Analysis;

-- 5.2 Held vs not held: count and response time
SELECT Held_Indicator,
       COUNT(*)                                                    AS Total_Incidents,
       ROUND(AVG(CASE WHEN Valid_Incident_Response = 1 AND Standby_Indicator = 0
                      THEN Response_Time_Minutes END), 2)          AS Average_Response_Minutes
FROM gold.vw_EMS_Analysis
GROUP BY Held_Indicator;

-- 5.3 Disposition codes (meanings not confirmed, so codes only)
SELECT Disposition_Code, COUNT(*) AS Total_Incidents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS Percent_Of_All
FROM gold.vw_EMS_Analysis
GROUP BY Disposition_Code
ORDER BY Total_Incidents DESC;
GO