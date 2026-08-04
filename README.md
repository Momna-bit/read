	
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


-- WHY: To merge the credit-quality finding into the day-of-week/seasonal
-- forecast, we first need two things: how many active customers fall into
-- each credit tier today, and how often each tier actually calls, on average.
-- This step gets the customer counts by tier.

SELECT
    CASE
        WHEN CreditScore <= 500 THEN 'Low (\u2264500)'
        WHEN CreditScore BETWEEN 501 AND 700 THEN 'Medium (501-700)'
        WHEN CreditScore > 700 THEN 'High (700+)'
    END AS CreditTier,
    COUNT(*) AS CustomerCount
FROM iSigma_Customer_Master
WHERE Market = 'Texas' AND CustomerType = 'Residential'
    AND CreditScore <> 0
    AND FlowEnd IS NULL
GROUP BY CASE
        WHEN CreditScore <= 500 THEN 'Low (\u2264500)'
        WHEN CreditScore BETWEEN 501 AND 700 THEN 'Medium (501-700)'
        WHEN CreditScore > 700 THEN 'High (700+)'
    END
ORDER BY CreditTier;
