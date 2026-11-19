# Leaving test, in two parts:
# Part 1: does knowing when the contract ends help predict who leaves? Also splits leavers into
#         "non-payment", "voluntary" and "moved", and checks the leave reasons are found.
# Part 2: builds three separate predictions (leaves for any reason, leaves because of non-payment,
#         leaves by choice) with customers who moved left out, and checks if the lists overlap.
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
bk = bk.astype(object).where(dd.NoFixedEnd != 1, "Post-term (variable rate, free to leave)")
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
print("\n===== PART 2: three separate predictions =====")

# who left, and why (same simple rule as before: owing / disconnected / disconnect request = non-payment)
lv = y == 1
nonpay = (lv & ((unp == 1) | (dis == 1) | dreq)).astype(int)
vol = (lv & ~nonpay.astype(bool) & ~moved).astype(int)
anyleave = (lv & ~moved).astype(int)
keep = ~moved                       # customers who moved are left out of all three questions
FE = m.FEATS + PIECES + CONTRACT
trk = (tr.values & keep.values); tek = (te.values & keep.values)
Q = {"Leaves for any reason (moves left out)": anyleave,
     "Leaves because of non-payment": nonpay,
     "Leaves by choice (voluntary)": vol}
rows = []; scores = {}
for nice, yy in Q.items():
    mod = fit2(new[trk], yy[trk], FE)
    p = mod.predict_proba(new[tek][FE])[:, 1]
    yt = yy[tek].reset_index(drop=True)
    scores[nice] = pd.Series(p)
    rows.append({"Question": nice, "Test bills": int(tek.sum()), "Happens": yt.mean(), "AUC": roc_auc_score(yt, p),
                 "Top 10% catches": m.capture(yt, p, 0.10), "Top 4% catches": m.capture(yt, p, 0.04)})
res = pd.DataFrame(rows)

# do the two risk lists overlap? (top 10% by each score)
a = scores["Leaves because of non-payment"]; b = scores["Leaves by choice (voluntary)"]
ta = a >= a.quantile(0.90); tb = b >= b.quantile(0.90)
overlap = pd.DataFrame({"Measure": ["Share of the top 10% non-payment list that is also in the top 10% voluntary list",
                                    "Correlation between the two scores"],
                        "Value": [(ta & tb).sum() / ta.sum(), np.corrcoef(a, b)[0, 1]]})

pd.set_option("display.width", 220, "display.max_columns", 20)
print("\nThree questions, same inputs (higher is better):"); print(res.round(3).to_string(index=False))
print("\nDo the two lists pick the same customers?"); print(overlap.round(3).to_string(index=False))
with pd.ExcelWriter("Bill_Risk_Leaving_Split_Totals.xlsx", engine="openpyxl") as xw:
    res.to_excel(xw, sheet_name="Three questions", index=False)
    overlap.to_excel(xw, sheet_name="Overlap", index=False)
print("\nWrote Bill_Risk_Leaving_Split_Totals.xlsx (totals only)")

# ============================================================================================
# PART 3: the same split using the "leaving with debt" logic from the earlier discussions
#   - Non-payment: the customer was disconnected in the collection cycle and then left,
#                  or left after the due date still owing.
#   - Voluntary (shopped around): the customer saw the bill and left BEFORE it was due.
#   - Voluntary (nothing owing): left after the due date with nothing owing.
#   - Moved: left out.
# ============================================================================================
print("\n===== PART 3: split using the 'leaving with debt' logic =====")
dl = d.DaysToLeave.reset_index(drop=True)
dd_ = d.DaysToDisconnect.reset_index(drop=True)
owing = d.StillOutstanding.reset_index(drop=True) == 1
lv = (y == 1) & ~moved
left_before_due = lv & (dl < 0)
disc_then_left = lv & dd_.notna() & (dl >= dd_)
left_owing_after_due = lv & (dl >= 0) & owing & ~disc_then_left
left_clean = lv & (dl >= 0) & ~owing & ~disc_then_left
cats = pd.DataFrame({"Type of leaver": [
    "Left before the bill was due (shopped around)",
    "Disconnected in the collection cycle, then left",
    "Left after the due date, still owing",
    "Left after the due date, nothing owing"],
    "Bills": [int(left_before_due.sum()), int((disc_then_left & ~left_before_due).sum()),
              int((left_owing_after_due & ~left_before_due).sum()), int((left_clean & ~left_before_due).sum())]})
cats["Share of leavers (moves left out)"] = cats.Bills / cats.Bills.sum()
cats["Share of those still owing"] = [float((left_before_due & owing).sum() / max(left_before_due.sum(), 1)),
    float((disc_then_left & ~left_before_due & owing).sum() / max((disc_then_left & ~left_before_due).sum(), 1)),
    1.0, 0.0]
print(cats.round(3).to_string(index=False))

nonpay2 = ((disc_then_left | left_owing_after_due) & ~left_before_due).astype(int)
vol2 = (left_before_due | left_clean).astype(int)
Q2 = {"Leaves because of non-payment (debt logic)": nonpay2, "Leaves by choice (debt logic)": vol2}
rows2 = []; sc2 = {}
for nice, yy in Q2.items():
    mod = fit2(new[trk], yy[trk], FE)
    p = mod.predict_proba(new[tek][FE])[:, 1]
    yt = yy[tek].reset_index(drop=True)
    sc2[nice] = pd.Series(p)
    rows2.append({"Question": nice, "Test bills": int(tek.sum()), "Happens": yt.mean(), "AUC": roc_auc_score(yt, p),
                  "Top 10% catches": m.capture(yt, p, 0.10), "Top 4% catches": m.capture(yt, p, 0.04)})
res2 = pd.DataFrame(rows2)
a2 = sc2["Leaves because of non-payment (debt logic)"]; b2 = sc2["Leaves by choice (debt logic)"]
print("\nTwo questions with the debt logic (higher is better):"); print(res2.round(3).to_string(index=False))
print("\nShare of top 10% non-payment list also in top 10% voluntary list:",
      round(float(((a2 >= a2.quantile(0.9)) & (b2 >= b2.quantile(0.9))).sum() / (a2 >= a2.quantile(0.9)).sum()), 3))
with pd.ExcelWriter("Bill_Risk_Leaving_Debt_Logic_Totals.xlsx", engine="openpyxl") as xw:
    cats.to_excel(xw, sheet_name="Type of leaver", index=False)
    res2.to_excel(xw, sheet_name="Two questions", index=False)
print("\nWrote Bill_Risk_Leaving_Debt_Logic_Totals.xlsx (totals only)")

# ============================================================================================
# PART 4: the group a bill-shock credit is aimed at: customers who see the bill and leave before it is due
# ============================================================================================
print("\n===== PART 4: who leaves before the bill is due =====")
lbd = left_before_due.astype(int)
lbd_owe = (left_before_due & owing).astype(int)
Q4 = {"Leaves before the bill is due": lbd, "Leaves before the bill is due, still owing": lbd_owe}
rows4 = []
for nice, yy in Q4.items():
    mod = fit2(new[trk], yy[trk], FE)
    p = mod.predict_proba(new[tek][FE])[:, 1]
    yt = yy[tek].reset_index(drop=True)
    rows4.append({"Question": nice, "Test bills": int(tek.sum()), "Happens": yt.mean(), "AUC": roc_auc_score(yt, p),
                  "Top 10% catches": m.capture(yt, p, 0.10), "Top 4% catches": m.capture(yt, p, 0.04)})
res4 = pd.DataFrame(rows4)
# how big is the bill for these customers, compared with everyone else?
amt = d.BillAmount.reset_index(drop=True)
size = pd.DataFrame({"Group": ["Left before due", "Left before due, still owing", "All other bills"],
    "Bills": [int(left_before_due.sum()), int((left_before_due & owing).sum()), int((~left_before_due).sum())],
    "Average bill": [amt[left_before_due].mean(), amt[left_before_due & owing].mean(), amt[~left_before_due].mean()],
    "Median bill": [amt[left_before_due].median(), amt[left_before_due & owing].median(), amt[~left_before_due].median()]})
print(res4.round(3).to_string(index=False))
print("\nBill size for these groups:"); print(size.round(1).to_string(index=False))
with pd.ExcelWriter("Bill_Risk_Leaving_Before_Due_Totals.xlsx", engine="openpyxl") as xw:
    res4.to_excel(xw, sheet_name="Before due", index=False)
    size.to_excel(xw, sheet_name="Bill size", index=False)
print("\nWrote Bill_Risk_Leaving_Before_Due_Totals.xlsx (totals only)")
