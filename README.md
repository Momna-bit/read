/* ============================================================
   BILL RISK, PHASE TWO, STEP 14: what happened after each bill
   Same bills as the first score (Texas residential, a random 1 in 10),
   but due 120 or more days ago so we can see what happened next.
   For each bill we pull the same 22 columns as before, plus six
   "what happened" columns:
     DaysToFullPay     days from the due date until the bill was fully
                       paid (negative = paid before the due date;
                       blank = not fully paid yet)
     DaysToFirstPay    days from the due date to the first payment
     AmountPaid        total paid on the bill (write-offs not counted)
     DaysToLeave       days from the due date until the customer left
                       (blank = still with us)
     DaysToDisconnect  days from the due date until we disconnected them
                       (blank = never disconnected in the 120 days after)
     DaysToReconnect   days from the due date until they were reconnected
                       (blank = not reconnected)
   Bills dated after the customer's flow ended are left out, as Jonathon
   asked. Final bills are kept in the file and have FinalBill = Yes, so
   they can be scored as their own group.
   Run each step separately, with nothing highlighted, then F5.
   ============================================================ */


/* ------------------------------------------------------------
   STEP 14A: quick counts, so we know the size before pulling.
   Save the result as: bill_risk_phase2_counts.csv
   ------------------------------------------------------------ */
WITH cohort AS (
    SELECT b.Bill_No, b.cust_id, b.Instance, b.Bill_Date, b.FinalBill
    FROM iSigma_Bill_Master b
    WHERE EXISTS (SELECT 1 FROM iSigma_Customer_Master c
                  WHERE c.cust_id = b.cust_id
                    AND c.Market = 'Texas' AND c.CustomerType = 'Residential')
      AND b.Due_Date <  DATEADD(day,   -120, CAST(GETDATE() AS date))
      AND b.Due_Date >= DATEADD(month, -24,  CAST(GETDATE() AS date))
      AND ABS(CHECKSUM(b.Bill_No)) % 10 = 0
)
SELECT
    COUNT(*)                                                       AS CohortBills,
    SUM(CASE WHEN x.cust_id IS NULL THEN 1 ELSE 0 END)             AS BillsDatedAfterFlowEnd,
    SUM(CASE WHEN x.cust_id IS NOT NULL THEN 1 ELSE 0 END)         AS BillsKept,
    SUM(CASE WHEN x.cust_id IS NOT NULL AND c.FinalBill = 'Yes' THEN 1 ELSE 0 END) AS FinalBillsKept
FROM cohort c
OUTER APPLY (SELECT TOP 1 m.cust_id
             FROM iSigma_Customer_Master m
             WHERE m.cust_id = c.cust_id
               AND m.Market = 'Texas' AND m.CustomerType = 'Residential'
               AND m.FlowStart <= c.Bill_Date
               AND (m.FlowEnd IS NULL OR m.FlowEnd >= c.Bill_Date)) x;


/* ------------------------------------------------------------
   STEP 14B: the pull. May take 15 to 30 minutes.
   Save the result as: bill_risk_phase2_pull.csv
   Column order (in case the file has no header row):
     1 DueDate, 2 StillOutstanding, 3 WrittenOff, 4 BillAmount,
     5 Usage, 6 EffectiveRate, 7 FinalBill, 8 TransferDebit,
     9 PriorPastDue, 10 UsageCredit, 11 BillCredit, 12 AutoPayOn,
     13 TenureDays, 14 BudgetCategoryGroup, 15 SalesChannelGroup,
     16 CreditCategory, 17 Brand, 18 Product, 19 FreeTimeCredit,
     20 UsageCreditPlan, 21 MinUsageFee, 22 FlatBill,
     23 DaysToFullPay, 24 DaysToFirstPay, 25 AmountPaid,
     26 DaysToLeave, 27 DaysToDisconnect, 28 DaysToReconnect
   ------------------------------------------------------------ */
WITH sample AS (
    SELECT b.Bill_No, b.cust_id, b.Instance, b.Bill_Date, b.Due_Date, b.NetCharge, b.Usage,
           b.FinalBill, b.TransferDebit, b.PriorPastDue, b.UsageCredit, b.BillCredit,
           b.AutoPayOn, b.PastDue, b.WriteOff
    FROM iSigma_Bill_Master b
    WHERE EXISTS (SELECT 1 FROM iSigma_Customer_Master c
                  WHERE c.cust_id = b.cust_id
                    AND c.Market = 'Texas' AND c.CustomerType = 'Residential')
      AND b.Due_Date <  DATEADD(day,   -120, CAST(GETDATE() AS date))
      AND b.Due_Date >= DATEADD(month, -24,  CAST(GETDATE() AS date))
      AND ABS(CHECKSUM(b.Bill_No)) % 10 = 0
),
cust AS (
    -- the enrollment that was active on the day the bill was issued
    SELECT s.Bill_No, c.FlowStart, c.FlowEnd, c.BudgetCategoryGroup, c.SalesChannelGroup,
           c.CreditCategory, c.Brand,
           ROW_NUMBER() OVER (PARTITION BY s.Bill_No ORDER BY c.FlowStart DESC) AS rn
    FROM sample s
    JOIN iSigma_Customer_Master c
      ON c.cust_id = s.cust_id
     AND c.Market = 'Texas' AND c.CustomerType = 'Residential'
     AND c.FlowStart <= s.Bill_Date
     AND (c.FlowEnd IS NULL OR c.FlowEnd >= s.Bill_Date)
),
bill_flags AS (
    SELECT d.BILL_NO,
           MIN(d.Product) AS Product,
           MAX(CASE WHEN d.charge_desc LIKE '%Free Energy%' OR d.charge_desc LIKE 'Days Free%'
                    THEN 1 ELSE 0 END) AS FreeTimeCredit,
           MAX(CASE WHEN d.charge_desc IN ('Mega Saver Credit', 'Power Plus Credit', 'Base Saver Credit')
                    THEN 1 ELSE 0 END) AS UsageCreditPlan,
           MAX(CASE WHEN d.charge_desc = 'Minimum Usage Fee'
                    THEN 1 ELSE 0 END) AS MinUsageFee,
           MAX(CASE WHEN d.charge_desc = 'Flat Bill Charge'
                    THEN 1 ELSE 0 END) AS FlatBill
    FROM iSigma_Bill_Contract_Details d
    WHERE d.BILL_NO IN (SELECT Bill_No FROM sample)
    GROUP BY d.BILL_NO
),
pay_day AS (
    SELECT p.Bill_No, p.pay_date, SUM(p.amount_applied) AS amt
    FROM iSigma_Customer_Fin_Payments p
    WHERE p.Bill_No IN (SELECT Bill_No FROM sample)
      AND p.ExceptionDate IS NULL
      AND p.CategoryFinance NOT LIKE '%Write Off%'
    GROUP BY p.Bill_No, p.pay_date
),
pay_cum AS (
    SELECT Bill_No, pay_date, amt,
           SUM(amt) OVER (PARTITION BY Bill_No ORDER BY pay_date
                          ROWS UNBOUNDED PRECEDING) AS cum_amt
    FROM pay_day
),
pay_sum AS (
    SELECT c.Bill_No,
           MIN(c.pay_date)                                    AS FirstPayDate,
           SUM(c.amt)                                         AS AmountPaid,
           MIN(CASE WHEN c.cum_amt >= s.NetCharge - 0.50
                    THEN c.pay_date END)                      AS FullPayDate
    FROM pay_cum c
    JOIN sample s ON s.Bill_No = c.Bill_No
    GROUP BY c.Bill_No
),
disc AS (
    SELECT s.Bill_No, MIN(CAST(e.Created_date AS date)) AS DiscDate
    FROM sample s
    JOIN iSigma_EDI_Premise e
      ON e.cust_id = s.cust_id AND e.Instance = s.Instance
     AND e.Action_id = '650_02' AND e.Trans_type = 'D' AND e.resp_type = 'A'
     AND e.Created_date >= s.Due_Date
     AND e.Created_date <  DATEADD(day, 120, s.Due_Date)
    GROUP BY s.Bill_No
),
reconn AS (
    SELECT d.Bill_No, MIN(CAST(e.Created_date AS date)) AS ReconnDate
    FROM disc d
    JOIN sample s ON s.Bill_No = d.Bill_No
    JOIN iSigma_EDI_Premise e
      ON e.cust_id = s.cust_id AND e.Instance = s.Instance
     AND e.Action_id = '650_02' AND e.Trans_type = 'R' AND e.resp_type = 'A'
     AND e.Created_date >= d.DiscDate
    GROUP BY d.Bill_No
)
SELECT
    s.Due_Date                                                         AS DueDate,
    CASE WHEN s.PastDue > 0 OR s.WriteOff > 0 THEN 1 ELSE 0 END        AS StillOutstanding,
    CASE WHEN s.WriteOff > 0 THEN 1 ELSE 0 END                         AS WrittenOff,
    s.NetCharge                                                        AS BillAmount,
    s.Usage,
    CASE WHEN s.Usage > 0 THEN s.NetCharge / s.Usage END               AS EffectiveRate,
    s.FinalBill,
    s.TransferDebit,
    s.PriorPastDue,
    s.UsageCredit,
    s.BillCredit,
    s.AutoPayOn,
    DATEDIFF(day, c.FlowStart, s.Bill_Date)                            AS TenureDays,
    ISNULL(c.BudgetCategoryGroup, 'Not recorded')                      AS BudgetCategoryGroup,
    ISNULL(c.SalesChannelGroup,   'Not recorded')                      AS SalesChannelGroup,
    ISNULL(c.CreditCategory,      'Not recorded')                      AS CreditCategory,
    ISNULL(c.Brand,               'Not recorded')                      AS Brand,
    ISNULL(f.Product,             'Not recorded')                      AS Product,
    ISNULL(f.FreeTimeCredit, 0)                                        AS FreeTimeCredit,
    ISNULL(f.UsageCreditPlan, 0)                                       AS UsageCreditPlan,
    ISNULL(f.MinUsageFee, 0)                                           AS MinUsageFee,
    ISNULL(f.FlatBill, 0)                                              AS FlatBill,
    DATEDIFF(day, s.Due_Date, ps.FullPayDate)                          AS DaysToFullPay,
    DATEDIFF(day, s.Due_Date, ps.FirstPayDate)                         AS DaysToFirstPay,
    ps.AmountPaid                                                      AS AmountPaid,
    CASE WHEN c.FlowEnd IS NOT NULL
         THEN DATEDIFF(day, s.Due_Date, c.FlowEnd) END                 AS DaysToLeave,
    DATEDIFF(day, s.Due_Date, dc.DiscDate)                             AS DaysToDisconnect,
    DATEDIFF(day, s.Due_Date, rc.ReconnDate)                           AS DaysToReconnect
FROM sample s
JOIN cust c ON c.Bill_No = s.Bill_No AND c.rn = 1
LEFT JOIN bill_flags f ON f.BILL_NO = s.Bill_No
LEFT JOIN pay_sum   ps ON ps.Bill_No = s.Bill_No
LEFT JOIN disc      dc ON dc.Bill_No = s.Bill_No
LEFT JOIN reconn    rc ON rc.Bill_No = s.Bill_No;
