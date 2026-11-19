/* ============================================================
   BILL RISK, STEP 30: the real contract term dates
   The dates in Step 29 turned out to be the billing period, not the contract term.
   Here we take the term from the contract master instead.
   Run PART A first and send a screenshot. Then run PART B and export WITH the header row
   as: bill_risk_contract_leave_pull.csv   (replaces the Step 29 file)
   If PART A says a column name is invalid, run:  SELECT TOP 5 * FROM iSigma_Contract_Master;
   and send a screenshot of the column names.
   ============================================================ */

-- PART A1: what the contract end dates look like (counts only)
SELECT YEAR(END_DATE) AS EndYear, COUNT(*) AS Contracts
FROM iSigma_Contract_Master
GROUP BY YEAR(END_DATE)
ORDER BY EndYear;

-- PART A2: how long the contracts are, in months (counts only)
SELECT TOP 30 DATEDIFF(month, EFFECTIVE_DATE, END_DATE) AS TermMonths, COUNT(*) AS Contracts
FROM iSigma_Contract_Master
GROUP BY DATEDIFF(month, EFFECTIVE_DATE, END_DATE)
ORDER BY COUNT(*) DESC;

-- PART B: the pull
WITH sample AS (
    SELECT b.Bill_No, b.cust_id, b.Instance, b.Bill_Date, b.Due_Date
    FROM iSigma_Bill_Master b
    WHERE EXISTS (SELECT 1 FROM iSigma_Customer_Master c
                  WHERE c.cust_id = b.cust_id
                    AND c.Market = 'Texas' AND c.CustomerType = 'Residential')
      AND b.Due_Date <  DATEADD(day,   -120, CAST(GETDATE() AS date))
      AND b.Due_Date >= DATEADD(month, -24,  CAST(GETDATE() AS date))
      AND ABS(CHECKSUM(b.Bill_No)) % 10 = 0
),
bill_contract AS (
    SELECT DISTINCT d.BILL_NO, d.CONTRACT_ID
    FROM iSigma_Bill_Contract_Details d
    WHERE d.BILL_NO IN (SELECT Bill_No FROM sample)
),
term AS (
    SELECT bc.BILL_NO,
           MIN(cm.EFFECTIVE_DATE) AS TermStart,
           MAX(cm.END_DATE)       AS TermEnd
    FROM bill_contract bc
    JOIN iSigma_Contract_Master cm ON cm.CONTRACT_ID = bc.CONTRACT_ID
    GROUP BY bc.BILL_NO
),
leave_msgs AS (
    SELECT s.Bill_No,
           MIN(CASE WHEN e.REQ_REASON LIKE '%moved%'  THEN CAST(e.Created_date AS date) END) AS MovedDate,
           MIN(CASE WHEN e.REQ_REASON LIKE '%swit%'   THEN CAST(e.Created_date AS date) END) AS SwitchDate,
           MIN(CASE WHEN e.REQ_REASON LIKE 'Disconnect Request%' THEN CAST(e.Created_date AS date) END) AS DisconnectRequestDate,
           MIN(CASE WHEN e.REQ_REASON IN ('Dropped','cancel') OR e.REQ_REASON LIKE 'CANCELLED%' THEN CAST(e.Created_date AS date) END) AS DroppedDate
    FROM sample s
    JOIN iSigma_EDI_Premise e
      ON e.cust_id = s.cust_id AND e.Instance = s.Instance
     AND e.Created_date >= s.Due_Date
     AND e.Created_date <  DATEADD(day, 120, s.Due_Date)
     AND e.REQ_REASON IS NOT NULL AND e.REQ_REASON <> ''
    GROUP BY s.Bill_No
)
SELECT s.Bill_No, s.cust_id, s.Bill_Date, s.Due_Date,
       t.TermStart, t.TermEnd,
       DATEDIFF(day, s.Bill_Date, t.TermEnd) AS DaysToTermEnd,
       DATEDIFF(month, t.TermStart, t.TermEnd) AS TermMonths,
       l.MovedDate, l.SwitchDate, l.DisconnectRequestDate, l.DroppedDate
FROM sample s
LEFT JOIN term       t ON t.BILL_NO = s.Bill_No
LEFT JOIN leave_msgs l ON l.Bill_No = s.Bill_No;
