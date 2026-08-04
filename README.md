	
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
