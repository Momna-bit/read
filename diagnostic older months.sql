-- =====================================================================
-- DIAGNOSTIC: Inspect raw rows behind the "Older 9 Months" bucket
-- Goal: the 75% average error in that bucket doesn't match what we
-- already validated (9.9% MAPE blended across all 12 months), so
-- something is likely wrong in how ActiveCustomerCount or
-- ForecastedCalls is being calculated for older dates. This pulls
-- individual rows so we can see the actual numbers with our own eyes.
-- =====================================================================

-- ---- Clear out any old temp tables first (must come before anything else) ----
IF OBJECT_ID('tempdb..#Forecasted') IS NOT NULL DROP TABLE #Forecasted;
IF OBJECT_ID('tempdb..#Actual') IS NOT NULL DROP TABLE #Actual;

-- ---- Build #Forecasted (the WITH block must be immediately followed by
-- the one SELECT that uses it - nothing else can come in between) ----
WITH BaselineCount AS (
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),
ActiveDelta AS (
    SELECT CAST(FlowStart AS DATE) AS EventDate, 1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowStart >= '2022-07-01'
    UNION ALL
    SELECT CAST(DATEADD(DAY, 1, FlowEnd) AS DATE) AS EventDate, -1 AS Delta
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowEnd >= '2022-07-01'
),
DailyDelta AS (SELECT EventDate, SUM(Delta) AS NetChange FROM ActiveDelta GROUP BY EventDate),

RecentRates AS (
    SELECT * FROM (VALUES
        (1, 0.000), (2, 7.485), (3, 6.407), (4, 5.582),
        (5, 4.948), (6, 5.418), (7, 2.238)
    ) AS t(DayNum, RecentRatePer1000)
),
SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 0.904), (2, 0.932), (3, 0.865), (4, 0.774),
        (5, 0.752), (6, 0.915), (7, 1.028), (8, 1.354),
        (9, 1.369), (10, 1.268), (11, 0.910), (12, 0.900)
    ) AS t(MonthNum, SeasonalIdx)
),

Digits AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
Numbers AS (SELECT (d1.n + d2.n*10 + d3.n*100) AS OffsetDay FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3),
CheckCalendar AS (
    SELECT DATEADD(DAY, -OffsetDay, CAST(DATEADD(DAY, -1, GETDATE()) AS DATE)) AS CallDay
    FROM Numbers WHERE OffsetDay < 365
),

ForecastActive AS (
    SELECT cc.CallDay,
        bc.BaselineCount + ISNULL((SELECT SUM(dd.NetChange) FROM DailyDelta dd WHERE dd.EventDate <= cc.CallDay), 0) AS ActiveCustomerCount
    FROM CheckCalendar cc CROSS JOIN BaselineCount bc
),

Forecasted AS (
    SELECT
        fa.CallDay,
        fa.ActiveCustomerCount,
        rr.RecentRatePer1000,
        si.SeasonalIdx,
        ROUND((rr.RecentRatePer1000 * si.SeasonalIdx / 1000.0) * fa.ActiveCustomerCount, 0) AS ForecastedCalls
    FROM ForecastActive fa
    JOIN RecentRates rr ON rr.DayNum = DATEPART(WEEKDAY, fa.CallDay)
    JOIN SeasonalIndex si ON si.MonthNum = MONTH(fa.CallDay)
)
SELECT * INTO #Forecasted FROM Forecasted;

-- ---- Build #Actual as its own separate, standalone statement ----
SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS ActualCalls
INTO #Actual
FROM dbo.IVR
WHERE Department = 'Care' AND CallType IN ('Inbound', 'Transfer') AND AgentTalkTime > 0
GROUP BY CAST(CallDate AS DATE);

-- ---- Check 1: Sample rows from deep in history (300-330 days back) ----
SELECT TOP 15
    f.CallDay,
    DATENAME(WEEKDAY, f.CallDay) AS DayOfWeek,
    f.ActiveCustomerCount,
    f.RecentRatePer1000,
    f.SeasonalIdx,
    f.ForecastedCalls,
    a.ActualCalls,
    ROUND(100.0 * (a.ActualCalls - f.ForecastedCalls) / NULLIF(f.ForecastedCalls, 0), 1) AS PctVariance
FROM #Forecasted f
JOIN #Actual a ON a.CallDay = f.CallDay
WHERE f.CallDay <= DATEADD(DAY, -300, CAST(GETDATE() AS DATE))
ORDER BY f.CallDay DESC;

-- ---- Check 2: Data completeness - how many real actual-call days do we have per month? ----
-- A month should have roughly 26-27 rows (365 days minus ~52 Sundays / 12).
-- If any month has far fewer, that's a sign of missing data driving up error.
SELECT
    FORMAT(CallDay, 'yyyy-MM') AS CallMonth,
    COUNT(*) AS DaysWithData
FROM #Actual
WHERE CallDay >= DATEADD(DAY, -365, CAST(GETDATE() AS DATE))
GROUP BY FORMAT(CallDay, 'yyyy-MM')
ORDER BY CallMonth;
