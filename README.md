	
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
        WHEN DaysOnAutopayBeforeCall <= 90 THEN 'Recent enrollee (31-90 days)'
        ELSE 'Long-time autopay customer (90+ days)'
    END
ORDER BY Calls DESC;


-- STEP 18: Investigate the "No prior Add event" group
WITH RemovalWithRealTenure AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        ba.CustID,
        ba.ID AS SalesforceAccountID,
        add_evt.LastAddDate
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
SELECT TOP 20
    ContactID,
    CallDate,
    CustID,
    SalesforceAccountID
FROM RemovalWithRealTenure
WHERE LastAddDate IS NULL
ORDER BY CallDate DESC;


-- STEP 19: Check if these accounts have ANY autopay events, and how old they are
WITH RemovalWithRealTenure AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        ba.CustID,
        ba.ID AS SalesforceAccountID,
        add_evt.LastAddDate
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
SELECT TOP 20
    r.ContactID,
    r.CallDate,
    r.CustID,
    r.SalesforceAccountID,
    cm.FlowStart,
    DATEDIFF(DAY, cm.FlowStart, r.CallDate) AS DaysSinceEnrollment,
    (SELECT COUNT(*) FROM vw_Salesforce_Autopay sa WHERE sa.AccountID = r.SalesforceAccountID) AS TotalAutopayEventsOnRecord
FROM RemovalWithRealTenure r
JOIN iSigma_Customer_Master cm ON cm.cust_id = r.CustID
WHERE r.LastAddDate IS NULL
ORDER BY r.CallDate DESC;


-- STEP 20: Rebucket tenure, falling back to FlowStart when no Add event exists
-- (autopay set at enrollment isn't logged as a separate Salesforce event)
WITH RemovalWithRealTenure AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        ba.CustID,
        add_evt.LastAddDate,
        cm.FlowStart,
        COALESCE(add_evt.LastAddDate, cm.FlowStart) AS EffectiveAutopayStart
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN vw_Salesforce_BillingAccount ba ON ba.CustID = ivr.AccountNumber
    JOIN iSigma_Customer_Master cm ON cm.cust_id = ba.CustID
    CROSS APPLY (
        SELECT MAX(sa.Created) AS LastAddDate
        FROM vw_Salesforce_Autopay sa
        WHERE sa.AccountID = ba.ID
          AND sa.Action = 'Add'
          AND sa.Created <= cai.[Date]
    ) add_evt
    WHERE cai.[call.reason] = 'Remove Autopay'
      AND cm.FlowStart IS NOT NULL
),
Bucketed AS (
    SELECT
        *,
        DATEDIFF(DAY, EffectiveAutopayStart, CallDate) AS DaysOnAutopayBeforeCall,
        CASE WHEN LastAddDate IS NULL THEN 1 ELSE 0 END AS UsedFallback
    FROM RemovalWithRealTenure
)
SELECT
    CASE
        WHEN DaysOnAutopayBeforeCall <= 30 THEN 'New enrollee (0-30 days)'
        WHEN DaysOnAutopayBeforeCall <= 90 THEN 'Recent enrollee (31-90 days)'
        ELSE 'Long-time autopay customer (90+ days)'
    END AS Category,
    COUNT(*) AS Calls,
    CAST(COUNT(*) AS FLOAT) / SUM(COUNT(*)) OVER () AS PctOfCalls,
    SUM(UsedFallback) AS CallsUsingFlowStartFallback
FROM Bucketed
GROUP BY
    CASE
        WHEN DaysOnAutopayBeforeCall <= 30 THEN 'New enrollee (0-30 days)'
        WHEN DaysOnAutopayBeforeCall <= 90 THEN 'Recent enrollee (31-90 days)'
        ELSE 'Long-time autopay customer (90+ days)'
    END
ORDER BY Calls DESC;


-- STEP 21: Find candidate "due date" columns for the days-until-next-due-date test
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE (COLUMN_NAME LIKE '%DueDate%' OR COLUMN_NAME LIKE '%Due_Date%')
  AND TABLE_NAME IN ('iSigma_Bill_Master', 'JESouth_CollectionAR_DailyDue');


-- STEP 22: For each Remove Autopay call, find the days until the NEXT due date
WITH RemovalCalls AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        bm.cust_id
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Remove Autopay'
    GROUP BY cai.ContactID, cai.[Date], bm.cust_id
)
SELECT TOP 20
    rc.ContactID,
    rc.CallDate,
    rc.cust_id,
    next_due.NextDueDate,
    DATEDIFF(DAY, rc.CallDate, next_due.NextDueDate) AS DaysUntilNextDueDate
FROM RemovalCalls rc
CROSS APPLY (
    SELECT MIN(bm2.Due_Date) AS NextDueDate
    FROM iSigma_Bill_Master bm2
    WHERE bm2.cust_id = rc.cust_id
      AND bm2.Due_Date >= rc.CallDate
) next_due
ORDER BY rc.CallDate DESC;

-- STEP 23: Full distribution of days-until-next-due-date across all Remove Autopay calls
WITH RemovalCalls AS (
    SELECT
        cai.ContactID,
        cai.[Date] AS CallDate,
        bm.cust_id
    FROM Care_CallAI cai
    JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
    JOIN iSigma_Bill_Master bm ON bm.cust_id = ivr.AccountNumber
    WHERE cai.[call.reason] = 'Remove Autopay'
    GROUP BY cai.ContactID, cai.[Date], bm.cust_id
),
WithDueDate AS (
    SELECT
        rc.ContactID,
        DATEDIFF(DAY, rc.CallDate, next_due.NextDueDate) AS DaysUntilNextDueDate
    FROM RemovalCalls rc
    CROSS APPLY (
        SELECT MIN(bm2.Due_Date) AS NextDueDate
        FROM iSigma_Bill_Master bm2
        WHERE bm2.cust_id = rc.cust_id
          AND bm2.Due_Date >= rc.CallDate
    ) next_due
)
SELECT
    CASE
        WHEN DaysUntilNextDueDate IS NULL THEN 'No upcoming due date found'
        WHEN DaysUntilNextDueDate <= 3 THEN '0-3 days before due'
        WHEN DaysUntilNextDueDate <= 7 THEN '4-7 days before due'
        WHEN DaysUntilNextDueDate <= 14 THEN '8-14 days before due'
        ELSE '15+ days before due'
    END AS Bucket,
    COUNT(*) AS Calls,
    CAST(COUNT(*) AS FLOAT) / SUM(COUNT(*)) OVER () AS PctOfCalls
FROM WithDueDate
GROUP BY
    CASE
        WHEN DaysUntilNextDueDate IS NULL THEN 'No upcoming due date found'
        WHEN DaysUntilNextDueDate <= 3 THEN '0-3 days before due'
        WHEN DaysUntilNextDueDate <= 7 THEN '4-7 days before due'
        WHEN DaysUntilNextDueDate <= 14 THEN '8-14 days before due'
        ELSE '15+ days before due'
    END
ORDER BY Calls DESC;

-- STEP 24: Confirm exact deposit-paid column name on iSigma_Customer_Master
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Customer_Master'
  AND (COLUMN_NAME LIKE '%Deposit%' OR COLUMN_NAME LIKE '%Waiver%');


-- STEP 25: Check for concentration of Remove actions by specific agents (potential gaming signal)
SELECT TOP 20
    CreatedBy,
    COUNT(*) AS RemovalsProcessed
FROM vw_Salesforce_Autopay
WHERE Action = 'Remove'
GROUP BY CreatedBy
ORDER BY RemovalsProcessed DESC;

-- STEP 26: Confirm the suspected system account by checking its Add-side volume too
SELECT Action, COUNT(*) AS EventCount
FROM vw_Salesforce_Autopay
WHERE CreatedBy = '0054T000001dhK1QAI'
GROUP BY Action;


-- STEP 27: Test the deposit-waiver loophole (credit score 600-699, waived deposit, later removed autopay)
SELECT
    cm.CreditScore,
    cm.DepositPaid,
    cm.DepositRequired,
    cm.Waiver,
    COUNT(DISTINCT cai.ContactID) AS RemovalCalls
FROM Care_CallAI cai
JOIN dbo.IVR ivr ON ivr.ContactID = cai.ContactID
JOIN iSigma_Customer_Master cm ON cm.cust_id = ivr.AccountNumber
WHERE cai.[call.reason] = 'Remove Autopay'
  AND cm.CreditScore BETWEEN 600 AND 699
  AND cm.DepositPaid = 0
GROUP BY cm.CreditScore, cm.DepositPaid, cm.DepositRequired, cm.Waiver
ORDER BY RemovalCalls DESC;


-- STEP 28: Confirm what Waiver actually contains, and check its relationship to DepositRequired/DepositPaid
SELECT DISTINCT Waiver, DepositRequired, DepositPaid, COUNT(*) AS CustomerCount
FROM iSigma_Customer_Master
WHERE CreditScore BETWEEN 600 AND 699
GROUP BY Waiver, DepositRequired, DepositPaid
ORDER BY CustomerCount DESC;


-- STEP 29: Test the real deposit-waiver loophole using Waiver = 'Autopay'
SELECT
    cm.CreditScore,
    COUNT(DISTINCT cm.cust_id) AS CustomersOnAutopayWaiver,
    COUNT(DISTINCT cai.ContactID) AS RemovalCalls,
    CAST(COUNT(DISTINCT cai.ContactID) AS FLOAT) / COUNT(DISTINCT cm.cust_id) AS PctWhoRemoved
FROM iSigma_Customer_Master cm
LEFT JOIN dbo.IVR ivr ON ivr.AccountNumber = cm.cust_id
LEFT JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID AND cai.[call.reason] = 'Remove Autopay'
WHERE cm.Waiver = 'Autopay'
  AND cm.CreditScore BETWEEN 600 AND 699
GROUP BY cm.CreditScore
ORDER BY cm.CreditScore;


-- Confirm exact SalesChannel value for telesales, in a fresh query window
SELECT DISTINCT SalesChannel
FROM iSigma_Customer_Master
WHERE SalesChannel LIKE '%tele%';

-- Test the telesales clawback theory: removal within 60 days of enrollment, by channel
SELECT
    cm.SalesChannel,
    COUNT(DISTINCT cm.cust_id) AS TotalEnrolled,
    COUNT(DISTINCT cai.ContactID) AS RemovedWithin60Days,
    CAST(COUNT(DISTINCT cai.ContactID) AS FLOAT) / COUNT(DISTINCT cm.cust_id) AS PctRemovedWithin60Days
FROM iSigma_Customer_Master cm
LEFT JOIN dbo.IVR ivr ON ivr.AccountNumber = cm.cust_id
LEFT JOIN Care_CallAI cai
    ON cai.ContactID = ivr.ContactID
    AND cai.[call.reason] = 'Remove Autopay'
    AND DATEDIFF(DAY, cm.FlowStart, cai.[Date]) BETWEEN 0 AND 60
WHERE cm.SalesChannel IN ('Inbound Telesales', 'Telemarketing', 'TELESALES')
  AND cm.FlowStart IS NOT NULL
GROUP BY cm.SalesChannel
ORDER BY PctRemovedWithin60Days DESC;

-- Sanity check: any Remove Autopay calls at all from these channels, regardless of timing
SELECT
    cm.SalesChannel,
    COUNT(DISTINCT cm.cust_id) AS TotalEnrolled,
    COUNT(DISTINCT cai.ContactID) AS AnyRemovalCallEver
FROM iSigma_Customer_Master cm
LEFT JOIN dbo.IVR ivr ON ivr.AccountNumber = cm.cust_id
LEFT JOIN Care_CallAI cai
    ON cai.ContactID = ivr.ContactID
    AND cai.[call.reason] = 'Remove Autopay'
WHERE cm.SalesChannel IN ('Inbound Telesales', 'Telemarketing', 'TELESALES')
GROUP BY cm.SalesChannel;

-- Check for concentration of Remove actions by real (non-system) agents
SELECT TOP 20
    CreatedBy,
    COUNT(*) AS RemovalsProcessed
FROM vw_Salesforce_Autopay
WHERE Action = 'Remove'
  AND CreatedBy <> '0054T000001dhK1QAI'
GROUP BY CreatedBy
ORDER BY RemovalsProcessed DESC;

task 4 follow up

-- Confirm verification-status column name on dbo.IVR
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'IVR'
  AND (COLUMN_NAME LIKE '%Verif%' OR COLUMN_NAME LIKE '%Queue%');

-- Confirm actual values in VerificationStatus
SELECT DISTINCT VerificationStatus, COUNT(*) AS Cnt
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallDate >= '2022-07-01'
GROUP BY VerificationStatus
ORDER BY Cnt DESC;

SELECT DISTINCT VerificationStatus, COUNT(*) AS Cnt
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallDate >= '2022-07-01'
GROUP BY VerificationStatus
ORDER BY Cnt DESC;

-- STEP 4 (corrected): IVR containment rate using Jonathan's real definition
SELECT
    CAST(CallDate AS DATE) AS CallDay,
    COUNT(*) AS Calls,
    SUM(CASE WHEN VerificationStatus = 'Verified' AND (Queue IS NULL OR QueueTime = 0) THEN 1 ELSE 0 END) AS ContainedCalls,
    SUM(CASE WHEN QueueTime > 0 THEN 1 ELSE 0 END) AS UncontainedCalls,
    SUM(CASE WHEN VerificationStatus = 'Verified' OR QueueTime > 0 THEN 1 ELSE 0 END) AS ContainmentDenominator,
    1.0 - (
        CAST(SUM(CASE WHEN QueueTime > 0 THEN 1 ELSE 0 END) AS FLOAT)
        / NULLIF(SUM(CASE WHEN VerificationStatus = 'Verified' OR QueueTime > 0 THEN 1 ELSE 0 END), 0)
    ) AS IVRContainmentRate_Corrected
FROM dbo.IVR
WHERE Department = 'Care'
  AND CallType IN ('Inbound','Transfer')
  AND CallDate >= '2022-07-01'
GROUP BY CAST(CallDate AS DATE)
ORDER BY CallDay;


-- STEP 3 (corrected): Past-due customer count, active customers only
SELECT
    CAST(pd.[Date] AS DATE) AS CallDay,
    COUNT(DISTINCT pd.CustID) AS PastDueCustomerCount_ActiveOnly
FROM JESouth_CollectionAR_DailyDue pd
JOIN iSigma_Customer_Master cm
    ON cm.cust_id = pd.CustID
    AND cm.Market = 'Texas'
    AND cm.CustomerType = 'Residential'
    AND cm.FlowStart <= pd.[Date]
    AND (cm.FlowEnd IS NULL OR cm.FlowEnd >= pd.[Date])
WHERE pd.[Date] >= '2022-07-01'
    AND pd.AR > 0
GROUP BY CAST(pd.[Date] AS DATE)
ORDER BY CallDay;
