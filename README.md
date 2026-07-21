	
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




task 5 follow up
-- STEP 11: Find the exact Salesforce autopay log and billing account bridge view names
SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_NAME LIKE '%Salesforce%AutoPay%'
   OR TABLE_NAME LIKE '%Salesforce%Billing%Account%';

-- STEP 12: Confirm columns on both Salesforce views before joining
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Salesforce_Autopay'
ORDER BY ORDINAL_POSITION;

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Salesforce_BillingAccount'
ORDER BY ORDINAL_POSITION;

-- STEP 13: Confirm what Action, Add, and Remove actually represent
SELECT TOP 20 AccountID, Created, Action, [Add], [Remove]
FROM vw_Salesforce_Autopay
ORDER BY Created DESC;

-- STEP 14: Join autopay events to billing account bridge to get real cust_id
SELECT TOP 20
    sa.AccountID,
    sa.Created AS EventDate,
    sa.Action,
    ba.CustID
FROM vw_Salesforce_Autopay sa
JOIN vw_Salesforce_BillingAccount ba ON ba.ID = sa.AccountID
WHERE sa.Action = 'Remove'
ORDER BY sa.Created DESC;


-- STEP 15: Join real autopay-removal events to Remove Autopay calls
SELECT TOP 20
    cai.ContactID,
    cai.[Date] AS CallDate,
    ba.CustID,
    sa.Created AS AutopayRemovedDate,
    DATEDIFF(DAY, sa.Created, cai.[Date]) AS DaysBetweenRemovalAndCall
FROM Care_CallAI cai
JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
JOIN vw_Salesforce_BillingAccount ba ON ba.CustID = ivr.AccountNumber
JOIN vw_Salesforce_Autopay sa ON sa.AccountID = ba.ID AND sa.Action = 'Remove'
WHERE cai.[call.reason] = 'Remove Autopay'
ORDER BY cai.[Date] DESC;


-- STEP 16: For each Remove Autopay call, find the most recent Add event BEFORE the call
SELECT TOP 20
    cai.ContactID,
    cai.[Date] AS CallDate,
    ba.CustID,
    add_evt.LastAddDate,
    DATEDIFF(DAY, add_evt.LastAddDate, cai.[Date]) AS DaysOnAutopayBeforeCall
FROM Care_CallAI cai
JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
JOIN vw_Salesforce_BillingAccount ba ON ba.CustID = ivr.AccountNumber
CROSS APPLY (
    SELECT MAX(sa.Created) AS LastAddDate
    FROM vw_Salesforce_Autopay sa
    WHERE sa.AccountID = ba.ID
      AND sa.Action = 'Add'
      AND sa.Created <= cai.[Date]
) add_evt
WHERE cai.[call.reason] = 'Remove Autopay'
ORDER BY cai.[Date] DESC;

-- STEP 17: Rebucket "days on autopay before call" using real event history
WITH RemovalWithRealTenure AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        ba.CustID,
        add_evt.LastAddDate,
        DATEDIFF(DAY, add_evt.LastAddDate, cai.[Date]) AS DaysOnAutopayBeforeCall
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN vw_Salesforce_BillingAccount ba ON ba.CustID = ivr.AccountNumber
    CROSS APPLY (
        SELECT MAX(sa.Created) AS LastAddDate
        FROM vw_Salesforce_Autopay sa
        WHERE sa.AccountID = ba.ID
          AND sa.Action = 'Add'
          AND sa.Created <= cai.[Date]
    ) add_evt
    WHERE cai.[call.reason] = 'Remove Autopay'
)
SELECT
    CASE
        WHEN DaysOnAutopayBeforeCall IS NULL THEN 'No prior Add event found'
        WHEN DaysOnAutopayBeforeCall <= 30 THEN 'New enrollee (0-30 days)'
        WHEN DaysOnAutopayBeforeCall <= 90 THEN 'Recent enrollee (31-90 days)'
        ELSE 'Long-time autopay customer (90+ days)'
    END AS Category,
    COUNT(*) AS Calls,
    CAST(COUNT(*) AS FLOAT) / SUM(COUNT(*)) OVER () AS PctOfCalls
FROM RemovalWithRealTenure
GROUP BY
    CASE
        WHEN DaysOnAutopayBeforeCall IS NULL THEN 'No prior Add event found'
        WHEN DaysOnAutopayBeforeCall <= 30 THEN 'New enrollee (0-30 days)'
        WHEN DaysOnAutopayBeforeCall 


