# Does the cleaner price help? Runs only on your laptop. Totals only are written.
# Run:  py Bill_Risk_Clean_Price_Test.py PHASE2_PULL.csv bill_risk_clean_price.csv
# Keep it in the same folder as Bill_Risk_Phase2_Local.py. The Phase 2 pull must have the header row and a Bill_No column.
import sys
import numpy as np, pandas as pd
from sklearn.metrics import roc_auc_score
import Bill_Risk_Phase2_Local as m

pull, cleanf = sys.argv[1], sys.argv[2]
d = m.read_any(pull, m.COLS22 + m.OUT6)
if "Bill_No" not in d.columns:
    sys.exit("The Phase 2 pull file has no Bill_No column. Use the 2026 pull instead (the one with Bill_No).")
c = pd.read_csv(cleanf, encoding="utf-8-sig", dtype={"Bill_No": str, "cust_id": str})
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
tr = base.DueDate < m.TRAIN_END; te = ~tr
print(f"train {tr.sum():,}  test {te.sum():,}  unpaid at 60 days (test): {y[te].mean():.3f}")

def run(frame, label, mask=None):
    mk = tr if mask is None else tr & mask
    mt = te if mask is None else te & mask
    mod = m.fit(frame[mk], y[mk])
    p = mod.predict_proba(frame[mt][m.FEATS])[:, 1]
    yy = y[mt]
    return {"Model": label, "Test bills": int(mt.sum()), "Unpaid rate": yy.mean(),
            "AUC": roc_auc_score(yy, p), "Top 10% catches": m.capture(yy.reset_index(drop=True), p, 0.10),
            "Top 4% catches": m.capture(yy.reset_index(drop=True), p, 0.04)}

rows = []
for name, mask in [("All regular bills", None), ("First bills (tenure under 60 days)", base.TenureDays < 60)]:
    for label, fr in [("Current price", base), ("Cleaner price", clean)]:
        r = run(fr, label, mask); r = {"Group": name, **r}; rows.append(r)
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
    res.to_excel(w, "Model comparison", index=False); mix.to_excel(w, "Bill makeup")
print("\nWrote Bill_Risk_Clean_Price_Totals.xlsx (totals only)")
