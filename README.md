	
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


-- STEP 1: Build per-customer feature set for usage-alert predictive score
-- Features: bill increase % vs personal historical median, credit score, tenure (days)
-- Label: did the customer call within N days of this bill (1) or not (0)

WITH BillHistory AS (
    SELECT
        AccountNumber,
        BillDate,
        CAST(TotalCharges AS DECIMAL(10,2)) AS TotalCharges,
        CreditScore,
        FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.AccountNumber = c.AccountNumber
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
),
MedianCalc AS (
    SELECT
        AccountNumber,
        BillDate,
        TotalCharges,
        CreditScore,
        FlowStart,
        -- personal historical median charge, excluding current bill
        (
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TotalCharges)
            FROM BillHistory b2
            WHERE b2.AccountNumber = b1.AccountNumber
              AND b2.BillDate < b1.BillDate
        ) AS PersonalMedianCharge
    FROM BillHistory b1
),
FeatureSet AS (
    SELECT
        AccountNumber,
        BillDate,
        TotalCharges,
        PersonalMedianCharge,
        CASE WHEN PersonalMedianCharge > 0
             THEN (TotalCharges - PersonalMedianCharge) / PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        CreditScore,
        DATEDIFF(DAY, FlowStart, BillDate) AS TenureDays
    FROM MedianCalc
    WHERE PersonalMedianCharge IS NOT NULL
      AND CreditScore IS NOT NULL AND CreditScore != 0
)
SELECT
    f.*,
    CASE WHEN EXISTS (
        SELECT 1 FROM dbo.Care_CallAI ca
        WHERE ca.AccountNumber = f.AccountNumber
          AND ca.CallDate BETWEEN f.BillDate AND DATEADD(DAY, 14, f.BillDate)
    ) THEN 1 ELSE 0 END AS CalledWithin14Days
FROM FeatureSet f
