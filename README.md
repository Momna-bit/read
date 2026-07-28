	
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


-- ============================================================================
-- SEASONAL ADJUSTMENT FACTOR
-- Isolates month-of-year seasonality, independent of the year-over-year
-- level shift caused by IVR/phone system changes
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

DailyActive AS (
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
    -- STEP 1: Daily rate, tagged with year and month, holidays excluded
    SELECT
        da.CallDay,
        YEAR(da.CallDay) AS CallYear,
        MONTH(da.CallDay) AS CallMonth,
        CAST(ISNULL(fc.AgentHandledCalls, 0) AS FLOAT) / NULLIF(da.ActiveCustomerCount, 0) * 1000 AS RatePer1000
    FROM DailyActive da
    LEFT JOIN FilteredCalls fc ON fc.CallDay = da.CallDay
    WHERE da.IsHoliday = 0
),

YearlyAverage AS (
    -- STEP 2: Each year's own average rate (this is what we normalize against)
    SELECT CallYear, AVG(RatePer1000) AS YearAvgRate
    FROM DailyRates
    GROUP BY CallYear
),

NormalizedDaily AS (
    -- STEP 3: Express each day as a ratio to its OWN year's average
    -- (cancels out the year-over-year level shift from phone system changes)
    SELECT
        dr.CallMonth,
        dr.RatePer1000 / NULLIF(ya.YearAvgRate, 0) AS NormalizedRatio
    FROM DailyRates dr
    JOIN YearlyAverage ya ON ya.CallYear = dr.CallYear
)

-- STEP 4: Average the normalized ratios by calendar month = seasonal index
SELECT
    CallMonth,
    DATENAME(MONTH, DATEFROMPARTS(2000, CallMonth, 1)) AS MonthName,
    COUNT(*) AS DaysObserved,
    ROUND(AVG(NormalizedRatio), 3) AS SeasonalIndex
FROM NormalizedDaily
GROUP BY CallMonth
ORDER BY CallMonth;



-- ============================================================================
-- COMBINED FORECAST: Day-of-Week Blended Rate x Seasonal Index
-- Projects daily call volume forward using both adjustments together
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

DailyActive AS (
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
        da.CallDay,
        YEAR(da.CallDay) AS CallYear,
        MONTH(da.CallDay) AS CallMonth,
        CAST(ISNULL(fc.AgentHandledCalls, 0) AS FLOAT) / NULLIF(da.ActiveCustomerCount, 0) * 1000 AS RatePer1000
    FROM DailyActive da
    LEFT JOIN FilteredCalls fc ON fc.CallDay = da.CallDay
    WHERE da.IsHoliday = 0
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
    -- Seasonal index per calendar month (from prior validated step)
    SELECT
        CallMonth,
        AVG(NormalizedRatio) AS SeasonalIndex
    FROM NormalizedDaily
    GROUP BY CallMonth
),

BlendedRates AS (
    -- Blended day-of-week rate (from prior validated step)
    SELECT * FROM (VALUES
        (1, 0.000),
        (2, 7.814),
        (3, 6.513),
        (4, 5.872),
        (5, 5.188),
        (6, 5.397),
        (7, 2.162)
    ) AS t(DayNum, BlendedRatePer1000)
)

-- STEP: Combined 90-day forward projection
SELECT
    da.CallDay,
    DATENAME(WEEKDAY, da.CallDay) AS DayOfWeek,
    DATENAME(MONTH, da.CallDay) AS MonthName,
    da.IsHoliday,
    da.ActiveCustomerCount,
    br.BlendedRatePer1000,
    ROUND(si.SeasonalIndex, 3) AS SeasonalIndex,
    ROUND(br.BlendedRatePer1000 * si.SeasonalIndex, 3) AS AdjustedRatePer1000,
    ROUND((br.BlendedRatePer1000 * si.SeasonalIndex / 1000.0) * da.ActiveCustomerCount, 0) AS ForecastedCalls
FROM DailyActive da
JOIN BlendedRates br ON br.DayNum = DATEPART(WEEKDAY, da.CallDay)
JOIN SeasonalIndex si ON si.CallMonth = MONTH(da.CallDay)
WHERE da.CallDay >= CAST(GETDATE() AS DATE)
    AND da.CallDay < DATEADD(DAY, 90, CAST(GETDATE() AS DATE))
ORDER BY da.CallDay;

