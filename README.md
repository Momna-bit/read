/* ============================================================
   BILL RISK, STEP 23: list of adjustment types (for Jonathon)
   Jonathon: "look at CategoryGranular for the best explanation".
   Run each step separately: highlight one step, press F5.
   Totals only come back. Screenshots are fine to share.
   ============================================================ */

/* ---- STEP 23A: where does CategoryGranular live?
   Tell me the table name(s) and the other columns beside it. */
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME LIKE '%CategoryGranular%'
   OR COLUMN_NAME LIKE '%Category_Granular%';

/* ---- STEP 23B: every column of that table, so we can see amount, date and customer columns.
   Change the table name on the next line to the one 23A found (keep the quotes). */
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'PUT_TABLE_NAME_FROM_23A_HERE'
ORDER BY ORDINAL_POSITION;

/* ---- STEP 23C: the adjustment types, how often, and the dollars (totals only).
   Change the table name and the AmountColumn name below, then run. */
SELECT CategoryGranular,
       COUNT(*)                         AS Items,
       COUNT(DISTINCT cust_id)          AS Customers,
       AVG(AmountColumn * 1.0)          AS AverageAmount,
       MIN(AmountColumn)                AS Smallest,
       MAX(AmountColumn)                AS Largest,
       SUM(CASE WHEN AmountColumn < 0 THEN 1 ELSE 0 END) AS CreditsOrReversals
FROM PUT_TABLE_NAME_FROM_23A_HERE
GROUP BY CategoryGranular
ORDER BY COUNT(*) DESC;
