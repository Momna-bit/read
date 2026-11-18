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
    -- the real Summer At Risk list (all groups): each list customer's latest bill
    SELECT x.Bill_No, x.cust_id, x.Instance, x.Bill_Date, x.Due_Date, x.NetCharge, x.Usage, x.PerDay,
           x.FinalBill, x.TransferDebit, x.PriorPastDue, x.UsageCredit, x.BillCredit,
           x.AutoPayOn, x.PastDue, x.WriteOff, x.GroupName, x.TreatmentGroup
    FROM (
        SELECT b.Bill_No, b.cust_id, b.Instance, b.Bill_Date, b.Due_Date, b.NetCharge, b.Usage, b.PerDay,
               b.FinalBill, b.TransferDebit, b.PriorPastDue, b.UsageCredit, b.BillCredit,
               b.AutoPayOn, b.PastDue, b.WriteOff, l.GroupName, l.TreatmentGroup,
               ROW_NUMBER() OVER (PARTITION BY b.cust_id, l.GroupName ORDER BY b.Bill_Date DESC) AS r
        FROM (SELECT DISTINCT cust_id, GroupName, TreatmentGroup FROM dbo.JESouth_SummerRisk) l
        JOIN iSigma_Bill_Master b ON CAST(b.cust_id AS varchar(20)) = CAST(l.cust_id AS varchar(20))
        WHERE b.Bill_Date >= '2026-08-01'
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
    SELECT s.Bill_No, COUNT(*) AS PriorNotices
    FROM sample s
    JOIN dbo.vw_JESouth_DNPNotice n
      ON CAST(n.cust_id AS varchar(20)) = CAST(s.cust_id AS varchar(20))
     AND n.notice_date < s.Bill_Date
     AND n.notice_type = 'D'
     AND n.D1 > 0
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



"""
Rank the real Summer At Risk list with the bill-risk score. Runs only on your laptop.

Put next to phase2_models.pkl and Bill_Risk_Phase2_Local.py:
    bill_risk_sar_pull.csv     (from Bill_Risk_Step22_SAR_List_Pull.sql, with header row)

Run:   py Bill_Risk_SAR_Ranking.py bill_risk_sar_pull.csv

Writes ONE small file of totals (no customer IDs, no bill numbers):
    Bill_Risk_SAR_Ranking_Totals.xlsx
Only that file is safe to share.

In plain words:
 - The score is set at the moment the bill is issued.
 - Every bill on the Summer At Risk list gets a score and a band
   (Very high = riskiest 4% of all bills, High = next 6%, Medium = next 20%, Low = the rest).
 - We show where the list sits: how many are Very high / High / Medium / Low.
 - We also show how much of each band is still overdue today. It is early, so treat it as a
   first look, not a final result.
"""
import sys, os, pickle
import numpy as np, pandas as pd
import Bill_Risk_Phase2_Local as m

EXTRA = ["Bill_No","cust_id","GroupName","TreatmentGroup","Utility","TotalDueApprox",
         "PriorNotices","PerDayNow","BaselinePerDay","PriorBillCount"]
BANDS = ["1. Very high","2. High","3. Medium","4. Low"]

def main(path):
    here = os.path.dirname(os.path.abspath(__file__))
    pk = pickle.load(open(os.path.join(here, "phase2_models.pkl"), "rb"))
    d = m.read_any(path, m.COLS22 + m.OUT6 + EXTRA)
    for c in ["BudgetCategoryGroup","SalesChannelGroup","CreditCategory","Brand","Product"]:
        d[c] = d[c].astype(str)
    print("List bills read:", len(d), "| customers:", d.cust_id.nunique())
    reg = (d.FinalBill != "Yes").values
    dd = m.prep(d, pd.Index(pk["top"]), pk["maps"])
    score = np.full(len(d), np.nan)
    model = pk["models"][("Regular bills", "Unpaid_60_Days")]
    score[reg] = model.predict_proba(dd.loc[reg, m.FEATS])[:, 1]
    cuts = pk["cuts"][("Regular bills", "Unpaid_60_Days")]
    band = np.where(np.isnan(score), "Final bill (scored separately)", m.band_of(np.nan_to_num(score), cuts))
    d["Band"] = band; d["Score"] = score
    d["OverdueNow"] = (d.StillOutstanding == 1).astype(int)

    # 1. where each group sits
    mix = pd.crosstab(d.GroupName, d.Band)
    for b in BANDS:
        if b not in mix.columns: mix[b] = 0
    cols = BANDS + [c for c in mix.columns if c not in BANDS]
    mix = mix[cols]
    mix_pct = mix.div(mix.sum(axis=1), axis=0)
    mix_pct.insert(0, "Customers", mix.sum(axis=1))
    exp = {"Customers": np.nan, "1. Very high": .04, "2. High": .06, "3. Medium": .20, "4. Low": .70}
    mix_pct.loc["(if no better than random)"] = pd.Series(exp).reindex(mix_pct.columns)

    # 2. still overdue today, by band
    od = d[reg].groupby("Band").agg(Bills=("OverdueNow","size"), StillOverdueNow=("OverdueNow","mean"))
    # 3. ten equal steps of score, still overdue today
    r = d[reg].copy()
    r["Step"] = pd.qcut(r.Score.rank(method="first"), 10, labels=[f"{i}" for i in range(10, 0, -1)])
    steps = r.groupby("Step", observed=True).agg(Bills=("OverdueNow","size"), AvgScore=("Score","mean"),
                                                 StillOverdueNow=("OverdueNow","mean")).sort_index(key=lambda x: x.astype(int))
    # 4. with and without autopay / notices for context
    notes = pd.DataFrame({"Notes": [
        "Real Summer At Risk list, each customer's latest bill. Totals only.",
        "Band cut-offs come from the score's own test months: Very high = riskiest 4% of all bills, High = next 6%, Medium = next 20%, Low = the rest.",
        "If the list were no better than random, it would show 4% / 6% / 20% / 70% in those bands.",
        "'Still overdue now' is early: many bills are not yet 60 days old. Read it as a direction, not a final answer.",
        "Final bills are scored separately and are shown on their own row."]})
    fn = os.path.join(os.path.dirname(os.path.abspath(path)), "Bill_Risk_SAR_Ranking_Totals.xlsx")
    with pd.ExcelWriter(fn, engine="openpyxl") as xw:
        mix_pct.to_excel(xw, sheet_name="Where the list sits")
        od.to_excel(xw, sheet_name="Overdue now by band")
        steps.to_excel(xw, sheet_name="Ten steps of score")
        notes.to_excel(xw, sheet_name="Read me", index=False)
    pd.set_option("display.width", 220, "display.max_columns", 20)
    print("\nWhere each group sits (share of bills in each band):"); print(mix_pct.round(3).to_string())
    print("\nStill overdue today, by band:"); print(od.round(3).to_string())
    print("\nTen steps of score (10 = highest):"); print(steps.round(3).to_string())
    print("\nWrote", fn, "(totals only)")

if __name__ == "__main__":
    if len(sys.argv) < 2: print(__doc__)
    else: main(sys.argv[1])





/* ============================================================
   BILL RISK vs SUMMER RISK, STEP 19 (version 2: notice FEE rule)
   Same as before, but "earlier disconnect notice" now means a notice where the
   fee was actually charged (Jonathon: notice goes out due date +2, fee lands on
   due date +3, no fee if they pay by +2).
   Same columns as before. Save as: bill_risk_vs_summer_pull_v2.csv
   Run with nothing highlighted, then F5. Export WITH the header row.
   ============================================================ */
WITH sample AS (
    SELECT b.Bill_No, b.cust_id, b.Instance, b.Bill_Date, b.Due_Date, b.NetCharge, b.Usage, b.PerDay,
           b.FinalBill, b.TransferDebit, b.PriorPastDue, b.UsageCredit, b.BillCredit,
           b.AutoPayOn, b.PastDue, b.WriteOff
    FROM iSigma_Bill_Master b
    WHERE EXISTS (SELECT 1 FROM iSigma_Customer_Master c
                  WHERE c.cust_id = b.cust_id
                    AND c.Market = 'Texas' AND c.CustomerType = 'Residential')
      AND b.Due_Date <  DATEADD(day, -120, CAST(GETDATE() AS date))
      AND b.Due_Date >= '2026-01-01'
      AND ABS(CHECKSUM(b.Bill_No)) % 10 = 0
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
    SELECT s.Bill_No, COUNT(*) AS PriorNotices
    FROM sample s
    JOIN dbo.vw_JESouth_DNPNotice n
      ON CAST(n.cust_id AS varchar(20)) = CAST(s.cust_id AS varchar(20))
     AND n.notice_date < s.Bill_Date
     AND n.notice_type = 'D'
     AND n.D1 > 0
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




