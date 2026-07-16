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

---STEP 8: Confirm the billing/charge date columns available
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Bill_Master';



-- STEP 9a: Confirm exact column names (Step 9 failed due to a name mismatch)
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Bill_Master'
  AND COLUMN_NAME LIKE '%LastPaid%';


-- STEP 9: Check how many days before their removal call each customer was last charged via autopay
SELECT
    cai.ContactID,
    cai.[Date] AS CallDate,
    bm.LastPaidDateiSigma,
    bm.LastPaidiSigma,
    DATEDIFF(DAY, bm.LastPaidDateiSigma, cai.[Date]) AS DaysSinceLastCharge
FROM Care_CallAI cai
JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
WHERE cai.[call.reason] = 'Remove Autopay'
  AND bm.AutoPayOn = 'Yes'
  AND bm.Bill_Date = (
      SELECT MAX(bm2.Bill_Date)
      FROM iSigma_Bill_Master bm2
      WHERE bm2.cust_id = bm.cust_id AND bm2.Bill_Date <= cai.[Date]
  );

---STEP 10: Bucket “days since last autopay charge” into readable categories
SELECT
    CASE
        WHEN DaysSinceLastCharge IS NULL THEN 'No recent autopay charge on record'
        WHEN DaysSinceLastCharge <= 3 THEN 'Charged within 3 days of call'
        WHEN DaysSinceLastCharge <= 7 THEN 'Charged within a week'
        WHEN DaysSinceLastCharge <= 14 THEN 'Charged within 2 weeks'
        WHEN DaysSinceLastCharge <= 30 THEN 'Charged within a month'
        ELSE 'Charged over a month ago'
    END AS ChargeTiming,
    COUNT(*) AS Calls
FROM (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        bm.LastPaidDateiSigma,
        DATEDIFF(DAY, bm.LastPaidDateiSigma, cai.[Date]) AS DaysSinceLastCharge
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Remove Autopay'
      AND bm.AutoPayOn = 'Yes'
      AND bm.Bill_Date = (
          SELECT MAX(bm2.Bill_Date)
          FROM iSigma_Bill_Master bm2
          WHERE bm2.cust_id = bm.cust_id AND bm2.Bill_Date <= cai.[Date]
      )
) t
GROUP BY
    CASE
        WHEN DaysSinceLastCharge IS NULL THEN 'No recent autopay charge on record'
        WHEN DaysSinceLastCharge <= 3 THEN 'Charged within 3 days of call'
        WHEN DaysSinceLastCharge <= 7 THEN 'Charged within a week'
        WHEN DaysSinceLastCharge <= 14 THEN 'Charged within 2 weeks'
        WHEN DaysSinceLastCharge <= 30 THEN 'Charged within a month'
        ELSE 'Charged over a month ago'
    END
ORDER BY Calls DESC;


task 4


-- STEP 1: Daily call metrics from dbo.IVR
-- Scoped to July 2022 onward, per Jonathan's guidance (3 full summers of data)
-- Excludes 2021 data entirely, so historical anomalies from that period
-- (e.g., the 70,648-call spike on 2021-02-15) don't need to be investigated.

SELECT
    CAST(CallDate AS DATE) AS CallDay,
    COUNT(*) AS Calls,
    SUM(CASE WHEN AgentTalkTime > 0 THEN 1 ELSE 0 END) AS AgentCalls,
    COUNT(DISTINCT CASE WHEN AgentTalkTime > 0 THEN Username END) AS UniqueAgentCount,
    AVG(CASE WHEN AgentTalkTime > 0 THEN CAST(AgentTalkTime AS FLOAT) END) AS AvgTalkTimeSeconds
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallType IN ('Inbound','Transfer')
  AND CallDate >= '2022-07-01'
GROUP BY CAST(CallDate AS DATE)
ORDER BY CallDay;


-- STEP 2: Active customer count, per day
-- For every day in the call data (2022-07-01 onward), counts how many
-- Texas Residential customers were active ON THAT SPECIFIC DAY - meaning
-- their FlowStart was on or before that day, and they either haven't left
-- yet (FlowEnd IS NULL) or their FlowEnd hasn't happened yet.

;WITH DateRange AS (
    SELECT CAST(CallDate AS DATE) AS CallDay
    FROM dbo.IVR
    WHERE Department = 'Care'
      AND CallDate >= '2022-07-01'
    GROUP BY CAST(CallDate AS DATE)
)
SELECT
    d.CallDay,
    COUNT(DISTINCT cm.cust_id) AS ActiveCustomerCount
FROM DateRange d
JOIN iSigma_Customer_Master cm
    ON cm.Market = 'Texas'
    AND cm.CustomerType = 'Residential'
    AND cm.FlowStart <= d.CallDay
    AND (cm.FlowEnd IS NULL OR cm.FlowEnd >= d.CallDay)
GROUP BY d.CallDay
ORDER BY d.CallDay;


-- STEP 3: Past-due customer count, per day
-- Uses JESouth_CollectionAR_DailyDue, which already tracks daily
-- collection/AR status per customer. Counts distinct customers with
-- a positive past-due amount (AR field) on each day.

SELECT
    CAST([Date] AS DATE) AS CallDay,
    COUNT(DISTINCT CustID) AS PastDueCustomerCount
FROM JESouth_CollectionAR_DailyDue
WHERE [Date] >= '2022-07-01'
  AND AR > 0
GROUP BY CAST([Date] AS DATE)
ORDER BY CallDay;


