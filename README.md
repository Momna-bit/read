/* ============================================================
   BILL RISK, STEP 29: contract end date and "why they left" for the same bills as the model pull
   Uses the exact same bill sample as Step 26, so the two files line up on Bill_No.
   Export WITH the header row. Save as: bill_risk_contract_leave_pull.csv
   Keep it on your laptop. It has bill numbers and customer IDs.
   ============================================================ */
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
contract AS (
    -- the contract dates printed on that bill
    SELECT d.BILL_NO,
           MIN(CAST(d.CO_START_DATE AS date)) AS ContractStart,
           MAX(CAST(d.CO_END_DATE   AS date)) AS ContractEnd
    FROM iSigma_Bill_Contract_Details d
    WHERE d.BILL_NO IN (SELECT Bill_No FROM sample)
    GROUP BY d.BILL_NO
),
leave_msgs AS (
    -- requests sent to the utility in the 120 days after the due date, with the reason written on them
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
       c.ContractStart, c.ContractEnd,
       DATEDIFF(day, s.Bill_Date, c.ContractEnd) AS DaysToContractEnd,
       l.MovedDate, l.SwitchDate, l.DisconnectRequestDate, l.DroppedDate
FROM sample s
LEFT JOIN contract   c ON c.BILL_NO = s.Bill_No
LEFT JOIN leave_msgs l ON l.Bill_No = s.Bill_No;
