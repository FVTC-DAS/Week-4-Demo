-- Type 1 SCD upsert via MERGE (Customers_OLTP -> DimCustomer_T1)
-- Overwrites changed attributes; inserts new NKs

SET XACT_ABORT ON;
BEGIN TRAN;

MERGE dbo.DimCustomer_T1 AS tgt WITH (HOLDLOCK)
USING dbo.Customers_OLTP AS src
    ON tgt.CustomerNK = src.CustomerID

WHEN MATCHED AND (
       tgt.CustomerName <> src.CustomerName
    OR tgt.City         <> src.City
    OR tgt.State        <> src.State
    OR tgt.Zip          <> src.Zip
)
THEN UPDATE SET
       tgt.CustomerName = src.CustomerName,
       tgt.City         = src.City,
       tgt.State        = src.State,
       tgt.Zip          = src.Zip

WHEN NOT MATCHED BY TARGET
THEN INSERT (CustomerNK, CustomerName, City, State, Zip)
     VALUES (src.CustomerID, src.CustomerName, src.Cit
