	
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


[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Users\MAli\AppData\Local\Programs\Python\Python313;C:\Users\MAli\AppData\Local\Programs\Python\Python313\Scripts", "User")


py -m pip list


SELECT CalledWithin14Days, COUNT(*) AS RowCount
FROM dbo.Task7_FeatureSet
GROUP BY CalledWithin14Days


SELECT 
    COUNT(DISTINCT CreditScore) AS DistinctCreditScores,
    AVG(BillIncreasePct) AS AvgBillIncreasePct,
    SUM(CASE WHEN CalledWithin14Days = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS CallRate
FROM dbo.Task7_FeatureSet




"""
Task 7 - Proactive Usage & Bill Shock Alert
Fits a logistic regression to estimate each customer's likelihood of
calling within 14 days of a bill, using bill increase %, credit score,
and tenure as inputs. Outputs a per-row predicted probability (0-100%).

Run from PowerShell:
    py task7_logistic_regression.py
"""

import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, classification_report

# ---- STEP 1: Load the data ----
# Update this path if your CSV lives somewhere else.
INPUT_PATH = r"C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Task7_FeatureSet_2026-08-12.csv"
OUTPUT_PATH = r"C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Task7_FeatureSet_Scored.csv"

print("Loading data... (this may take a minute or two for 13M+ rows)")

# Specify dtypes up front so pandas doesn't have to guess row-by-row,
# which is much faster and uses less memory on a file this size.
dtype_map = {
    "cust_id": "int64",
    "inv_amount": "float64",
    "PersonalMedianCharge": "float64",
    "BillIncreasePct": "float64",
    "CreditScore": "int64",
    "TenureDays": "int64",
    "CalledWithin14Days": "int64",
}

df = pd.read_csv(
    INPUT_PATH,
    dtype=dtype_map,
    parse_dates=["Bill_Date"],
)

print(f"Loaded {len(df):,} rows.")

# ---- STEP 2: Clean up rows the model can't use ----
# Drop rows with missing values in the columns we actually need.
model_cols = ["BillIncreasePct", "CreditScore", "TenureDays", "CalledWithin14Days"]
before = len(df)
df = df.dropna(subset=model_cols)
after = len(df)
print(f"Dropped {before - after:,} rows with missing values. {after:,} rows remain.")

# ---- STEP 3: Set up features (X) and label (y) ----
X = df[["BillIncreasePct", "CreditScore", "TenureDays"]]
y = df["CalledWithin14Days"]

# ---- STEP 4: Train/test split ----
# We hold out 20% of the data to check how well the model generalizes
# to bills it hasn't seen before.
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

print(f"Training on {len(X_train):,} rows, testing on {len(X_test):,} rows.")

# ---- STEP 5: Fit the logistic regression ----
# class_weight='balanced' helps because only ~4% of bills result in a call -
# without this, the model would just predict "no call" for everyone and
# still be 96% "accurate" while being useless.
model = LogisticRegression(max_iter=1000, class_weight="balanced")
model.fit(X_train, y_train)

# ---- STEP 6: Evaluate on the held-out test set ----
y_pred_proba_test = model.predict_proba(X_test)[:, 1]
auc = roc_auc_score(y_test, y_pred_proba_test)
print(f"\nModel AUC on test set: {auc:.4f}  (0.5 = no better than chance, 1.0 = perfect)")

y_pred_test = model.predict(X_test)
print("\nClassification report on test set (using default 0.5 cutoff):")
print(classification_report(y_test, y_pred_test, digits=3))

# ---- STEP 7: Show what the model learned ----
print("\nModel coefficients (higher = stronger positive relationship with calling):")
for name, coef in zip(X.columns, model.coef_[0]):
    print(f"  {name:20s} {coef:+.6f}")
print(f"  {'Intercept':20s} {model.intercept_[0]:+.6f}")

# ---- STEP 8: Score every row in the full dataset ----
# This produces a percentage likelihood (0-100%) for every customer-bill,
# not just the test set - this is what gets used to pick a cutoff later.
print("\nScoring full dataset...")
df["CallLikelihoodPct"] = model.predict_proba(X)[:, 1] * 100

# ---- STEP 9: Save results ----
print(f"Saving scored file to:\n{OUTPUT_PATH}")
df.to_csv(OUTPUT_PATH, index=False)

print("\nDone. Open the output CSV to see CallLikelihoodPct for each customer-bill.")
print("Next step: pick a cutoff percentage with Jonathan to decide who gets an alert.")



cd "$env:USERPROFILE\OneDrive - Just Energy Corp\Desktop"
py -m pip install scikit-learn
py task7_logistic_regression.py


Get-Content "Task7_FeatureSet_2026-08-12.csv" -TotalCount 1

7716418,2024-12-03,488.02,488.020000,0.000000,974,703,1




"""
Task 7 - Proactive Usage & Bill Shock Alert
Fits a logistic regression to estimate each customer's likelihood of
calling within 14 days of a bill, using bill increase %, credit score,
and tenure as inputs. Outputs a per-row predicted probability (0-100%).

Run from PowerShell:
    py task7_logistic_regression.py
"""

import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, classification_report

# ---- STEP 1: Load the data ----
# Update this path if your CSV lives somewhere else.
INPUT_PATH = r"C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Task7_FeatureSet_2026-08-12.csv"
OUTPUT_PATH = r"C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Task7_FeatureSet_Scored.csv"

print("Loading data... (this may take a minute or two for 13M+ rows)")

# Specify dtypes up front so pandas doesn't have to guess row-by-row,
# which is much faster and uses less memory on a file this size.
dtype_map = {
    "cust_id": "int64",
    "inv_amount": "float64",
    "PersonalMedianCharge": "float64",
    "BillIncreasePct": "float64",
    "CreditScore": "int64",
    "TenureDays": "int64",
    "CalledWithin14Days": "int64",
}

# The CSV exported from SSMS does NOT include a header row - the first
# line is already real data. So we tell pandas the column names directly,
# in the same order as the original SQL query's SELECT list.
column_names = [
    "cust_id",
    "Bill_Date",
    "inv_amount",
    "PersonalMedianCharge",
    "BillIncreasePct",
    "CreditScore",
    "TenureDays",
    "CalledWithin14Days",
]

df = pd.read_csv(
    INPUT_PATH,
    header=None,
    names=column_names,
    dtype=dtype_map,
    parse_dates=["Bill_Date"],
)

print(f"Loaded {len(df):,} rows.")

# ---- STEP 2: Clean up rows the model can't use ----
# Drop rows with missing values in the columns we actually need.
model_cols = ["BillIncreasePct", "CreditScore", "TenureDays", "CalledWithin14Days"]
before = len(df)
df = df.dropna(subset=model_cols)
after = len(df)
print(f"Dropped {before - after:,} rows with missing values. {after:,} rows remain.")

# ---- STEP 3: Set up features (X) and label (y) ----
X = df[["BillIncreasePct", "CreditScore", "TenureDays"]]
y = df["CalledWithin14Days"]

# ---- STEP 4: Train/test split ----
# We hold out 20% of the data to check how well the model generalizes
# to bills it hasn't seen before.
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

print(f"Training on {len(X_train):,} rows, testing on {len(X_test):,} rows.")

# ---- STEP 5: Fit the logistic regression ----
# class_weight='balanced' helps because only ~4% of bills result in a call -
# without this, the model would just predict "no call" for everyone and
# still be 96% "accurate" while being useless.
model = LogisticRegression(max_iter=1000, class_weight="balanced")
model.fit(X_train, y_train)

# ---- STEP 6: Evaluate on the held-out test set ----
y_pred_proba_test = model.predict_proba(X_test)[:, 1]
auc = roc_auc_score(y_test, y_pred_proba_test)
print(f"\nModel AUC on test set: {auc:.4f}  (0.5 = no better than chance, 1.0 = perfect)")

y_pred_test = model.predict(X_test)
print("\nClassification report on test set (using default 0.5 cutoff):")
print(classification_report(y_test, y_pred_test, digits=3))

# ---- STEP 7: Show what the model learned ----
print("\nModel coefficients (higher = stronger positive relationship with calling):")
for name, coef in zip(X.columns, model.coef_[0]):
    print(f"  {name:20s} {coef:+.6f}")
print(f"  {'Intercept':20s} {model.intercept_[0]:+.6f}")

# ---- STEP 8: Score every row in the full dataset ----
# This produces a percentage likelihood (0-100%) for every customer-bill,
# not just the test set - this is what gets used to pick a cutoff later.
print("\nScoring full dataset...")
df["CallLikelihoodPct"] = model.predict_proba(X)[:, 1] * 100

# ---- STEP 9: Save results ----
print(f"Saving scored file to:\n{OUTPUT_PATH}")
df.to_csv(OUTPUT_PATH, index=False)

print("\nDone. Open the output CSV to see CallLikelihoodPct for each customer-bill.")
print("Next step: pick a cutoff percentage with Jonathan to decide who gets an alert.")





dtype_map = {
    "cust_id": "float64",
    "inv_amount": "float64",
    "PersonalMedianCharge": "float64",
    "BillIncreasePct": "float64",
    "CreditScore": "float64",
    "TenureDays": "float64",
    "CalledWithin14Days": "float64",
}


df["CreditScore"] = df["CreditScore"].astype("int64")
df["TenureDays"] = df["TenureDays"].astype("int64")
df["CalledWithin14Days"] = df["CalledWithin14Days"].astype("int64")




model_cols = ["BillIncreasePct", "CreditScore", "TenureDays", "CalledWithin14Days"]

before = len(df)
df = df.dropna(subset=model_cols)
after = len(df)
print(f"Dropped {before - after:,} rows with missing values. {after:,} rows remain.")

df["CreditScore"] = df["CreditScore"].astype("int64")
df["TenureDays"] = df["TenureDays"].astype("int64")
df["CalledWithin14Days"] = df["CalledWithin14Days"].astype("int64")




"""
Task 7 - Proactive Usage & Bill Shock Alert
Fits a logistic regression to estimate each customer's likelihood of
calling within 14 days of a bill, using bill increase %, credit score,
and tenure as inputs. Outputs a per-row predicted probability (0-100%).

Run from PowerShell:
    py task7_logistic_regression.py
"""

import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import roc_auc_score, classification_report

# ---- STEP 1: Load the data ----
# Update this path if your CSV lives somewhere else.
INPUT_PATH = r"C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Task7_FeatureSet_2026-08-12.csv"
OUTPUT_PATH = r"C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Task7_FeatureSet_Scored.csv"

print("Loading data... (this may take a minute or two for 13M+ rows)")

# Specify dtypes up front so pandas doesn't have to guess row-by-row,
# which is much faster and uses less memory on a file this size.
# Note: integer dtypes can't hold missing values (NaN), and this data has
# some blanks. So we load numeric columns as float64 first (which can hold
# NaN), drop incomplete rows in Step 2, then convert to int afterward.
dtype_map = {
    "cust_id": "float64",
    "inv_amount": "float64",
    "PersonalMedianCharge": "float64",
    "BillIncreasePct": "float64",
    "CreditScore": "float64",
    "TenureDays": "float64",
    "CalledWithin14Days": "float64",
}

# The CSV exported from SSMS does NOT include a header row - the first
# line is already real data. So we tell pandas the column names directly,
# in the same order as the original SQL query's SELECT list.
column_names = [
    "cust_id",
    "Bill_Date",
    "inv_amount",
    "PersonalMedianCharge",
    "BillIncreasePct",
    "CreditScore",
    "TenureDays",
    "CalledWithin14Days",
]

df = pd.read_csv(
    INPUT_PATH,
    header=None,
    names=column_names,
    dtype=dtype_map,
    parse_dates=["Bill_Date"],
)

print(f"Loaded {len(df):,} rows.")

# ---- STEP 2: Clean up rows the model can't use ----
# Drop rows with missing values in the columns we actually need.
model_cols = ["BillIncreasePct", "CreditScore", "TenureDays", "CalledWithin14Days"]
before = len(df)
df = df.dropna(subset=model_cols)
after = len(df)
print(f"Dropped {before - after:,} rows with missing values. {after:,} rows remain.")

# Now that missing rows are gone, convert these back to whole numbers.
df["CreditScore"] = df["CreditScore"].astype("int64")
df["TenureDays"] = df["TenureDays"].astype("int64")
df["CalledWithin14Days"] = df["CalledWithin14Days"].astype("int64")

# ---- STEP 3: Set up features (X) and label (y) ----
X = df[["BillIncreasePct", "CreditScore", "TenureDays"]]
y = df["CalledWithin14Days"]

# ---- STEP 4: Train/test split ----
# We hold out 20% of the data to check how well the model generalizes
# to bills it hasn't seen before.
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

print(f"Training on {len(X_train):,} rows, testing on {len(X_test):,} rows.")

# ---- STEP 5: Fit the logistic regression ----
# class_weight='balanced' helps because only ~4% of bills result in a call -
# without this, the model would just predict "no call" for everyone and
# still be 96% "accurate" while being useless.
model = LogisticRegression(max_iter=1000, class_weight="balanced")
model.fit(X_train, y_train)

# ---- STEP 6: Evaluate on the held-out test set ----
y_pred_proba_test = model.predict_proba(X_test)[:, 1]
auc = roc_auc_score(y_test, y_pred_proba_test)
print(f"\nModel AUC on test set: {auc:.4f}  (0.5 = no better than chance, 1.0 = perfect)")

y_pred_test = model.predict(X_test)
print("\nClassification report on test set (using default 0.5 cutoff):")
print(classification_report(y_test, y_pred_test, digits=3))

# ---- STEP 7: Show what the model learned ----
print("\nModel coefficients (higher = stronger positive relationship with calling):")
for name, coef in zip(X.columns, model.coef_[0]):
    print(f"  {name:20s} {coef:+.6f}")
print(f"  {'Intercept':20s} {model.intercept_[0]:+.6f}")

# ---- STEP 8: Score every row in the full dataset ----
# This produces a percentage likelihood (0-100%) for every customer-bill,
# not just the test set - this is what gets used to pick a cutoff later.
print("\nScoring full dataset...")
df["CallLikelihoodPct"] = model.predict_proba(X)[:, 1] * 100

# ---- STEP 9: Save results ----
print(f"Saving scored file to:\n{OUTPUT_PATH}")
df.to_csv(OUTPUT_PATH, index=False)

print("\nDone. Open the output CSV to see CallLikelihoodPct for each customer-bill.")
print("Next step: pick a cutoff percentage with Jonathan to decide who gets an alert.")




"""
Task 7 - Cutoff Analysis
Summarizes the CallLikelihoodPct distribution from the scored dataset,
and shows what happens at different cutoff thresholds - how many
customers would get an alert, and what % of actual callers you'd catch.

This is the output to bring to Jonathan when picking a cutoff.

Run from PowerShell:
    py task7_cutoff_analysis.py
"""

import pandas as pd

INPUT_PATH = r"C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Task7_FeatureSet_Scored.csv"

print("Loading scored data...")
df = pd.read_csv(INPUT_PATH)
print(f"Loaded {len(df):,} rows.\n")

# ---- Overall distribution of scores ----
print("CallLikelihoodPct distribution:")
print(df["CallLikelihoodPct"].describe())

# ---- Percentile breakdown ----
print("\nPercentiles:")
for p in [50, 75, 90, 95, 99]:
    val = df["CallLikelihoodPct"].quantile(p / 100)
    print(f"  {p}th percentile: {val:.2f}%")

# ---- Cutoff table ----
# For each candidate cutoff, show:
#  - how many customers would get flagged
#  - what % of the total population that is
#  - how many actual callers are caught (recall)
#  - what % of flagged customers actually called (precision)
total = len(df)
total_actual_callers = df["CalledWithin14Days"].sum()

print("\nCutoff analysis:")
print(f"{'Cutoff':>8} {'Flagged':>12} {'% of All':>10} {'Callers Caught':>16} {'Recall':>8} {'Precision':>10}")

for cutoff in [5, 10, 15, 20, 25, 30, 40, 50]:
    flagged = df[df["CallLikelihoodPct"] >= cutoff]
    n_flagged = len(flagged)
    pct_of_all = n_flagged / total * 100
    callers_caught = flagged["CalledWithin14Days"].sum()
    recall = callers_caught / total_actual_callers * 100 if total_actual_callers > 0 else 0
    precision = callers_caught / n_flagged * 100 if n_flagged > 0 else 0
    print(f"{cutoff:>7}% {n_flagged:>12,} {pct_of_all:>9.2f}% {callers_caught:>16,} {recall:>7.1f}% {precision:>9.1f}%")

print("\nHow to read this:")
print("- 'Flagged' = how many customer-bills would trigger an alert at that cutoff")
print("- 'Recall' = what % of customers who actually called would have gotten an alert")
print("- 'Precision' = of the customers who got an alert, what % actually called")
print("- Lower cutoff = catches more real callers, but sends far more alerts overall")
print("- Higher cutoff = fewer alerts, but misses more real callers")
print("\nBring this table to Jonathan to help decide where to draw the line.")



"""
Task 7 - Cutoff Analysis
Summarizes the CallLikelihoodPct distribution from the scored dataset,
and shows what happens at different cutoff thresholds - how many
customers would get an alert, and what % of actual callers you'd catch.

This is the output to bring to Jonathan when picking a cutoff.

Run from PowerShell:
    py task7_cutoff_analysis.py
"""

import pandas as pd

INPUT_PATH = r"C:\Users\MAli\OneDrive - Just Energy Corp\Desktop\Task7_FeatureSet_Scored.csv"

print("Loading scored data...")
df = pd.read_csv(INPUT_PATH)
print(f"Loaded {len(df):,} rows.\n")

# ---- Overall distribution of scores ----
print("CallLikelihoodPct distribution:")
print(df["CallLikelihoodPct"].describe())

# ---- Percentile breakdown ----
print("\nPercentiles:")
for p in [50, 75, 90, 95, 99]:
    val = df["CallLikelihoodPct"].quantile(p / 100)
    print(f"  {p}th percentile: {val:.2f}%")

# ---- Cutoff table ----
# For each candidate cutoff, show:
#  - how many customers would get flagged
#  - what % of the total population that is
#  - how many actual callers are caught (recall)
#  - what % of flagged customers actually called (precision)
total = len(df)
total_actual_callers = df["CalledWithin14Days"].sum()

print("\nCutoff analysis:")
print(f"{'Cutoff':>8} {'Flagged':>12} {'% of All':>10} {'Callers Caught':>16} {'Recall':>8} {'Precision':>10}")

for cutoff in [5, 10, 15, 20, 25, 30, 40, 50, 55, 60, 65, 70, 75, 80, 85, 90]:
    flagged = df[df["CallLikelihoodPct"] >= cutoff]
    n_flagged = len(flagged)
    pct_of_all = n_flagged / total * 100
    callers_caught = flagged["CalledWithin14Days"].sum()
    recall = callers_caught / total_actual_callers * 100 if total_actual_callers > 0 else 0
    precision = callers_caught / n_flagged * 100 if n_flagged > 0 else 0
    print(f"{cutoff:>7}% {n_flagged:>12,} {pct_of_all:>9.2f}% {callers_caught:>16,} {recall:>7.1f}% {precision:>9.1f}%")

print("\nHow to read this:")
print("- 'Flagged' = how many customer-bills would trigger an alert at that cutoff")
print("- 'Recall' = what % of customers who actually called would have gotten an alert")
print("- 'Precision' = of the customers who got an alert, what % actually called")
print("- Lower cutoff = catches more real callers, but sends far more alerts overall")
print("- Higher cutoff = fewer alerts, but misses more real callers")
print("\nBring this table to Jonathan to help decide where to draw the line.")

# ---- Diagnostic: is there a usable cutoff at all? ----
# A cutoff is "usable" here if it flags a clearly smaller slice of the
# population (under ~20%) while still catching a meaningful share of
# real callers (recall above ~20%). If nothing in the tested range meets
# both conditions, that's a sign the three inputs alone may not separate
# callers from non-callers well enough for a workable single cutoff.
print("\n---- Diagnostic ----")
found_usable = False
for cutoff in [55, 60, 65, 70, 75, 80, 85, 90]:
    flagged = df[df["CallLikelihoodPct"] >= cutoff]
    n_flagged = len(flagged)
    pct_of_all = n_flagged / total * 100
    callers_caught = flagged["CalledWithin14Days"].sum()
    recall = callers_caught / total_actual_callers * 100 if total_actual_callers > 0 else 0
    if pct_of_all < 20 and recall > 20:
        found_usable = True
        print(f"Cutoff {cutoff}% looks workable: flags {pct_of_all:.1f}% of customers, catches {recall:.1f}% of real callers.")

if not found_usable:
    print("No cutoff in the tested range (55-90%) flags under 20% of customers")
    print("while still catching over 20% of real callers.")
    print("This suggests BillIncreasePct, CreditScore, and TenureDays alone may not")
    print("separate future callers from non-callers well enough for a single workable")
    print("cutoff. Worth raising with Jonathan: either accept a higher volume of alerts,")
    print("or discuss adding more features (payment history, prior call frequency, etc.)")
    print("to improve separation before finalizing a cutoff.")
