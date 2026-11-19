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






# Rebuild test: does the new set of inputs (cleaner price, deposit, exit fee, adjustments, credits,
# late and notice fees as their own columns) predict better than today's inputs?
# Tests three questions: unpaid at 60 days, leaves within 90 days, disconnected within 120 days.
# Run:  py Bill_Risk_Rebuild_Test.py bill_risk_phase2_pull_v2.csv bill_risk_clean_price.csv
# Keep it in the same folder as Bill_Risk_Phase2_Local.py. Only totals are written.
import sys
import numpy as np, pandas as pd
from sklearn.metrics import roc_auc_score
from sklearn.ensemble import HistGradientBoostingClassifier
import Bill_Risk_Phase2_Local as m

pull, cleanf = sys.argv[1], sys.argv[2]
NAMES = m.COLS22 + m.OUT6 + ["Bill_No", "cust_id"]
first = open(pull, "r", encoding="utf-8-sig", errors="replace").readline()
has_header = first.strip().lower().startswith("duedate")
d = pd.read_csv(pull, header=0 if has_header else None, encoding="utf-8-sig",
                dtype={"Bill_No": str, "cust_id": str}, low_memory=False)
if not has_header:
    d.columns = NAMES[:d.shape[1]]
if "Bill_No" not in d.columns:
    sys.exit("The pull has no Bill_No column. Use the file from Step 26.")
d["DueDate"] = pd.to_datetime(d["DueDate"])

CN = ["Bill_No", "cust_id", "NetCharge", "Usage", "CleanCharge", "CreditsAmt", "DepositAmt", "ETPAmt",
      "LateFeesAmt", "WriteOffAmt", "AdjustAmt", "TaxPassAmt", "OtherAmt"]
cfirst = open(cleanf, "r", encoding="utf-8-sig", errors="replace").readline()
c_header = cfirst.strip().lower().startswith("bill_no")
c = pd.read_csv(cleanf, header=0 if c_header else None, encoding="utf-8-sig", dtype=str, low_memory=False)
if not c_header:
    c.columns = CN[:c.shape[1]]
for k in CN[2:]:
    c[k] = pd.to_numeric(c[k], errors="coerce")
c = c[["Bill_No", "CleanCharge", "CreditsAmt", "DepositAmt", "ETPAmt", "LateFeesAmt", "AdjustAmt", "OtherAmt"]]
d["Bill_No"] = d["Bill_No"].astype(str)
d = d[d.BillAmount > 0].merge(c, on="Bill_No", how="inner")
print("bills matched:", f"{len(d):,}")
d = d[(d.FinalBill != "Yes") & (d.Usage > 0) & (d.CleanCharge > 0)].reset_index(drop=True)
print("regular bills used:", f"{len(d):,}", "| due", d.DueDate.min().date(), "to", d.DueDate.max().date())
for k in ["BudgetCategoryGroup", "SalesChannelGroup", "CreditCategory", "Brand", "Product"]:
    d[k] = d[k].astype(str)
top = d.Product.value_counts().head(45).index
tmp = d.copy(); tmp["ProductG"] = np.where(tmp.Product.isin(top), tmp.Product, "OTHER")
maps = {k: {v: i for i, v in enumerate(sorted(tmp[k].astype(str).unique()))} for k in m.CATS}
base = m.prep(d, top, maps)
new = d.copy()
new["BillAmount"] = new.CleanCharge
new["EffectiveRate"] = new.CleanCharge / new.Usage
new = m.prep(new, top, maps)
PIECES = ["CreditsAmt", "DepositAmt", "ETPAmt", "AdjustAmt", "OtherAmt", "LateFeesAmt"]
for k in PIECES:
    new[k] = d[k].values
NEWF = m.FEATS + PIECES
T = m.make_targets(base)
tr = base.DueDate < m.TRAIN_END; te = ~tr
print(f"train {tr.sum():,}  test {te.sum():,}")

def fit2(X, y, feats):
    cat_idx = [feats.index(k + "_c") for k in m.CATS]
    return HistGradientBoostingClassifier(max_iter=300, learning_rate=0.08, max_leaf_nodes=48,
        min_samples_leaf=200, l2_regularization=1.0, categorical_features=cat_idx,
        early_stopping=True, validation_fraction=0.1, random_state=7).fit(X[feats], y)

QUESTIONS = {"Unpaid_60_Days": "Unpaid 60 days after due", "Leaves_90_Days": "Leaves within 90 days",
             "Disconnected": "Disconnected within 120 days"}
rows = []
for tname, nice in QUESTIONS.items():
    y = T[tname]
    for label, fr, fs in [("Today's inputs", base, m.FEATS), ("New inputs", new, NEWF)]:
        mod = fit2(fr[tr], y[tr], fs)
        p = mod.predict_proba(fr[te][fs])[:, 1]
        yy = y[te].reset_index(drop=True)
        rows.append({"Question": nice, "Model": label, "Test bills": int(te.sum()), "Happens": yy.mean(),
                     "AUC": roc_auc_score(yy, p), "Top 10% catches": m.capture(yy, p, 0.10),
                     "Top 4% catches": m.capture(yy, p, 0.04)})
res = pd.DataFrame(rows)
pd.set_option("display.width", 200)
print("\nToday's inputs vs new inputs (higher is better):")
print(res.round(3).to_string(index=False))
res.to_excel("Bill_Risk_Rebuild_Totals.xlsx", sheet_name="Comparison", index=False)
print("\nWrote Bill_Risk_Rebuild_Totals.xlsx (totals only)")

