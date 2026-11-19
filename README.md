# Leaving test: does knowing when the contract ends help predict who leaves?
# Also splits leavers into "non-payment", "voluntary" and "moved", and checks the leave reasons are found.
# Run:  py Bill_Risk_Leaving_Test.py bill_risk_phase2_pull_v2.csv bill_risk_clean_price.csv bill_risk_contract_leave_pull.csv
# Keep it in the same folder as Bill_Risk_Phase2_Local.py. Only totals are written.
import sys
import numpy as np, pandas as pd
from sklearn.metrics import roc_auc_score
from sklearn.ensemble import HistGradientBoostingClassifier
import Bill_Risk_Phase2_Local as m

pull, cleanf, termf = sys.argv[1], sys.argv[2], sys.argv[3]
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
KN = ["Bill_No", "cust_id", "Bill_Date", "Due_Date", "TermStart", "TermEnd", "DaysToTermEnd", "TermMonths",
      "MovedDate", "SwitchDate", "DisconnectRequestDate", "DroppedDate"]
kfirst = open(termf, "r", encoding="utf-8-sig", errors="replace").readline()
k_header = kfirst.strip().lower().startswith("bill_no")
k = pd.read_csv(termf, header=0 if k_header else None, encoding="utf-8-sig", dtype=str, low_memory=False)
if not k_header:
    k.columns = KN[:k.shape[1]]
for col in ["DaysToTermEnd", "TermMonths"]:
    k[col] = pd.to_numeric(k[col], errors="coerce")
if "TermStart" not in k.columns:
    sys.exit("This contract file is the old one (Step 29). Please run Part B of Step 30 again and save it with the header row as bill_risk_contract_leave_pull.csv, replacing the old file.")
for col in ["TermStart", "TermEnd", "MovedDate", "SwitchDate", "DisconnectRequestDate", "DroppedDate"]:
    k[col] = pd.to_datetime(k[col], errors="coerce")
# the system uses 2050-12-31 (and similar far-off dates) when there is no fixed end, so treat those as "no fixed end"
k["NoFixedEnd"] = ((k.TermEnd.isna()) | (k.TermEnd.dt.year >= 2045) | (k.TermMonths > 120)).astype(int)
k["DaysToTermEnd"] = np.where(k.NoFixedEnd == 1, np.nan, k.DaysToTermEnd)
k["TermMonths"] = np.where(k.NoFixedEnd == 1, np.nan, k.TermMonths)
k = k[["Bill_No", "DaysToTermEnd", "TermMonths", "NoFixedEnd", "MovedDate", "SwitchDate", "DisconnectRequestDate", "DroppedDate"]]
d = d.merge(k, on="Bill_No", how="left")
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
PIECES = ["CreditsAmt", "DepositAmt", "ETPAmt", "AdjustAmt", "OtherAmt", "LateFeesAmt"]
for col in PIECES:
    new[col] = d[col].values

CONTRACT = ["DaysToTermEnd", "TermMonths", "NoFixedEnd"]
for col in CONTRACT:
    new[col] = d[col].values
y = T["Leaves_90_Days"].reset_index(drop=True)
unp = T["Unpaid_60_Days"].reset_index(drop=True)
dis = T["Disconnected"].reset_index(drop=True)
moved = d.MovedDate.notna().reset_index(drop=True)
switched = d.SwitchDate.notna().reset_index(drop=True)
dreq = d.DisconnectRequestDate.notna().reset_index(drop=True)
dropped = d.DroppedDate.notna().reset_index(drop=True)

# 1. are the leave reasons being found?
lv = y == 1
cov = pd.DataFrame({"Group": ["All bills", "Bills where customer left within 90 days"],
    "Bills": [len(y), int(lv.sum())],
    "Moved found": [moved.mean(), moved[lv].mean()], "Switch found": [switched.mean(), switched[lv].mean()],
    "Disconnect request found": [dreq.mean(), dreq[lv].mean()], "Dropped found": [dropped.mean(), dropped[lv].mean()],
    "Any reason found": [(moved | switched | dreq | dropped).mean(), (moved | switched | dreq | dropped)[lv].mean()]})

# 2. split of leavers (simple rule: owing / disconnected / disconnect request = non-payment; moved = move; rest = voluntary)
nonpay = lv & ((unp == 1) | (dis == 1) | dreq)
mv = lv & ~nonpay & moved
vol = lv & ~nonpay & ~moved
split = pd.DataFrame({"Type of leaver": ["Non-payment", "Moved", "Voluntary (everything else)"],
                      "Bills": [int(nonpay.sum()), int(mv.sum()), int(vol.sum())]})
split["Share of leavers"] = split.Bills / split.Bills.sum()

# 3. leaving by how close the contract end is
dd = d.reset_index(drop=True)
bk = pd.cut(dd.DaysToTermEnd, [-10**6, -1, 30, 60, 90, 180, 365, 10**6],
            labels=["Already past end", "0-30 days", "31-60", "61-90", "91-180", "181-365", "Over a year"])
bk = bk.astype(object).where(dd.NoFixedEnd != 1, "No fixed end (month to month)")
by_end = pd.DataFrame({"Bucket": bk, "Left": y, "Unpaid60": unp, "Moved": moved}).groupby("Bucket").agg(
    Bills=("Left", "size"), LeftIn90=("Left", "mean"), UnpaidAt60=("Unpaid60", "mean")).reset_index()

# 4. does it help predict leaving?
rows = []
for label, feats in [("Without contract end", m.FEATS + PIECES), ("With contract end", m.FEATS + PIECES + CONTRACT)]:
    mod = fit2(new[tr], y[tr], feats)
    p = mod.predict_proba(new[te][feats])[:, 1]
    yy = y[te].reset_index(drop=True)
    rows.append({"Model": label, "Test bills": int(te.sum()), "Leave rate": yy.mean(), "AUC": roc_auc_score(yy, p),
                 "Top 10% catches": m.capture(yy, p, 0.10), "Top 4% catches": m.capture(yy, p, 0.04)})
res = pd.DataFrame(rows)

pd.set_option("display.width", 220, "display.max_columns", 20)
print("\nAre the leave reasons being found?"); print(cov.round(4).to_string(index=False))
print("\nWho leaves, by type (simple rule):"); print(split.round(3).to_string(index=False))
print("\nLeaving and unpaid, by how close the contract end is:"); print(by_end.round(4).to_string(index=False))
print("\nDoes the contract end help predict leaving? (higher is better)"); print(res.round(3).to_string(index=False))
with pd.ExcelWriter("Bill_Risk_Leaving_Totals.xlsx", engine="openpyxl") as xw:
    cov.to_excel(xw, sheet_name="Reasons found", index=False)
    split.to_excel(xw, sheet_name="Type of leaver", index=False)
    by_end.to_excel(xw, sheet_name="By contract end", index=False)
    res.to_excel(xw, sheet_name="Does it help", index=False)
print("\nWrote Bill_Risk_Leaving_Totals.xlsx (totals only)")
