-- Purpose: six analytical views for Power BI
-- Depends on: 07_analysis_queries.sql (setup part)
-- Rules: response KPIs use vw_EMS_Valid_Response (valid flag = 1, standby excluded, zero-second kept)
--        Demand counts use ALL incidents. All response times are in minutes.
USE NYC_EMS_DW;
GO

-- 1) Overall KPIs (one row, calculated from the underlying records, not from averages of averages)
CREATE OR ALTER VIEW gold.vw_ems_overall_kpis AS
WITH demand AS (
    SELECT COUNT(*) AS Total_Incidents,
           SUM(CASE WHEN Standby_Indicator = 0 THEN 1 ELSE 0 END) AS Eligible_Incidents,
           SUM(CAST(Is_Weekend AS INT)) AS Weekend_Incidents
    FROM gold.vw_EMS_Analysis),
resp AS (
    SELECT TOP 1
        COUNT(*) OVER ()                                                    AS Valid_Incident_Responses,
        AVG(Response_Time_Minutes) OVER ()                                  AS Average_Response_Minutes,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER () AS Median_Response_Minutes,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Response_Time_Minutes) OVER () AS P90_Response_Minutes,
        SUM(Response_Threshold_Flag) OVER ()                                AS Above_Threshold_Count
    FROM gold.vw_EMS_Valid_Response),
peak AS (
    SELECT TOP 1 Incident_Hour AS Peak_Demand_Hour FROM gold.PeakHour ORDER BY Hour_Rank)
SELECT d.Total_Incidents,
       r.Valid_Incident_Responses,
       ROUND(100.0 * r.Valid_Incident_Responses / d.Eligible_Incidents, 2) AS Valid_Response_Rate_Pct,
       ROUND(r.Average_Response_Minutes, 2)  AS Average_Response_Minutes,
       ROUND(r.Median_Response_Minutes, 2)   AS Median_Response_Minutes,
       ROUND(r.P90_Response_Minutes, 2)      AS P90_Response_Minutes,
       p.Peak_Demand_Hour,
       ROUND(100.0 * d.Weekend_Incidents / d.Total_Incidents, 2) AS Weekend_Incident_Share_Pct,
       ROUND(100.0 * r.Above_Threshold_Count / r.Valid_Incident_Responses, 2) AS Response_Threshold_Rate_Pct
FROM demand d CROSS JOIN resp r CROSS JOIN peak p;
GO

-- 2) Demand trends (grain: one row per date and hour)
CREATE OR ALTER VIEW gold.vw_ems_demand_trends AS
SELECT dd.Full_Date,
       a.Incident_Year, a.Incident_Month_Number, a.Incident_Month, a.Incident_Quarter,
       a.Day_Of_Week, a.Is_Weekend, a.Incident_Hour, a.Is_Peak_Hour,
       COUNT(*) AS Total_Incidents
FROM gold.vw_EMS_Analysis a
JOIN gold.DimDate dd ON dd.Date_Key = a.Date_Key
GROUP BY dd.Full_Date, a.Incident_Year, a.Incident_Month_Number, a.Incident_Month, a.Incident_Quarter,
         a.Day_Of_Week, a.Is_Weekend, a.Incident_Hour, a.Is_Peak_Hour;
GO

-- 3) Geographic analysis (grain: borough + dispatch area + ZIP)
CREATE OR ALTER VIEW gold.vw_ems_geographic_analysis AS
WITH demand AS (
    SELECT Borough, Dispatch_Area, ZIP_Code, COUNT(*) AS Total_Incidents
    FROM gold.vw_EMS_Analysis
    GROUP BY Borough, Dispatch_Area, ZIP_Code),
resp AS (
    SELECT DISTINCT Borough, Dispatch_Area, ZIP_Code,
        COUNT(*) OVER (PARTITION BY Borough, Dispatch_Area, ZIP_Code) AS Valid_Responses,
        ROUND(AVG(Response_Time_Minutes) OVER (PARTITION BY Borough, Dispatch_Area, ZIP_Code), 2) AS Average_Response_Minutes,
        ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Response_Time_Minutes)
              OVER (PARTITION BY Borough, Dispatch_Area, ZIP_Code), 2) AS P90_Response_Minutes
    FROM gold.vw_EMS_Valid_Response)
SELECT d.Borough, d.Dispatch_Area, d.ZIP_Code, d.Total_Incidents,
       r.Valid_Responses, r.Average_Response_Minutes, r.P90_Response_Minutes
FROM demand d
LEFT JOIN resp r ON r.Borough = d.Borough AND r.Dispatch_Area = d.Dispatch_Area AND r.ZIP_Code = d.ZIP_Code;
GO

-- 4) Response performance (grain: year + borough + hour + initial call type)
CREATE OR ALTER VIEW gold.vw_ems_response_performance AS
SELECT DISTINCT
    Incident_Year, Borough, Incident_Hour, Initial_Call_Type,
    COUNT(*) OVER (PARTITION BY Incident_Year, Borough, Incident_Hour, Initial_Call_Type) AS Valid_Responses,
    ROUND(AVG(Response_Time_Minutes) OVER (PARTITION BY Incident_Year, Borough, Incident_Hour, Initial_Call_Type), 2) AS Average_Response_Minutes,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Response_Time_Minutes)
          OVER (PARTITION BY Incident_Year, Borough, Incident_Hour, Initial_Call_Type), 2) AS Median_Response_Minutes,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Response_Time_Minutes)
          OVER (PARTITION BY Incident_Year, Borough, Incident_Hour, Initial_Call_Type), 2) AS P90_Response_Minutes,
    SUM(Response_Threshold_Flag) OVER (PARTITION BY Incident_Year, Borough, Incident_Hour, Initial_Call_Type) AS Above_Threshold_Count
FROM gold.vw_EMS_Valid_Response;
GO

-- 5) Call type and severity (grain: initial/final call type + initial/final severity)
CREATE OR ALTER VIEW gold.vw_ems_call_type_analysis AS
SELECT Initial_Call_Type, Final_Call_Type, Initial_Severity_Level, Final_Severity_Level,
       COUNT(*) AS Total_Incidents,
       SUM(ISNULL(Severity_Changed, 0)) AS Severity_Changed_Count,
       COUNT(CASE WHEN Valid_Incident_Response = 1 AND Standby_Indicator = 0 THEN 1 END) AS Valid_Responses,
       ROUND(AVG(CASE WHEN Valid_Incident_Response = 1 AND Standby_Indicator = 0
                      THEN Response_Time_Minutes END), 2) AS Average_Response_Minutes
FROM gold.vw_EMS_Analysis
GROUP BY Initial_Call_Type, Final_Call_Type, Initial_Severity_Level, Final_Severity_Level;
GO

-- 6) Operational analysis (grain: indicators + disposition code)
-- Note: standby incidents are NOT excluded here, so the standby group shows its own response time.
CREATE OR ALTER VIEW gold.vw_ems_operational_analysis AS
SELECT Held_Indicator, Special_Event_Indicator, Transfer_Indicator, Standby_Indicator,
       Reopen_Indicator, Disposition_Code,
       COUNT(*) AS Total_Incidents,
       COUNT(CASE WHEN Valid_Incident_Response = 1 AND Response_Time_Minutes IS NOT NULL THEN 1 END) AS Valid_Responses,
       ROUND(AVG(CASE WHEN Valid_Incident_Response = 1 THEN Response_Time_Minutes END), 2) AS Average_Response_Minutes
FROM gold.vw_EMS_Analysis
GROUP BY Held_Indicator, Special_Event_Indicator, Transfer_Indicator, Standby_Indicator,
         Reopen_Indicator, Disposition_Code;
GO

-- Checks: demand totals in every view must equal the total incidents
DELETE FROM audit.DataQualityReport WHERE Check_Name LIKE 'View total:%';
GO
INSERT INTO audit.DataQualityReport (Check_Name, Table_Name, Expected_Value, Actual_Value, Check_Status)
SELECT Check_Name, Table_Name, Expected_Value, Actual_Value,
       CASE WHEN Actual_Value = Expected_Value THEN 'PASS' ELSE 'FAIL' END
FROM (VALUES
 ('View total: demand_trends',      'gold.vw_ems_demand_trends',      (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident), (SELECT SUM(CAST(Total_Incidents AS BIGINT)) FROM gold.vw_ems_demand_trends)),
 ('View total: geographic',         'gold.vw_ems_geographic_analysis',(SELECT COUNT_BIG(*) FROM gold.FactEMSIncident), (SELECT SUM(CAST(Total_Incidents AS BIGINT)) FROM gold.vw_ems_geographic_analysis)),
 ('View total: call_type',          'gold.vw_ems_call_type_analysis', (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident), (SELECT SUM(CAST(Total_Incidents AS BIGINT)) FROM gold.vw_ems_call_type_analysis)),
 ('View total: operational',        'gold.vw_ems_operational_analysis',(SELECT COUNT_BIG(*) FROM gold.FactEMSIncident), (SELECT SUM(CAST(Total_Incidents AS BIGINT)) FROM gold.vw_ems_operational_analysis)),
 ('View total: response_performance','gold.vw_ems_response_performance',(SELECT COUNT_BIG(*) FROM gold.vw_EMS_Valid_Response), (SELECT SUM(CAST(Valid_Responses AS BIGINT)) FROM gold.vw_ems_response_performance))
) AS t(Check_Name, Table_Name, Expected_Value, Actual_Value);
GO

SELECT * FROM audit.DataQualityReport ORDER BY Check_ID;
GO
SELECT * FROM gold.vw_ems_overall_kpis;