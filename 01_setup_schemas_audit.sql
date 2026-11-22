USE NYC_EMS_DW;
GO
IF SCHEMA_ID('bronze') IS NULL EXEC('CREATE SCHEMA bronze');
IF SCHEMA_ID('silver') IS NULL EXEC('CREATE SCHEMA silver');
IF SCHEMA_ID('gold')   IS NULL EXEC('CREATE SCHEMA gold');
IF SCHEMA_ID('audit')  IS NULL EXEC('CREATE SCHEMA audit');
GO
IF OBJECT_ID('audit.DataQualityReport') IS NULL
CREATE TABLE audit.DataQualityReport (
    Check_ID        INT IDENTITY(1,1) PRIMARY KEY,
    Check_Name      NVARCHAR(200) NOT NULL,
    Table_Name      NVARCHAR(200) NULL,
    Expected_Value  BIGINT NULL,
    Actual_Value    BIGINT NULL,
    Difference      AS (Actual_Value - Expected_Value),
    Check_Status    VARCHAR(10) NULL,   -- PASS / FAIL / REVIEW
    Notes           NVARCHAR(500) NULL,
    Execution_Date  DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO