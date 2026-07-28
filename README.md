	
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





-- Check how far vw_calendarWH extends into the future
SELECT MAX([Date]) AS LatestCalendarDate
FROM vw_calendarWH;




-- ============================================================================
-- REWORKED BLEND: Rolling 6-Month Recency Window
-- Replaces the fixed 40/60 blend. Recent data now drives the actual rate;
-- full history is used only to confirm the day-of-week shape still holds.
-- Recompute this periodically (e.g., monthly) as phone system changes roll out.
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
        DATEPART(WEEKDAY, da.CallDay) AS DayNum,
        DATENAME(WEEKDAY, da.CallDay) AS DayOfWeek,
        CAST(ISNULL(fc.AgentHandledCalls, 0) AS FLOAT) / NULLIF(da.ActiveCustomerCount, 0) * 1000 AS RatePer1000
    FROM DailyActive da
    LEFT JOIN FilteredCalls fc ON fc.CallDay = da.CallDay
    WHERE da.IsHoliday = 0
),

-- STEP 1: Rolling 6-month (180-day) rate -- this is the new forecast basis
RecentRate AS (
    SELECT
        DayNum,
        DayOfWeek,
        COUNT(*) AS DaysObserved,
        AVG(RatePer1000) AS RecentRatePer1000
    FROM DailyRates
    WHERE CallDay >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
    GROUP BY DayNum, DayOfWeek
),

-- STEP 2: Full 4-year history -- used only to confirm the shape still holds
FullHistoryRate AS (
    SELECT
        DayNum,
        DayOfWeek,
        COUNT(*) AS DaysObserved,
        AVG(RatePer1000) AS FullHistoryRatePer1000
    FROM DailyRates
    GROUP BY DayNum, DayOfWeek
)

-- STEP 3: Compare shape (rank order) between recent window and full history
SELECT
    r.DayNum,
    r.DayOfWeek,
    r.DaysObserved AS RecentDaysObserved,
    ROUND(r.RecentRatePer1000, 3) AS RecentRatePer1000,
    RANK() OVER (ORDER BY r.RecentRatePer1000 DESC) AS RecentRank,
    ROUND(f.FullHistoryRatePer1000, 3) AS FullHistoryRatePer1000,
    RANK() OVER (ORDER BY f.FullHistoryRatePer1000 DESC) AS FullHistoryRank
FROM RecentRate r
JOIN FullHistoryRate f ON f.DayNum = r.DayNum
ORDER BY r.DayNum;


-- ============================================================================
-- COMBINED FORECAST: Recent Day-of-Week Rate (180-day) x Seasonal Index
-- Replaces the fixed 40/60 blend with the rolling recent-window rate
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

-- Replaces the old fixed BlendedRates -- now the 180-day recent rate
RecentRates AS (
    SELECT * FROM (VALUES
        (1, 0.000),
        (2, 6.703),
        (3, 5.254),
        (4, 4.826),
        (5, 4.279),
        (6, 4.668),
        (7, 1.875)
    ) AS t(DayNum, RecentRatePer1000)
),

Digits AS (
    SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)
),
Numbers AS (
    SELECT (d1.n + d2.n * 10) AS OffsetDay
    FROM Digits d1 CROSS JOIN Digits d2
),
ForecastCalendar AS (
    SELECT DATEADD(DAY, OffsetDay, CAST(GETDATE() AS DATE)) AS CallDay
    FROM Numbers
    WHERE OffsetDay < 90
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
)

SELECT
    fa.CallDay,
    DATENAME(WEEKDAY, fa.CallDay) AS DayOfWeek,
    DATENAME(MONTH, fa.CallDay) AS MonthName,
    fa.ActiveCustomerCount,
    rr.RecentRatePer1000,
    ROUND(si.SeasonalIndex, 3) AS SeasonalIndex,
    ROUND(rr.RecentRatePer1000 * si.SeasonalIndex, 3) AS AdjustedRatePer1000,
    ROUND((rr.RecentRatePer1000 * si.SeasonalIndex / 1000.0) * fa.ActiveCustomerCount, 0) AS ForecastedCalls
FROM ForecastActive fa
JOIN RecentRates rr ON rr.DayNum = DATEPART(WEEKDAY, fa.CallDay)
JOIN SeasonalIndex si ON si.CallMonth = MONTH(fa.CallDay)
ORDER BY fa.CallDay;

-- ============================================================================
-- COHORT MODEL SCOPING: Feasibility Check
-- Cross-tabs bill size x credit quality to see if each cohort cell has
-- enough volume to support a statistically solid per-cohort rate
-- ============================================================================

WITH LatestBill AS (
    -- Most recent bill per active Texas Residential customer
    SELECT
        bm.cust_id,
        bm.NetCharge,
        ROW_NUMBER() OVER (PARTITION BY bm.cust_id ORDER BY bm.LastPaidDateiSigma DESC) AS rn
    FROM iSigma_Bill_Master bm
    JOIN iSigma_Customer_Master cm 
        ON cm.cust_id = bm.cust_id
        AND cm.Market = 'Texas' 
        AND cm.CustomerType = 'Residential'
        AND cm.FlowEnd IS NULL  -- currently active
),

CustomerCohort AS (
    -- STEP 1: Assign each customer to a bill-size bucket and credit-quality bucket
    SELECT
        lb.cust_id,
        cm.CreditScore,
        lb.NetCharge,
        CASE 
            WHEN lb.NetCharge < 100 THEN '< $100'
            WHEN lb.NetCharge < 200 THEN '$100-$200'
            WHEN lb.NetCharge < 300 THEN '$200-$300'
            WHEN lb.NetCharge < 400 THEN '$300-$400'
            ELSE '$400+'
        END AS BillBucket,
        CASE 
            WHEN cm.CreditScore = 0 THEN 'Unknown/Junk'
            WHEN cm.CreditScore <= 500 THEN 'Low (<=500)'
            WHEN cm.CreditScore <= 700 THEN 'Medium (501-700)'
            ELSE 'High (700+)'
        END AS CreditBucket
    FROM LatestBill lb
    JOIN iSigma_Customer_Master cm ON cm.cust_id = lb.cust_id
    WHERE lb.rn = 1
),

CallVolume AS (
    -- Agent-handled calls per customer, last 180 days (same filter as the main model)
    SELECT
        AccountNumber AS cust_id,
        COUNT(*) AS CallCount
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND CallType IN ('Inbound', 'Transfer')
        AND AgentTalkTime > 0
        AND CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
    GROUP BY AccountNumber
)

-- STEP 2: Cross-tab -- customer count and call count per cohort cell
SELECT
    cc.BillBucket,
    cc.CreditBucket,
    COUNT(DISTINCT cc.cust_id) AS CustomerCount,
    SUM(ISNULL(cv.CallCount, 0)) AS TotalCalls,
    ROUND(AVG(CAST(ISNULL(cv.CallCount, 0) AS FLOAT)), 3) AS AvgCallsPerCustomer
FROM CustomerCohort cc
LEFT JOIN CallVolume cv ON cv.cust_id = cc.cust_id
GROUP BY cc.BillBucket, cc.CreditBucket
ORDER BY cc.BillBucket, cc.CreditBucket;


-- STEP 1: Check how much of the volume is unclassified ("no reason captured")
SELECT
    CASE 
        WHEN [call.reason] IS NULL OR [call.reason] = '' THEN 'Unclassified'
        ELSE [call.reason]
    END AS ReasonBucket,
    COUNT(*) AS CallCount
FROM Care_CallAI
WHERE Date >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
GROUP BY CASE 
        WHEN [call.reason] IS NULL OR [call.reason] = '' THEN 'Unclassified'
        ELSE [call.reason]
    END
ORDER BY CallCount DESC;


-- STEP 2: Join call-reason classification to actual agent-handled call volume,
-- broken out by day, so deviations from expected can eventually be flagged
SELECT
    CAST(ivr.CallDate AS DATE) AS CallDay,
    CASE 
        WHEN cai.[call.reason] IS NULL OR cai.[call.reason] = '' THEN 'Unclassified'
        ELSE cai.[call.reason]
    END AS ReasonBucket,
    COUNT(*) AS CallCount
FROM dbo.IVR ivr
JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID
WHERE ivr.Department = 'Care'
    AND ivr.CallType IN ('Inbound', 'Transfer')
    AND ivr.AgentTalkTime > 0
    AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
GROUP BY CAST(ivr.CallDate AS DATE),
    CASE 
        WHEN cai.[call.reason] IS NULL OR cai.[call.reason] = '' THEN 'Unclassified'
        ELSE cai.[call.reason]
    END
ORDER BY CallDay, CallCount DESC;

