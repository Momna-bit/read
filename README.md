/* ============================================================
   BILL RISK, STEP 25: are late and notice fees on a bill known on the day the bill is issued?
   For the same random 1-in-10 Texas residential sample, look at when each late-type fee line
   was created compared with the bill date and the due date. Totals only, safe to share.
   Run as one step: nothing highlighted, then F5.
   ============================================================ */
WITH sample AS (
    SELECT b.Bill_No, b.Bill_Date, b.Due_Date
    FROM iSigma_Bill_Master b
    WHERE EXISTS (SELECT 1 FROM iSigma_Customer_Master c
                  WHERE c.cust_id = b.cust_id
                    AND c.Market = 'Texas' AND c.CustomerType = 'Residential')
      AND ABS(CHECKSUM(b.Bill_No)) % 10 = 0
      AND b.Due_Date >= '2026-01-01'
)
SELECT i.CategoryGranular,
       CASE WHEN CAST(i.create_date AS date) <= CAST(s.Bill_Date AS date) THEN '1 On or before the bill date'
            WHEN CAST(i.create_date AS date) <= CAST(s.Due_Date  AS date) THEN '2 After the bill date, by the due date'
            WHEN CAST(i.create_date AS date) <= DATEADD(day, 30, CAST(s.Due_Date AS date)) THEN '3 Within 30 days after the due date'
            ELSE '4 More than 30 days after the due date' END AS WhenCreated,
       COUNT(*)            AS Lines,
       AVG(CAST(i.inv_amount AS float)) AS AverageAmount
FROM sample s
JOIN iSigma_Customer_Fin_Invoices i
  ON CAST(i.bill_no AS varchar(30)) = CAST(s.Bill_No AS varchar(30))
WHERE (i.CategoryGranular LIKE 'Late Fee%' OR i.CategoryGranular LIKE 'DNP Notice%'
       OR i.CategoryGranular LIKE 'Utility Disconnect%'
       OR i.CategoryGranular IN ('Return Payment Fee','NSF','ACH Return','eCheck Return','Check Return',
                                 'Third Party Collections Fee'))
  AND i.inv_amount BETWEEN -5000 AND 5000
GROUP BY i.CategoryGranular,
         CASE WHEN CAST(i.create_date AS date) <= CAST(s.Bill_Date AS date) THEN '1 On or before the bill date'
              WHEN CAST(i.create_date AS date) <= CAST(s.Due_Date  AS date) THEN '2 After the bill date, by the due date'
              WHEN CAST(i.create_date AS date) <= DATEADD(day, 30, CAST(s.Due_Date AS date)) THEN '3 Within 30 days after the due date'
              ELSE '4 More than 30 days after the due date' END
ORDER BY i.CategoryGranular, WhenCreated;
