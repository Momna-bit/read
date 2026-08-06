	
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
-- Label: did the customer call within 14 days of this bill (1) or not (0)

WITH BillHistory AS (
    SELECT
        b.cust_id,
        b.Bill_Date,
        CAST(b.inv_amount AS DECIMAL(10,2)) AS inv_amount,
        c.CreditScore,
        c.FlowStart
    FROM iSigma_Bill_Master b
    INNER JOIN iSigma_Customer_Master c
        ON b.cust_id = c.cust_id
    WHERE c.Market = 'Texas'
      AND c.CustomerType = 'Residential'
),
MedianCalc AS (
    SELECT
        b1.cust_id,
        b1.Bill_Date,
        b1.inv_amount,
        b1.CreditScore,
        b1.FlowStart,
        m.PersonalMedianCharge
    FROM BillHistory b1
    CROSS APPLY (
        SELECT AVG(inv_amount) AS PersonalMedianCharge
        FROM (
            SELECT
                inv_amount,
                ROW_NUMBER() OVER (ORDER BY inv_amount) AS rn,
                COUNT(*) OVER () AS cnt
            FROM BillHistory b2
            WHERE b2.cust_id = b1.cust_id
              AND b2.Bill_Date < b1.Bill_Date
        ) ranked
        WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    ) m
),
FeatureSet AS (
    SELECT
        cust_id,
        Bill_Date,
        inv_amount,
        PersonalMedianCharge,
        CASE WHEN PersonalMedianCharge > 0
             THEN (inv_amount - PersonalMedianCharge) / PersonalMedianCharge * 100.0
             ELSE NULL END AS BillIncreasePct,
        CreditScore,
        DATEDIFF(DAY, FlowStart, Bill_Date) AS TenureDays
    FROM MedianCalc
    WHERE PersonalMedianCharge IS NOT NULL
      AND CreditScore IS NOT NULL AND CreditScore != 0
)
SELECT
    f.*,
    CASE WHEN EXISTS (
        SELECT 1 FROM dbo.Care_CallAI ca
        WHERE ca.cust_id = f.cust_id
          AND ca.CallDate BETWEEN f.Bill_Date AND DATEADD(DAY, 14, f.Bill_Date)
    ) THEN 1 ELSE 0 END AS CalledWithin14Days
FROM FeatureSet f


SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Care_CallAI'
ORDER BY ORDINAL_POSITION



SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Care_CustomerContact'
ORDER BY ORDINAL_POSITION
