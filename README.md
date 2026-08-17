	
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
