	
Pehle terminal dekh -> git bash

(step by step check karna. Example node -v likh ke hit enter)
Phir check -> node -v
	      npm -v


npm create vite@latest call-dashboard -- --template react

(jab upper wala run karogi tou neeche options ayege usme se)

ESLint
Yes

Ctrl + C (ye server stop karne k liye hai)

cd ~/call-dashboard
code .

(jab vs code khule ga tab)
select src on the left panel
then right click on src and add new file
rename the file to call_forecast_dashboard.jsx
open the file and paste the code from github to the newly created file in vscode.

(ye karke phir terminal mein jana)

npm install recharts

npm list recharts


(neeche walay code b terminal mein run karna and make sure they are not empty)

npm list react
npm list react-dom

(finally neeche wala karna server live karne k liye)
npm run dev



-- STEP 1: Validate Jonathan's numbers — wrap the existing query and check
-- the Outcome breakdown by customer count and total debt

WITH CustomerAttrition AS (
    -- PASTE your entire existing query here, exactly as it is now
    -- (everything from "SELECT CM.[cust_id] AS 'CustID'" down through
    -- the final "GROUP BY ... ,P.PreviousCustID")
)
SELECT 
    Outcome,
    COUNT(*) AS CustomerCount,
    SUM(Debt) AS TotalDebt,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS PctOfCustomers,
    CAST(100.0 * SUM(Debt) / SUM(SUM(Debt)) OVER () AS DECIMAL(5,2)) AS PctOfTotalDebt
FROM CustomerAttrition
GROUP BY Outcome
ORDER BY TotalDebt DESC;


SELECT CONCAT('Tenure bucket: ', TenureBucket),
    COUNT(*), AVG(Tenure), AVG(CAST(CreditScore AS FLOAT)), AVG(Debt), SUM(Debt)
FROM (
    SELECT *,
        CASE WHEN Tenure < 3 THEN '0-2 months'
             WHEN Tenure < 6 THEN '3-5 months'
             WHEN Tenure < 12 THEN '6-11 months'
             WHEN Tenure < 24 THEN '1-2 years'
             ELSE '2+ years' END AS TenureBucket
    FROM SwitchBeforeBillDue
) WithBucket
GROUP BY TenureBucket


-- STEP 4: Search for any usage/meter-related tables in the warehouse,
-- in case daily usage data already exists somewhere we haven't found yet

SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%usage%'
   OR TABLE_NAME LIKE '%meter%'
   OR TABLE_NAME LIKE '%kwh%'
   OR TABLE_NAME LIKE '%consumption%'
   OR TABLE_NAME LIKE '%read%'
ORDER BY TABLE_NAME;


-- STEP 5: Check what columns iSigma_Bill_Master actually has,
-- in case usage-at-billing-time is already sitting there
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Bill_Master'
ORDER BY ORDINAL_POSITION;

-- STEP 6: Sample real bills to see what D10/D20/D30/D60 actually contain
SELECT TOP 20
    Bill_No,
    cust_id,
    service_start,
    service_end,
    ServicePeriod,
    Usage,
    PerDay,
    D10,
    D20,
    D30,
    D60
FROM [Analytics_ConstellationWH].[dbo].[iSigma_Bill_Master]
WHERE service_start IS NOT NULL
ORDER BY service_start DESC;


-- STEP 7: Profile SwitchBeforeBillDue by utility, brand, and product

WITH CustomerAttrition AS (
    -- (same full query as before)
),
SwitchBeforeBillDue AS (
    SELECT * FROM CustomerAttrition WHERE Outcome = 'SwitchBeforeBillDue'
)
SELECT 'Overall' AS Segment, 
    COUNT(*) AS CustomerCount, AVG(Debt) AS AvgDebt, SUM(Debt) AS TotalDebt
FROM SwitchBeforeBillDue

UNION ALL

SELECT CONCAT('Utility: ', Utility), 
    COUNT(*), AVG(Debt), SUM(Debt)
FROM SwitchBeforeBillDue
GROUP BY Utility

UNION ALL

SELECT CONCAT('Brand: ', Brand), 
    COUNT(*), AVG(Debt), SUM(Debt)
FROM SwitchBeforeBillDue
GROUP BY Brand

UNION ALL

SELECT CONCAT('Product: ', ProductName), 
    COUNT(*), AVG(Debt), SUM(Debt)
FROM SwitchBeforeBillDue
GROUP BY ProductName

ORDER BY Segment;



-- STEP 8: Compare each utility's share of SwitchBeforeBillDue against
-- its share of the OVERALL residential Texas customer base

WITH CustomerAttrition AS (
    -- (same full query as before)
),
SwitchBeforeBillDue AS (
    SELECT * FROM CustomerAttrition WHERE Outcome = 'SwitchBeforeBillDue'
),
SegmentByUtility AS (
    SELECT Utility, 
        COUNT(*) AS SegmentCount,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS PctOfSegment
    FROM SwitchBeforeBillDue
    GROUP BY Utility
),
OverallByUtility AS (
    SELECT Utility, 
        COUNT(*) AS OverallCount,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS PctOfOverall
    FROM CustomerAttrition
    GROUP BY Utility
)
SELECT 
    S.Utility,
    S.SegmentCount,
    S.PctOfSegment,
    O.OverallCount,
    O.PctOfOverall,
    CAST(S.PctOfSegment - O.PctOfOverall AS DECIMAL(5,2)) AS PctPointDifference
FROM SegmentByUtility S
JOIN OverallByUtility O ON S.Utility = O.Utility
ORDER BY PctPointDifference DESC;



# backtest_granularity_comparison.py
# Tests whether coarser time buckets (30-min, hourly) improve forecast
# accuracy compared to the 15-minute baseline (~48% MAPE). Builds the
# coarser buckets directly from the existing 15-min data (no new SQL
# needed), then runs the same leave-one-out backtest method used before
# so all three granularities are directly comparable.

import pandas as pd
import numpy as np

df = pd.read_csv("interval_call_data_clean.csv", parse_dates=["CallDay", "IntervalStart"])


def build_bucket_time(interval_start, minutes):
    """Round IntervalStart down to the nearest `minutes`-sized bucket."""
    total_minutes = interval_start.hour * 60 + interval_start.minute
    bucket_minutes = (total_minutes // minutes) * minutes
    return f"{bucket_minutes // 60:02d}:{bucket_minutes % 60:02d}:00"


def run_backtest(data, granularity_minutes, label):
    data = data.copy()
    data["BucketTime"] = data["IntervalStart"].apply(lambda x: build_bucket_time(x, granularity_minutes))

    # Re-aggregate call volume into the coarser buckets
    bucketed = data.groupby(["Queue", "CallDay", "BucketTime"], as_index=False)["CallVolume"].sum()
    bucketed["DayOfWeek"] = pd.to_datetime(bucketed["CallDay"]).dt.day_name()

    backtest_rows = []
    for queue in bucketed["Queue"].unique():
        q_data = bucketed[bucketed["Queue"] == queue]
        real_buckets = sorted(q_data["BucketTime"].unique())
        all_days = pd.date_range(q_data["CallDay"].min(), q_data["CallDay"].max(), freq="D")

        grid = pd.MultiIndex.from_product([all_days, real_buckets], names=["CallDay", "BucketTime"]).to_frame(index=False)
        grid["CallDay"] = grid["CallDay"].astype(str)
        merged = grid.merge(q_data[["CallDay", "BucketTime", "CallVolume"]].astype({"CallDay": str}),
                             on=["CallDay", "BucketTime"], how="left")
        merged["CallVolume"] = merged["CallVolume"].fillna(0)
        merged["DayOfWeek"] = pd.to_datetime(merged["CallDay"]).dt.day_name()

        for (dow, btime), group in merged.groupby(["DayOfWeek", "BucketTime"]):
            vols = group["CallVolume"].values
            n = len(vols)
            if n < 2:
                continue
            total = vols.sum()
            for idx, actual in zip(group.index, vols):
                loo_forecast = (total - actual) / (n - 1)
                backtest_rows.append({"Queue": queue, "Actual": actual, "Forecast": round(loo_forecast, 2)})

    bt = pd.DataFrame(backtest_rows)
    bt["AbsError"] = (bt["Actual"] - bt["Forecast"]).abs()
    nonzero = bt[bt["Actual"] > 0].copy()
    nonzero["APE"] = nonzero["AbsError"] / nonzero["Actual"] * 100
    nonzero["Within15pct"] = nonzero["APE"] <= 15

    mape = nonzero["APE"].mean()
    within15 = 100 * nonzero["Within15pct"].mean()
    print(f"=== {label} ===")
    print(f"Bucket-days tested: {len(bt):,} | Non-zero: {len(nonzero):,}")
    print(f"MAPE: {mape:.1f}%")
    print(f"% within 15% of actual: {within15:.1f}%")
    print()
    return {"Granularity": label, "MAPE": round(mape, 1), "Within15pct": round(within15, 1)}


results = []
results.append(run_backtest(df, 15, "15-minute (baseline)"))
results.append(run_backtest(df, 30, "30-minute"))
results.append(run_backtest(df, 60, "Hourly"))

summary = pd.DataFrame(results)
print("=== SUMMARY: accuracy by granularity ===")
print(summary.to_string(index=False))

summary.to_csv("granularity_comparison_results.csv", index=False)
print()
print("Saved to granularity_comparison_results.csv")



# generate_forward_forecast.py
# Builds the real forward-looking 15-minute interval forecast for the next
# 3 months, using the day-of-week + time-of-day baseline already validated
# via backtesting (~48% MAPE, honestly disclosed). This is the actual
# forecast table -- not a backtest -- meant for WFM/Lou to use.

import pandas as pd
from datetime import timedelta

# Load the validated baseline (built in build_interval_forecast.py)
baseline = pd.read_csv("interval_forecast_baseline.csv")

# Forecast horizon: next 3 months from today
today = pd.Timestamp.now().normalize()
horizon_days = 90
future_dates = pd.date_range(today, today + timedelta(days=horizon_days - 1), freq="D")

forecast_rows = []
for date in future_dates:
    dow = date.day_name()
    day_forecast = baseline[baseline["DayOfWeek"] == dow].copy()
    day_forecast["ForecastDate"] = date
    forecast_rows.append(day_forecast)

forward_forecast = pd.concat(forecast_rows, ignore_index=True)
forward_forecast = forward_forecast[["Queue", "ForecastDate", "DayOfWeek", "IntervalTime",
                                       "ForecastVolume", "StdDev", "SampleSize"]]
forward_forecast = forward_forecast.sort_values(["Queue", "ForecastDate", "IntervalTime"])

print(f"Generated forward forecast: {len(forward_forecast):,} rows")
print(f"Covering {forward_forecast['Queue'].nunique()} queues over {horizon_days} days "
      f"({future_dates.min().date()} to {future_dates.max().date()})")
print()

# Quick sanity check: total forecasted calls per queue over the full 90 days
totals = forward_forecast.groupby("Queue")["ForecastVolume"].sum().round(0).sort_values(ascending=False)
print("=== Total forecasted calls per queue, next 90 days ===")
print(totals.to_string())
print()

# Sample: tomorrow's forecast for the highest-volume queue
top_queue = totals.index[0]
tomorrow = future_dates[1]
sample = forward_forecast[
    (forward_forecast["Queue"] == top_queue) &
    (forward_forecast["ForecastDate"] == tomorrow)
]
print(f"=== Sample: {top_queue}, forecast for {tomorrow.date()} ({tomorrow.day_name()}) ===")
print(sample[["IntervalTime", "ForecastVolume", "StdDev"]].head(15).to_string(index=False))

forward_forecast.to_csv("interval_forecast_forward_90day.csv", index=False)
print()
print("Saved to interval_forecast_forward_90day.csv")


# build_deviation_alert.py
# Deviation/anomaly alert: flags a 15-min interval as unusual when the
# actual call volume strays too far from the forecast for THAT SPECIFIC
# interval, measured in standard deviations rather than a flat percentage.
# This matters because some intervals are naturally stable (low std) and
# others are naturally volatile (high std) -- a flat % threshold would
# false-alarm constantly on volatile intervals and miss real problems on
# stable ones. The z-score threshold is a single adjustable cutoff, same
# idea as the tunable cutoff used for the Task 7 targeting model.

import pandas as pd

df = pd.read_csv("interval_call_data_clean.csv", parse_dates=["CallDay", "IntervalStart"])
baseline = pd.read_csv("interval_forecast_baseline.csv")

df["IntervalTime"] = df["IntervalStart"].dt.time
df["DayOfWeek"] = df["CallDay"].dt.day_name()

# Match baseline's IntervalTime format (string) to df's (time object)
baseline["IntervalTime"] = pd.to_datetime(baseline["IntervalTime"], format="%H:%M:%S").dt.time

# Join actuals to their forecast + std dev for that exact Queue/DayOfWeek/Interval
merged = df.merge(
    baseline[["Queue", "DayOfWeek", "IntervalTime", "ForecastVolume", "StdDev"]],
    on=["Queue", "DayOfWeek", "IntervalTime"],
    how="left"
)

# Avoid divide-by-zero: where StdDev is 0 (perfectly stable interval), any
# deviation at all is flagged rather than computing an undefined z-score
merged["Deviation"] = merged["CallVolume"] - merged["ForecastVolume"]
merged["ZScore"] = merged.apply(
    lambda r: (r["Deviation"] / r["StdDev"]) if r["StdDev"] > 0 else (999 if r["Deviation"] != 0 else 0),
    axis=1
)

# ADJUSTABLE CUTOFF -- this is the single tunable knob for alert sensitivity
Z_THRESHOLD = 2.5

# MINIMUM VOLUME FLOOR -- queues too sparse to have a meaningful StdDev
# produce false "anomalies" from a single call landing on a normally-silent
# interval (StdDev near 0 makes any nonzero actual look extreme). Exclude
# intervals where the forecast baseline itself is too small to trust.
MIN_FORECAST_VOLUME = 3.0

merged["Flagged"] = (merged["ZScore"].abs() >= Z_THRESHOLD) & (merged["ForecastVolume"] >= MIN_FORECAST_VOLUME)
merged["ExcludedTooSparse"] = merged["ForecastVolume"] < MIN_FORECAST_VOLUME

flagged = merged[merged["Flagged"]].copy()
flagged = flagged.sort_values("ZScore", key=abs, ascending=False)

excluded_count = merged["ExcludedTooSparse"].sum()
eligible = merged[~merged["ExcludedTooSparse"]]

print(f"Threshold: |z-score| >= {Z_THRESHOLD}, minimum forecast volume >= {MIN_FORECAST_VOLUME}")
print(f"Total intervals checked: {len(merged):,}")
print(f"Excluded as too sparse (forecast < {MIN_FORECAST_VOLUME}): {excluded_count:,} "
      f"({100 * excluded_count / len(merged):.1f}%)")
print(f"Eligible intervals: {len(eligible):,}")
print(f"Flagged as anomalies: {len(flagged):,} ({100 * len(flagged) / len(eligible):.2f}% of eligible)")
print()

print("=== Top 15 most extreme deviations found in the historical data ===")
print(flagged[["Queue", "CallDay", "IntervalTime", "CallVolume", "ForecastVolume", "ZScore"]]
      .head(15).to_string(index=False))
print()

print("=== Flag rate by queue, eligible intervals only (sanity check) ===")
by_queue = eligible.groupby("Queue")["Flagged"].agg(FlagRate=lambda x: 100 * x.mean(), Count="count")
by_queue["FlagRate"] = by_queue["FlagRate"].round(2)
print(by_queue.sort_values("FlagRate", ascending=False).to_string())
print()

sparse_queues = merged[merged["ExcludedTooSparse"]]["Queue"].unique()
if len(sparse_queues) > 0:
    print(f"NOTE: These queues had intervals excluded as too sparse for reliable alerting: "
          f"{', '.join(sparse_queues)}")
    print("These queues need a different monitoring approach (e.g., daily/weekly volume "
          "checks rather than per-15-min alerting).")

flagged.to_csv("deviation_alert_flagged_history.csv", index=False)
print()
print("Saved flagged historical anomalies to deviation_alert_flagged_history.csv")
print()
print("NOTE: Z_THRESHOLD = 2.5 is a starting point, not a fixed rule --")
print("adjust up (fewer, more extreme alerts) or down (more sensitive) as needed.")



-- STEP 9: Pull daily-level (not 15-min) volume for the 6 sparse queues
-- plus the 1 zero-recent-calls queue, over the last 90 days.
-- These don't have enough volume for 15-min forecasting, so we're
-- building a simpler daily view instead -- day-of-week averages only.

SELECT 
    Queue,
    CAST(CallDate AS DATE) AS CallDay,
    COUNT(*) AS DailyCallCount
FROM dbo.IVR
WHERE Queue IN (
    'Sams Club Hotline South-ENG',
    'Sams Club Hotline South-SPA',
    'Kroger Hotline South - ENG',
    'Kroger Hotline South - SPA',
    'OTC_Outbound_FCC_Consent_Yes_Active',
    'HEB Hotline South - ENG',
    'HEB Hotline South - SPA'
)
AND CallDate >= DATEADD(DAY, -90, CAST(GETDATE() AS DATE))
GROUP BY Queue, CAST(CallDate AS DATE)
ORDER BY Queue, CallDay;


# build_sparse_queue_forecast.py
# For the 6 sparse queues (plus HEB Hotline South-SPA, which had ZERO
# calls in the 90-day window), 15-minute forecasting doesn't make sense --
# there isn't enough volume to support it. Instead, this builds a much
# simpler DAILY day-of-week average, the most granularity this data can
# honestly support. Every queue here should be flagged to Jonathan as
# low-confidence / directional-only, not something WFM should staff to
# precisely.

import pandas as pd

col_names = ["Queue", "CallDay", "DailyCallCount"]
df = pd.read_csv("sparse_queue_daily_data.csv", header=None, names=col_names)
df["CallDay"] = pd.to_datetime(df["CallDay"])

print(f"Loaded {len(df):,} rows across {df['Queue'].nunique()} queues.")
print()

# The 7 target queues from Bidya's original list (6 sparse + 1 zero-volume)
target_queues = [
    "Sams Club Hotline South-ENG",
    "Sams Club Hotline South-SPA",
    "Kroger Hotline South - ENG",
    "Kroger Hotline South - SPA",
    "OTC_Outbound_FCC_Consent_Yes_Active",
    "HEB Hotline South - ENG",
    "HEB Hotline South - SPA",
]

# Build a full date grid so days with ZERO calls are counted as zero,
# not silently missing (same principle as the main forecast build)
all_days = pd.date_range(df["CallDay"].min(), df["CallDay"].max(), freq="D")
results = []

for queue in target_queues:
    q_data = df[df["Queue"] == queue]

    if len(q_data) == 0:
        # Queue had ZERO calls in the entire 90-day window
        results.append({
            "Queue": queue,
            "TotalCalls90Days": 0,
            "DaysWithAnyCalls": 0,
            "AvgCallsPerDay": 0.0,
            "Status": "ZERO VOLUME - no calls in 90 days, cannot forecast"
        })
        continue

    grid = pd.DataFrame({"CallDay": all_days})
    merged = grid.merge(q_data[["CallDay", "DailyCallCount"]], on="CallDay", how="left")
    merged["DailyCallCount"] = merged["DailyCallCount"].fillna(0)

    total_calls = merged["DailyCallCount"].sum()
    days_with_calls = (merged["DailyCallCount"] > 0).sum()
    avg_per_day = merged["DailyCallCount"].mean()

    status = "Low volume - directional only" if avg_per_day < 5 else "Sparse but usable"

    results.append({
        "Queue": queue,
        "TotalCalls90Days": int(total_calls),
        "DaysWithAnyCalls": int(days_with_calls),
        "AvgCallsPerDay": round(avg_per_day, 2),
        "Status": status
    })

summary = pd.DataFrame(results)
print("=== Sparse queue summary (90-day window) ===")
print(summary.to_string(index=False))
print()

# Day-of-week breakdown for queues that have SOME usable volume
print("=== Day-of-week averages (for queues with any real volume) ===")
dow_order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
dow_results = []

for queue in target_queues:
    q_data = df[df["Queue"] == queue]
    if len(q_data) == 0:
        continue

    grid = pd.DataFrame({"CallDay": all_days})
    merged = grid.merge(q_data[["CallDay", "DailyCallCount"]], on="CallDay", how="left")
    merged["DailyCallCount"] = merged["DailyCallCount"].fillna(0)
    merged["DayOfWeek"] = merged["CallDay"].dt.day_name()

    dow_avg = merged.groupby("DayOfWeek")["DailyCallCount"].mean().reindex(dow_order)
    for dow, avg in dow_avg.items():
        dow_results.append({"Queue": queue, "DayOfWeek": dow, "AvgCalls": round(avg, 2)})

dow_summary = pd.DataFrame(dow_results)
pivot = dow_summary.pivot(index="Queue", columns="DayOfWeek", values="AvgCalls")[dow_order]
print(pivot.to_string())

summary.to_csv("sparse_queue_summary.csv", index=False)
dow_summary.to_csv("sparse_queue_dayofweek.csv", index=False)
print()
print("Saved sparse_queue_summary.csv and sparse_queue_dayofweek.csv")



-- STEP 1 (corrected): Export the manifest, scoped to the actual
-- Texas TDU territories this tool covers

SELECT 
    BM.Bill_No,
    CM.CustomerType AS account_type,
    CASE 
        WHEN CM.Utility LIKE 'Centerpoint Energy%' THEN 'Centerpoint'
        WHEN CM.Utility LIKE 'AEP Texas%' THEN 'AEP'
        WHEN CM.Utility = 'Texas-New Mexico Power Co' THEN 'TNMP'
        WHEN CM.Utility = 'Lubbock Power & Light' THEN 'Lubbock'
        WHEN CM.Utility = 'Oncor' THEN 'Oncor'
        ELSE CM.Utility
    END AS territory
FROM [Analytics_ConstellationWH].[dbo].[iSigma_Bill_Master] BM
LEFT JOIN [Analytics_ConstellationWH].[dbo].[iSigma_Customer_Master] CM
    ON BM.cust_id = CM.cust_id
WHERE BM.Bill_Date >= DATEADD(MONTH, -12, GETDATE())
AND CM.Utility IN (
    'Centerpoint Energy', 'AEP Texas Central', 'AEP Texas North',
    'Texas-New Mexico Power Co', 'Lubbock Power & Light', 'Oncor'
)
ORDER BY BM.Bill_No;


py check_bill_rules.py --batch "." --manifest bill_manifest_full.csv

-- STEP 1 (re-scoped): Same TDU filter, but narrowed to a recent window
-- since our 33 sample PDFs are recent test exports, not a full year's worth

SELECT 
    BM.Bill_No,
    CM.CustomerType AS account_type,
    CASE 
        WHEN CM.Utility LIKE 'Centerpoint Energy%' THEN 'Centerpoint'
        WHEN CM.Utility LIKE 'AEP Texas%' THEN 'AEP'
        WHEN CM.Utility = 'Texas-New Mexico Power Co' THEN 'TNMP'
        WHEN CM.Utility = 'Lubbock Power & Light' THEN 'Lubbock'
        WHEN CM.Utility = 'Oncor' THEN 'Oncor'
        ELSE CM.Utility
    END AS territory
FROM [Analytics_ConstellationWH].[dbo].[iSigma_Bill_Master] BM
LEFT JOIN [Analytics_ConstellationWH].[dbo].[iSigma_Customer_Master] CM
    ON BM.cust_id = CM.cust_id
WHERE BM.Bill_Date >= DATEADD(DAY, -30, GETDATE())
AND CM.Utility IN (
    'Centerpoint Energy', 'AEP Texas Central', 'AEP Texas North',
    'Texas-New Mexico Power Co', 'Lubbock Power & Light', 'Oncor'
)
ORDER BY BM.Bill_No;


py check_bill_rules.py "Amigo_Energy_Sample.pdf" --account-type residential --territory Oncor



def check_things_you_should_know(text):
    if "THINGS YOU SHOULD KNOW ABOUT YOUR BILL" in text.upper():
        return True, "Required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice present"
    return False, "MISSING required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice"


def check_unauthorized_charges_notice(text, customer_care_phone):
    text_lower = text.lower()
    if "unauthorized charges" not in text_lower:
        return False, "MISSING unauthorized charges notification"
    if customer_care_phone and customer_care_phone in text:
        return True, f"Unauthorized charges notice present with correct phone number ({customer_care_phone})"
    return True, "Unauthorized charges notice present (phone number not cross-checked)"


def check_puct_complaint_info(text):
    required_fragments = ["P.O. Box 13326", "78711", "936-7120"]
    missing = [f for f in required_fragments if f not in text]
    if not missing:
        return True, "PUCT complaint-filing info present and complete"
    return False, f"PUCT complaint info incomplete - missing: {', '.join(missing)}"


results["things_you_should_know"] = check_things_you_should_know(text)
results["unauthorized_charges"] = check_unauthorized_charges_notice(text, customer_care_phone)
results["puct_complaint_info"] = check_puct_complaint_info(text)



# fix_functions.py
# One-time repair script. Run this once from your Bill pdf folder:
#     py fix_functions.py
#
# It finds the three new check functions (however broken their current
# indentation is), removes them completely, and reinserts clean, correctly
# formatted versions right before check_tdu_contact. This avoids all manual
# editing in VS Code, which is where the indentation kept breaking.

import re

SOURCE_FILE = "check_bill_rules.py"

with open(SOURCE_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# The three functions we're fixing, exactly as they should be -- clean,
# consistent 4-space indentation, guaranteed correct.
clean_block = '''def check_things_you_should_know(text):
    if "THINGS YOU SHOULD KNOW ABOUT YOUR BILL" in text.upper():
        return True, "Required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice present"
    return False, "MISSING required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice"


def check_unauthorized_charges_notice(text, customer_care_phone):
    text_lower = text.lower()
    if "unauthorized charges" not in text_lower:
        return False, "MISSING unauthorized charges notification"
    if customer_care_phone and customer_care_phone in text:
        return True, f"Unauthorized charges notice present with correct phone number ({customer_care_phone})"
    return True, "Unauthorized charges notice present (phone number not cross-checked)"


def check_puct_complaint_info(text):
    required_fragments = ["P.O. Box 13326", "78711", "936-7120"]
    missing = [f for f in required_fragments if f not in text]
    if not missing:
        return True, "PUCT complaint-filing info present and complete"
    return False, f"PUCT complaint info incomplete - missing: {', '.join(missing)}"


'''

# Step 1: remove any existing (possibly broken) versions of these three
# functions -- match from "def check_things_you_should_know" up to (but
# not including) the next "def " that follows, no matter how mangled the
# indentation in between is.
pattern = re.compile(
    r"def check_things_you_should_know\(.*?(?=\ndef )",
    re.DOTALL
)

if pattern.search(content):
    content = pattern.sub("", content)
    print("Found and removed the existing (broken) function block.")
else:
    print("No existing broken block found -- will insert fresh.")

# Step 2: insert the clean block right before "def check_tdu_contact"
insertion_marker = "def check_tdu_contact"

if insertion_marker not in content:
    print(f"ERROR: could not find '{insertion_marker}' in the file.")
    print("Nothing was changed. Please double check the file structure.")
else:
    content = content.replace(insertion_marker, clean_block + insertion_marker, 1)

    with open(SOURCE_FILE, "w", encoding="utf-8") as f:
        f.write(content)

    print("Success! The three functions have been cleanly inserted.")
    print("Now search for where results['critical_care'] is set, and add")
    print("these three lines right after it (this part still needs a quick")
    print("manual check, but the function definitions themselves are fixed):")
    print()
    print('    results["things_you_should_know"] = check_things_you_should_know(text)')
    print('    results["unauthorized_charges"] = check_unauthorized_charges_notice(text, customer_care_phone)')
    print('    results["puct_complaint_info"] = check_puct_complaint_info(text)')



    results["things_you_should_know"] = check_things_you_should_know(text)
    results["unauthorized_charges"] = check_unauthorized_charges_notice(text, customer_care_phone)
    results["puct_complaint_info"] = check_puct_complaint_info(text)


    results["unauthorized_charges"] = check_unauthorized_charges_notice(text, None)


# fix_line226.py
# One-time repair for the single persistent indentation problem.
# Run once: py fix_line226.py

import re

SOURCE_FILE = "check_bill_rules.py"

with open(SOURCE_FILE, "r", encoding="utf-8") as f:
    lines = f.readlines()

fixed_count = 0
for i, line in enumerate(lines):
    if "results[\"unauthorized_charges\"]" in line and "check_unauthorized_charges_notice" in line:
        # Rebuild this line from scratch with guaranteed-correct 4-space indent
        lines[i] = '    results["unauthorized_charges"] = check_unauthorized_charges_notice(text, None)\n'
        fixed_count += 1

if fixed_count == 0:
    print("Could not find the unauthorized_charges line -- nothing changed.")
else:
    with open(SOURCE_FILE, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"Fixed {fixed_count} line(s). The unauthorized_charges line now has guaranteed-correct indentation.")

for rule in ["solar", "refer_a_friend", "power_to_choose", "critical_care", "things_you_should_know", "unauthorized_charges", "puct_complaint_info", "tdu_contact"]:


# fix_pass_fail.py
# The three new functions were returning True/False, but every other
# function in this file returns "PASS"/"FAIL" strings. This rewrites
# them to match. Run once: py fix_pass_fail.py

SOURCE_FILE = "check_bill_rules.py"

with open(SOURCE_FILE, "r", encoding="utf-8") as f:
    content = f.read()

old_block_marker_start = "def check_things_you_should_know(text):"
old_block_marker_end = "def check_tdu_contact"

start_idx = content.find(old_block_marker_start)
end_idx = content.find(old_block_marker_end)

if start_idx == -1 or end_idx == -1:
    print("ERROR: could not find the expected functions in the file. Nothing changed.")
else:
    clean_block = '''def check_things_you_should_know(text):
    if "THINGS YOU SHOULD KNOW ABOUT YOUR BILL" in text.upper():
        return "PASS", "Required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice present"
    return "FAIL", "MISSING required 'THINGS YOU SHOULD KNOW ABOUT YOUR BILL' notice"


def check_unauthorized_charges_notice(text, customer_care_phone):
    text_lower = text.lower()
    if "unauthorized charges" not in text_lower:
        return "FAIL", "MISSING unauthorized charges notification"
    if customer_care_phone and customer_care_phone in text:
        return "PASS", f"Unauthorized charges notice present with correct phone number ({customer_care_phone})"
    return "PASS", "Unauthorized charges notice present (phone number not cross-checked)"


def check_puct_complaint_info(text):
    required_fragments = ["P.O. Box 13326", "78711", "936-7120"]
    missing = [f for f in required_fragments if f not in text]
    if not missing:
        return "PASS", "PUCT complaint-filing info present and complete"
    return "FAIL", f"PUCT complaint info incomplete - missing: {', '.join(missing)}"


'''
    content = content[:start_idx] + clean_block + content[end_idx:]

    with open(SOURCE_FILE, "w", encoding="utf-8") as f:
        f.write(content)

    print("Fixed! The three functions now return 'PASS'/'FAIL' strings, matching every other check in the file.")

