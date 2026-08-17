	
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

