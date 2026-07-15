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



SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_calendarWH';


SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Customer_Notices';



SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'JESouth_CollectionAR_DailyDue';


SELECT DISTINCT [call.reason]
FROM Care_CallAI
WHERE [call.reason] LIKE '%autopay%' OR [call.reason] LIKE '%auto pay%' OR [call.reason] LIKE '%recurring%';


task 5


-- STEP 1: Size the population — how many customers called to remove autopay?
SELECT COUNT(DISTINCT ContactID) AS RemoveAutopayCalls
FROM Care_CallAI
WHERE [call.reason] = 'Remove Autopay';

--- step 2
SELECT
    FORMAT([Date], 'yyyy-MM') AS CallMonth,
    COUNT(DISTINCT ContactID) AS RemoveAutopayCalls
FROM Care_CallAI
WHERE [call.reason] = 'Remove Autopay'
GROUP BY FORMAT([Date], 'yyyy-MM')
ORDER BY CallMonth;

-- STEP 3a: Find tables that might track autopay/payment method info
SELECT TABLE_NAME, COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME LIKE '%autopay%' 
   OR COLUMN_NAME LIKE '%auto_pay%'
   OR COLUMN_NAME LIKE '%PaymentMethod%'
   OR COLUMN_NAME LIKE '%RecurringPay%';

--Step 3b: Look at the Autopay fields on iSigma_Customer_Master
SELECT TOP 20 cust_id, AutoPay, AutoPayEffectiveDate
FROM iSigma_Customer_Master
WHERE AutoPay IS NOT NULL;


--Step 4 Join Remove Autopay calls to Customer Autopay status 
SELECT
    cai.ContactID,
    cai.[Date] AS CallDate,
    cm.AutoPay AS CurrentAutoPayStatus,
    cm.AutoPayEffectiveDate,
    DATEDIFF(DAY, cm.AutoPayEffectiveDate, cai.[Date]) AS DaysOnAutopayBeforeCall
FROM Care_CallAI cai
JOIN iSigma_Customer_Master cm ON cm.cust_id = cai.ContactID
WHERE cai.[call.reason] = 'Remove Autopay';

--Step 5 : Turn this into summary buckets instead of raw rows
SELECT
    CASE 
        WHEN CurrentAutoPayStatus = 'No' THEN 'Currently Off (likely successfully removed)'
        WHEN DaysOnAutopayBeforeCall < 0 THEN 'Re-enrolled after this call (history unclear)'
        WHEN DaysOnAutopayBeforeCall <= 30 THEN 'New enrollee (0-30 days before calling)'
        WHEN DaysOnAutopayBeforeCall <= 90 THEN 'Recent enrollee (31-90 days)'
        WHEN DaysOnAutopayBeforeCall > 90 THEN 'Long-time autopay customer (90+ days)'
        ELSE 'Unknown'
    END AS Category,
    COUNT(*) AS Calls
FROM (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        cm.AutoPay AS CurrentAutoPayStatus,
        DATEDIFF(DAY, cm.AutoPayEffectiveDate, cai.[Date]) AS DaysOnAutopayBeforeCall
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Customer_Master cm ON cm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Remove Autopay'
) t
GROUP BY 
    CASE 
        WHEN CurrentAutoPayStatus = 'No' THEN 'Currently Off (likely successfully removed)'
        WHEN DaysOnAutopayBeforeCall < 0 THEN 'Re-enrolled after this call (history unclear)'
        WHEN DaysOnAutopayBeforeCall <= 30 THEN 'New enrollee (0-30 days before calling)'
        WHEN DaysOnAutopayBeforeCall <= 90 THEN 'Recent enrollee (31-90 days)'
        WHEN DaysOnAutopayBeforeCall > 90 THEN 'Long-time autopay customer (90+ days)'
        ELSE 'Unknown'
    END
ORDER BY Calls DESC;


---Step 6: checking whether iSigma_Customer_Master has a channel/enrollment-source field, so we can see if the “new enrollee removal calls” cluster around a specific sign-up channel.

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Customer_Master'
  AND (COLUMN_NAME LIKE '%channel%' 
    OR COLUMN_NAME LIKE '%source%' 
    OR COLUMN_NAME LIKE '%enroll%');


---STEP 7: Break down the “new enrollee” removal calls by sales channel
SELECT
    cm.SalesChannel,
    cm.EnrollmentType,
    COUNT(*) AS RemovalCalls
FROM Care_CallAI cai
JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
JOIN iSigma_Customer_Master cm ON cm.cust_id = ivr.AccountNumber
WHERE cai.[call.reason] = 'Remove Autopay'
  AND DATEDIFF(DAY, cm.AutoPayEffectiveDate, cai.[Date]) BETWEEN 0 AND 30
GROUP BY cm.SalesChannel, cm.EnrollmentType
ORDER BY RemovalCalls DESC;



