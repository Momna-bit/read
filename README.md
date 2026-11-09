"""
STEP 20 - Move-ins with a Sentilink identity-theft score of 600+ : account-level detail and a summary by flow month

Who is included
    Every contract that is a NEW sign-up moving in (not a moved house, added location or winback),
    with a Sentilink identity-theft score of 600 or more. All years, marked "Before checks" / "Since checks" (24 Aug 2024).

What it saves (one Excel file, no names, emails, phones or addresses - safe to share)
    movein_600_sentilink.xlsx
        Summary by flow month   - per sign-up month: how many, how many left by 3/6/12/24 months (actuals only),
                                  never paid, and average value to date (earned, cost to win, net)
        Survival curves         - actual share still active after each month, before vs since the checks
        Value by age            - average net value to date, by how many months old the contracts are now
        Account detail          - one row per contract with every number used
        Notes                   - how each number is worked out
Needs: customer_performance_all.parquet and usage_cost_11Sep.csv in this folder
Run:   py 20_movein_600_detail.py
"""
from pathlib import Path
import numpy as np, pandas as pd

FOLDER = Path(__file__).resolve().parent
CHECKS = pd.Timestamp("2024-08-24")
CUTOFF = 600
DAYS_PER_MONTH = 30.4375

cols = ["ParentID", "CustID", "FlowStart", "FlowEnd", "Status", "Designation", "EnrollmentType", "BudgetCategory",
        "CreditCategory", "CreditScore", "SentilinkIDTheftScore", "DepositPaid", "Waiver", "BillCount", "Usage",
        "Billed", "Revenue", "Debt", "Tax", "TDSP", "UsageCost", "CostToServe", "RetailerResidualCommission",
        "VendorResidualCommission", "UpfrontCommission", "OtherCommission", "R&RCommission", "GiftCard",
        "MarketingContractCost", "WageContractCost", "RentContractCost"]
d = pd.read_parquet(FOLDER / "customer_performance_all.parquet", columns=cols)
d["CustID"] = d["CustID"].astype(str)
TODAY = d["FlowStart"].max()
money = cols[cols.index("Usage"):]
for c in money + ["DepositPaid", "BillCount", "CreditScore", "SentilinkIDTheftScore"]:
    d[c] = pd.to_numeric(d[c], errors="coerce")
d[money] = d[money].fillna(0.0)

# usage cost: the warehouse shows $0, so use the 11 Sep values and estimate the rest from kWh (same as step 4)
d["UsageCostEstimated"] = False
if d["UsageCost"].abs().sum() == 0:
    old = pd.read_csv(FOLDER / "usage_cost_11Sep.csv").rename(columns={"UsageCost": "old"})
    old["CustID"] = old["CustID"].astype(str)
    d = d.merge(old, on="CustID", how="left")
    miss = d["old"].isna()
    known = d[~miss & (d["Usage"] > 0)]
    per_kwh = known.groupby(known.FlowStart.dt.year)["old"].sum() / known.groupby(known.FlowStart.dt.year)["Usage"].sum()
    d["UsageCost"] = d["old"].fillna(d["Usage"] * d["FlowStart"].dt.year.map(per_kwh).fillna(per_kwh.iloc[-1]))
    d["UsageCostEstimated"] = miss
    d = d.drop(columns="old")

# ---- the group -------------------------------------------------------------------------------------------------
new_signup = ~d["Designation"].isin(["Moving Location", "Adding Location", "Winback"])
g = d[new_signup & (d["EnrollmentType"] == "MoveIn") & (d["SentilinkIDTheftScore"] >= CUTOFF)].copy()

g["Period"] = np.where(g["FlowStart"] >= CHECKS, "Since checks", "Before checks")
g["FlowMonth"] = g["FlowStart"].dt.to_period("M").astype(str)
g["Left"] = g["FlowEnd"].notna() & (g["FlowEnd"] <= TODAY)
end = g["FlowEnd"].where(g["Left"], TODAY)
g["MonthsActive"] = ((end - g["FlowStart"]).dt.days / DAYS_PER_MONTH).clip(lower=0).round(1)
g["MonthsSinceFlow"] = ((TODAY - g["FlowStart"]).dt.days / DAYS_PER_MONTH).round(1)
g["NeverPaid"] = np.where(g["FlowStart"] <= TODAY - pd.Timedelta(days=90), (g["Revenue"] <= 0).astype(float), np.nan)
g["Earned"] = (g.Revenue - g.Tax - g.TDSP - g.UsageCost - g.CostToServe
               - g.RetailerResidualCommission - g.VendorResidualCommission)
g["Commission"] = g.UpfrontCommission + g.OtherCommission + g["R&RCommission"] + g.GiftCard
g["CostToWin"] = g["Commission"] + g.MarketingContractCost + g.WageContractCost + g.RentContractCost
g["Net"] = g["Earned"] - g["CostToWin"]
g["NetCashOnly"] = g["Earned"] - g["Commission"]
num = ["Earned", "Commission", "CostToWin", "Net", "NetCashOnly"]
g[num] = g[num].round(2)

# ---- summary by flow month (actuals only: a "left by N months" figure is blank until the month is N months old) ----
def by_month(x):
    r = {"Period": x["Period"].iloc[0], "Contracts": len(x), "Customers": x["ParentID"].nunique(),
         "StillActiveNow_%": round((~x["Left"]).mean() * 100, 1)}
    for h in [3, 6, 12, 24]:
        old = x["FlowStart"] + pd.Timedelta(days=h * DAYS_PER_MONTH) <= TODAY
        r[f"LeftWithin{h}m_%"] = round((x["Left"] & (x["MonthsActive"] <= h)).mean() * 100, 1) if old.all() else np.nan
    r["NeverPaid_%"] = round(x["NeverPaid"].mean() * 100, 1) if x["NeverPaid"].notna().any() else np.nan
    r["AvgMonthsActive"] = round(x["MonthsActive"].mean(), 1)
    for c in ["Earned", "CostToWin", "Net", "NetCashOnly"]:
        r[f"Avg{c}_ToDate"] = round(x[c].mean(), 0)
    r["TotalNet_ToDate"] = round(x["Net"].sum(), 0)
    r["AvgDebtOwed"] = round(x["Debt"].mean(), 0)
    return pd.Series(r)
rows = [by_month(x).rename(m) for (_, m), x in g.groupby(["Period", "FlowMonth"])]   # Aug 2024 is split at the 24th
rows += [by_month(x).drop("Period").rename(f"TOTAL {p}") for p, x in g.groupby("Period")]
summary = pd.DataFrame(rows).rename_axis("FlowMonth").reset_index()
summary["Period"] = summary["Period"].fillna("TOTAL")

# ---- actual survival curves (share still active after each month; stops where fewer than 200 are old enough) ----
def km(x, horizon=48):
    m, e = x["MonthsActive"].to_numpy(), x["Left"].to_numpy(dtype=float)
    out, s = [], 1.0
    for t in range(1, horizon + 1):
        at_risk = (m >= t - 1).sum()
        if at_risk < 200:
            out.append(np.nan); continue
        s *= 1 - ((m >= t - 1) & (m < t) & (e == 1)).sum() / at_risk
        out.append(round(s * 100, 1))
    return out
other = d[new_signup & (d["EnrollmentType"] == "MoveIn") & (d["SentilinkIDTheftScore"] < CUTOFF)].copy()
other["Left"] = other["FlowEnd"].notna() & (other["FlowEnd"] <= TODAY)
oend = other["FlowEnd"].where(other["Left"], TODAY)
other["MonthsActive"] = ((oend - other["FlowStart"]).dt.days / DAYS_PER_MONTH).clip(lower=0)
curves = pd.DataFrame({"Month": range(1, 49),
    "600+ Before checks": km(g[g.Period == "Before checks"]), "600+ Since checks": km(g[g.Period == "Since checks"]),
    "Under 600 Before checks": km(other[other.FlowStart < CHECKS]), "Under 600 Since checks": km(other[other.FlowStart >= CHECKS])})

# ---- value to date by age (does the since-checks group turn positive as it gets older?) ----------------------------
g["AgeBand"] = pd.cut(g["MonthsSinceFlow"], [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 36, 48, 60, 999],
                      labels=["0-3", "3-6", "6-9", "9-12", "12-15", "15-18", "18-21", "21-24", "24-27", "27-30",
                              "30-36", "36-48", "48-60", "60+"], right=False)
age = (g.groupby(["Period", "AgeBand"], observed=True)
         .agg(Contracts=("CustID", "size"), StillActive_pct=("Left", lambda s: round((~s).mean() * 100, 1)),
              AvgEarned=("Earned", "mean"), AvgCostToWin=("CostToWin", "mean"), AvgNet=("Net", "mean"),
              AvgNetCashOnly=("NetCashOnly", "mean")).round(0).reset_index()
         .rename(columns={"AgeBand": "MonthsSinceFlow"}))

detail_cols = ["Period", "FlowMonth", "ParentID", "CustID", "FlowStart", "FlowEnd", "Status", "Designation",
               "BudgetCategory", "CreditCategory", "CreditScore", "SentilinkIDTheftScore", "DepositPaid", "Waiver",
               "BillCount", "MonthsActive", "MonthsSinceFlow", "Left", "NeverPaid", "Usage", "Billed", "Revenue",
               "Debt", "Tax", "TDSP", "UsageCost", "UsageCostEstimated", "CostToServe", "RetailerResidualCommission",
               "VendorResidualCommission", "UpfrontCommission", "OtherCommission", "R&RCommission", "GiftCard",
               "MarketingContractCost", "WageContractCost", "RentContractCost"] + num
detail = g.sort_values("FlowStart")[detail_cols]

notes = pd.DataFrame({"Item": [
    "Who", "Since checks", "Data to", "Left", "Never paid", "Earned", "Cost to win", "Net", "Net cash only",
    "Usage cost", "Actuals only", "Customers vs contracts", "Personal details"],
  "Meaning": [
    f"New sign-ups moving in (not moved house, added location or winback) with a Sentilink identity-theft score of {CUTOFF} or more.",
    "Flow start on or after 24 Aug 2024, when the Sentilink checks went live.",
    f"{TODAY.date()}",
    "The contract has an end date on or before the data date.",
    "Paid nothing at all (Revenue <= 0). Only judged once the contract is at least 90 days old.",
    "Cash received minus tax, delivery charges (TDSP), energy cost, cost to serve and residual commissions, to date.",
    "Upfront, other and R&R commission, gift card, marketing, wage and rent cost.",
    "Earned minus cost to win, to date. Negative = we have lost money on it so far.",
    "Earned minus commission and gift card only (leaves out shared marketing, wage and rent costs).",
    "The warehouse shows $0 energy cost, so the 11 Sep values are used, and kWh x average cost per kWh for newer contracts (UsageCostEstimated = True).",
    "Nothing here is projected. 'Left within N months' is blank until the whole month is at least N months old.",
    "One row per contract. A customer (ParentID) can have more than one contract.",
    "No names, emails, phones or addresses are included."]})

out = FOLDER / "movein_600_sentilink.xlsx"
with pd.ExcelWriter(out, engine="openpyxl") as xw:
    summary.to_excel(xw, "Summary by flow month", index=False)
    curves.to_excel(xw, "Survival curves", index=False)
    age.to_excel(xw, "Value by age", index=False)
    detail.to_excel(xw, "Account detail", index=False)
    notes.to_excel(xw, "Notes", index=False)

since = g[g.Period == "Since checks"]
print(f"Data to {TODAY.date()}")
print(f"Since checks: {len(since):,} contracts, {since.ParentID.nunique():,} customers "
      f"(score over {CUTOFF} strictly: {(since.SentilinkIDTheftScore > CUTOFF).sum():,})")
print(f"Before checks: {(g.Period == 'Before checks').sum():,} contracts")
pd.set_option("display.width", 250); pd.set_option("display.max_columns", 30)
print(summary[summary.Period != "Before checks"].to_string(index=False))
print("\nValue to date by age:"); print(age.to_string(index=False))
print(f"\nSaved: {out.name}")
