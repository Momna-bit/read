	
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


-- STEP 1: Confirm actual columns on iSigma_Bill_Master before building Task 7
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Bill_Master'
ORDER BY ORDINAL_POSITION;


-- ============================================================================
-- TASK 7: PROACTIVE USAGE & BILL SHOCK ALERT MODEL
-- STEP 2 (with baseline confidence flag)
-- ============================================================================

WITH Callers AS (
    SELECT DISTINCT ivr.AccountNumber AS cust_id
    FROM dbo.IVR ivr
    JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID
    WHERE ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND cai.[call.reason] IN ('Bill Explanation', 'Bill Dispute')
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
        AND ivr.AccountNumber IS NOT NULL
),

RankedBills AS (
    SELECT bm.*,
        ROW_NUMBER() OVER (PARTITION BY bm.cust_id ORDER BY bm.Bill_Date DESC) AS rn
    FROM iSigma_Bill_Master bm
    JOIN Callers c ON c.cust_id = bm.cust_id
),

MostRecentBill AS (
    SELECT * FROM RankedBills WHERE rn = 1
),

PersonalBaseline AS (
    SELECT
        cust_id,
        AVG(NetCharge) AS BaselineNetCharge,
        AVG(Usage) AS BaselineUsage,
        COUNT(*) AS BaselineBillCount
    FROM RankedBills
    WHERE rn BETWEEN 2 AND 13
    GROUP BY cust_id
),

CustomerAttributes AS (
    SELECT
        cust_id,
        CreditScore,
        FlowStart,
        DATEDIFF(DAY, FlowStart, CAST(GETDATE() AS DATE)) AS TenureDays
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND CreditScore <> 0
)

SELECT
    mrb.cust_id,
    mrb.Bill_Date,
    mrb.NetCharge AS MostRecentNetCharge,
    pb.BaselineNetCharge,
    pb.BaselineBillCount,
    CASE 
        WHEN pb.BaselineBillCount >= 9 THEN 'High confidence'
        WHEN pb.BaselineBillCount >= 4 THEN 'Medium confidence'
        ELSE 'Low confidence (short tenure)'
    END AS BaselineConfidence,
    ROUND(mrb.NetCharge - pb.BaselineNetCharge, 2) AS DollarIncrease,
    ROUND((mrb.NetCharge - pb.BaselineNetCharge) / NULLIF(pb.BaselineNetCharge, 0) * 100, 2) AS PercentIncrease,
    mrb.Usage AS MostRecentUsage,
    pb.BaselineUsage,
    mrb.ServicePeriod AS ServicePeriodDays,
    ROUND((mrb.Usage - pb.BaselineUsage) / NULLIF(mrb.ServicePeriod, 0), 3) AS UsageIncreasePerDay,
    ca.CreditScore,
    ca.TenureDays
FROM MostRecentBill mrb
JOIN PersonalBaseline pb ON pb.cust_id = mrb.cust_id
JOIN CustomerAttributes ca ON ca.cust_id = mrb.cust_id
ORDER BY DollarIncrease DESC;


-- ============================================================================
-- TASK 7 STEP 3: Distribution summary by baseline confidence tier
-- Characterizes "typical" bill shock rather than just the extreme top rows
-- ============================================================================

WITH Callers AS (
    SELECT DISTINCT ivr.AccountNumber AS cust_id
    FROM dbo.IVR ivr
    JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID
    WHERE ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND cai.[call.reason] IN ('Bill Explanation', 'Bill Dispute')
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
        AND ivr.AccountNumber IS NOT NULL
),

RankedBills AS (
    SELECT bm.*,
        ROW_NUMBER() OVER (PARTITION BY bm.cust_id ORDER BY bm.Bill_Date DESC) AS rn
    FROM iSigma_Bill_Master bm
    JOIN Callers c ON c.cust_id = bm.cust_id
),

MostRecentBill AS (
    SELECT * FROM RankedBills WHERE rn = 1
),

PersonalBaseline AS (
    SELECT
        cust_id,
        AVG(NetCharge) AS BaselineNetCharge,
        AVG(Usage) AS BaselineUsage,
        COUNT(*) AS BaselineBillCount
    FROM RankedBills
    WHERE rn BETWEEN 2 AND 13
    GROUP BY cust_id
),

Metrics AS (
    SELECT
        mrb.cust_id,
        pb.BaselineBillCount,
        CASE 
            WHEN pb.BaselineBillCount >= 9 THEN 'High confidence'
            WHEN pb.BaselineBillCount >= 4 THEN 'Medium confidence'
            ELSE 'Low confidence (short tenure)'
        END AS BaselineConfidence,
        mrb.NetCharge - pb.BaselineNetCharge AS DollarIncrease,
        (mrb.NetCharge - pb.BaselineNetCharge) / NULLIF(pb.BaselineNetCharge, 0) * 100 AS PercentIncrease
    FROM MostRecentBill mrb
    JOIN PersonalBaseline pb ON pb.cust_id = mrb.cust_id
)

-- STEP 3 FINAL OUTPUT: distribution stats per confidence tier
SELECT
    BaselineConfidence,
    COUNT(*) AS CustomerCount,
    ROUND(AVG(DollarIncrease), 2) AS AvgDollarIncrease,
    ROUND(AVG(PercentIncrease), 2) AS AvgPercentIncrease,
    ROUND(
        (SELECT TOP 1 DollarIncrease FROM Metrics m2 
         WHERE m2.BaselineConfidence = m1.BaselineConfidence
         ORDER BY DollarIncrease OFFSET (COUNT(*) OVER (PARTITION BY m1.BaselineConfidence) / 2) ROWS FETCH NEXT 1 ROWS ONLY)
    , 2) AS ApproxMedianDollarIncrease,
    ROUND(MIN(PercentIncrease), 2) AS MinPercentIncrease,
    ROUND(MAX(PercentIncrease), 2) AS MaxPercentIncrease
FROM Metrics m1
GROUP BY BaselineConfidence
ORDER BY BaselineConfidence;



-- ============================================================================
-- TASK 7 STEP 3 (fixed): Distribution summary by baseline confidence tier
-- ============================================================================

WITH Callers AS (
    SELECT DISTINCT ivr.AccountNumber AS cust_id
    FROM dbo.IVR ivr
    JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID
    WHERE ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND cai.[call.reason] IN ('Bill Explanation', 'Bill Dispute')
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
        AND ivr.AccountNumber IS NOT NULL
),

RankedBills AS (
    SELECT bm.*,
        ROW_NUMBER() OVER (PARTITION BY bm.cust_id ORDER BY bm.Bill_Date DESC) AS rn
    FROM iSigma_Bill_Master bm
    JOIN Callers c ON c.cust_id = bm.cust_id
),

MostRecentBill AS (
    SELECT * FROM RankedBills WHERE rn = 1
),

PersonalBaseline AS (
    SELECT
        cust_id,
        AVG(NetCharge) AS BaselineNetCharge,
        AVG(Usage) AS BaselineUsage,
        COUNT(*) AS BaselineBillCount
    FROM RankedBills
    WHERE rn BETWEEN 2 AND 13
    GROUP BY cust_id
),

Metrics AS (
    SELECT
        mrb.cust_id,
        CASE 
            WHEN pb.BaselineBillCount >= 9 THEN 'High confidence'
            WHEN pb.BaselineBillCount >= 4 THEN 'Medium confidence'
            ELSE 'Low confidence (short tenure)'
        END AS BaselineConfidence,
        mrb.NetCharge - pb.BaselineNetCharge AS DollarIncrease,
        (mrb.NetCharge - pb.BaselineNetCharge) / NULLIF(pb.BaselineNetCharge, 0) * 100 AS PercentIncrease
    FROM MostRecentBill mrb
    JOIN PersonalBaseline pb ON pb.cust_id = mrb.cust_id
),

RankedMetrics AS (
    -- Rank each row within its confidence tier so we can pick the middle one (median)
    SELECT
        BaselineConfidence,
        DollarIncrease,
        ROW_NUMBER() OVER (PARTITION BY BaselineConfidence ORDER BY DollarIncrease) AS rn,
        COUNT(*) OVER (PARTITION BY BaselineConfidence) AS cnt
    FROM Metrics
),

MedianByTier AS (
    SELECT BaselineConfidence, DollarIncrease AS ApproxMedianDollarIncrease
    FROM RankedMetrics
    WHERE rn = (cnt + 1) / 2
)

-- STEP 3 FINAL OUTPUT
SELECT
    m.BaselineConfidence,
    COUNT(*) AS CustomerCount,
    ROUND(AVG(m.DollarIncrease), 2) AS AvgDollarIncrease,
    ROUND(AVG(m.PercentIncrease), 2) AS AvgPercentIncrease,
    ROUND(MAX(mb.ApproxMedianDollarIncrease), 2) AS ApproxMedianDollarIncrease,
    ROUND(MIN(m.PercentIncrease), 2) AS MinPercentIncrease,
    ROUND(MAX(m.PercentIncrease), 2) AS MaxPercentIncrease
FROM Metrics m
JOIN MedianByTier mb ON mb.BaselineConfidence = m.BaselineConfidence
GROUP BY m.BaselineConfidence
ORDER BY m.BaselineConfidence;



-- ============================================================================
-- TASK 7 STEP 4 (corrected): Caller vs. Non-Caller Comparison
-- Adds median percent increase + outlier-capped average, so extreme cases
-- don't distort the comparison the way they did last time
-- ============================================================================

WITH Callers AS (
    SELECT DISTINCT ivr.AccountNumber AS cust_id
    FROM dbo.IVR ivr
    JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID
    WHERE ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND cai.[call.reason] IN ('Bill Explanation', 'Bill Dispute')
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
        AND ivr.AccountNumber IS NOT NULL
),

ActiveResidential AS (
    SELECT cust_id, CreditScore, FlowStart,
        DATEDIFF(DAY, FlowStart, CAST(GETDATE() AS DATE)) AS TenureDays
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND CreditScore <> 0
        AND FlowEnd IS NULL
),

RankedBills AS (
    SELECT bm.*,
        ROW_NUMBER() OVER (PARTITION BY bm.cust_id ORDER BY bm.Bill_Date DESC) AS rn
    FROM iSigma_Bill_Master bm
    JOIN ActiveResidential ar ON ar.cust_id = bm.cust_id
),

MostRecentBill AS (
    SELECT * FROM RankedBills WHERE rn = 1
),

PersonalBaseline AS (
    SELECT
        cust_id,
        AVG(NetCharge) AS BaselineNetCharge,
        AVG(Usage) AS BaselineUsage,
        COUNT(*) AS BaselineBillCount
    FROM RankedBills
    WHERE rn BETWEEN 2 AND 13
    GROUP BY cust_id
),

Metrics AS (
    SELECT
        mrb.cust_id,
        CASE WHEN c.cust_id IS NOT NULL THEN 'Caller' ELSE 'Non-Caller' END AS CallerFlag,
        ar.CreditScore,
        ar.TenureDays,
        mrb.NetCharge - pb.BaselineNetCharge AS DollarIncrease,
        (mrb.NetCharge - pb.BaselineNetCharge) / NULLIF(pb.BaselineNetCharge, 0) * 100 AS PercentIncrease,
        (mrb.Usage - pb.BaselineUsage) / NULLIF(mrb.ServicePeriod, 0) AS UsageIncreasePerDay
    FROM MostRecentBill mrb
    JOIN PersonalBaseline pb ON pb.cust_id = mrb.cust_id
    JOIN ActiveResidential ar ON ar.cust_id = mrb.cust_id
    LEFT JOIN Callers c ON c.cust_id = mrb.cust_id
    WHERE pb.BaselineBillCount >= 9
),

RankedDollar AS (
    SELECT CallerFlag, DollarIncrease,
        ROW_NUMBER() OVER (PARTITION BY CallerFlag ORDER BY DollarIncrease) AS rn,
        COUNT(*) OVER (PARTITION BY CallerFlag) AS cnt
    FROM Metrics
),
MedianDollarByGroup AS (
    SELECT CallerFlag, DollarIncrease AS MedianDollarIncrease
    FROM RankedDollar WHERE rn = (cnt + 1) / 2
),

RankedPercent AS (
    SELECT CallerFlag, PercentIncrease,
        ROW_NUMBER() OVER (PARTITION BY CallerFlag ORDER BY PercentIncrease) AS rn,
        COUNT(*) OVER (PARTITION BY CallerFlag) AS cnt
    FROM Metrics
),
MedianPercentByGroup AS (
    SELECT CallerFlag, PercentIncrease AS MedianPercentIncrease
    FROM RankedPercent WHERE rn = (cnt + 1) / 2
)

-- STEP 4 FINAL OUTPUT: side-by-side comparison, outlier-resistant
SELECT
    m.CallerFlag,
    COUNT(*) AS CustomerCount,
    ROUND(AVG(m.DollarIncrease), 2) AS AvgDollarIncrease,
    ROUND(MAX(md.MedianDollarIncrease), 2) AS MedianDollarIncrease,
    ROUND(AVG(CASE WHEN m.PercentIncrease > 300 THEN 300 ELSE m.PercentIncrease END), 2) AS AvgPercentIncrease_Capped300,
    ROUND(MAX(mp.MedianPercentIncrease), 2) AS MedianPercentIncrease,
    SUM(CASE WHEN m.PercentIncrease > 300 THEN 1 ELSE 0 END) AS OutlierCount_Over300Pct,
    ROUND(AVG(m.UsageIncreasePerDay), 3) AS AvgUsageIncreasePerDay,
    ROUND(AVG(CAST(m.CreditScore AS FLOAT)), 0) AS AvgCreditScore,
    ROUND(AVG(CAST(m.TenureDays AS FLOAT)), 0) AS AvgTenureDays
FROM Metrics m
JOIN MedianDollarByGroup md ON md.CallerFlag = m.CallerFlag
JOIN MedianPercentByGroup mp ON mp.CallerFlag = m.CallerFlag
GROUP BY m.CallerFlag
ORDER BY m.CallerFlag;


-- ============================================================================
-- TASK 7 STEP 5: Threshold Sensitivity Test
-- Tests combinations of (bill increase %) x (credit score) to see how many
-- Callers each rule would have caught, and how many Non-Callers it would flag
-- ============================================================================

WITH Callers AS (
    SELECT DISTINCT ivr.AccountNumber AS cust_id
    FROM dbo.IVR ivr
    JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID
    WHERE ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND cai.[call.reason] IN ('Bill Explanation', 'Bill Dispute')
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
        AND ivr.AccountNumber IS NOT NULL
),

ActiveResidential AS (
    SELECT cust_id, CreditScore, FlowStart,
        DATEDIFF(DAY, FlowStart, CAST(GETDATE() AS DATE)) AS TenureDays
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND CreditScore <> 0
        AND FlowEnd IS NULL
),

RankedBills AS (
    SELECT bm.*,
        ROW_NUMBER() OVER (PARTITION BY bm.cust_id ORDER BY bm.Bill_Date DESC) AS rn
    FROM iSigma_Bill_Master bm
    JOIN ActiveResidential ar ON ar.cust_id = bm.cust_id
),

MostRecentBill AS (
    SELECT * FROM RankedBills WHERE rn = 1
),

PersonalBaseline AS (
    SELECT
        cust_id,
        AVG(NetCharge) AS BaselineNetCharge,
        COUNT(*) AS BaselineBillCount
    FROM RankedBills
    WHERE rn BETWEEN 2 AND 13
    GROUP BY cust_id
),

Metrics AS (
    SELECT
        mrb.cust_id,
        CASE WHEN c.cust_id IS NOT NULL THEN 'Caller' ELSE 'Non-Caller' END AS CallerFlag,
        ar.CreditScore,
        (mrb.NetCharge - pb.BaselineNetCharge) / NULLIF(pb.BaselineNetCharge, 0) * 100 AS PercentIncrease
    FROM MostRecentBill mrb
    JOIN PersonalBaseline pb ON pb.cust_id = mrb.cust_id
    JOIN ActiveResidential ar ON ar.cust_id = mrb.cust_id
    LEFT JOIN Callers c ON c.cust_id = mrb.cust_id
    WHERE pb.BaselineBillCount >= 9
),

GroupTotals AS (
    SELECT
        SUM(CASE WHEN CallerFlag = 'Caller' THEN 1 ELSE 0 END) AS TotalCallers,
        SUM(CASE WHEN CallerFlag = 'Non-Caller' THEN 1 ELSE 0 END) AS TotalNonCallers
    FROM Metrics
),

ThresholdCombos AS (
    SELECT * FROM (VALUES
        (30, 700), (30, 750), (30, 800),
        (40, 700), (40, 750), (40, 800),
        (50, 700), (50, 750), (50, 800)
    ) AS t(PctThreshold, CreditThreshold)
)

-- STEP 5 FINAL OUTPUT: reach vs. precision for each threshold combination
SELECT
    tc.PctThreshold,
    tc.CreditThreshold,
    SUM(CASE WHEN m.CallerFlag = 'Caller' AND m.PercentIncrease >= tc.PctThreshold AND m.CreditScore <= tc.CreditThreshold THEN 1 ELSE 0 END) AS CallersCaught,
    gt.TotalCallers,
    ROUND(100.0 * SUM(CASE WHEN m.CallerFlag = 'Caller' AND m.PercentIncrease >= tc.PctThreshold AND m.CreditScore <= tc.CreditThreshold THEN 1 ELSE 0 END) / NULLIF(gt.TotalCallers, 0), 1) AS PctCallersCaught,
    SUM(CASE WHEN m.CallerFlag = 'Non-Caller' AND m.PercentIncrease >= tc.PctThreshold AND m.CreditScore <= tc.CreditThreshold THEN 1 ELSE 0 END) AS NonCallersFlagged,
    gt.TotalNonCallers,
    ROUND(100.0 * SUM(CASE WHEN m.CallerFlag = 'Non-Caller' AND m.PercentIncrease >= tc.PctThreshold AND m.CreditScore <= tc.CreditThreshold THEN 1 ELSE 0 END) / NULLIF(gt.TotalNonCallers, 0), 2) AS PctNonCallersFlagged
FROM Metrics m
CROSS JOIN ThresholdCombos tc
CROSS JOIN GroupTotals gt
GROUP BY tc.PctThreshold, tc.CreditThreshold, gt.TotalCallers, gt.TotalNonCallers
ORDER BY tc.PctThreshold, tc.CreditThreshold;
