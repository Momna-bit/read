"""
Bill Risk, phase two. Runs entirely on your own computer.
Nothing is uploaded anywhere. Row-level files it writes stay in the output folder.

Needs: pandas, numpy, scikit-learn, openpyxl  (pip install pandas numpy scikit-learn openpyxl)

Step 1 (build the models and the summary workbook):
    python bill_risk_phase2_local.py train  PULL.csv  OUTPUT_FOLDER
Step 2 (score the upcoming bills and the recently overdue bills):
    python bill_risk_phase2_local.py score  UPCOMING.csv  OUTPUT_FOLDER  upcoming
    python bill_risk_phase2_local.py score  OVERDUE.csv   OUTPUT_FOLDER  overdue

Only the Phase2_Summary.xlsx file is meant to be shared. It has totals and rates,
no bill numbers and no customer IDs.
"""
import sys, os, time, pickle
import numpy as np, pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score

COLS22 = ["DueDate","StillOutstanding","WrittenOff","BillAmount","Usage","EffectiveRate","FinalBill",
          "TransferDebit","PriorPastDue","UsageCredit","BillCredit","AutoPayOn","TenureDays",
          "BudgetCategoryGroup","SalesChannelGroup","CreditCategory","Brand","Product",
          "FreeTimeCredit","UsageCreditPlan","MinUsageFee","FlatBill"]
OUT6 = ["DaysToFullPay","DaysToFirstPay","AmountPaid","DaysToLeave","DaysToDisconnect","DaysToReconnect"]
EXTRA3 = ["Bill_No","cust_id","PastDueNow"]
CATS = ["BudgetCategoryGroup","SalesChannelGroup","CreditCategory","Brand","ProductG"]
NUM = ["BillAmount","Usage","EffectiveRate","FinalBillF","TransferDebit","HasTransfer","UsageCredit",
       "BillCredit","TenureDays","FreeTimeCredit","UsageCreditPlan","MinUsageFee","FlatBill","DueMonth"]
FEATS = NUM + [c+"_c" for c in CATS] + ["AutoPay","PriorPastDue"]
TARGETS = {   # plain name -> (what it means)
    "Late_After_Due":   "Not fully paid by the due date",
    "Unpaid_30_Days":   "Still not fully paid 30 days after the due date",
    "Unpaid_60_Days":   "Still not fully paid 60 days after the due date",
    "Leaves_90_Days":   "Customer leaves within 90 days of the due date",
    "Disconnected":     "We disconnect the customer within 120 days of the due date",
    "Disconnect_Then_Reconnect": "Disconnected and then reconnected",
}
TRAIN_END = pd.Timestamp("2026-01-01")
MIN_FINAL_TRAIN = 5000

def read_any(path, names):
    first = open(path, "r", encoding="utf-8-sig", errors="replace").readline()
    has_header = first.strip().lower().startswith("duedate")
    d = pd.read_csv(path, header=0 if has_header else None, encoding="utf-8-sig",
                    dtype={"Bill_No":str, "cust_id":str}, low_memory=False)
    if not has_header:
        d = d.iloc[:, :len(names)]; d.columns = names[:d.shape[1]]
    d["DueDate"] = pd.to_datetime(d["DueDate"])
    return d

def prep(d, top, maps):
    d = d.copy()
    d["DueMonth"] = d.DueDate.dt.month
    d["FinalBillF"] = (d.FinalBill == "Yes").astype(int)
    d["AutoPay"] = (d.AutoPayOn == "Yes").astype(int)
    d["HasTransfer"] = (d.TransferDebit > 0).astype(int)
    d["ProductG"] = np.where(d.Product.isin(top), d.Product, "OTHER")
    d["EffectiveRate"] = d.EffectiveRate.clip(upper=3)
    for c, m in maps.items():
        d[c+"_c"] = d[c].map(m).astype(float)
    return d

def make_targets(d):
    t = pd.DataFrame(index=d.index)
    pay = d.DaysToFullPay
    t["Late_After_Due"] = (~(pay <= 0)).astype(int)
    t["Unpaid_30_Days"] = (~(pay <= 30)).astype(int)
    t["Unpaid_60_Days"] = (~(pay <= 60)).astype(int)
    t["Leaves_90_Days"] = (d.DaysToLeave.notna() & (d.DaysToLeave <= 90)).astype(int)
    t["Disconnected"] = d.DaysToDisconnect.notna().astype(int)
    t["Disconnect_Then_Reconnect"] = (d.DaysToDisconnect.notna() & d.DaysToReconnect.notna()).astype(int)
    return t

def fit(X, y):
    cat_idx = [FEATS.index(c+"_c") for c in CATS]
    m = HistGradientBoostingClassifier(max_iter=300, learning_rate=0.08, max_leaf_nodes=48,
        min_samples_leaf=200, l2_regularization=1.0, categorical_features=cat_idx,
        early_stopping=True, validation_fraction=0.1, random_state=7)
    return m.fit(X[FEATS], y)

def capture(y, p, frac):
    k = max(1, int(len(y) * frac))
    idx = np.argsort(-p)[:k]
    return y.values[idx].sum() / max(1, y.sum())

def band_of(p, cuts):
    c4, c10, c30 = cuts
    return np.where(p >= c4, "1. Very high", np.where(p >= c10, "2. High",
                    np.where(p >= c30, "3. Medium", "4. Low")))

def train(pull, outdir):
    os.makedirs(outdir, exist_ok=True)
    t0 = time.time()
    d = read_any(pull, COLS22 + OUT6)
    print("rows read:", len(d), "due", d.DueDate.min().date(), "to", d.DueDate.max().date())
    d = d[d.BillAmount > 0].reset_index(drop=True)
    top = d.Product.value_counts().head(45).index
    tmp = d.copy(); tmp["ProductG"] = np.where(tmp.Product.isin(top), tmp.Product, "OTHER")
    maps = {c: {v: i for i, v in enumerate(sorted(tmp[c].astype(str).unique()))} for c in CATS}
    for c in CATS: tmp[c] = tmp[c].astype(str)
    d["BudgetCategoryGroup"] = d["BudgetCategoryGroup"].astype(str)
    for c in ["SalesChannelGroup","CreditCategory","Brand","Product"]: d[c] = d[c].astype(str)
    d = prep(d, top, maps)
    T = make_targets(d)
    models, cutsd, quality, bands, rates = {}, {}, [], [], []
    groups = {"Regular bills": d.FinalBillF == 0, "Final bills": d.FinalBillF == 1}
    for gname, gmask in groups.items():
        g = d[gmask]; tg = T[gmask]
        tr = g.DueDate < TRAIN_END; te = ~tr
        print(f"\n{gname}: {len(g):,} bills, train {tr.sum():,}, test {te.sum():,}")
        for tname in TARGETS:
            rates.append({"Group": gname, "Question": TARGETS[tname], "Bills": len(g),
                          "Share that happen (all bills)": tg[tname].mean(),
                          "Share that happen (test months)": tg.loc[te, tname].mean() if te.sum() else np.nan})
        if tr.sum() < MIN_FINAL_TRAIN or te.sum() < 1000:
            print("  not enough bills to build a separate model; raw rates only")
            continue
        for tname in TARGETS:
            ytr, yte = tg.loc[tr, tname], tg.loc[te, tname]
            if ytr.sum() < 200 or yte.sum() < 50:
                print(f"  {tname}: too few cases, skipped"); continue
            m = fit(g[tr], ytr)
            p = m.predict_proba(g.loc[te, FEATS])[:, 1]
            auc = roc_auc_score(yte, p)
            cuts = (np.quantile(p, 0.96), np.quantile(p, 0.90), np.quantile(p, 0.70))
            models[(gname, tname)] = m; cutsd[(gname, tname)] = cuts
            quality.append({"Group": gname, "Question": TARGETS[tname], "Test bills": len(yte),
                "Share that happen": yte.mean(), "Ranking score (AUC)": auc,
                "Riskiest 4% hold this share of cases": capture(yte, p, 0.04),
                "Riskiest 10% hold": capture(yte, p, 0.10), "Riskiest 20% hold": capture(yte, p, 0.20),
                "Average predicted": p.mean()})
            b = band_of(p, cuts)
            for bn in ["1. Very high", "2. High", "3. Medium", "4. Low"]:
                k = b == bn
                bands.append({"Group": gname, "Question": TARGETS[tname], "Band": bn, "Bills": int(k.sum()),
                              "Share of bills": k.mean(), "Actually happened": yte.values[k].mean() if k.any() else np.nan,
                              "Share of all cases found": yte.values[k].sum() / max(1, yte.sum())})
            print(f"  {tname}: AUC {auc:.3f}  ({time.time()-t0:.0f}s)")
    pickle.dump({"models": models, "cuts": cutsd, "top": list(top), "maps": maps}, open(os.path.join(outdir, "phase2_models.pkl"), "wb"))
    # a few plain-English cuts that need no model
    d["RateGroup"] = pd.cut(d.EffectiveRate, [-1, .16, .20, .30, 99], labels=["Under 16c", "16-20c", "20-30c", "30c and over"])
    ex = []
    for gname, gmask in groups.items():
        g = d[gmask]; tg = T[gmask]
        for rg in ["Under 16c", "16-20c", "20-30c", "30c and over"]:
            k = (g.RateGroup == rg).values
            if k.sum() >= 200:
                row = {"Group": gname, "Rate per kWh": rg, "Bills": int(k.sum())}
                for tname in TARGETS: row[TARGETS[tname]] = tg.loc[k, tname].mean()
                ex.append(row)
    ap = []
    for flag, lab in [(1, "On autopay"), (0, "Not on autopay")]:
        k = (d.AutoPay == flag) & (d.FinalBillF == 0)
        row = {"Group": "Regular bills", "Autopay": lab, "Bills": int(k.sum()),
               "Median days to full payment (negative = early)": d.loc[k, "DaysToFullPay"].median()}
        for tname in TARGETS: row[TARGETS[tname]] = T.loc[k, tname].mean()
        ap.append(row)
    summ = pd.DataFrame(rates)
    notes = pd.DataFrame({"Notes": [
        "All numbers are totals and rates. There are no bill numbers or customer IDs in this file.",
        "Bills dated after the customer's flow ended are not included.",
        "Payment timing is counted in days from the due date; negative means paid before the due date.",
        "'Fully paid' means payments applied reached the bill amount (write-offs not counted).",
        "Models are tested on bills due from Jan 2026 on, after being built on earlier bills.",
        "Final bills are shown separately; they get their own model only if there are enough of them.",
        "Disconnect and leave counts use the 120 and 90 days after the due date.",
    ]})
    with pd.ExcelWriter(os.path.join(outdir, "Phase2_Summary.xlsx"), engine="openpyxl") as xw:
        notes.to_excel(xw, sheet_name="Read me", index=False)
        summ.to_excel(xw, sheet_name="What happens to bills", index=False)
        pd.DataFrame(quality).to_excel(xw, sheet_name="How well it ranks", index=False)
        pd.DataFrame(bands).to_excel(xw, sheet_name="Risk bands", index=False)
        pd.DataFrame(ex).to_excel(xw, sheet_name="By rate", index=False)
        pd.DataFrame(ap).to_excel(xw, sheet_name="By autopay", index=False)
    print("\nDone. Summary workbook:", os.path.join(outdir, "Phase2_Summary.xlsx"), f"({time.time()-t0:.0f}s)")

def score(path, outdir, tag):
    pk = pickle.load(open(os.path.join(outdir, "phase2_models.pkl"), "rb"))
    names = COLS22 + EXTRA3
    d = read_any(path, names)
    for c in ["BudgetCategoryGroup","SalesChannelGroup","CreditCategory","Brand","Product"]: d[c] = d[c].astype(str)
    d = prep(d, pd.Index(pk["top"]), pk["maps"])
    out = d[[c for c in ["Bill_No","cust_id","DueDate","FinalBill","BillAmount","PastDueNow"] if c in d.columns]].copy()
    out["DueDate"] = out.DueDate.dt.strftime("%Y-%m-%d")
    for tname in TARGETS:
        p = np.full(len(d), np.nan); cu = None
        for gname, fb in [("Regular bills", 0), ("Final bills", 1)]:
            m = pk["models"].get((gname, tname))
            if m is None: continue
            k = (d.FinalBillF == fb).values
            if k.any(): p[k] = m.predict_proba(d.loc[k, FEATS])[:, 1]
        out["P_" + tname] = np.round(p, 4)
        c = pk["cuts"].get(("Regular bills", tname))
        if c is not None and tname in ("Unpaid_60_Days", "Leaves_90_Days", "Disconnected"):
            out["Band_" + tname] = np.where(np.isnan(p), "No model", band_of(np.nan_to_num(p), c))
    out["FinalBillModel"] = np.where(d.FinalBillF == 1, ("yes" if ("Final bills", "Unpaid_60_Days") in pk["models"] else "no model: final bill"), "")
    fn = os.path.join(outdir, f"Scored_{tag}.csv")
    out.sort_values("P_Unpaid_60_Days", ascending=False).to_csv(fn, index=False)
    print("Wrote", fn, "(row-level, keep inside the company)")
    print(out.filter(like="Band_").apply(lambda s: s.value_counts(normalize=True).round(3).to_dict()))

if __name__ == "__main__":
    if sys.argv[1] == "train": train(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "score": score(sys.argv[2], sys.argv[3], sys.argv[4])
    else: print(__doc__)
