/*===============================================================
   SCD DEMO
   Safe to re-run: YES (drops & recreates DB)
================================================================*/

-- [0] Fresh DB
USE master;
GO
IF DB_ID('SCD_Demo') IS NOT NULL DROP DATABASE SCD_Demo;
GO
CREATE DATABASE SCD_Demo;
GO
USE SCD_Demo;
GO

-- [1] OLTP source + seed (2010-01-15)
DROP TABLE IF EXISTS dbo.Customers_OLTP;
CREATE TABLE dbo.Customers_OLTP
(
    CustomerID   INT           NOT NULL PRIMARY KEY,   -- natural key
    CustomerName VARCHAR(100)  NOT NULL,
    City         VARCHAR(60)   NOT NULL,
    State        CHAR(2)       NOT NULL,
    Zip          CHAR(5)       NOT NULL,
    UpdatedAt    DATE          NOT NULL
);

INSERT INTO dbo.Customers_OLTP (CustomerID, CustomerName, City, State, Zip, UpdatedAt)
VALUES
(1001, 'Jane Smith', 'Appleton',  'WI', '54911', '2010-01-15'),
(1002, 'Mark Lee',   'Oshkosh',   'WI', '54901', '2010-01-15'),
(1003, 'Ana Gomez',  'Green Bay', 'WI', '54301', '2010-01-15');

-- [2] Dimensions (T1 & T2) + filtered unique index
DROP TABLE IF EXISTS dbo.DimCustomer_T1;
CREATE TABLE dbo.DimCustomer_T1
(
    CustomerSK   INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNK   INT          NOT NULL UNIQUE,
    CustomerName VARCHAR(100) NOT NULL,
    City         VARCHAR(60)  NOT NULL,
    State        CHAR(2)      NOT NULL,
    Zip          CHAR(5)      NOT NULL
);

DROP TABLE IF EXISTS dbo.DimCustomer_T2;
CREATE TABLE dbo.DimCustomer_T2
(
    CustomerSK       INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNK       INT           NOT NULL,
    CustomerName     VARCHAR(100)  NOT NULL,
    City             VARCHAR(60)   NOT NULL,
    State            CHAR(2)       NOT NULL,
    Zip              CHAR(5)       NOT NULL,
    RowEffectiveDate DATE          NOT NULL,
    RowEndDate       DATE          NOT NULL,   -- '9999-12-31' = open-ended
    IsCurrent        BIT           NOT NULL
);
CREATE UNIQUE NONCLUSTERED INDEX IX_DimCustomer_T2_OneCurrent
ON dbo.DimCustomer_T2 (CustomerNK)
WHERE IsCurrent = 1;
GO

-- [3] Initial load (2010-01-15)
TRUNCATE TABLE dbo.DimCustomer_T1;
INSERT INTO dbo.DimCustomer_T1 (CustomerNK, CustomerName, City, State, Zip)
SELECT CustomerID, CustomerName, City, State, Zip
FROM dbo.Customers_OLTP;

TRUNCATE TABLE dbo.DimCustomer_T2;
INSERT INTO dbo.DimCustomer_T2
    (CustomerNK, CustomerName, City, State, Zip, RowEffectiveDate, RowEndDate, IsCurrent)
SELECT
    CustomerID, CustomerName, City, State, Zip,
    CAST('2010-01-15' AS DATE), CAST('9999-12-31' AS DATE), 1
FROM dbo.Customers_OLTP;

-- [4] TYPE 1 (overwrite) — apply ONLY these 4 events chronologically, then upsert
-- 2012-06-15: Jane Smith -> Jane Jones
UPDATE dbo.Customers_OLTP
  SET CustomerName='Jane Jones', UpdatedAt='2012-06-15'
WHERE CustomerID=1001;


-- Upsert into T1
INSERT INTO dbo.DimCustomer_T1 (CustomerNK, CustomerName, City, State, Zip)
SELECT s.CustomerID, s.CustomerName, s.City, s.State, s.Zip
FROM dbo.Customers_OLTP s
LEFT JOIN dbo.DimCustomer_T1 d
  ON d.CustomerNK = s.CustomerID
WHERE d.CustomerNK IS NULL;

UPDATE d
   SET d.CustomerName = s.CustomerName,
       d.City         = s.City,
       d.State        = s.State,
       d.Zip          = s.Zip
FROM dbo.DimCustomer_T1 d
JOIN dbo.Customers_OLTP s
  ON d.CustomerNK = s.CustomerID;

-- 2015-09-01: Jane moves to Neenah, WI 54956
UPDATE dbo.Customers_OLTP
  SET City='Neenah', State='WI', Zip='54956', UpdatedAt='2015-09-01'
WHERE CustomerID=1001;

-- Upsert into T1
INSERT INTO dbo.DimCustomer_T1 (CustomerNK, CustomerName, City, State, Zip)
SELECT s.CustomerID, s.CustomerName, s.City, s.State, s.Zip
FROM dbo.Customers_OLTP s
LEFT JOIN dbo.DimCustomer_T1 d
  ON d.CustomerNK = s.CustomerID
WHERE d.CustomerNK IS NULL;

UPDATE d
   SET d.CustomerName = s.CustomerName,
       d.City         = s.City,
       d.State        = s.State,
       d.Zip          = s.Zip
FROM dbo.DimCustomer_T1 d
JOIN dbo.Customers_OLTP s
  ON d.CustomerNK = s.CustomerID;


-- 2016-03-12: Mark Lee ZIP correction
UPDATE dbo.Customers_OLTP
  SET Zip='54902', UpdatedAt='2016-03-12'
WHERE CustomerID=1002;


-- Upsert into T1
INSERT INTO dbo.DimCustomer_T1 (CustomerNK, CustomerName, City, State, Zip)
SELECT s.CustomerID, s.CustomerName, s.City, s.State, s.Zip
FROM dbo.Customers_OLTP s
LEFT JOIN dbo.DimCustomer_T1 d
  ON d.CustomerNK = s.CustomerID
WHERE d.CustomerNK IS NULL;

UPDATE d
   SET d.CustomerName = s.CustomerName,
       d.City         = s.City,
       d.State        = s.State,
       d.Zip          = s.Zip
FROM dbo.DimCustomer_T1 d
JOIN dbo.Customers_OLTP s
  ON d.CustomerNK = s.CustomerID;

-- 2021-11-05: Jane Smith -> Jane Smith-Parker
UPDATE dbo.Customers_OLTP
  SET CustomerName='Jane Smith-Parker', UpdatedAt='2021-11-05'
WHERE CustomerID=1001;

-- Upsert into T1
INSERT INTO dbo.DimCustomer_T1 (CustomerNK, CustomerName, City, State, Zip)
SELECT s.CustomerID, s.CustomerName, s.City, s.State, s.Zip
FROM dbo.Customers_OLTP s
LEFT JOIN dbo.DimCustomer_T1 d
  ON d.CustomerNK = s.CustomerID
WHERE d.CustomerNK IS NULL;

UPDATE d
   SET d.CustomerName = s.CustomerName,
       d.City         = s.City,
       d.State        = s.State,
       d.Zip          = s.Zip
FROM dbo.DimCustomer_T1 d
JOIN dbo.Customers_OLTP s
  ON d.CustomerNK = s.CustomerID;

-- [5] RESET for TYPE 2 baseline (2010-01-15)
TRUNCATE TABLE dbo.Customers_OLTP;
INSERT INTO dbo.Customers_OLTP (CustomerID, CustomerName, City, State, Zip, UpdatedAt)
VALUES
(1001, 'Jane Smith', 'Appleton',  'WI', '54911', '2010-01-15'),
(1002, 'Mark Lee',   'Oshkosh',   'WI', '54901', '2010-01-15'),
(1003, 'Ana Gomez',  'Green Bay', 'WI', '54301', '2010-01-15');

TRUNCATE TABLE dbo.DimCustomer_T2;
INSERT INTO dbo.DimCustomer_T2
    (CustomerNK, CustomerName, City, State, Zip, RowEffectiveDate, RowEndDate, IsCurrent)
SELECT
    CustomerID, CustomerName, City, State, Zip,
    CAST('2010-01-15' AS DATE), CAST('9999-12-31' AS DATE), 1
FROM dbo.Customers_OLTP;

-- [6] SCD2 processor (run after EACH change)
DROP PROCEDURE IF EXISTS dbo.SCD2_Process_Once;
GO
CREATE PROCEDURE dbo.SCD2_Process_Once
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH CurrentDim AS
    (
        SELECT * FROM dbo.DimCustomer_T2 WHERE IsCurrent = 1
    ),
    Compare AS
    (
        SELECT
            d.CustomerSK, d.CustomerNK,
            d.CustomerName AS DimName, d.City AS DimCity, d.State AS DimState, d.Zip AS DimZip,
            s.CustomerName AS SrcName,  s.City AS SrcCity,  s.State AS SrcState, s.Zip AS SrcZip,
            s.UpdatedAt    AS ChangeDate,
            CASE WHEN (d.CustomerName <> s.CustomerName
                   OR  d.City         <> s.City
                   OR  d.State        <> s.State
                   OR  d.Zip          <> s.Zip)
                 THEN 1 ELSE 0 END AS IsChanged
        FROM CurrentDim d
        JOIN dbo.Customers_OLTP s ON s.CustomerID = d.CustomerNK
    )
    SELECT * INTO #ChangedRows FROM Compare WHERE IsChanged = 1;

    UPDATE d
       SET d.RowEndDate = c.ChangeDate,
           d.IsCurrent  = 0
    FROM dbo.DimCustomer_T2 d
    JOIN #ChangedRows c ON c.CustomerSK = d.CustomerSK
    WHERE d.IsCurrent = 1;

    INSERT INTO dbo.DimCustomer_T2
        (CustomerNK, CustomerName, City, State, Zip, RowEffectiveDate, RowEndDate, IsCurrent)
    SELECT
        c.CustomerNK, c.SrcName, c.SrcCity, c.SrcState, c.SrcZip,
        c.ChangeDate, CAST('9999-12-31' AS DATE), 1
    FROM #ChangedRows c;

    -- brand-new NKs (not used in this minimal demo, but kept for completeness)
    INSERT INTO dbo.DimCustomer_T2
        (CustomerNK, CustomerName, City, State, Zip, RowEffectiveDate, RowEndDate, IsCurrent)
    SELECT
        s.CustomerID, s.CustomerName, s.City, s.State, s.Zip,
        s.UpdatedAt, CAST('9999-12-31' AS DATE), 1
    FROM dbo.Customers_OLTP s
    LEFT JOIN dbo.DimCustomer_T2 d
      ON d.CustomerNK = s.CustomerID AND d.IsCurrent = 1
    WHERE d.CustomerNK IS NULL;

    DROP TABLE IF EXISTS #ChangedRows;
END
GO

-- [7] TYPE 2 walkthrough — ONLY 4 events (chronological)
-- Event 1: 2012-06-15 — Jane name change
UPDATE dbo.Customers_OLTP
  SET CustomerName='Jane Jones', UpdatedAt='2012-06-15'
WHERE CustomerID=1001;
EXEC dbo.SCD2_Process_Once;

-- Event 2: 2015-09-01 — Jane moves to Neenah, WI 54956
UPDATE dbo.Customers_OLTP
  SET City='Neenah', State='WI', Zip='54956', UpdatedAt='2015-09-01'
WHERE CustomerID=1001;
EXEC dbo.SCD2_Process_Once;

-- Event 3: 2016-03-12 — Mark ZIP correction (non-Jane)
UPDATE dbo.Customers_OLTP
  SET Zip='54902', UpdatedAt='2016-03-12'
WHERE CustomerID=1002;
EXEC dbo.SCD2_Process_Once;

-- Event 4: 2021-11-05 — Jane hyphenated name
UPDATE dbo.Customers_OLTP
  SET CustomerName='Jane Smith-Parker', UpdatedAt='2021-11-05'
WHERE CustomerID=1001;
EXEC dbo.SCD2_Process_Once;

-- Inspect history
SELECT CustomerNK, CustomerName, City, State, Zip,
       RowEffectiveDate, RowEndDate, IsCurrent
FROM dbo.DimCustomer_T2
ORDER BY CustomerNK, RowEffectiveDate;

-- Focus on Jane (1001)
SELECT CustomerNK, CustomerName, City, State, Zip,
       RowEffectiveDate, RowEndDate, IsCurrent
FROM dbo.DimCustomer_T2
WHERE CustomerNK = 1001
ORDER BY RowEffectiveDate;

-- [8] As-of example
DECLARE @AsOf DATE = '2016-12-31';
SELECT CustomerNK, CustomerName, City, State, Zip
FROM dbo.DimCustomer_T2
WHERE @AsOf >= RowEffectiveDate AND @AsOf < RowEndDate
ORDER BY CustomerNK;


