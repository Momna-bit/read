	
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


-- Check what values exist in DisconnectReason, to find the right
-- definition for "abandoned" before building Step 4
SELECT DISTINCT DisconnectReason, COUNT(*) AS Cnt
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallDate >= '2022-07-01'
GROUP BY DisconnectReason
ORDER BY Cnt DESC;


-- Check how many calls fit the proposed "abandoned" definition
SELECT COUNT(*) AS AbandonedCallsCandidate
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallDate >= '2022-07-01'
  AND AgentTalkTime = 0
  AND QueueTime > 0
  AND DisconnectReason = 'CUSTOMER_DISCONNECT';


-- STEP 4: Abandon rate and IVR containment rate, per day
-- Abandoned = customer hung up (CUSTOMER_DISCONNECT) while in queue
-- (QueueTime > 0) without ever reaching an agent (AgentTalkTime = 0).
-- IVR containment = resolved without ever reaching an agent, i.e. the
-- inverse of AgentCalls / Calls from Step 1.

SELECT
    CAST(CallDate AS DATE) AS CallDay,
    COUNT(*) AS Calls,
    SUM(CASE WHEN AgentTalkTime > 0 THEN 1 ELSE 0 END) AS AgentCalls,
    SUM(CASE 
            WHEN AgentTalkTime = 0 
             AND QueueTime > 0 
             AND DisconnectReason = 'CUSTOMER_DISCONNECT' 
            THEN 1 ELSE 0 
        END) AS AbandonedCalls,
    CAST(SUM(CASE 
            WHEN AgentTalkTime = 0 
             AND QueueTime > 0 
             AND DisconnectReason = 'CUSTOMER_DISCONNECT' 
            THEN 1 ELSE 0 
        END) AS FLOAT) / COUNT(*) AS AbandonRate,
    1.0 - (CAST(SUM(CASE WHEN AgentTalkTime > 0 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)) AS IVRContainmentRate
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallType IN ('Inbound','Transfer')
  AND CallDate >= '2022-07-01'
GROUP BY CAST(CallDate AS DATE)
ORDER BY CallDay;


-- STEP 5: Weekday and Holiday flags from the calendar table
-- Confirms structure before combining - matched to CallDay via Date column

SELECT
    [Date] AS CallDay,
    DayName,
    USHoliday,
    CDNHoliday
FROM [dbo].[vw_calendarWH]
WHERE [Date] >= '2022-07-01'
ORDER BY [Date];


IF OBJECT_ID('tempdb..#CallMetrics') IS NOT NULL DROP TABLE #CallMetrics;
SELECT
    CAST(CallDate AS DATE) AS CallDay,
    COUNT(*) AS Calls,
    SUM(CASE WHEN AgentTalkTime > 0 THEN 1 ELSE 0 END) AS AgentCalls,
    COUNT(DISTINCT CASE WHEN AgentTalkTime > 0 THEN Username END) AS UniqueAgentCount,
    AVG(CASE WHEN AgentTalkTime > 0 THEN CAST(AgentTalkTime AS FLOAT) END) AS AvgTalkTimeSeconds,
    SUM(CASE WHEN AgentTalkTime = 0 AND QueueTime > 0 AND DisconnectReason = 'CUSTOMER_DISCONNECT' THEN 1 ELSE 0 END) AS AbandonedCalls,
    CAST(SUM(CASE WHEN AgentTalkTime = 0 AND QueueTime > 0 AND DisconnectReason = 'CUSTOMER_DISCONNECT' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS AbandonRate,
    1.0 - (CAST(SUM(CASE WHEN AgentTalkTime > 0 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)) AS IVRContainmentRate
INTO #CallMetrics
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallType IN ('Inbound','Transfer')
  AND CallDate >= '2022-07-01'
GROUP BY CAST(CallDate AS DATE);

IF OBJECT_ID('tempdb..#ActiveCustomers') IS NOT NULL DROP TABLE #ActiveCustomers;
SELECT
    cm_days.CallDay,
    COUNT(DISTINCT cm.cust_id) AS ActiveCustomerCount
INTO #ActiveCustomers
FROM (SELECT DISTINCT CallDay FROM #CallMetrics) cm_days
JOIN iSigma_Customer_Master cm
    ON cm.Market = 'Texas'
    AND cm.CustomerType = 'Residential'
    AND cm.FlowStart <= cm_days.CallDay
    AND (cm.FlowEnd IS NULL OR cm.FlowEnd >= cm_days.CallDay)
GROUP BY cm_days.CallDay;

IF OBJECT_ID('tempdb..#PastDue') IS NOT NULL DROP TABLE #PastDue;
SELECT
    CAST([Date] AS DATE) AS CallDay,
    COUNT(DISTINCT CustID) AS PastDueCustomerCount
INTO #PastDue
FROM JESouth_CollectionAR_DailyDue
WHERE [Date] >= '2022-07-01'
  AND AR > 0
GROUP BY CAST([Date] AS DATE);

SELECT
    m.CallDay,
    m.Calls,
    m.AgentCalls,
    m.UniqueAgentCount,
    ac.ActiveCustomerCount,
    pd.PastDueCustomerCount,
    m.IVRContainmentRate,
    m.AbandonRate,
    m.AvgTalkTimeSeconds,
    cal.DayName AS Weekday,
    CASE WHEN cal.USHoliday IS NOT NULL AND cal.USHoliday <> '' THEN 1 ELSE 0 END AS IsHoliday
FROM #CallMetrics m
LEFT JOIN #ActiveCustomers ac ON ac.CallDay = m.CallDay
LEFT JOIN #PastDue pd ON pd.CallDay = m.CallDay
LEFT JOIN [dbo].[vw_calendarWH] cal ON cal.[Date] = m.CallDay
ORDER BY m.CallDay;

task 3 followup

-- STEP 1: Look at real sample data for the bill-amount fields before
-- assuming which one represents "total bill." Jonathan defined effective
-- rate as (total bill excluding past-due carryover) / usage in kWh, so we
-- need to confirm which column is the actual total due for that bill
-- (inv_amount vs NetCharge could mean different things - gross vs net of
-- adjustments) and confirm PriorPastDue is really the carryover amount to
-- subtract, not something else.

SELECT TOP 20
    Bill_No,
    cust_id,
    Bill_Date,
    Product,
    inv_amount,
    NetCharge,
    CommodityRevenue,
    AdminRevenue,
    TDSP,
    PriorPastDue,
    PastDue,
    Usage
FROM iSigma_Bill_Master
WHERE Usage > 0
ORDER BY Bill_Date DESC;


-- STEP 2: Calculate effective rate (NetCharge / Usage, in cents per kWh)
-- Excludes past-due carryover per Jonathan's definition. Excludes bills
-- with NetCharge <= 0 (credits/adjustments, not real usage charges).
SELECT TOP 20
    Bill_No,
    cust_id,
    Bill_Date,
    NetCharge,
    Usage,
    (NetCharge / Usage) * 100 AS EffectiveRateCentsPerKWh
FROM iSigma_Bill_Master
WHERE Usage > 0
  AND NetCharge > 0
ORDER BY Bill_Date DESC;

--Option A — Summary stats across the whole customer base:
SELECT
    COUNT(*) AS TotalBills,
    AVG((NetCharge / Usage) * 100) AS AvgEffectiveRate,
    SUM(CASE WHEN (NetCharge / Usage) * 100 >= 17 THEN 1 ELSE 0 END) AS BillsAboveThreshold,
    CAST(SUM(CASE WHEN (NetCharge / Usage) * 100 >= 17 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) AS PctAboveThreshold
FROM iSigma_Bill_Master
WHERE Usage > 0 AND NetCharge > 0;

--Let’s check this directly before trusting either number:
-- Check for outliers: bills with very low usage that could be inflating the average
SELECT TOP 20
    Bill_No,
    cust_id,
    NetCharge,
    Usage,
    (NetCharge / Usage) * 100 AS EffectiveRateCentsPerKWh
FROM iSigma_Bill_Master
WHERE Usage > 0 AND NetCharge > 0
ORDER BY (NetCharge / Usage) * 100 DESC;

--the median instead of the average, which is far more resistant to outliers:
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (NetCharge / Usage) * 100) 
        OVER () AS MedianEffectiveRate
FROM iSigma_Bill_Master
WHERE Usage > 0 AND NetCharge > 0;


-- Recompute median with sensible bounds to exclude data artifacts
-- Usage < 1 kWh is almost certainly bad data, not a real bill
-- NetCharge > $2000 likely indicates a commercial/aggregated account, not typical residential
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (NetCharge / Usage) * 100) 
        OVER () AS MedianEffectiveRate_Cleaned
FROM iSigma_Bill_Master
WHERE Usage >= 1 
  AND NetCharge > 0 
  AND NetCharge < 2000;

--Option B
-- Get each bill-explanation caller's most recent bill (as of call date),
-- using the same cleaned bounds (Usage >= 1, NetCharge between 0 and 2000)
-- to keep it comparable to the baseline median we just calculated.

;WITH CallerBills AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        bm.NetCharge,
        bm.Usage,
        (bm.NetCharge / bm.Usage) * 100 AS EffectiveRate
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Bill Explanation'
      AND bm.Usage >= 1
      AND bm.NetCharge > 0
      AND bm.NetCharge < 2000
      AND bm.Bill_Date = (
          SELECT MAX(bm2.Bill_Date)
          FROM iSigma_Bill_Master bm2
          WHERE bm2.cust_id = bm.cust_id AND bm2.Bill_Date <= cai.[Date]
      )
)
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EffectiveRate) 
        OVER () AS MedianEffectiveRate_BillExplanationCallers
FROM CallerBills;

-- STEP 1: For bill-explanation callers, compare their bill at time of call
-- to their own historical average bill (their personal norm), to calculate
-- a "bill increase %" - this is the "bill shock" metric Jonathan described,
-- not just comparing to other customers.

;WITH CallerBillAtCall AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        bm.cust_id,
        bm.Bill_No,
        bm.NetCharge AS BillAmountAtCall
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Bill Explanation'
      AND bm.NetCharge > 0
      AND bm.Bill_Date = (
          SELECT MAX(bm2.Bill_Date)
          FROM iSigma_Bill_Master bm2
          WHERE bm2.cust_id = bm.cust_id AND bm2.Bill_Date <= cai.[Date]
      )
),
CustomerHistoricalAvg AS (
    SELECT
        cust_id,
        AVG(NetCharge) AS AvgHistoricalBill
    FROM iSigma_Bill_Master
    WHERE NetCharge > 0
    GROUP BY cust_id
)
SELECT TOP 20
    c.ContactID,
    c.CallDate,
    c.cust_id,
    c.BillAmountAtCall,
    h.AvgHistoricalBill,
    (c.BillAmountAtCall - h.AvgHistoricalBill) / h.AvgHistoricalBill * 100 AS PctIncreaseVsPersonalAvg
FROM CallerBillAtCall c
JOIN CustomerHistoricalAvg h ON h.cust_id = c.cust_id
ORDER BY PctIncreaseVsPersonalAvg DESC;


---step 2
;WITH CallerBillAtCall AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        bm.cust_id,
        bm.Bill_No,
        bm.NetCharge AS BillAmountAtCall
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Bill Explanation'
      AND bm.NetCharge > 0
      AND bm.Bill_Date = (
          SELECT MAX(bm2.Bill_Date)
          FROM iSigma_Bill_Master bm2
          WHERE bm2.cust_id = bm.cust_id AND bm2.Bill_Date <= cai.[Date]
      )
),
CustomerHistoricalMedian AS (
    SELECT
        cust_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NetCharge) OVER (PARTITION BY cust_id) AS MedianHistoricalBill
    FROM iSigma_Bill_Master
    WHERE NetCharge > 10  -- excludes near-zero junk bills
      AND Usage >= 1
)
SELECT TOP 20
    c.ContactID,
    c.CallDate,
    c.cust_id,
    c.BillAmountAtCall,
    h.MedianHistoricalBill,
    (c.BillAmountAtCall - h.MedianHistoricalBill) / h.MedianHistoricalBill * 100 AS PctIncreaseVsPersonalMedian
FROM CallerBillAtCall c
JOIN (SELECT DISTINCT cust_id, MedianHistoricalBill FROM CustomerHistoricalMedian) h ON h.cust_id = c.cust_id
ORDER BY PctIncreaseVsPersonalMedian DESC;


-- STEP 3: Step 2's top-20 sort showed a math artifact, not bad data -
-- small historical bills (e.g. $11-16) inflate any % increase. Raised
-- floor to $30 and switched to ONE summary number: median % increase
-- across ALL callers, instead of chasing extremes.

;WITH CallerBillAtCall AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        bm.cust_id,
        bm.NetCharge AS BillAmountAtCall
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Bill Explanation'
      AND bm.NetCharge > 0
      AND bm.Bill_Date = (
          SELECT MAX(bm2.Bill_Date)
          FROM iSigma_Bill_Master bm2
          WHERE bm2.cust_id = bm.cust_id AND bm2.Bill_Date <= cai.[Date]
      )
),
CustomerHistoricalMedian AS (
    SELECT DISTINCT
        cust_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NetCharge) OVER (PARTITION BY cust_id) AS MedianHistoricalBill
    FROM iSigma_Bill_Master
    WHERE NetCharge > 30
      AND Usage >= 1
)
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (c.BillAmountAtCall - h.MedianHistoricalBill) / h.MedianHistoricalBill * 100) 
        OVER () AS MedianPctIncrease_AllCallers
FROM CallerBillAtCall c
JOIN CustomerHistoricalMedian h ON h.cust_id = c.cust_id;


-- -- STEP 4a: Confirm actual column name for tenure on iSigma_Customer_Master
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Customer_Master'
  AND COLUMN_NAME LIKE '%tenure%'
   OR COLUMN_NAME LIKE '%enroll%'
   OR COLUMN_NAME LIKE '%start%date%';


-- STEP 4d: Correctly scoped search for tenure/enrollment start date on iSigma_Customer_Master
SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Customer_Master'
  AND (COLUMN_NAME LIKE '%tenure%'
    OR COLUMN_NAME LIKE '%enroll%'
    OR COLUMN_NAME LIKE '%start%'
    OR COLUMN_NAME LIKE '%co_start%');

-- STEP 4e: Calculate tenure using FlowStart, join to CallerCustomers
WITH CallerCustomers AS (
    SELECT DISTINCT
        ivr.AccountNumber AS cust_id,
        cai.[Date]
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Bill Explanation'
      AND bm.NetCharge > 0
      AND bm.Bill_Date = (
          SELECT MAX(bm2.Bill_Date)
          FROM iSigma_Bill_Master bm2
          WHERE bm2.cust_id = bm.cust_id AND bm2.Bill_Date <= cai.[Date]
      )
)
SELECT
    DATEDIFF(DAY, cm.FlowStart, cc.[Date]) AS TenureDays,
    COUNT(*) AS Customers,
    AVG(CAST(cm.CreditScore AS FLOAT)) AS AvgCreditScore
FROM CallerCustomers cc
JOIN iSigma_Customer_Master cm ON cm.cust_id = cc.cust_id
WHERE cm.FlowStart IS NOT NULL
GROUP BY DATEDIFF(DAY, cm.FlowStart, cc.[Date])
ORDER BY TenureDays;


-- STEP 4f: Bucket tenure into ranges for easier pattern reading
WITH CallerCustomers AS (
    SELECT DISTINCT
        ivr.AccountNumber AS cust_id,
        cai.[Date]
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Bill Explanation'
      AND bm.NetCharge > 0
      AND bm.Bill_Date = (
          SELECT MAX(bm2.Bill_Date)
          FROM iSigma_Bill_Master bm2
          WHERE bm2.cust_id = bm.cust_id AND bm2.Bill_Date <= cai.[Date]
      )
)
SELECT
    CASE
        WHEN DATEDIFF(DAY, cm.FlowStart, cc.[Date]) <= 30 THEN '0-30 days'
        WHEN DATEDIFF(DAY, cm.FlowStart, cc.[Date]) <= 90 THEN '31-90 days'
        WHEN DATEDIFF(DAY, cm.FlowStart, cc.[Date]) <= 365 THEN '91-365 days'
        ELSE '365+ days'
    END AS TenureBucket,
    COUNT(*) AS Customers,
    AVG(CAST(cm.CreditScore AS FLOAT)) AS AvgCreditScore
FROM CallerCustomers cc
JOIN iSigma_Customer_Master cm ON cm.cust_id = cc.cust_id
WHERE cm.FlowStart IS NOT NULL
GROUP BY
    CASE
        WHEN DATEDIFF(DAY, cm.FlowStart, cc.[Date]) <= 30 THEN '0-30 days'
        WHEN DATEDIFF(DAY, cm.FlowStart, cc.[Date]) <= 90 THEN '31-90 days'
        WHEN DATEDIFF(DAY, cm.FlowStart, cc.[Date]) <= 365 THEN '91-365 days'
        ELSE '365+ days'
    END
ORDER BY MIN(DATEDIFF(DAY, cm.FlowStart, cc.[Date]));


-- STEP 5-count (v3): CreditScore tightened to <= 500
WITH CustomerBillAtCall AS (
    SELECT
        bm.cust_id,
        bm.NetCharge AS BillAmountAtCall,
        (bm.NetCharge / NULLIF(bm.Usage, 0)) * 100 AS EffectiveRateCents,
        bm.Bill_Date
    FROM iSigma_Bill_Master bm
    WHERE bm.NetCharge > 0
      AND bm.Usage >= 1
),
CustomerHistoricalMedian AS (
    SELECT
        cust_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NetCharge) OVER (PARTITION BY cust_id) AS MedianHistoricalBill
    FROM iSigma_Bill_Master
    WHERE NetCharge > 0
      AND Usage >= 1
),
FlaggedCustomers AS (
    SELECT DISTINCT
        cba.cust_id
    FROM CustomerBillAtCall cba
    JOIN CustomerHistoricalMedian h ON h.cust_id = cba.cust_id
    JOIN iSigma_Customer_Master cm ON cm.cust_id = cba.cust_id
    WHERE cba.EffectiveRateCents >= 20
      AND cba.EffectiveRateCents <= 50
      AND ((cba.BillAmountAtCall - h.MedianHistoricalBill) / NULLIF(h.MedianHistoricalBill, 0)) * 100 >= 20
      AND cm.CreditScore <= 500
      AND cm.CreditScore > 0
      AND cm.FlowStart IS NOT NULL
)
SELECT COUNT(*) AS TotalFlaggedCustomers FROM FlaggedCustomers;


-- STEP 6: Spot-check a sample of flagged customers with their actual values
WITH CustomerBillAtCall AS (
    SELECT
        bm.cust_id,
        bm.NetCharge AS BillAmountAtCall,
        (bm.NetCharge / NULLIF(bm.Usage, 0)) * 100 AS EffectiveRateCents,
        bm.Bill_Date
    FROM iSigma_Bill_Master bm
    WHERE bm.NetCharge > 0
      AND bm.Usage >= 1
),
CustomerHistoricalMedian AS (
    SELECT
        cust_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY NetCharge) OVER (PARTITION BY cust_id) AS MedianHistoricalBill
    FROM iSigma_Bill_Master
    WHERE NetCharge > 0
      AND Usage >= 1
)
SELECT TOP 20
    cba.cust_id,
    cba.BillAmountAtCall,
    ROUND(cba.EffectiveRateCents, 2) AS EffectiveRateCents,
    ROUND(h.MedianHistoricalBill, 2) AS MedianHistoricalBill,
    ROUND(((cba.BillAmountAtCall - h.MedianHistoricalBill) / NULLIF(h.MedianHistoricalBill, 0)) * 100, 2) AS PctIncreaseVsMedian,
    DATEDIFF(DAY, cm.FlowStart, cba.Bill_Date) AS TenureDays,
    cm.CreditScore
FROM CustomerBillAtCall cba
JOIN CustomerHistoricalMedian h ON h.cust_id = cba.cust_id
JOIN iSigma_Customer_Master cm ON cm.cust_id = cba.cust_id
WHERE cba.EffectiveRateCents >= 20
  AND cba.EffectiveRateCents <= 50
  AND ((cba.BillAmountAtCall - h.MedianHistoricalBill) / NULLIF(h.MedianHistoricalBill, 0)) * 100 >= 20
  AND cm.CreditScore <= 500
  AND cm.CreditScore > 0
  AND cm.FlowStart IS NOT NULL
ORDER BY NEWID();

-- Check billing history for the outlier customer (cust_id as string)
SELECT
    cust_id,
    Bill_Date,
    NetCharge,
    Usage
FROM iSigma_Bill_Master
WHERE cust_id = '1502110268'
ORDER BY Bill_Date;

