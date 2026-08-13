-- =====================================================================
-- Call Forecast Accuracy - 3-Month Window Breakdown (v2)
-- Same goal as before: split the 12-month backtest into "most recent
-- 3 months" vs. "older 9 months" so we can see whether near-term
-- accuracy meets Lou's stricter bar on its own.
--
-- This version adds one safety check at the top: confirm the join
-- between Forecasted and Actual doesn't produce duplicate rows per
-- day, since a silent duplicate-row bug is the most likely explanation
-- for the earlier mismatched 75% result (individual sample rows all
-- looked healthy, so the problem was most likely in the aggregation
-- step, not the underlying data).
-- =====================================================================

IF OBJECT_ID('tempdb..#Forecasted') IS NOT NULL DROP TABLE #Forecasted;
IF OBJECT_ID('tempdb..#Actual') IS NOT NULL DROP TABLE #Actual;

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
        ROUND((rr.RecentRatePer1000 * si.SeasonalIdx / 1000.0) * fa.ActiveCustomerCount, 0) AS ForecastedCalls
    FROM ForecastActive fa
    JOIN RecentRates rr ON rr.DayNum = DATEPART(WEEKDAY, fa.CallDay)
    JOIN SeasonalIndex si ON si.MonthNum = MONTH(fa.CallDay)
)
SELECT * INTO #Forecasted FROM Forecasted;

SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS ActualCalls
INTO #Actual
FROM dbo.IVR
WHERE Department = 'Care' AND CallType IN ('Inbound', 'Transfer') AND AgentTalkTime > 0
GROUP BY CAST(CallDate AS DATE);

-- =====================================================================
-- SAFETY CHECK: confirm no duplicate CallDay rows in either temp table
-- before trusting any aggregate built from them
-- =====================================================================
SELECT 'Forecasted' AS TableName, COUNT(*) AS TotalRows, COUNT(DISTINCT CallDay) AS DistinctDays
FROM #Forecasted
UNION ALL
SELECT 'Actual', COUNT(*), COUNT(DISTINCT CallDay)
FROM #Actual;

-- =====================================================================
-- Main result: split into Most Recent 3 Months vs Older 9 Months
-- =====================================================================
SELECT
    CASE WHEN c.CallDay >= DATEADD(MONTH, -3, (SELECT MAX(CallDay) FROM #Actual))
        THEN 'Most Recent 3 Months' ELSE 'Older 9 Months' END AS Window_,
    COUNT(*) AS DaysChecked,
    ROUND(AVG(ABS(100.0 * (a.ActualCalls - c.ForecastedCalls) / c.ForecastedCalls)), 1) AS AvgPctError_MAPE,
    SUM(CASE WHEN ABS(100.0 * (a.ActualCalls - c.ForecastedCalls) / c.ForecastedCalls) <= 15 THEN 1 ELSE 0 END) AS DaysWithinRange,
    ROUND(100.0 * SUM(CASE WHEN ABS(100.0 * (a.ActualCalls - c.ForecastedCalls) / c.ForecastedCalls) <= 15 THEN 1 ELSE 0 END) / COUNT(*), 1) AS PctWithinRange
FROM #Forecasted c
JOIN #Actual a ON a.CallDay = c.CallDay
WHERE c.ForecastedCalls > 0
GROUP BY CASE WHEN c.CallDay >= DATEADD(MONTH, -3, (SELECT MAX(CallDay) FROM #Actual))
        THEN 'Most Recent 3 Months' ELSE 'Older 9 Months' END
ORDER BY Window_ DESC;
