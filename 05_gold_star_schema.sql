-- Purpose: build the gold star schema (6 dimensions + 1 fact table)
-- Depends on: 04_silver.sql
USE NYC_EMS_DW;
GO
SET LANGUAGE English;   -- so day and month names come out in English
GO

-- Drop old versions (fact first)
DROP TABLE IF EXISTS gold.FactEMSIncident;
DROP TABLE IF EXISTS gold.DimDate;
DROP TABLE IF EXISTS gold.DimTime;
DROP TABLE IF EXISTS gold.DimLocation;
DROP TABLE IF EXISTS gold.DimCallType;
DROP TABLE IF EXISTS gold.DimSeverity;
DROP TABLE IF EXISTS gold.DimDisposition;
GO

---------------------------------------------------------------
-- 1) DimDate (one row per calendar date found in the data)
---------------------------------------------------------------
CREATE TABLE gold.DimDate (
    Date_Key     INT PRIMARY KEY,          -- YYYYMMDD
    Full_Date    DATE NOT NULL,
    [Year]       INT,
    [Quarter]    INT,
    Month_Number INT,
    Month_Name   VARCHAR(20),
    [Day]        INT,
    Day_Name     VARCHAR(20),
    Is_Weekend   BIT
);
GO
INSERT INTO gold.DimDate
SELECT DISTINCT
    CONVERT(INT, CONVERT(CHAR(8), d, 112)),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    MONTH(d),
    DATENAME(MONTH, d),
    DAY(d),
    DATENAME(WEEKDAY, d),
    CASE WHEN DATENAME(WEEKDAY, d) IN ('Saturday','Sunday') THEN 1 ELSE 0 END
FROM (SELECT DISTINCT CAST(incident_datetime AS DATE) AS d FROM silver.EMS_Incident) x;
GO

---------------------------------------------------------------
-- 2) DimTime (one row per minute of the day: 1440 rows)
---------------------------------------------------------------
CREATE TABLE gold.DimTime (
    Time_Key    INT PRIMARY KEY,           -- hour*100 + minute (e.g. 1830)
    Full_Time   TIME(0),
    [Hour]      INT,
    [Minute]    INT,
    Time_Period VARCHAR(10)
);
GO
WITH n AS (
    SELECT 0 AS m
    UNION ALL
    SELECT m + 1 FROM n WHERE m < 1439
)
INSERT INTO gold.DimTime
SELECT
    (m / 60) * 100 + (m % 60),
    DATEADD(MINUTE, m, CAST('00:00' AS TIME(0))),
    m / 60,
    m % 60,
    CASE WHEN m / 60 BETWEEN 5  AND 11 THEN 'Morning'
         WHEN m / 60 BETWEEN 12 AND 16 THEN 'Afternoon'
         WHEN m / 60 BETWEEN 17 AND 20 THEN 'Evening'
         ELSE 'Night' END
FROM n
OPTION (MAXRECURSION 1500);
GO

---------------------------------------------------------------
-- 3) DimLocation (-1 means the value is missing)
---------------------------------------------------------------
CREATE TABLE gold.DimLocation (
    Location_Key              INT IDENTITY(1,1) PRIMARY KEY,
    Borough                   NVARCHAR(50),
    Dispatch_Area             NVARCHAR(50),
    ZIP_Code                  NVARCHAR(10),
    Police_Precinct           SMALLINT,
    City_Council_District     SMALLINT,
    Community_District        SMALLINT,
    Community_School_District SMALLINT,
    Congressional_District    SMALLINT
);
GO
INSERT INTO gold.DimLocation
    (Borough, Dispatch_Area, ZIP_Code, Police_Precinct, City_Council_District,
     Community_District, Community_School_District, Congressional_District)
SELECT DISTINCT
    borough, incident_dispatch_area, zipcode,
    ISNULL(CAST(police_precinct AS SMALLINT), -1),
    ISNULL(CAST(city_council_district AS SMALLINT), -1),
    ISNULL(CAST(community_district AS SMALLINT), -1),
    ISNULL(CAST(community_school_district AS SMALLINT), -1),
    ISNULL(CAST(congressional_district AS SMALLINT), -1)
FROM silver.EMS_Incident;
GO

---------------------------------------------------------------
-- 4) DimCallType
---------------------------------------------------------------
CREATE TABLE gold.DimCallType (
    CallType_Key      INT IDENTITY(1,1) PRIMARY KEY,
    Initial_Call_Type NVARCHAR(50),
    Final_Call_Type   NVARCHAR(50)
);
GO
INSERT INTO gold.DimCallType (Initial_Call_Type, Final_Call_Type)
SELECT DISTINCT ISNULL(initial_call_type,'Unknown'), ISNULL(final_call_type,'Unknown')
FROM silver.EMS_Incident;
GO

---------------------------------------------------------------
-- 5) DimSeverity (-1 means missing)
---------------------------------------------------------------
CREATE TABLE gold.DimSeverity (
    Severity_Key           INT IDENTITY(1,1) PRIMARY KEY,
    Initial_Severity_Level SMALLINT,
    Final_Severity_Level   SMALLINT
);
GO
INSERT INTO gold.DimSeverity (Initial_Severity_Level, Final_Severity_Level)
SELECT DISTINCT ISNULL(CAST(initial_severity_level AS SMALLINT), -1),
                ISNULL(CAST(final_severity_level AS SMALLINT), -1)
FROM silver.EMS_Incident;
GO

---------------------------------------------------------------
-- 6) DimDisposition (descriptions left empty until the official ones are confirmed)
---------------------------------------------------------------
CREATE TABLE gold.DimDisposition (
    Disposition_Key         INT IDENTITY(1,1) PRIMARY KEY,
    Disposition_Code        NVARCHAR(50),
    Disposition_Description NVARCHAR(200) NULL
);
GO
INSERT INTO gold.DimDisposition (Disposition_Code)
SELECT DISTINCT ISNULL(incident_disposition_code,'Unknown')
FROM silver.EMS_Incident;
GO

---------------------------------------------------------------
-- 7) FactEMSIncident (one row per incident)
---------------------------------------------------------------
CREATE TABLE gold.FactEMSIncident (
    Incident_Key              BIGINT IDENTITY(1,1) PRIMARY KEY,
    Incident_ID               INT NOT NULL,
    Date_Key                  INT NOT NULL,
    Time_Key                  INT NOT NULL,
    Location_Key              INT NOT NULL,
    CallType_Key              INT NOT NULL,
    Severity_Key              INT NOT NULL,
    Disposition_Key           INT NOT NULL,
    -- measures (kept in seconds)
    Dispatch_Response_Seconds INT NULL,
    Incident_Response_Seconds INT NULL,
    Travel_Time_Seconds       INT NULL,
    -- validity and quality flags
    Valid_Dispatch_Response   BIT NULL,
    Valid_Incident_Response   BIT NULL,
    Is_Zero_Response          BIT NULL,
    Has_Time_Issue            INT NULL,
    -- operational indicators
    Held_Indicator            BIT NULL,
    Reopen_Indicator          BIT NULL,
    Special_Event_Indicator   BIT NULL,
    Standby_Indicator         BIT NULL,
    Transfer_Indicator        BIT NULL,
    -- original timestamps (used later for durations)
    Incident_DateTime         DATETIME2 NULL,
    First_Assignment_DateTime DATETIME2 NULL,
    First_Activation_DateTime DATETIME2 NULL,
    First_On_Scene_DateTime   DATETIME2 NULL,
    First_To_Hosp_DateTime    DATETIME2 NULL,
    First_Hosp_Arrival_DateTime DATETIME2 NULL,
    Incident_Close_DateTime   DATETIME2 NULL
);
GO

INSERT INTO gold.FactEMSIncident (
    Incident_ID, Date_Key, Time_Key, Location_Key, CallType_Key, Severity_Key, Disposition_Key,
    Dispatch_Response_Seconds, Incident_Response_Seconds, Travel_Time_Seconds,
    Valid_Dispatch_Response, Valid_Incident_Response, Is_Zero_Response, Has_Time_Issue,
    Held_Indicator, Reopen_Indicator, Special_Event_Indicator, Standby_Indicator, Transfer_Indicator,
    Incident_DateTime, First_Assignment_DateTime, First_Activation_DateTime, First_On_Scene_DateTime,
    First_To_Hosp_DateTime, First_Hosp_Arrival_DateTime, Incident_Close_DateTime)
SELECT
    s.incident_id,
    CONVERT(INT, CONVERT(CHAR(8), s.incident_datetime, 112)),
    DATEPART(HOUR, s.incident_datetime) * 100 + DATEPART(MINUTE, s.incident_datetime),
    l.Location_Key, c.CallType_Key, v.Severity_Key, d.Disposition_Key,
    s.dispatch_response_seconds, s.incident_response_seconds, s.incident_travel_seconds,
    s.is_valid_dispatch_response, s.is_valid_incident_response, s.is_zero_response, s.has_time_issue,
    s.is_held, s.is_reopened, s.is_special_event, s.is_standby, s.is_transfer,
    s.incident_datetime, s.first_assignment_datetime, s.first_activation_datetime, s.first_on_scene_datetime,
    s.first_to_hosp_datetime, s.first_hosp_arrival_datetime, s.incident_close_datetime
FROM silver.EMS_Incident s
JOIN gold.DimLocation l
  ON  l.Borough = s.borough
  AND l.Dispatch_Area = s.incident_dispatch_area
  AND l.ZIP_Code = s.zipcode
  AND l.Police_Precinct = ISNULL(CAST(s.police_precinct AS SMALLINT), -1)
  AND l.City_Council_District = ISNULL(CAST(s.city_council_district AS SMALLINT), -1)
  AND l.Community_District = ISNULL(CAST(s.community_district AS SMALLINT), -1)
  AND l.Community_School_District = ISNULL(CAST(s.community_school_district AS SMALLINT), -1)
  AND l.Congressional_District = ISNULL(CAST(s.congressional_district AS SMALLINT), -1)
JOIN gold.DimCallType c
  ON  c.Initial_Call_Type = ISNULL(s.initial_call_type,'Unknown')
  AND c.Final_Call_Type   = ISNULL(s.final_call_type,'Unknown')
JOIN gold.DimSeverity v
  ON  v.Initial_Severity_Level = ISNULL(CAST(s.initial_severity_level AS SMALLINT), -1)
  AND v.Final_Severity_Level   = ISNULL(CAST(s.final_severity_level AS SMALLINT), -1)
JOIN gold.DimDisposition d
  ON  d.Disposition_Code = ISNULL(s.incident_disposition_code,'Unknown');
GO

---------------------------------------------------------------
-- 8) Unique incident ID + foreign keys (added after the load for speed)
---------------------------------------------------------------
CREATE UNIQUE INDEX UX_Fact_Incident_ID ON gold.FactEMSIncident (Incident_ID);
GO
ALTER TABLE gold.FactEMSIncident ADD CONSTRAINT FK_Fact_Date        FOREIGN KEY (Date_Key)        REFERENCES gold.DimDate (Date_Key);
ALTER TABLE gold.FactEMSIncident ADD CONSTRAINT FK_Fact_Time        FOREIGN KEY (Time_Key)        REFERENCES gold.DimTime (Time_Key);
ALTER TABLE gold.FactEMSIncident ADD CONSTRAINT FK_Fact_Location    FOREIGN KEY (Location_Key)    REFERENCES gold.DimLocation (Location_Key);
ALTER TABLE gold.FactEMSIncident ADD CONSTRAINT FK_Fact_CallType    FOREIGN KEY (CallType_Key)    REFERENCES gold.DimCallType (CallType_Key);
ALTER TABLE gold.FactEMSIncident ADD CONSTRAINT FK_Fact_Severity    FOREIGN KEY (Severity_Key)    REFERENCES gold.DimSeverity (Severity_Key);
ALTER TABLE gold.FactEMSIncident ADD CONSTRAINT FK_Fact_Disposition FOREIGN KEY (Disposition_Key) REFERENCES gold.DimDisposition (Disposition_Key);
GO

---------------------------------------------------------------
-- 9) Checks logged in the audit table
---------------------------------------------------------------
DELETE FROM audit.DataQualityReport WHERE Table_Name LIKE 'gold.%';
GO
INSERT INTO audit.DataQualityReport (Check_Name, Table_Name, Expected_Value, Actual_Value, Check_Status)
SELECT Check_Name, Table_Name, Expected_Value, Actual_Value,
       CASE WHEN Actual_Value = Expected_Value THEN 'PASS' ELSE 'FAIL' END
FROM (VALUES
    ('Row count: silver vs gold fact', 'gold.FactEMSIncident',
        (SELECT COUNT_BIG(*) FROM silver.EMS_Incident),
        (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident)),
    ('Distinct incident IDs in fact', 'gold.FactEMSIncident',
        (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident),
        (SELECT COUNT_BIG(DISTINCT Incident_ID) FROM gold.FactEMSIncident)),
    ('Fact rows with no matching dimension', 'gold.FactEMSIncident', CAST(0 AS BIGINT),
        (SELECT COUNT_BIG(*) FROM gold.FactEMSIncident f
         WHERE NOT EXISTS (SELECT 1 FROM gold.DimDate WHERE Date_Key = f.Date_Key)
            OR NOT EXISTS (SELECT 1 FROM gold.DimTime WHERE Time_Key = f.Time_Key)
            OR NOT EXISTS (SELECT 1 FROM gold.DimLocation WHERE Location_Key = f.Location_Key)
            OR NOT EXISTS (SELECT 1 FROM gold.DimCallType WHERE CallType_Key = f.CallType_Key)
            OR NOT EXISTS (SELECT 1 FROM gold.DimSeverity WHERE Severity_Key = f.Severity_Key)
            OR NOT EXISTS (SELECT 1 FROM gold.DimDisposition WHERE Disposition_Key = f.Disposition_Key)))
) AS t(Check_Name, Table_Name, Expected_Value, Actual_Value);
GO

SELECT * FROM audit.DataQualityReport ORDER BY Check_ID;
GO

-- Dimension sizes (for the ERD and documentation)
SELECT 'DimDate' AS dim, COUNT(*) AS n FROM gold.DimDate
UNION ALL SELECT 'DimTime', COUNT(*) FROM gold.DimTime
UNION ALL SELECT 'DimLocation', COUNT(*) FROM gold.DimLocation
UNION ALL SELECT 'DimCallType', COUNT(*) FROM gold.DimCallType
UNION ALL SELECT 'DimSeverity', COUNT(*) FROM gold.DimSeverity
UNION ALL SELECT 'DimDisposition', COUNT(*) FROM gold.DimDisposition
UNION ALL SELECT 'FactEMSIncident', COUNT(*) FROM gold.FactEMSIncident;