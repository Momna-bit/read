	
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


-- WHY: To merge the credit-quality finding into the day-of-week/seasonal
-- forecast, we first need two things: how many active customers fall into
-- each credit tier today, and how often each tier actually calls, on average.
-- This step gets the customer counts by tier.

SELECT
    CASE
        WHEN CreditScore <= 500 THEN 'Low (\u2264500)'
        WHEN CreditScore BETWEEN 501 AND 700 THEN 'Medium (501-700)'
        WHEN CreditScore > 700 THEN 'High (700+)'
    END AS CreditTier,
    COUNT(*) AS CustomerCount
FROM iSigma_Customer_Master
WHERE Market = 'Texas' AND CustomerType = 'Residential'
    AND CreditScore <> 0
    AND FlowEnd IS NULL
GROUP BY CASE
        WHEN CreditScore <= 500 THEN 'Low (\u2264500)'
        WHEN CreditScore BETWEEN 501 AND 700 THEN 'Medium (501-700)'
        WHEN CreditScore > 700 THEN 'High (700+)'
    END
ORDER BY CreditTier;


-- WHY: Now that we know how many customers are in each credit tier, we need
-- to know how often each tier actually calls, on average, over the last
-- 180 days. This gives us a real, observed call rate per tier to blend into
-- the aggregate forecast.

WITH TierCustomers AS (
    SELECT
        cust_id,
        CASE
            WHEN CreditScore <= 500 THEN 'Low (\u2264500)'
            WHEN CreditScore BETWEEN 501 AND 700 THEN 'Medium (501-700)'
            WHEN CreditScore > 700 THEN 'High (700+)'
        END AS CreditTier
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND CreditScore <> 0
        AND FlowEnd IS NULL
),

TierCalls AS (
    SELECT
        tc.CreditTier,
        COUNT(ivr.ContactID) AS TotalCalls
    FROM TierCustomers tc
    LEFT JOIN dbo.IVR ivr 
        ON ivr.AccountNumber = tc.cust_id
        AND ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
    GROUP BY tc.CreditTier
),

TierCounts AS (
    SELECT CreditTier, COUNT(*) AS CustomerCount
    FROM TierCustomers
    GROUP BY CreditTier
)

SELECT
    tc.CreditTier,
    tn.CustomerCount,
    tc.TotalCalls,
    ROUND(CAST(tc.TotalCalls AS FLOAT) / tn.CustomerCount, 4) AS AvgCallsPerCustomer,
    ROUND(CAST(tc.TotalCalls AS FLOAT) / tn.CustomerCount / 180.0 * 1000, 3) AS CallsPer1000PerDay
FROM TierCalls tc
JOIN TierCounts tn ON tn.CreditTier = tc.CreditTier
ORDER BY tc.CreditTier;



-- ============================================================================
-- WHY: Jonathan asked to merge the credit-tier finding into the aggregate
-- forecast, drillable day by day and rollable up by month. This combines:
-- (1) each tier's real observed call rate, (2) the day-of-week pattern, and
-- (3) the seasonal pattern -- without double-counting, since the tier rate
-- is a 180-day average and the day/season indexes are relative deviations
-- from that average (each averages to 1.0 across the week/year).
-- ============================================================================

WITH TierRates AS (
    SELECT * FROM (VALUES
        ('High (700+)', 426935, 1.723),
        ('Medium (501-700)', 116829, 2.489),
        ('Low (\u2264500)', 45512, 3.744)
    ) AS t(CreditTier, TierCustomerCount, CallsPer1000PerDay)
),

DayIndex AS (
    SELECT * FROM (VALUES
        (1, 0.0000),   -- Sunday
        (2, 1.6997),   -- Monday
        (3, 1.3323),   -- Tuesday
        (4, 1.2238),   -- Wednesday
        (5, 1.0851),   -- Thursday
        (6, 1.1837),   -- Friday
        (7, 0.4755)    -- Saturday
    ) AS t(DayNum, DayOfWeekIndex)
),

SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 1.107), (2, 1.214), (3, 1.049), (4, 0.931), (5, 0.928), (6, 0.955),
        (7, 1.074), (8, 1.085), (9, 1.059), (10, 0.935), (11, 0.848), (12, 0.802)
    ) AS t(MonthNum, SeasonalIdx)
),

Digits AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
Numbers AS (SELECT (d1.n + d2.n*10 + d3.n*100) AS OffsetDay FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3),
ForecastCalendar AS (
    SELECT DATEADD(DAY, OffsetDay, CAST('2026-08-01' AS DATE)) AS CallDay
    FROM Numbers WHERE OffsetDay < 184
)

-- FINAL OUTPUT: daily grain, by credit tier -- roll up or filter as needed
SELECT
    fc.CallDay,
    FORMAT(fc.CallDay, 'yyyy-MM') AS ForecastMonth,
    DATENAME(WEEKDAY, fc.CallDay) AS DayOfWeek,
    tr.CreditTier,
    tr.TierCustomerCount,
    ROUND(tr.TierCustomerCount * (tr.CallsPer1000PerDay / 1000.0) * di.DayOfWeekIndex * si.SeasonalIdx, 1) AS ForecastedCalls
FROM ForecastCalendar fc
JOIN DayIndex di ON di.DayNum = DATEPART(WEEKDAY, fc.CallDay)
JOIN SeasonalIndex si ON si.MonthNum = MONTH(fc.CallDay)
CROSS JOIN TierRates tr
ORDER BY fc.CallDay, tr.CreditTier;


-- ============================================================================
-- WHY: The daily/tier data is correct, but 552 rows isn't useful to look at
-- directly. This rolls it up to one row per month per tier, plus a combined
-- total row per month, so it's easy to read and compare against the original
-- tier-agnostic forecast.
-- ============================================================================

WITH TierRates AS (
    SELECT * FROM (VALUES
        ('High (700+)', 426935, 1.723),
        ('Medium (501-700)', 116829, 2.489),
        ('Low (\u2264500)', 45512, 3.744)
    ) AS t(CreditTier, TierCustomerCount, CallsPer1000PerDay)
),

DayIndex AS (
    SELECT * FROM (VALUES
        (1, 0.0000), (2, 1.6997), (3, 1.3323), (4, 1.2238),
        (5, 1.0851), (6, 1.1837), (7, 0.4755)
    ) AS t(DayNum, DayOfWeekIndex)
),

SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 1.107), (2, 1.214), (3, 1.049), (4, 0.931), (5, 0.928), (6, 0.955),
        (7, 1.074), (8, 1.085), (9, 1.059), (10, 0.935), (11, 0.848), (12, 0.802)
    ) AS t(MonthNum, SeasonalIdx)
),

Digits AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
Numbers AS (SELECT (d1.n + d2.n*10 + d3.n*100) AS OffsetDay FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3),
ForecastCalendar AS (
    SELECT DATEADD(DAY, OffsetDay, CAST('2026-08-01' AS DATE)) AS CallDay
    FROM Numbers WHERE OffsetDay < 184
),

DailyByTier AS (
    SELECT
        FORMAT(fc.CallDay, 'yyyy-MM') AS ForecastMonth,
        tr.CreditTier,
        tr.TierCustomerCount * (tr.CallsPer1000PerDay / 1000.0) * di.DayOfWeekIndex * si.SeasonalIdx AS ForecastedCalls
    FROM ForecastCalendar fc
    JOIN DayIndex di ON di.DayNum = DATEPART(WEEKDAY, fc.CallDay)
    JOIN SeasonalIndex si ON si.MonthNum = MONTH(fc.CallDay)
    CROSS JOIN TierRates tr
)

-- FINAL OUTPUT: one row per tier per month, plus an "All Tiers Combined" row per month
SELECT
    ForecastMonth,
    ISNULL(CreditTier, 'All Tiers Combined') AS CreditTier,
    ROUND(SUM(ForecastedCalls), 0) AS TotalForecastedCalls
FROM DailyByTier
GROUP BY GROUPING SETS ((ForecastMonth, CreditTier), (ForecastMonth))
ORDER BY ForecastMonth, CreditTier;



-- ============================================================================
-- WHY: The tier-blended forecast came out at almost exactly half the original
-- forecast, every month. This checks whether the customer-tier join is
-- silently dropping calls -- e.g., calls from customers who don't have a
-- clean match in the customer master table (a different account number
-- format, a missing record, etc.) -- versus counting all calls directly.
-- ============================================================================

WITH RawCallCount AS (
    -- Same filters as the original day-of-week rate calculation: no join at all
    SELECT COUNT(*) AS TotalCalls
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND CallType IN ('Inbound', 'Transfer')
        AND AgentTalkTime > 0
        AND CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
),

TierJoinedCallCount AS (
    -- Same filters, but only counting calls that successfully joined to a
    -- customer with a valid (non-zero) credit score
    SELECT COUNT(*) AS TotalCalls
    FROM dbo.IVR ivr
    JOIN iSigma_Customer_Master cm 
        ON cm.cust_id = ivr.AccountNumber
        AND cm.Market = 'Texas' AND cm.CustomerType = 'Residential'
        AND cm.CreditScore <> 0
        AND cm.FlowEnd IS NULL
    WHERE ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
)

SELECT
    (SELECT TotalCalls FROM RawCallCount) AS RawCallCount_NoJoin,
    (SELECT TotalCalls FROM TierJoinedCallCount) AS CallCount_JoinedToTieredCustomers,
    ROUND(100.0 * (SELECT TotalCalls FROM TierJoinedCallCount) / (SELECT TotalCalls FROM RawCallCount), 1) AS PctCallsRetainedAfterJoin;



-- ============================================================================
-- WHY: The tier call rate was calculated using only customers active TODAY,
-- but the 180-day call count includes customers who've since churned. This
-- recalculates the rate using anyone who was a valid tiered customer at any
-- point during the 180-day window (whether or not they're still with us
-- today), which should match the raw call count much more closely.
-- ============================================================================

WITH TierCustomers AS (
    SELECT
        cust_id,
        CASE
            WHEN CreditScore <= 500 THEN 'Low (\u2264500)'
            WHEN CreditScore BETWEEN 501 AND 700 THEN 'Medium (501-700)'
            WHEN CreditScore > 700 THEN 'High (700+)'
        END AS CreditTier
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND CreditScore <> 0
        -- Was a customer at some point during the last 180 days,
        -- regardless of whether they're still active today:
        AND FlowStart <= CAST(GETDATE() AS DATE)
        AND (FlowEnd IS NULL OR FlowEnd >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE)))
),

TierCalls AS (
    SELECT
        tc.CreditTier,
        COUNT(ivr.ContactID) AS TotalCalls
    FROM TierCustomers tc
    LEFT JOIN dbo.IVR ivr 
        ON ivr.AccountNumber = tc.cust_id
        AND ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
    GROUP BY tc.CreditTier
),

TierCounts AS (
    SELECT CreditTier, COUNT(*) AS CustomerCount
    FROM TierCustomers
    GROUP BY CreditTier
)

SELECT
    tc.CreditTier,
    tn.CustomerCount AS CustomersEverActiveInWindow,
    tc.TotalCalls,
    ROUND(CAST(tc.TotalCalls AS FLOAT) / tn.CustomerCount, 4) AS AvgCallsPerCustomer,
    ROUND(CAST(tc.TotalCalls AS FLOAT) / tn.CustomerCount / 180.0 * 1000, 3) AS CallsPer1000PerDay,
    SUM(tc.TotalCalls) OVER () AS GrandTotalCalls
FROM TierCalls tc
JOIN TierCounts tn ON tn.CreditTier = tc.CreditTier
ORDER BY tc.CreditTier;



-- WHY: We're still missing about 40% of calls after fixing the FlowEnd issue.
-- This checks how much of that gap comes specifically from excluding
-- customers with no credit score on file (CreditScore = 0), versus some
-- other mismatch entirely (e.g., AccountNumber not matching at all).

WITH AllTexasResidential AS (
    -- Same population as before, but WITHOUT excluding CreditScore = 0
    SELECT cust_id, CreditScore
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND (FlowEnd IS NULL OR FlowEnd >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE)))
)

SELECT
    SUM(CASE WHEN a.CreditScore = 0 THEN 1 ELSE 0 END) AS CustomersWithNoScoreOnFile,
    SUM(CASE WHEN a.CreditScore <> 0 THEN 1 ELSE 0 END) AS CustomersWithValidScore,
    (SELECT COUNT(*) FROM dbo.IVR ivr
        JOIN AllTexasResidential a2 ON a2.cust_id = ivr.AccountNumber AND a2.CreditScore = 0
        WHERE ivr.Department = 'Care' AND ivr.CallType IN ('Inbound', 'Transfer')
            AND ivr.AgentTalkTime > 0 AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
    ) AS CallsFromNoScoreCustomers,
    (SELECT COUNT(*) FROM dbo.IVR ivr
        JOIN AllTexasResidential a2 ON a2.cust_id = ivr.AccountNumber
        WHERE ivr.Department = 'Care' AND ivr.CallType IN ('Inbound', 'Transfer')
            AND ivr.AgentTalkTime > 0 AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
    ) AS TotalCallsAllTexasResidential
FROM AllTexasResidential a;



-- ============================================================================
-- WHY: We've fixed two causes of the call-count gap (FlowEnd, CreditScore=0)
-- and closed it from 46% to 83% coverage, but there's still a real gap.
-- Instead of testing one guess at a time, this breaks down ALL 464,362 raw
-- calls into exactly why each one does or doesn't match a clean, valid,
-- tiered customer record -- so we see the complete picture in one shot.
-- ============================================================================

WITH RawCalls AS (
    SELECT ContactID, AccountNumber
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND CallType IN ('Inbound', 'Transfer')
        AND AgentTalkTime > 0
        AND CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
),

Categorized AS (
    SELECT
        rc.ContactID,
        CASE
            WHEN cm.cust_id IS NULL THEN '1. No matching customer record at all'
            WHEN cm.Market <> 'Texas' THEN '2. Matched, but not Texas'
            WHEN cm.CustomerType <> 'Residential' THEN '3. Matched, Texas, but not Residential'
            WHEN cm.CreditScore IS NULL THEN '4. Matched, Texas Residential, but CreditScore is NULL'
            WHEN cm.CreditScore = 0 THEN '5. Matched, Texas Residential, CreditScore = 0 (no score on file)'
            ELSE '6. Clean match -- valid tiered customer'
        END AS MatchCategory
    FROM RawCalls rc
    LEFT JOIN iSigma_Customer_Master cm 
        ON cm.cust_id = rc.AccountNumber
        AND (cm.FlowEnd IS NULL OR cm.FlowEnd >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE)))
)

SELECT
    MatchCategory,
    COUNT(*) AS CallCount,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS PctOfTotalCalls
FROM Categorized
GROUP BY MatchCategory
ORDER BY MatchCategory;


-- ============================================================================
-- WHY: We found the real cause of the forecast mismatch -- CreditScore NULL
-- was being silently dropped from every tier, on top of the CreditScore = 0
-- customers we already excluded. This rebuilds the tier rates treating NULL
-- and 0 the same way (both mean "no usable score"), so the tier population
-- properly matches the customers actually generating the calls.
-- ============================================================================

WITH TierCustomers AS (
    SELECT
        cust_id,
        CASE
            WHEN CreditScore IS NULL OR CreditScore = 0 THEN NULL  -- excluded, not a real tier
            WHEN CreditScore <= 500 THEN 'Low (\u2264500)'
            WHEN CreditScore BETWEEN 501 AND 700 THEN 'Medium (501-700)'
            WHEN CreditScore > 700 THEN 'High (700+)'
        END AS CreditTier
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND (FlowEnd IS NULL OR FlowEnd >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE)))
),

TierCustomersClean AS (
    SELECT * FROM TierCustomers WHERE CreditTier IS NOT NULL
),

TierCalls AS (
    SELECT
        tc.CreditTier,
        COUNT(ivr.ContactID) AS TotalCalls
    FROM TierCustomersClean tc
    LEFT JOIN dbo.IVR ivr 
        ON ivr.AccountNumber = tc.cust_id
        AND ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
    GROUP BY tc.CreditTier
),

TierCounts AS (
    SELECT CreditTier, COUNT(*) AS CustomerCount
    FROM TierCustomersClean
    GROUP BY CreditTier
)

SELECT
    tc.CreditTier,
    tn.CustomerCount,
    tc.TotalCalls,
    ROUND(CAST(tc.TotalCalls AS FLOAT) / tn.CustomerCount, 4) AS AvgCallsPerCustomer,
    ROUND(CAST(tc.TotalCalls AS FLOAT) / tn.CustomerCount / 180.0 * 1000, 3) AS CallsPer1000PerDay,
    SUM(tc.TotalCalls) OVER () AS GrandTotalCalls
FROM TierCalls tc
JOIN TierCounts tn ON tn.CreditTier = tc.CreditTier
ORDER BY tc.CreditTier;


-- WHY: The tiered forecast only ever covers customers with a valid credit
-- score. To make the total forecast complete (not just the tiered majority),
-- we need the same rate/count info for the "no score on file" group -- both
-- the broader population used for the rate, and the currently-active count
-- used for the forward projection.

WITH UnknownScoreCustomers AS (
    SELECT cust_id, FlowEnd
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND (CreditScore IS NULL OR CreditScore = 0)
),

UnknownEverActive AS (
    SELECT * FROM UnknownScoreCustomers
    WHERE FlowEnd IS NULL OR FlowEnd >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
),

UnknownCurrentlyActive AS (
    SELECT * FROM UnknownScoreCustomers WHERE FlowEnd IS NULL
),

UnknownCalls AS (
    SELECT COUNT(ivr.ContactID) AS TotalCalls
    FROM UnknownEverActive u
    LEFT JOIN dbo.IVR ivr 
        ON ivr.AccountNumber = u.cust_id
        AND ivr.Department = 'Care'
        AND ivr.CallType IN ('Inbound', 'Transfer')
        AND ivr.AgentTalkTime > 0
        AND ivr.CallDate >= DATEADD(DAY, -180, CAST(GETDATE() AS DATE))
)

SELECT
    (SELECT COUNT(*) FROM UnknownEverActive) AS CustomerCount_EverActive_ForRate,
    (SELECT TotalCalls FROM UnknownCalls) AS TotalCalls,
    ROUND(CAST((SELECT TotalCalls FROM UnknownCalls) AS FLOAT) / (SELECT COUNT(*) FROM UnknownEverActive) / 180.0 * 1000, 3) AS CallsPer1000PerDay,
    (SELECT COUNT(*) FROM UnknownCurrentlyActive) AS CustomerCount_CurrentlyActive_ForForecast
FROM UnknownCalls;



-- WHY: Checking if iSigma_Customer_Master has multiple rows per customer,
-- which would explain the unexpectedly high "ever active" count.
SELECT COUNT(*) AS TotalRows, COUNT(DISTINCT cust_id) AS UniqueCustomers
FROM iSigma_Customer_Master
WHERE Market = 'Texas' AND CustomerType = 'Residential';



-- ============================================================================
-- WHY: This is the final combined forecast Jonathan asked for -- day-by-day,
-- broken out by credit tier, rolled up monthly. It uses validated tier rates
-- for the ~589,276 customers we can reliably classify (High/Medium/Low), and
-- a residual "Unknown" group (49,584 = 638,860 total minus tiered total) for
-- customers whose credit tier we can't trust, using the original overall
-- day-of-week rates for that group since we can't tier them.
-- ============================================================================

WITH TierRates AS (
    SELECT * FROM (VALUES
        ('High (700+)', 426935, 1.914),
        ('Medium (501-700)', 116829, 2.748),
        ('Low (\u2264500)', 45512, 4.075)
    ) AS t(CreditTier, TierCustomerCount, CallsPer1000PerDay)
),

UnknownGroup AS (
    SELECT 49584 AS UnknownCustomerCount
),

RecentRatesByDay AS (
    -- Original overall day-of-week rates, used directly for the Unknown group
    SELECT * FROM (VALUES
        (1, 0.000),   -- Sunday
        (2, 6.703),   -- Monday
        (3, 5.254),   -- Tuesday
        (4, 4.826),   -- Wednesday
        (5, 4.279),   -- Thursday
        (6, 4.668),   -- Friday
        (7, 1.875)    -- Saturday
    ) AS t(DayNum, RecentRatePer1000)
),

DayIndex AS (
    -- Relative day-of-week index (avg = 1), used to scale the TIER rates
    SELECT * FROM (VALUES
        (1, 0.0000), (2, 1.6997), (3, 1.3323), (4, 1.2238),
        (5, 1.0851), (6, 1.1837), (7, 0.4755)
    ) AS t(DayNum, DayOfWeekIndex)
),

SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 1.107), (2, 1.214), (3, 1.049), (4, 0.931), (5, 0.928), (6, 0.955),
        (7, 1.074), (8, 1.085), (9, 1.059), (10, 0.935), (11, 0.848), (12, 0.802)
    ) AS t(MonthNum, SeasonalIdx)
),

Digits AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
Numbers AS (SELECT (d1.n + d2.n*10 + d3.n*100) AS OffsetDay FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3),
ForecastCalendar AS (
    SELECT DATEADD(DAY, OffsetDay, CAST('2026-08-01' AS DATE)) AS CallDay
    FROM Numbers WHERE OffsetDay < 184
),

DailyByGroup AS (
    -- Tiered groups: 180-day average rate x day-of-week index x seasonal index
    SELECT
        fc.CallDay,
        tr.CreditTier AS GroupName,
        tr.TierCustomerCount * (tr.CallsPer1000PerDay / 1000.0) * di.DayOfWeekIndex * si.SeasonalIdx AS ForecastedCalls
    FROM ForecastCalendar fc
    JOIN DayIndex di ON di.DayNum = DATEPART(WEEKDAY, fc.CallDay)
    JOIN SeasonalIndex si ON si.MonthNum = MONTH(fc.CallDay)
    CROSS JOIN TierRates tr

    UNION ALL

    -- Unknown group: original day-specific rate x seasonal index (no separate day-index needed)
    SELECT
        fc.CallDay,
        'Unknown Credit Score' AS GroupName,
        ug.UnknownCustomerCount * (rr.RecentRatePer1000 / 1000.0) * si.SeasonalIdx AS ForecastedCalls
    FROM ForecastCalendar fc
    JOIN RecentRatesByDay rr ON rr.DayNum = DATEPART(WEEKDAY, fc.CallDay)
    JOIN SeasonalIndex si ON si.MonthNum = MONTH(fc.CallDay)
    CROSS JOIN UnknownGroup ug
)

-- FINAL OUTPUT: one row per group per month, plus a combined total per month
SELECT
    FORMAT(CallDay, 'yyyy-MM') AS ForecastMonth,
    ISNULL(GroupName, 'All Groups Combined') AS CreditGroup,
    ROUND(SUM(ForecastedCalls), 0) AS TotalForecastedCalls
FROM DailyByGroup
GROUP BY GROUPING SETS ((FORMAT(CallDay, 'yyyy-MM'), GroupName), (FORMAT(CallDay, 'yyyy-MM')))
ORDER BY ForecastMonth, CreditGroup;



-- ============================================================================
-- WHY: Jonathan asked to be able to drill into any single day, not just see
-- monthly totals. This takes the already-trusted daily total forecast and
-- splits it into credit tiers using the validated proportions (56.9% High,
-- 22.4% Medium, 12.9% Low, 7.8% Unknown) -- the same split validated at the
-- monthly level, applied here at the daily grain.
-- ============================================================================

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
        (1, 0.000), (2, 6.703), (3, 5.254), (4, 4.826),
        (5, 4.279), (6, 4.668), (7, 1.875)
    ) AS t(DayNum, RecentRatePer1000)
),
SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 1.107), (2, 1.214), (3, 1.049), (4, 0.931), (5, 0.928), (6, 0.955),
        (7, 1.074), (8, 1.085), (9, 1.059), (10, 0.935), (11, 0.848), (12, 0.802)
    ) AS t(MonthNum, SeasonalIdx)
),

Digits AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS d(n)),
Numbers AS (SELECT (d1.n + d2.n*10 + d3.n*100) AS OffsetDay FROM Digits d1 CROSS JOIN Digits d2 CROSS JOIN Digits d3),
ForecastCalendar AS (
    SELECT DATEADD(DAY, OffsetDay, CAST('2026-08-01' AS DATE)) AS CallDay
    FROM Numbers WHERE OffsetDay < 184
),

ForecastActive AS (
    SELECT fc.CallDay,
        bc.BaselineCount + ISNULL((SELECT SUM(dd.NetChange) FROM DailyDelta dd WHERE dd.EventDate <= fc.CallDay), 0) AS ActiveCustomerCount
    FROM ForecastCalendar fc CROSS JOIN BaselineCount bc
),

DailyTotal AS (
    SELECT
        fa.CallDay,
        ROUND((rr.RecentRatePer1000 * si.SeasonalIdx / 1000.0) * fa.ActiveCustomerCount, 0) AS TotalForecastedCalls
    FROM ForecastActive fa
    JOIN RecentRates rr ON rr.DayNum = DATEPART(WEEKDAY, fa.CallDay)
    JOIN SeasonalIndex si ON si.MonthNum = MONTH(fa.CallDay)
)

-- FINAL OUTPUT: one row per day, total plus tier breakdown -- fully drillable
SELECT
    CallDay,
    DATENAME(WEEKDAY, CallDay) AS DayOfWeek,
    FORMAT(CallDay, 'yyyy-MM') AS ForecastMonth,
    TotalForecastedCalls,
    ROUND(TotalForecastedCalls * 0.569, 0) AS High_700Plus,
    ROUND(TotalForecastedCalls * 0.224, 0) AS Medium_501to700,
    ROUND(TotalForecastedCalls * 0.129, 0) AS Low_500OrBelow,
    ROUND(TotalForecastedCalls * 0.078, 0) AS UnknownCreditScore
FROM DailyTotal
ORDER BY CallDay;



-- ============================================================================
-- WHY: This is the last piece of the 6-month forecast task -- comparing what
-- the forecast predicted against real results, so drift can be caught early
-- (e.g., when IVR/LLM changes roll out). Using real early-August data since
-- it now exists. NOTE: still can't be saved as a permanent view due to the
-- CREATE VIEW permissions block -- re-run this manually until that's resolved.
-- ============================================================================

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
        (1, 0.000), (2, 6.703), (3, 5.254), (4, 4.826),
        (5, 4.279), (6, 4.668), (7, 1.875)
    ) AS t(DayNum, RecentRatePer1000)
),
SeasonalIndex AS (
    SELECT * FROM (VALUES
        (1, 1.107), (2, 1.214), (3, 1.049), (4, 0.931), (5, 0.928), (6, 0.955),
        (7, 1.074), (8, 1.085), (9, 1.059), (10, 0.935), (11, 0.848), (12, 0.802)
    ) AS t(MonthNum, SeasonalIdx)
),

CheckCalendar AS (
    -- The real days we're validating against: adjust end date to whatever is fully closed out
    SELECT CAST('2026-08-01' AS DATE) AS CallDay
    UNION ALL SELECT CAST('2026-08-02' AS DATE)
    UNION ALL SELECT CAST('2026-08-03' AS DATE)
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
        AND CAST(CallDate AS DATE) IN ('2026-08-01', '2026-08-02', '2026-08-03')
    GROUP BY CAST(CallDate AS DATE)
)

-- FINAL OUTPUT: forecast vs. actual, with variance and a flag for anything beyond +/-15%
SELECT
    f.CallDay,
    DATENAME(WEEKDAY, f.CallDay) AS DayOfWeek,
    f.ForecastedCalls,
    a.ActualCalls,
    ROUND(100.0 * (a.ActualCalls - f.ForecastedCalls) / f.ForecastedCalls, 1) AS PctVariance,
    CASE 
        WHEN ABS(100.0 * (a.ActualCalls - f.ForecastedCalls) / f.ForecastedCalls) > 15 
        THEN 'INVESTIGATE' ELSE 'Within Range' 
    END AS Flag
FROM Forecasted f
JOIN Actual a ON a.CallDay = f.CallDay
ORDER BY f.CallDay;



WITH DailyPhoneCalls AS (
    SELECT CustomerPhone, CAST(CallDate AS DATE) AS CallDay,
        COUNT(DISTINCT InitialContact) AS Calls
    FROM Analytics_ConstellationWH.dbo.IVR
    WHERE Department = 'CARE' AND CallType IN ('INBOUND', 'Transfer')
        AND CAST(CallDate AS DATE) >= '2026-07-01' AND CAST(CallDate AS DATE) < '2026-08-01'
    GROUP BY CustomerPhone, CAST(CallDate AS DATE)
)
SELECT 'With Anonymous' AS Version,
    SUM(CASE WHEN Calls > 2 THEN 1 ELSE 0 END) AS Repeats,
    COUNT(DISTINCT CustomerPhone) AS Customers,
    ROUND(100.0 * SUM(CASE WHEN Calls > 2 THEN 1 ELSE 0 END) / COUNT(DISTINCT CustomerPhone), 2) AS Pct
FROM DailyPhoneCalls
UNION ALL
SELECT 'Without Anonymous',
    SUM(CASE WHEN Calls > 2 THEN 1 ELSE 0 END),
    COUNT(DISTINCT CustomerPhone),
    ROUND(100.0 * SUM(CASE WHEN Calls > 2 THEN 1 ELSE 0 END) / COUNT(DISTINCT CustomerPhone), 2)
FROM DailyPhoneCalls WHERE CustomerPhone <> 'Anonymous';



SELECT TOP 20 ivr.AccountNumber, ivr.CustomerPhone, CAST(ivr.CallDate AS DATE) AS CallDay,
    COUNT(DISTINCT ivr.InitialContact) AS CallsThatDay
FROM Analytics_ConstellationWH.dbo.IVR ivr
WHERE ivr.Department = 'CARE' AND ivr.CallType IN ('INBOUND', 'Transfer')
    AND CAST(ivr.CallDate AS DATE) >= '2026-07-01' AND CAST(ivr.CallDate AS DATE) < '2026-08-01'
    AND ivr.CustomerPhone <> 'Anonymous'
GROUP BY ivr.AccountNumber, ivr.CustomerPhone, CAST(ivr.CallDate AS DATE)
HAVING COUNT(DISTINCT ivr.InitialContact) >= 3
ORDER BY CallsThatDay DESC;


SELECT ivr.ContactID, ivr.CallDate, cai.[call.summary]
FROM Analytics_ConstellationWH.dbo.IVR ivr
LEFT JOIN Care_CallAI cai ON cai.ContactID = ivr.ContactID
WHERE ivr.AccountNumber = '2412260078'
    AND CAST(ivr.CallDate AS DATE) >= '2026-07-01' AND CAST(ivr.CallDate AS DATE) < '2026-08-01'
ORDER BY ivr.CallDate;



SELECT ivr.AccountNumber, CAST(ivr.CallDate AS DATE) AS CallDay,
    COUNT(DISTINCT ivr.InitialContact) AS CallsThatDay
FROM Analytics_ConstellationWH.dbo.IVR ivr
WHERE ivr.Department = 'CARE' AND ivr.CallType IN ('INBOUND', 'Transfer')
    AND CAST(ivr.CallDate AS DATE) >= '2026-07-01' AND CAST(ivr.CallDate AS DATE) < '2026-08-01'
    AND ivr.AccountNumber IS NOT NULL
GROUP BY ivr.AccountNumber, CAST(ivr.CallDate AS DATE)
HAVING COUNT(DISTINCT ivr.InitialContact) >= 2
ORDER BY CallsThatDay DESC, CallDay;


SELECT ivr.Department, ivr.Queue, ivr.CallType, ivr.VerificationStatus,
    COUNT(*) AS CallCount
FROM Analytics_ConstellationWH.dbo.IVR ivr
WHERE ivr.AccountNumber = '2412260078'
    AND CAST(ivr.CallDate AS DATE) >= '2026-07-01' AND CAST(ivr.CallDate AS DATE) < '2026-08-01'
GROUP BY ivr.Department, ivr.Queue, ivr.CallType, ivr.VerificationStatus
ORDER BY CallCount DESC;



