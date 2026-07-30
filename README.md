	
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


-- ============================================================================
-- 6-MONTH FORECAST (FULL CALENDAR MONTHS): Aug 2026 - Jan 2027
-- Fixes the partial-month issue by starting at Aug 1 instead of "today"
-- ============================================================================

WITH BaselineCount AS (
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),

Calendar AS (
    SELECT 
        CAST([Date] AS DATE) AS CallDay, 
        CASE WHEN USHoliday IS NOT NULL THEN 1 ELSE 0 END AS IsHoliday
    FROM vw_calendarWH 
    WHERE [Date] >= '2022-07-01'
),

ActiveDelta AS (
    SELECT CAST(FlowStart AS DATE) AS EventDate, 1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' 
        AND FlowStart >= '2022-07-01'
    UNION ALL
    SELECT CAST(DATEADD(DAY, 1, FlowEnd) AS DATE) AS EventDate, -1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' 
        AND FlowEnd >= '2022-07-01'
),

DailyDelta AS (
    SELECT EventDate, SUM(Delta) AS NetChange 
    FROM ActiveDelta 
    GROUP BY EventDate
),

HistoricalActive AS (
    SELECT
        cal.CallDay,
        cal.IsHoliday,
        bc.BaselineCount + ISNULL((
            SELECT SUM(dd.NetChange) 
            FROM DailyDelta dd 
            WHERE dd.EventDate <= cal.CallDay
        ), 0) AS ActiveCustomerCount
    FROM Calendar cal
    CROSS JOIN BaselineCount bc
),

FilteredCalls AS (
    SELECT
        CAST(CallDate AS DATE) AS CallDay,
        COUNT(*) AS AgentHandledCalls
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND CallType IN ('Inbound', 'Transfer')
        AND AgentTalkTime > 0
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
        AND CallDate >= '2022-07-01'
    GROUP BY CAST(CallDate AS DATE)
),

DailyRates AS (
    SELECT
        ha.CallDay,
        YEAR(ha.CallDay) AS CallYear,
        MONTH(ha.CallDay) AS CallMonth,
        CAST(ISNULL(fc.AgentHandledCalls, 0) AS FLOAT) / NULLIF(ha.ActiveCustomerCount, 0) * 1000 AS RatePer1000
    FROM HistoricalActive ha
    LEFT JOIN FilteredCalls fc ON fc.CallDay = ha.CallDay
    WHERE ha.IsHoliday = 0
),

YearlyAverage AS (
    SELECT CallYear, AVG(RatePer1000) AS YearAvgRate
    FROM DailyRates
    GROUP BY CallYear
),

NormalizedDaily AS (
    SELECT
        dr.CallMonth,
        dr.RatePer1000 / NULLIF(ya.YearAvgRate, 0) AS NormalizedRatio
    FROM DailyRates dr
    JOIN YearlyAverage ya ON ya.CallYear = dr.CallYear
),

SeasonalIndex AS (
    SELECT CallMonth, AVG(NormalizedRatio) AS SeasonalIndex
    FROM NormalizedDaily
    GROUP BY CallMonth
),

RecentRates AS (
    SELECT * FROM (VALUES
        (1, 0.000), (2, 6.703), (3, 5.254), (4, 4.826),
        (5, 4.279), (6, 4.668), (7, 1.875)
    ) AS t(DayNum, RecentRatePer1000)
),

Digits AS (
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
Numbers AS (
    SELECT (d1.n + d2.n * 10 + d3.n * 100) AS OffsetDay
    FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3
),
ForecastCalendar AS (
    -- Fixed 6 full calendar months: Aug 1, 2026 - Jan 31, 2027 (184 days)
    SELECT DATEADD(DAY, OffsetDay, CAST('2026-08-01' AS DATE)) AS CallDay
    FROM Numbers
    WHERE OffsetDay < 184
),

ForecastActive AS (
    SELECT
        fc2.CallDay,
        bc.BaselineCount + ISNULL((
            SELECT SUM(dd.NetChange) 
            FROM DailyDelta dd 
            WHERE dd.EventDate <= fc2.CallDay
        ), 0) AS ActiveCustomerCount
    FROM ForecastCalendar fc2
    CROSS JOIN BaselineCount bc
),

DailyForecast AS (
    SELECT
        fa.CallDay,
        fa.ActiveCustomerCount,
        ROUND((rr.RecentRatePer1000 * si.SeasonalIndex / 1000.0) * fa.ActiveCustomerCount, 0) AS ForecastedCalls
    FROM ForecastActive fa
    JOIN RecentRates rr ON rr.DayNum = DATEPART(WEEKDAY, fa.CallDay)
    JOIN SeasonalIndex si ON si.CallMonth = MONTH(fa.CallDay)
)

-- FINAL OUTPUT: 6 full calendar months, active customers and call volume shown separately
SELECT
    FORMAT(CallDay, 'yyyy-MM') AS ForecastMonth,
    DATENAME(MONTH, CallDay) AS MonthName,
    COUNT(*) AS DaysInMonth,
    ROUND(AVG(CAST(ActiveCustomerCount AS FLOAT)), 0) AS AvgActiveCustomers,
    SUM(ForecastedCalls) AS TotalForecastedCalls,
    ROUND(SUM(ForecastedCalls) * 1.0 / NULLIF(AVG(CAST(ActiveCustomerCount AS FLOAT)), 0) * 1000, 2) AS CallsPer1000Customers
FROM DailyForecast
GROUP BY FORMAT(CallDay, 'yyyy-MM'), DATENAME(MONTH, CallDay), DATEPART(MONTH, CallDay)
ORDER BY ForecastMonth;

