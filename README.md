/* ============================================================
   BILL RISK, STEP 23 (second version): adjustment types.
   23A showed 7 places with CategoryGranular. The main one is iSigma_Customer_Fin_Invoices
   (every charge, credit and adjustment line). Nothing to edit. Run each step separately:
   highlight one step, press F5. Totals only. Screenshots are fine to share.
   ============================================================ */

/* ---- STEP 23B: the columns of the main table and the two credit views.
   I need to see the amount, date and type columns. */
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('iSigma_Customer_Fin_Invoices', 'vw_Reporting_TexasCredits', 'vw_JESouth_SummerRisk_Transactions')
ORDER BY TABLE_NAME, ORDINAL_POSITION;

/* ---- STEP 23C: adjustment types in the main table, how often, and dollars (totals only).
   inv_amount is the amount column used elsewhere in these invoice tables.
   If it says "Invalid column name", send me the screenshot and the 23B result. */
SELECT CategoryGranular,
       COUNT(*)                                   AS Items,
       COUNT(DISTINCT cust_id)                    AS Customers,
       AVG(CAST(inv_amount AS float))             AS AverageAmount,
       MIN(inv_amount)                            AS Smallest,
       MAX(inv_amount)                            AS Largest,
       SUM(CASE WHEN inv_amount < 0 THEN 1 ELSE 0 END) AS CreditsOrReversals
FROM iSigma_Customer_Fin_Invoices
GROUP BY CategoryGranular
ORDER BY COUNT(*) DESC;
