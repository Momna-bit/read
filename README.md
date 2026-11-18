/* ============================================================
   BILL RISK vs THE REAL SUMMER AT RISK LIST, STEP 22
   Jonathon: "use the SAR list and rank them with the scores, see how they
   compare 1:1."
   For every customer in the Summer At Risk table (all groups), pull their
   latest bill with the same columns as before, plus GroupName and TreatmentGroup.
   Save as: bill_risk_sar_pull.csv  (export WITH the header row)
   Row-level file: keep it on your laptop.
   Columns: the same 29 as before, then Bill_No, cust_id, GroupName, TreatmentGroup,
   Utility, TotalDueApprox, PriorNotices, PerDayNow, BaselinePerDay, PriorBillCount.
   ============================================================ */

/* 22A: quick check of the list table (columns), tiny result */
SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'JESouth_SummerRisk' ORDER BY ORDINAL_POSITION;

/* 22B: the pull */
WITH sample AS (
    -- the real Summer At Risk list (all groups): the bill each customer was flagged on
    -- (the list's own CurrentBillDate), so we score the same bill the list used
    SELECT x.Bill_No, x.cust_id, x.Instance, x.Bill_Date, x.Due_Date, x.NetCharge, x.Usage, x.PerDay,
           x.FinalBill, x.TransferDebit, x.PriorPastDue, x.UsageCredit, x.BillCredit,
           x.AutoPayOn, x.PastDue, x.WriteOff, x.GroupName, x.TreatmentGroup
    FROM (
        SELECT b.Bill_No, b.cust_id, b.Instance, b.Bill_Date, b.Due_Date, b.NetCharge, b.Usage, b.PerDay,
               b.FinalBill, b.TransferDebit, b.PriorPastDue, b.UsageCredit, b.BillCredit,
               b.AutoPayOn, b.PastDue, b.WriteOff, l.GroupName, l.TreatmentGroup,
               ROW_NUMBER() OVER (PARTITION BY b.cust_id, l.GroupName ORDER BY b.Bill_No DESC) AS r
        FROM (SELECT DISTINCT cust_id, GroupName, TreatmentGroup, TRY_CAST(CurrentBillDate AS date) AS ListBillDate
              FROM dbo.JESouth_SummerRisk) l
        JOIN iSigma_Bill_Master b
          ON CAST(b.cust_id AS varchar(20)) = CAST(l.cust_id AS varchar(20))
         AND CAST(b.Bill_Date AS date) = l.ListBillDate
    ) x
    WHERE x.r = 1
),
cust AS (
    -- the enrollment that was active on the day the bill was issued
    SELECT s.Bill_No, c.FlowStart, c.FlowEnd, c.BudgetCategoryGroup, c.SalesChannelGroup,
           c.CreditCategory, c.Brand, c.Utility,
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
),
notices AS (
    -- notices where the fee was actually charged: the notice goes out on due date +2,
    -- the fee lands on due date +3, and customers who pay by +2 are not charged.
    -- D1 > 0 means money was still owing at the end of the notice day (fee charged).
    -- (if D1 is blank, the notice amount is used instead)
    SELECT s.Bill_No, COUNT(*) AS PriorNotices
    FROM sample s
    JOIN iSigma_Customer_Notices n
      ON n.cust_id = s.cust_id
     AND n.notice_date < s.Bill_Date
     AND n.notice_type = 'D'
     AND COALESCE(n.D1, n.notice_amount) > 0
    GROUP BY s.Bill_No
),
base AS (
    -- the customer's usual price per day from earlier bills
    SELECT s.Bill_No,
           COUNT(*) AS N12,
           AVG(h.PerDay) AS Avg12,
           SUM(CASE WHEN h.Bill_Date >= DATEADD(month,-4,s.Bill_Date) THEN 1 ELSE 0 END) AS N4,
           AVG(CASE WHEN h.Bill_Date >= DATEADD(month,-4,s.Bill_Date) THEN h.PerDay END) AS Avg4
    FROM sample s
    JOIN iSigma_Bill_Master h
      ON h.cust_id = s.cust_id AND h.Bill_Date < s.Bill_Date
     AND h.Bill_Date >= DATEADD(month,-12,s.Bill_Date)
    GROUP BY s.Bill_No
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
    s.cust_id,
    s.GroupName,
    s.TreatmentGroup,
    c.Utility,
    s.NetCharge + ISNULL(s.PriorPastDue, 0)                            AS TotalDueApprox,
    ISNULL(nt.PriorNotices, 0)                                         AS PriorNotices,
    s.PerDay                                                           AS PerDayNow,
    CASE WHEN bs.N12 >= 10 THEN bs.Avg12 ELSE bs.Avg4 END             AS BaselinePerDay,
    CASE WHEN bs.N12 >= 10 THEN bs.N12   ELSE bs.N4   END             AS PriorBillCount
FROM sample s
JOIN cust c ON c.Bill_No = s.Bill_No AND c.rn = 1
LEFT JOIN bill_flags f ON f.BILL_NO = s.Bill_No
LEFT JOIN pay_sum   ps ON ps.Bill_No = s.Bill_No
LEFT JOIN disc      dc ON dc.Bill_No = s.Bill_No
LEFT JOIN reconn    rc ON rc.Bill_No = s.Bill_No
LEFT JOIN notices   nt ON nt.Bill_No = s.Bill_No
LEFT JOIN base      bs ON bs.Bill_No = s.Bill_No;
