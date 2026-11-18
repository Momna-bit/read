# Does the cleaner price help? Runs only on your laptop. Totals only are written.
# Run:  py Bill_Risk_Clean_Price_Check.py bill_risk_vs_summer_pull.csv bill_risk_clean_price.csv
# Keep it in the same folder as Bill_Risk_Phase2_Local.py. Uses the 2026 pull (it has Bill_No).
import sys
import numpy as np, pandas as pd
from sklearn.metrics import roc_auc_score
import Bill_Risk_Phase2_Local as m

pull, cleanf = sys.argv[1], sys.argv[2]
NAMES = m.COLS22 + m.OUT6 + ["Bill_No", "cust_id", "Utility", "TotalDueApprox", "PriorNotices",
                             "PerDayNow", "BaselinePerDay", "PriorBillCount"]
first = open(pull, "r", encoding="utf-8-sig", errors="replace").readline()
has_header = first.strip().lower().startswith("duedate")
d = pd.read_csv(pull, header=0 if has_header else None, encoding="utf-8-sig",
                dtype={"Bill_No": str, "cust_id": str}, low_memory=False)
if not has_header:
    d.columns = NAMES[:d.shape[1]]
d["DueDate"] = pd.to_datetime(d["DueDate"])
CNAMES = ["Bill_No", "cust_id", "NetCharge", "Usage", "CleanCharge", "CreditsAmt", "DepositAmt", "ETPAmt",
          "LateFeesAmt", "WriteOffAmt", "AdjustAmt", "TaxPassAmt", "OtherAmt"]
cfirst = open(cleanf, "r", encoding="utf-8-sig", errors="replace").readline()
c_header = cfirst.strip().lower().startswith("bill_no")
c = pd.read_csv(cleanf, header=0 if c_header else None, encoding="utf-8-sig", dtype=str, low_memory=False)
if not c_header:
    c.columns = CNAMES[:c.shape[1]]
for k in CNAMES[2:]:
    c[k] = pd.to_numeric(c[k], errors="coerce")
d["Bill_No"] = d["Bill_No"].astype(str)
d = d[d.BillAmount > 0].merge(c.drop(columns=["cust_id", "NetCharge", "Usage"], errors="ignore"), on="Bill_No", how="inner")
print("bills matched to the clean price file:", f"{len(d):,}")
d = d[(d.FinalBill != "Yes") & (d.Usage > 0) & (d.CleanCharge > 0)].reset_index(drop=True)
print("regular bills used:", f"{len(d):,}")
for col in ["BudgetCategoryGroup", "SalesChannelGroup", "CreditCategory", "Brand", "Product"]:
    d[col] = d[col].astype(str)
top = d.Product.value_counts().head(45).index
tmp = d.copy(); tmp["ProductG"] = np.where(tmp.Product.isin(top), tmp.Product, "OTHER")
maps = {k: {v: i for i, v in enumerate(sorted(tmp[k].astype(str).unique()))} for k in m.CATS}
base = m.prep(d, top, maps)
clean = d.copy()
clean["BillAmount"] = clean.CleanCharge
clean["EffectiveRate"] = clean.CleanCharge / clean.Usage
clean = m.prep(clean, top, maps)
T = m.make_targets(base)
y = T["Unpaid_60_Days"]
SPLIT = pd.Timestamp('2026-05-01')   # train on Jan-Apr 2026 bills, test on May onward
tr = base.DueDate < SPLIT; te = ~tr
print(f"train {tr.sum():,}  test {te.sum():,}  unpaid at 60 days (test): {y[te].mean():.3f}")

from sklearn.ensemble import HistGradientBoostingClassifier
def fit2(X, y, feats):
    cat_idx = [feats.index(k + "_c") for k in m.CATS]
    mod = HistGradientBoostingClassifier(max_iter=300, learning_rate=0.08, max_leaf_nodes=48,
        min_samples_leaf=200, l2_regularization=1.0, categorical_features=cat_idx,
        early_stopping=True, validation_fraction=0.1, random_state=7)
    return mod.fit(X[feats], y)

def run(frame, label, mask=None, feats=None):
    feats = feats or m.FEATS
    mk = tr if mask is None else tr & mask
    mt = te if mask is None else te & mask
    mod = fit2(frame[mk], y[mk], feats)
    p = mod.predict_proba(frame[mt][feats])[:, 1]
    yy = y[mt]
    return {"Model": label, "Test bills": int(mt.sum()), "Unpaid rate": yy.mean(),
            "AUC": roc_auc_score(yy, p), "Top 10% catches": m.capture(yy.reset_index(drop=True), p, 0.10),
            "Top 4% catches": m.capture(yy.reset_index(drop=True), p, 0.04)}

PIECES = ["CreditsAmt", "DepositAmt", "ETPAmt", "AdjustAmt", "OtherAmt"]
for k in PIECES + ["LateFeesAmt"]:
    clean[k] = d[k].values

rows = []
for name, mask in [("All regular bills", None), ("First bills (tenure under 60 days)", base.TenureDays < 60)]:
    for label, fr, fs in [("Current price", base, None),
                          ("Cleaner price", clean, None),
                          ("Cleaner price + the removed pieces as their own columns", clean, m.FEATS + PIECES),
                          ("  same, plus late and notice fees (check)", clean, m.FEATS + PIECES + ["LateFeesAmt"])]:
        r = run(fr, label, mask, fs); r = {"Group": name, **r}; rows.append(r)
res = pd.DataFrame(rows)
pd.set_option("display.width", 200)
print("\nDoes the cleaner price help? (higher is better)")
print(res.round(3).to_string(index=False))

fam = ["CleanCharge", "CreditsAmt", "DepositAmt", "ETPAmt", "LateFeesAmt", "WriteOffAmt", "AdjustAmt", "TaxPassAmt", "OtherAmt"]
first = base.TenureDays < 60
mix = pd.DataFrame({
    "Share of bills with this (all)": [(d[f].abs() >= 1).mean() for f in fam],
    "Share of bills with this (first bills)": [(d.loc[first, f].abs() >= 1).mean() for f in fam],
    "Average when present": [d.loc[d[f].abs() >= 1, f].mean() for f in fam]}, index=fam)
print("\nWhat is on the bill, by family:")
print(mix.round(3).to_string())
with pd.ExcelWriter("Bill_Risk_Clean_Price_Totals.xlsx") as w:
    res.to_excel(w, sheet_name="Model comparison", index=False); mix.to_excel(w, sheet_name="Bill makeup")
print("\nWrote Bill_Risk_Clean_Price_Totals.xlsx (totals only)")
