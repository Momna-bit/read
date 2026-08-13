-- =====================================================================
-- Call Forecast Accuracy - 3-Month Window Breakdown
-- Goal: Lou wants near-100% accuracy for the next 3 months specifically,
-- and 90% is acceptable beyond that. Our existing 9.9% MAPE was a
-- blanket 12-month average. This splits it into "most recent 3 months"
-- vs. "older 9 months" of the backtest, so we can see whether the
-- near-term accuracy actually meets the stricter bar on its own.
-- =====================================================================

-- STEP 1-4 are unchanged from the existing backtest (day-of-week rates,
-- seasonal index, and the full day-by-day forecast vs. actual comparison).
-- Reusing that exact same logic here, just adding one more step at the end.

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
),

Actual AS (
    SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS ActualCalls
    FROM dbo.IVR
    WHERE Department = 'Care' AND CallType IN ('Inbound', 'Transfer') AND AgentTalkTime > 0
    GROUP BY CAST(CallDate AS DATE)
),

-- ---- Combine forecast + actual, same as before ----
Combined AS (
    SELECT
        f.CallDay,
        f.ForecastedCalls,
        a.ActualCalls,
        ABS(100.0 * (a.ActualCalls - f.ForecastedCalls) / f.ForecastedCalls) AS AbsPctError,
        CASE WHEN ABS(100.0 * (a.ActualCalls - f.ForecastedCalls) / f.ForecastedCalls) <= 15
            THEN 1 ELSE 0 END AS WithinRange
    FROM Forecasted f
    JOIN Actual a ON a.CallDay = f.CallDay
    WHERE f.ForecastedCalls > 0  -- exclude Sundays / zero-forecast days, same as original
),

-- =====================================================================
-- STEP 5 (NEW): Split into "most recent 3 months" vs "older 9 months"
-- Window: relative to the most recent day we actually have real call
-- data for, not relative to today - so this measures how accurate the
-- forecast is on the freshest data available, as the closest proxy we
-- have for "how accurate will it be going forward."
-- =====================================================================
Windowed AS (
    SELECT
        c.*,
        CASE WHEN c.CallDay >= DATEADD(MONTH, -3, (SELECT MAX(CallDay) FROM Combined))
            THEN 'Most Recent 3 Months'
            ELSE 'Older 9 Months'
        END AS Window_
    FROM Combined c
)

SELECT
    Window_,
    COUNT(*) AS DaysChecked,
    ROUND(AVG(AbsPctError), 1) AS AvgPctError_MAPE,
    SUM(WithinRange) AS DaysWithinRange,
    ROUND(100.0 * SUM(WithinRange) / COUNT(*), 1) AS PctWithinRange
FROM Windowed
GROUP BY Window_
ORDER BY Window_ DESC;
