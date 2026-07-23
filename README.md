o	
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

-- STEP 3 (comparison): Original vs. corrected past-due counts
SELECT
    CAST(pd.[Date] AS DATE) AS CallDay,
    COUNT(DISTINCT pd.CustID) AS PastDueCustomerCount_Original,
    COUNT(DISTINCT CASE 
        WHEN cm.cust_id IS NOT NULL 
             AND cm.Market = 'Texas'
             AND cm.CustomerType = 'Residential'
             AND cm.FlowStart <= pd.[Date]
             AND (cm.FlowEnd IS NULL OR cm.FlowEnd >= pd.[Date])
        THEN pd.CustID 
    END) AS PastDueCustomerCount_ActiveOnly
FROM JESouth_CollectionAR_DailyDue pd
LEFT JOIN iSigma_Customer_Master cm
    ON cm.cust_id = pd.CustID
WHERE pd.[Date] >= '2022-07-01'
    AND pd.[Date] < '2022-08-01'
    AND pd.AR > 0
GROUP BY CAST(pd.[Date] AS DATE)
ORDER BY CallDay;

-- STEP 5 (corrected): Texas vs. Alberta IVR split
SELECT
    CAST(CallDate AS DATE) AS CallDay,
    SUM(CASE 
        WHEN Queue IS NULL 
             OR (Queue NOT LIKE '%Alberta%' 
                 AND Queue NOT LIKE '%California%' 
                 AND Queue NOT LIKE '%NorthCanada%')
        THEN 1 ELSE 0 END) AS TexasCalls,
    SUM(CASE 
        WHEN Queue LIKE '%Alberta%' 
        THEN 1 ELSE 0 END) AS AlbertaCalls
FROM dbo.IVR
WHERE Department = 'Care'
    AND CallDate >= '2022-07-01'
GROUP BY CAST(CallDate AS DATE)
ORDER BY CallDay;


-- STEP 6 (corrected): Combined transfer count (regular + escalation)
SELECT
    CAST(CallDate AS DATE) AS CallDay,
    SUM(CASE WHEN TransferToQueue IS NOT NULL THEN 1 ELSE 0 END) AS RegularTransfers,
    SUM(CASE WHEN FinalQueue IS NOT NULL AND FinalQueue <> Queue THEN 1 ELSE 0 END) AS EscalationTransfers,
    SUM(CASE 
        WHEN TransferToQueue IS NOT NULL 
             OR (FinalQueue IS NOT NULL AND FinalQueue <> Queue)
        THEN 1 ELSE 0 END) AS TotalTransfers_Combined
FROM dbo.IVR
WHERE Department = 'Care'
    AND CallDate >= '2022-07-01'
GROUP BY CAST(CallDate AS DATE)
ORDER BY CallDay;


SELECT DISTINCT Queue FROM dbo.IVR WHERE Department = 'Care' AND CallDate >= '2022-07-01' ORDER BY Queue;

-- Debug: confirm Alberta volume exists and check date range
SELECT 
    Queue,
    COUNT(*) AS CallCount,
    MIN(CallDate) AS FirstCall,
    MAX(CallDate) AS LastCall
FROM dbo.IVR
WHERE Department = 'Care'
    AND Queue LIKE '%Alberta%'
GROUP BY Queue;

-- STEP 5 (corrected v2): Texas vs. Alberta IVR split with data-availability flag
SELECT
    CAST(CallDate AS DATE) AS CallDay,
    SUM(CASE 
        WHEN Queue IS NULL 
             OR (Queue NOT LIKE '%Alberta%' 
                 AND Queue NOT LIKE '%California%' 
                 AND Queue NOT LIKE '%NorthCanada%')
        THEN 1 ELSE 0 END) AS TexasCalls,
    SUM(CASE 
        WHEN Queue LIKE '%Alberta%' 
        THEN 1 ELSE 0 END) AS AlbertaCalls,
    CASE 
        WHEN CAST(CallDate AS DATE) < '2024-03-20' THEN 'Alberta data not yet available'
        ELSE 'Alberta data available'
    END AS AlbertaDataAvailability
FROM dbo.IVR
WHERE Department = 'Care'
    AND CallDate >= '2022-07-01'
GROUP BY CAST(CallDate AS DATE)
ORDER BY CallDay;


-- STEP 6: Language field reliability check
SELECT
    Language AS StatedLanguage,
    CASE 
        WHEN Queue LIKE '%SPA%' OR Queue LIKE '%Spanish%' THEN 'Spanish (by queue)'
        WHEN Queue LIKE '%ENG%' THEN 'English (by queue)'
        ELSE 'Unclear (by queue)'
    END AS QueueBasedLanguage,
    VerificationStatus,
    COUNT(*) AS CallCount
FROM dbo.IVR
WHERE Department = 'Care'
    AND CallDate >= '2022-07-01'
GROUP BY Language, 
    CASE 
        WHEN Queue LIKE '%SPA%' OR Queue LIKE '%Spanish%' THEN 'Spanish (by queue)'
        WHEN Queue LIKE '%ENG%' THEN 'English (by queue)'
        ELSE 'Unclear (by queue)'
    END,
    VerificationStatus
ORDER BY StatedLanguage, QueueBasedLanguage, VerificationStatus;


-- STEP 1: Texas residential filter applied to base population
SELECT
    cm.cust_id,
    cm.Market,
    cm.CustomerType,
    cm.FlowStart,
    cm.FlowEnd
FROM iSigma_Customer_Master cm
WHERE cm.Market = 'Texas'
    AND cm.CustomerType = 'Residential'
    AND cm.FlowStart IS NOT NULL
    AND (cm.FlowEnd IS NULL OR cm.FlowEnd >= GETDATE());


-- STEP 1 (count): Total active Texas-residential population
SELECT COUNT(*) AS TexasResidentialActiveCount
FROM iSigma_Customer_Master cm
WHERE cm.Market = 'Texas'
    AND cm.CustomerType = 'Residential'
    AND cm.FlowStart IS NOT NULL
    AND (cm.FlowEnd IS NULL OR cm.FlowEnd >= GETDATE());


-- STEP 2a: Confirm call-reason/classification column name
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Care_CallAI'
    AND (COLUMN_NAME LIKE '%Reason%' OR COLUMN_NAME LIKE '%Classif%' OR COLUMN_NAME LIKE '%Category%');


-- STEP 2b: Confirm exact value strings for Bill Explanation / Bill Dispute
SELECT DISTINCT [call.reason], COUNT(*) AS Cnt
FROM Care_CallAI
WHERE [call.reason] LIKE '%Bill%'
GROUP BY [call.reason]
ORDER BY Cnt DESC;


-- STEP 2c: Confirm all column names on Care_CallAI
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Care_CallAI'
ORDER BY ORDINAL_POSITION;


-- STEP 2 (corrected v2): Bill Explanation + Bill Dispute combined
SELECT
    cai.ContactID,
    cai.[Date],
    cai.transcript_analysis_id,
    [call.reason] AS CallReason
FROM Care_CallAI cai
WHERE [call.reason] IN ('Bill Explanation', 'Bill Dispute');


-- Check if any table links ContactID (GUID) to cust_id
SELECT TABLE_NAME, COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE COLUMN_NAME IN ('ContactID', 'cust_id')
ORDER BY TABLE_NAME;

-- Check full columns on both candidate bridge tables
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('vw_Salesforce_Contact', 'vw_SFPortalCallIn')
ORDER BY TABLE_NAME, ORDINAL_POSITION;


-- STEP 2 (final): Bill Explanation + Bill Dispute, bridged to cust_id
SELECT
    sfc.CustID,
    cai.ContactID,
    cai.[Date],
    cai.transcript_analysis_id,
    [call.reason] AS CallReason
FROM Care_CallAI cai
JOIN vw_Salesforce_Contact sfc
    ON cai.ContactID = sfc.ContactID
WHERE [call.reason] IN ('Bill Explanation', 'Bill Dispute');


-- Diagnostic: do ContactID formats actually match between the two tables?
SELECT TOP 5 ContactID FROM Care_CallAI WHERE ContactID IS NOT NULL;

SELECT TOP 5 ContactID FROM vw_Salesforce_Contact WHERE ContactID IS NOT NULL;


-- Check if vw_Care_CustomerContact bridges the GUID ContactID to cust_id
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Care_CustomerContact'
ORDER BY ORDINAL_POSITION;


-- Sanity check: CustID coverage on vw_Care_CustomerContact
SELECT 
    COUNT(*) AS TotalRows,
    COUNT(CustID) AS RowsWithCustID,
    COUNT(DISTINCT CustID) AS DistinctCustIDs
FROM vw_Care_CustomerContact;


-- STEP 2 (rebuilt): Bill Explanation + Bill Dispute, using vw_Care_CustomerContact directly
SELECT
    vcc.CustID,
    vcc.ContactID,
    vcc.CallDate,
    vcc.Market,
    vcc.CustomerTenure,
    vcc.CustomerTenureOrder,
    vcc.AI_CallReason
FROM vw_Care_CustomerContact vcc
WHERE vcc.AI_CallReason IN ('Bill Explanation', 'Bill Dispute');


-- STEP 2 (final v2): Bill Explanation + Bill Dispute, Texas-residential only
SELECT
    vcc.CustID,
    vcc.ContactID,
    vcc.CallDate,
    vcc.Market,
    vcc.CustomerTenure,
    vcc.CustomerTenureOrder,
    vcc.AI_CallReason
FROM vw_Care_CustomerContact vcc
WHERE vcc.AI_CallReason IN ('Bill Explanation', 'Bill Dispute')
    AND vcc.Market = 'Texas'
    AND vcc.CustID IS NOT NULL;

SELECT COUNT(*) AS BillCallCount_TexasResidential
FROM vw_Care_CustomerContact vcc
WHERE vcc.AI_CallReason IN ('Bill Explanation', 'Bill Dispute')
    AND vcc.Market = 'Texas'
    AND vcc.CustID IS NOT NULL;

-- Check for a more granular tenure-in-days/months field
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_Care_CustomerContact'
    AND (COLUMN_NAME LIKE '%Tenure%' OR COLUMN_NAME LIKE '%FlowStart%' OR COLUMN_NAME LIKE '%Enroll%');


-- STEP 4: Tenure bucketed as Jonathan wants — <=14 months vs. >14 months
SELECT
    vcc.CustID,
    vcc.ContactID,
    vcc.CallDate,
    vcc.FlowStart,
    DATEDIFF(MONTH, vcc.FlowStart, vcc.CallDate) AS TenureMonths,
    CASE 
        WHEN DATEDIFF(MONTH, vcc.FlowStart, vcc.CallDate) <= 14 THEN '<=14 Months'
        ELSE '>14 Months'
    END AS TenureBucket,
    vcc.AI_CallReason
FROM vw_Care_CustomerContact vcc
WHERE vcc.AI_CallReason IN ('Bill Explanation', 'Bill Dispute')
    AND vcc.Market = 'Texas'
    AND vcc.CustID IS NOT NULL
    AND vcc.FlowStart IS NOT NULL;


-- Check FlowStart coverage within the 27,117 population
SELECT 
    COUNT(*) AS TotalInPopulation,
    COUNT(FlowStart) AS RowsWithFlowStart
FROM vw_Care_CustomerContact vcc
WHERE vcc.AI_CallReason IN ('Bill Explanation', 'Bill Dispute')
    AND vcc.Market = 'Texas'
    AND vcc.CustID IS NOT NULL;


-- Check columns on both collections tables
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('Collections_DebtSale', 'Collections_DebtSaleBuyBack')
ORDER BY TABLE_NAME, ORDINAL_POSITION;


-- STEP 5: Historical payment-behavior signal (eventual-payer vs. write-off)
SELECT
    ds.cust_id,
    ds.WriteOffAmount,
    ds.WriteOffDate,
    ds.SaleDate,
    CASE 
        WHEN bb.cust_id IS NOT NULL THEN 'Eventual Payer'
        ELSE 'Write-Off'
    END AS PaymentBehaviorSignal
FROM Collections_DebtSale ds
LEFT JOIN Collections_DebtSaleBuyBack bb
    ON ds.cust_id = bb.cust_id;

-- Check what reasons drive buybacks — confirm they're payment-related
SELECT DISTINCT Reason, COUNT(*) AS Cnt
FROM Collections_DebtSaleBuyBack
GROUP BY Reason
ORDER BY Cnt DESC;


-- Quick tally: how many total customers land in each bucket?
SELECT PaymentBehaviorSignal, COUNT(*) AS Cnt
FROM (
    SELECT ds.cust_id,
        CASE WHEN bb.cust_id IS NOT NULL THEN 'Eventual Payer' ELSE 'Write-Off' END AS PaymentBehaviorSignal
    FROM Collections_DebtSale ds
    LEFT JOIN Collections_DebtSaleBuyBack bb ON ds.cust_id = bb.cust_id
) t
GROUP BY PaymentBehaviorSignal;


-- STEP 5 (flagged finding, not a resolved signal):
-- Collections_DebtSaleBuyBack reasons (Fraud, Deceased, Bankruptcy, Escalation, 
-- Sold in error, Invalid Enrollment, Waiving ETF) do NOT indicate the customer 
-- eventually paid -- they reflect operational/legal reversals of the debt sale.
-- This table cannot answer Jonathan's "eventual-payer vs write-off" question as-is.
-- Open item for final deliverable: is there a different source (e.g. payment 
-- applied post-write-off) that captures true eventual payment?

