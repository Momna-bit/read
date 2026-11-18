/* ============================================================
   BILL RISK, STEP 24: the cleaner price
   For each bill in the same random 1-in-10 Texas residential sample, add up the
   invoice lines by family (from the adjustments list), so we can build a price that
   leaves out deposits, exit fees, late and notice fees, adjustments, write-offs, taxes.
   Row-level file: keep it on your laptop. Save as: bill_risk_clean_price.csv (with header row).
   Run as one step: nothing highlighted, then F5. It may take a few minutes.
   ============================================================ */
WITH sample AS (
    SELECT b.Bill_No, b.cust_id, b.NetCharge, b.Usage
    FROM iSigma_Bill_Master b
    WHERE EXISTS (SELECT 1 FROM iSigma_Customer_Master c
                  WHERE c.cust_id = b.cust_id
                    AND c.Market = 'Texas' AND c.CustomerType = 'Residential')
      AND ABS(CHECKSUM(b.Bill_No)) % 10 = 0
),
lines AS (
    SELECT s.Bill_No,
           i.inv_amount AS Amt,
           CASE
             WHEN i.CategoryGranular IN ('Energy Charges','TDSP Charges','Monthly Charge Revenue',
                  'Volumetric TDU Surcharge','Flat TDU Surcharge','Capacity Energy Charges',
                  'NITS Energy Charges','Volumetric Green Unbundled','Flat Green-Unbundled',
                  'Minimum Usage Fee','Daily Fee Revenue','Energy Charges MAC') THEN 'Clean'
             WHEN i.CategoryGranular LIKE 'Deposit%' OR i.CategoryGranular LIKE '%Deposit' THEN 'Deposit'
             WHEN i.CategoryGranular LIKE '%ETP%' OR i.CategoryGranular LIKE 'REP Cancellation%' THEN 'ETP'
             WHEN i.CategoryGranular LIKE 'Late Fee%' OR i.CategoryGranular LIKE 'DNP Notice%'
               OR i.CategoryGranular LIKE 'Utility Disconnect%' OR i.CategoryGranular IN
                  ('Return Payment Fee','NSF','ACH Return','eCheck Return','Check Return',
                   'Third Party Collections Fee') THEN 'LateFees'
             WHEN i.CategoryGranular LIKE 'Write Off%' OR i.CategoryGranular LIKE '%Debt Sale%'
               OR i.CategoryGranular = 'Settlement' THEN 'WriteOff'
             WHEN i.CategoryGranular IN ('Payment Adjustment','Manual Payment Fee','DPP AR Adjustments',
                  'Transfer','ISTA Migration','NITS Rate Adjustment','Capacity Rate Adjustment',
                  'Goodwill','Refunds','Miscellaneous Revenue') THEN 'Adjustments'
             WHEN i.CategoryGranular LIKE '%Tax' OR i.CategoryGranular LIKE 'ERCOT%' THEN 'TaxPassThrough'
             WHEN i.CategoryGranular LIKE '%Credit%' OR i.CategoryGranular LIKE '%Discount%'
               OR i.CategoryGranular LIKE '%Free%' OR i.CategoryGranular LIKE '%Reward%'
               OR i.CategoryGranular LIKE '%Saver%' THEN 'Credits'
             WHEN i.CategoryGranular IS NULL THEN 'Unmapped'
             ELSE 'Other'
           END AS Fam
    FROM sample s
    JOIN iSigma_Customer_Fin_Invoices i
      ON CAST(i.bill_no AS varchar(30)) = CAST(s.Bill_No AS varchar(30))
     AND i.inv_amount BETWEEN -5000 AND 5000          -- leaves out the impossible amounts
)
SELECT s.Bill_No, s.cust_id, s.NetCharge, s.Usage,
       SUM(CASE WHEN l.Fam = 'Clean'          THEN l.Amt ELSE 0 END) AS CleanCharge,
       SUM(CASE WHEN l.Fam = 'Credits'        THEN l.Amt ELSE 0 END) AS CreditsAmt,
       SUM(CASE WHEN l.Fam = 'Deposit'        THEN l.Amt ELSE 0 END) AS DepositAmt,
       SUM(CASE WHEN l.Fam = 'ETP'            THEN l.Amt ELSE 0 END) AS ETPAmt,
       SUM(CASE WHEN l.Fam = 'LateFees'       THEN l.Amt ELSE 0 END) AS LateFeesAmt,
       SUM(CASE WHEN l.Fam = 'WriteOff'       THEN l.Amt ELSE 0 END) AS WriteOffAmt,
       SUM(CASE WHEN l.Fam = 'Adjustments'    THEN l.Amt ELSE 0 END) AS AdjustAmt,
       SUM(CASE WHEN l.Fam = 'TaxPassThrough' THEN l.Amt ELSE 0 END) AS TaxPassAmt,
       SUM(CASE WHEN l.Fam IN ('Other','Unmapped') THEN l.Amt ELSE 0 END) AS OtherAmt
FROM sample s
LEFT JOIN lines l ON l.Bill_No = s.Bill_No
GROUP BY s.Bill_No, s.cust_id, s.NetCharge, s.Usage;
