-- Run this first to find where iSigma_Customer_Master, iSigma_Customer_Fin_Invoices,
-- and iSigma_Bill_Master actually live, and confirm exact spelling/casing.

SELECT
      TABLE_CATALOG
    , TABLE_SCHEMA
    , TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%Customer_Master%'
   OR TABLE_NAME LIKE '%Fin_Invoices%'
   OR TABLE_NAME LIKE '%Bill_Master%';
