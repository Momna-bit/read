-- Try this from your CURRENT connection (Care_BillAnalyzerTool_WH) to see if
-- Fabric allows cross-warehouse three-part naming. Adjust the warehouse name
-- if Analytics_ConstellationWH isn't exactly right.

SELECT
      TABLE_CATALOG
    , TABLE_SCHEMA
    , TABLE_NAME
FROM Analytics_ConstellationWH.INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%Customer_Master%'
   OR TABLE_NAME LIKE '%Fin_Invoices%'
   OR TABLE_NAME LIKE '%Bill_Master%';

-- If this errors out (cross-database queries aren't always allowed in Fabric
-- warehouses), the simplest path is: open a NEW query window, connect it to
-- Analytics_ConstellationWH directly, and run the original diagnostic there.
