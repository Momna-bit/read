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
