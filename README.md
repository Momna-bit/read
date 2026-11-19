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

def leave_by_group_step(d, reg, nsteps=5):
    """Share of customers who have left since the list bill, by group and score step (1 = highest)."""
    r = d[reg].copy()
    r["Left"] = r.DaysToLeave.notna().astype(int)
    r["Step"] = pd.qcut(r.Score.rank(method="first"), nsteps, labels=[str(i) for i in range(nsteps, 0, -1)])
    t = r.groupby(["Step", "GroupName"], observed=True).agg(Customers=("Left", "size"), Left=("Left", "mean"),
                                                           StillOverdueNow=("OverdueNow", "mean")).reset_index()
    t["Step"] = t["Step"].astype(int)
    w = t.pivot(index="Step", columns="GroupName", values=["Customers", "Left"]).sort_index(ascending=False)
    return w

def credit_size_by_step(d, reg, nsteps=5):
    """How big is the bill above the customer's usual bill (the 'overage'), versus a third of the bill?
    Usual bill = bill size at their usual per-day use. Overage = bill minus usual bill, never below zero."""
    r = d[reg].copy()
    for c in ["TotalDueApprox", "PerDayNow", "BaselinePerDay"]:
        r[c] = pd.to_numeric(r[c], errors="coerce")
    r = r[(r.TotalDueApprox > 0) & (r.PerDayNow > 0) & (r.BaselinePerDay > 0)]
    r["UsualBill"] = np.where(r.PerDayNow > r.BaselinePerDay, r.TotalDueApprox * r.BaselinePerDay / r.PerDayNow, r.TotalDueApprox)
    r["Overage"] = (r.TotalDueApprox - r.UsualBill).clip(lower=0)
    r["ThirdOfBill"] = r.TotalDueApprox / 3
    r["Step"] = pd.qcut(r.Score.rank(method="first"), nsteps, labels=[str(i) for i in range(nsteps, 0, -1)])
    t = r.groupby(["Step", "GroupName"], observed=True).agg(
        Customers=("Overage", "size"), AvgBill=("TotalDueApprox", "mean"), AvgUsualBill=("UsualBill", "mean"),
        AvgOverage=("Overage", "mean"), MedianOverage=("Overage", "median"), AvgThirdOfBill=("ThirdOfBill", "mean"),
        ShareOverageUnder25=("Overage", lambda x: (x < 25).mean())).reset_index()
    t["Step"] = t["Step"].astype(int)
    return t.sort_values(["Step", "GroupName"])

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
    # 3b. who has left since, by group and score step: where does a credit make the biggest difference?
    lg = leave_by_group_step(d, reg)
    cs = credit_size_by_step(d, reg)
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
        lg.to_excel(xw, sheet_name="Left by group and step")
        cs.to_excel(xw, sheet_name="Credit size by step", index=False)
        notes.to_excel(xw, sheet_name="Read me", index=False)
    pd.set_option("display.width", 220, "display.max_columns", 20)
    print("\nWhere each group sits (share of bills in each band):"); print(mix_pct.round(3).to_string())
    print("\nStill overdue today, by band:"); print(od.round(3).to_string())
    print("\nTen steps of score (1 = highest score):"); print(steps.round(3).to_string())
    print("\nShare who have left since the list bill, by group and score step (1 = highest score):")
    print(lg.round(3).to_string())
    print("\nCredit size: bill vs usual bill, by step (1 = highest score) and group:")
    print(cs.round(2).to_string(index=False))
    print("\nWrote", fn, "(totals only)")

if __name__ == "__main__":
    if len(sys.argv) < 2: print(__doc__)
    else: main(sys.argv[1])







-- Bill Risk, Step 28: look closer at the contract end date and "why did they leave" fields
-- Run each part on its own (highlight it, then Execute). Send a screenshot of each result.
-- Nothing here shows customer details. Part A and B only show column names and counts.

-- PART A: every column in the tables that hold contract end dates and leave reasons
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('iSigma_Bill_Contract_Details','iSigma_Contract_Master','iSigma_EDI_Premise')
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- PART B: the full names of the views that were cut off on screen, and their leave-related columns
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE (TABLE_NAME LIKE 'vw[_]JESouth[_]Disconnect%'
    OR TABLE_NAME LIKE 'vw[_]JESouth[_]DailyARCam%'
    OR TABLE_NAME LIKE 'vw[_]JESouth[_]SummerRisk%'
    OR TABLE_NAME LIKE 'vw[_]JESouth[_]Collections%'
    OR TABLE_NAME LIKE 'vw[_]CX[_]PortalMigration%'
    OR TABLE_NAME = 'vw_BI_Inventory')
  AND (COLUMN_NAME LIKE '%Attrition%' OR COLUMN_NAME LIKE '%Switch%' OR COLUMN_NAME LIKE '%Move%'
    OR COLUMN_NAME LIKE '%Reason%' OR COLUMN_NAME LIKE '%Drop%' OR COLUMN_NAME LIKE '%Renewal%'
    OR COLUMN_NAME LIKE '%Disposition%' OR COLUMN_NAME LIKE '%cust%' OR COLUMN_NAME LIKE '%Account%')
ORDER BY TABLE_NAME, COLUMN_NAME;

-- PART C: what the leave codes look like (counts only)
SELECT TOP 40 'DROP_CODE' AS Field, CAST(DROP_CODE AS varchar(100)) AS Value, COUNT(*) AS Rows_
FROM iSigma_EDI_Premise GROUP BY DROP_CODE ORDER BY COUNT(*) DESC;

SELECT TOP 40 'reject_reason' AS Field, CAST(reject_reason AS varchar(100)) AS Value, COUNT(*) AS Rows_
FROM iSigma_EDI_Premise GROUP BY reject_reason ORDER BY COUNT(*) DESC;

SELECT TOP 40 'REQ_REASON' AS Field, CAST(REQ_REASON AS varchar(100)) AS Value, COUNT(*) AS Rows_
FROM iSigma_EDI_Premise GROUP BY REQ_REASON ORDER BY COUNT(*) DESC;



