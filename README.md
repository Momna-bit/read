/* ============================================================
   BILL RISK, STEP 27: find the contract end date and the reason a customer left
   Lists column names only (no customer data). Run as one step, nothing highlighted, then F5.
   Send a screenshot of the result. If it is long, scroll and send each screen.
   ============================================================ */
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE (   COLUMN_NAME LIKE '%contract%end%' OR COLUMN_NAME LIKE '%contractend%'
       OR COLUMN_NAME LIKE '%term%'         OR COLUMN_NAME LIKE '%expir%'
       OR COLUMN_NAME LIKE '%renew%'        OR COLUMN_NAME LIKE '%Contract%Date%'
       OR COLUMN_NAME LIKE '%EndDate%'      OR COLUMN_NAME LIKE '%End_Date%'
       OR COLUMN_NAME LIKE '%Reason%'       OR COLUMN_NAME LIKE '%Drop%'
       OR COLUMN_NAME LIKE '%Cancel%'       OR COLUMN_NAME LIKE '%Deenroll%'
       OR COLUMN_NAME LIKE '%De_enroll%'    OR COLUMN_NAME LIKE '%Switch%'
       OR COLUMN_NAME LIKE '%Move%'         OR COLUMN_NAME LIKE '%Transfer%'
       OR COLUMN_NAME LIKE '%Disposition%'  OR COLUMN_NAME LIKE '%Churn%'
       OR COLUMN_NAME LIKE '%Attrition%'    OR COLUMN_NAME LIKE '%Leave%')
  AND (TABLE_NAME LIKE 'iSigma_Customer%' OR TABLE_NAME LIKE 'iSigma_Contract%'
       OR TABLE_NAME LIKE 'iSigma_Bill%'    OR TABLE_NAME LIKE 'iSigma_EDI%'
       OR TABLE_NAME LIKE 'vw_%')
ORDER BY TABLE_NAME, COLUMN_NAME;
