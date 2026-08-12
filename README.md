	
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

