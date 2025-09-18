/*===============================================================
   SCD DEMO DATABASE — Type 1 overwrite, then Type 2 history
   Author: <Your Name>
   Safe to re-run: YES (drops/reseeds objects each run)
================================================================*/

-------------------------------------------------------------------------------
-- [0] Create a fresh demo database
-------------------------------------------------------------------------------
USE master;
GO
IF DB_ID('SCD_Demo') IS NOT NULL
    DROP DATABASE SCD_Demo;
GO
CREATE DATABASE SCD_Demo;
GO
USE SCD_Demo;
GO

-------------------------------------------------------------------------------
-- [1] OLTP SOURCE: create + seed initial snapshot (as of 2010-01-15)
-------------------------------------------------------------------------------
PRINT '=== [1] Build OLTP source and seed initial customers ===';
DROP TABLE IF EXISTS Customers_OLTP;
CREATE TABLE Customers_OLTP
(
    CustomerID   INT           NOT NULL PRIMARY KEY,   -- natural/source key (NK)
    CustomerName VARCHAR(100)  NOT NULL,
    City         VARCHAR(60)   NOT NULL,
    State        CHAR(2)       NOT NULL,
    Zip          CHAR(5)       NOT NULL,
    UpdatedAt    DATE          NOT NULL
);

INSERT INTO Customers_OLTP (CustomerID, CustomerName, City, State, Zip, UpdatedAt)
VALUES
(1001, 'Jane Smith', 'Appleton',  'WI', '54911', '2010-01-15'),
(1002, 'Mark Lee',   'Oshkosh',   'WI', '54901', '2010-01-15'),
(1003, 'Ana Gomez',  'Green Bay', 'WI', '54301', '2010-01-15');

SELECT * FROM Customers_OLTP ORDER BY CustomerID;

-------------------------------------------------------------------------------
-- [2] DIMENSIONS: create Type 1 and Type 2
-------------------------------------------------------------------------------
PRINT '=== [2] Create DimCustomer_T1 (overwrite) and DimCustomer_T2 (history) ===';
DROP TABLE IF EXISTS DimCustomer_T1;
CREATE TABLE DimCustomer_T1
(
    CustomerSK   INT IDENTITY(1,1) PRIMARY KEY,
    CustomerNK   INT          NOT NULL UNIQUE,  -- NK from source
    CustomerName VARCHAR(100) NOT NULL,
    City         VARCHAR(60)  NOT NULL,
    State        CHAR(2)      NOT NULL,
    Zip          CHAR(5)      NOT NULL
);

DROP TABLE IF EXISTS DimCustomer_T2;
CREATE TABLE DimCustomer_T2
(
    CustomerSK       INT IDENTITY(1,1) PRIMARY KEY,   -- surrogate key (SK)
    CustomerNK       INT           NOT NULL,          -- natural key
    CustomerName     VARCHAR(100)  NOT NULL,
    City             VARCHAR(60)   NOT NULL,
    State            CHAR(2)       NOT NULL,
    Zip              CHAR(5)       NOT NULL,
    RowEffectiveDate DATE          NOT NULL,
    RowEndDate       DATE          NOT NULL,          -- '9999-12-31' = open-ended
    IsCurrent        BIT           NOT NULL,
    CONSTRAINT UX_DimCustomer_T2_Current UNIQUE (CustomerNK, IsCurrent)
);

-------------------------------------------------------------------------------
-- [3] INITIAL LOAD: populate both dimensions from OLTP
-------------------------------------------------------------------------------
PRINT '=== [3] Initial load into T1 and T2 (as of 2010-01-15) ===';
TRUNCATE TABLE DimCustomer_T1;
INSERT INTO DimCustomer_T1 (CustomerNK, CustomerName, City, State, Zip)
SELECT CustomerID, CustomerName, City, State, Zip
FROM Customers_OLTP;

TRUNCATE TABLE DimCustomer_T2;
INSERT INTO DimCustomer_T2
    (CustomerNK, CustomerName, City, State, Zip, RowEffectiveDate, RowEndDate, IsCurrent)
SELECT
    CustomerID, CustomerName, City, State, Zip,
    CAST('2010-01-15' AS DATE), CAST('9999-12-31' AS DATE), 1
FROM Customers_OLTP;

SELECT * FROM DimCustomer_T1 ORDER BY CustomerNK;
SELECT * FROM DimCustomer_T2 ORDER BY CustomerNK, RowEffectiveDate;

-------------------------------------------------------------------------------
-- [4] SIMULATE SOURCE CHANGES (2012–2023)
-------------------------------------------------------------------------------
PRINT '=== [4] Apply staged changes to OLTP ===';
UPDATE Customers_OLTP
  SET CustomerName = 'Jane Jones', UpdatedAt = '2012-06-15'
WHERE CustomerID = 1001;

UPDATE Customers_OLTP
  SET City = 'Neenah', State = 'WI', Zip = '54956', UpdatedAt = '2015-09-01'
WHERE CustomerID = 1001;

UPDATE Customers_OLTP
  SET CustomerName = 'Jane Smith', UpdatedAt = '2018-04-10'
WHERE CustomerID = 1001;

UPDATE Customers_OLTP
  SET CustomerName = 'Jane Smith-Parker', UpdatedAt = '2021-11-05'
WHERE CustomerID = 1001;

UPDATE Customers_OLTP
  SET CustomerName = 'Lucy Smith', UpdatedAt = '2023-02-20'
WHERE CustomerID = 1001;

UPDATE Customers_OLTP
  SET Zip = '54902', UpdatedAt = '2016-03-12'
WHERE CustomerID = 1002;

UPDATE Customers_OLTP
  SET CustomerName = 'Ana M. Gomez', UpdatedAt = '2017-08-23'
WHERE CustomerID = 1003;

SELECT * FROM Customers_OLTP ORDER BY CustomerID;

-------------------------------------------------------------------------------
-- [5] TYPE 1 SCD: overwrite dimension
-------------------------------------------------------------------------------
PRINT '=== [5] SCD Type 1 (overwrite) ===';

INSERT INTO DimCustomer_T1 (CustomerNK, CustomerName, City, State, Zip)
SELECT s.CustomerID, s.CustomerName, s.City, s.State, s.Zip
FROM Customers_OLTP s
LEFT JOIN DimCustomer_T1 d
  ON d.CustomerNK = s.CustomerID
WHERE d.CustomerNK IS NULL;

UPDATE d
   SET d.CustomerName = s.CustomerName,
       d.City         = s.City,
       d.State        = s.State,
       d.Zip          = s.Zip
FROM DimCustomer_T1 d
JOIN Customers_OLTP s
  ON d.CustomerNK = s.CustomerID;

SELECT * FROM DimCustomer_T1 ORDER BY CustomerNK;

-------------------------------------------------------------------------------
-- [6] RESET: restore OLTP to initial snapshot and reload T2 baseline
-------------------------------------------------------------------------------
PRINT '=== [6] Reset for SCD Type 2 demo ===';
TRUNCATE TABLE Customers_OLTP;
INSERT INTO Customers_OLTP (CustomerID, CustomerName, City, State, Zip, UpdatedAt)
VALUES
(1001, 'Jane Smith', 'Appleton',  'WI', '54911', '2010-01-15'),
(1002, 'Mark Lee',   'Oshkosh',   'WI', '54901', '2010-01-15'),
(1003, 'Ana Gomez',  'Green Bay', 'WI', '54301', '2010-01-15');

TRUNCATE TABLE DimCustomer_T2;
INSERT INTO DimCustomer_T2
    (CustomerNK, CustomerName, City, State, Zip, RowEffectiveDate, RowEndDate, IsCurrent)
SELECT
    CustomerID, CustomerName, City, State, Zip,
    CAST('2010-01-15' AS DATE), CAST('9999-12-31' AS DATE), 1
FROM Customers_OLTP;

-- Re-apply the same changes to OLTP as above
-- (for brevity, you can re-run block [4] here)

-------------------------------------------------------------------------------
-- [7] TYPE 2 SCD: close old + insert new
-------------------------------------------------------------------------------
PRINT '=== [7] SCD Type 2 (history) ===';
;WITH CurrentDim AS
(
    SELECT * FROM DimCustomer_T2 WHERE IsCurrent = 1
),
Compare AS
(
    SELECT
        d.CustomerSK, d.CustomerNK,
        d.CustomerName AS DimName, d.City AS DimCity, d.State AS DimState, d.Zip AS DimZip,
        s.CustomerName AS SrcName, s.City AS SrcCity, s.State AS SrcState, s.Zip AS SrcZip,
        s.UpdatedAt AS ChangeDate,
        CASE WHEN (d.CustomerName <> s.CustomerName
               OR  d.City         <> s.City
               OR  d.State        <> s.State
               OR  d.Zip          <> s.Zip)
             THEN 1 ELSE 0 END AS IsChanged
    FROM CurrentDim d
    JOIN Customers_OLTP s ON s.CustomerID = d.CustomerNK
)
SELECT * INTO #ChangedRows FROM Compare WHERE IsChanged = 1;

-- Close out old
UPDATE d
   SET d.RowEndDate = c.ChangeDate,
       d.IsCurrent  = 0
FROM DimCustomer_T2 d
JOIN #ChangedRows c ON c.CustomerSK = d.CustomerSK
WHERE d.IsCurrent = 1;

-- Insert new
INSERT INTO DimCustomer_T2
    (CustomerNK, CustomerName, City, State, Zip, RowEffectiveDate, RowEndDate, IsCurrent)
SELECT
    c.CustomerNK, c.SrcName, c.SrcCity, c.SrcState, c.SrcZip,
    c.ChangeDate, CAST('9999-12-31' AS DATE), 1
FROM #ChangedRows c;

DROP TABLE IF EXISTS #ChangedRows;

SELECT * FROM DimCustomer_T2 ORDER BY CustomerNK, RowEffectiveDate;

-------------------------------------------------------------------------------
-- [8] As-of lookup
-------------------------------------------------------------------------------
DECLARE @AsOf DATE = '2016-12-31';
SELECT CustomerNK, CustomerName, City, State, Zip
FROM DimCustomer_T2
WHERE @AsOf >= RowEffectiveDate AND @AsOf < RowEndDate
ORDER BY CustomerNK;
