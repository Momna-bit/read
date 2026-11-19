/* ============================================================
   BILL RISK, STEP 26: the same model pull as before, with Bill_No and cust_id added
   Same bills (Texas residential, random 1 in 10, due 24 months back to 120 days ago),
   same 29 columns in the same order, plus 2 more at the end: 30 Bill_No, 31 cust_id.
   This lets us join the cleaner price and fee columns (Step 24) onto every bill.
   Row-level file: keep it on your laptop.
   Run as one step, nothing highlighted, then F5. May take 15 to 30 minutes.
   Export WITH the header row. Save as: bill_risk_phase2_pull_v2.csv
   ============================================================ */
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
     AND (c.FlowEnd IS NULL OR c.FlowEnd >= s.Bill_Date OR s.FinalBill = 'Yes')
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
                    THEN c.pay_date END)                      AS FullPayDate,
           MAX(CASE WHEN c.amt > 0 THEN c.pay_date END)       AS LastPayDate
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
    DATEDIFF(day, s.Due_Date, rc.ReconnDate)                           AS DaysToReconnect,
    DATEDIFF(day, s.Due_Date, ps.LastPayDate)                          AS DaysToLastPay,
    s.Bill_No,
    s.cust_id
FROM sample s
JOIN cust c ON c.Bill_No = s.Bill_No AND c.rn = 1
LEFT JOIN bill_flags f ON f.BILL_NO = s.Bill_No
LEFT JOIN pay_sum   ps ON ps.Bill_No = s.Bill_No
LEFT JOIN disc      dc ON dc.Bill_No = s.Bill_No
LEFT JOIN reconn    rc ON rc.Bill_No = s.Bill_No;
