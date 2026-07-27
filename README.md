	
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
-- TASK 4: Baseline Forecasting Dataset — Full End-to-End Rebuild
-- South Mass Market & Canada | Texas Residential Care
-- Prepared by: Momna Ali
-- ============================================================================
-- Produces one row per calendar day (July 2022 onward) combining:
--   - Weekday / holiday flags
--   - Active customer count (event-based, not a per-day brute-force join)
--   - Past-due customer count (active-status filtered)
--   - IVR call volume, containment rate, abandon rate, avg talk time
--   - Combined transfer count (regular + escalation)
--   - Alberta data-availability flag
--
-- Corrections incorporated (per Jonathan's feedback):
--   STEP 1: Past-due count restricted to active, Texas-residential customers only
--   STEP 2: Containment rate rebuilt to real definition (verified + zero-queue calls)
--   STEP 3: Texas/Alberta split by queue, with data-availability flag for pre-2024 gap
--   STEP 4: Regular + escalation transfers combined without double-counting
--   STEP 5: Language field caveat documented separately (not applicable to this dataset)
--   STEP 6: Queue reclassification applied per Jonathan's Teams message
--            (retail-partner/hotline queues treated as Texas; compliance/legacy
--             queues excluded entirely from Care call volume)
--   STEP 7: Active customer count added via event-based net-change calculation
-- ============================================================================

WITH BaselineCount AS (
    -- Customers already active before the dataset window starts (July 1, 2022)
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),

Calendar AS (
    -- STEP: Calendar spine with US holiday flag
    SELECT 
        CAST([Date] AS DATE) AS CallDay, 
        DayName AS Weekday,
        CASE WHEN USHoliday IS NOT NULL THEN 1 ELSE 0 END AS IsHoliday
    FROM vw_calendarWH 
    WHERE [Date] >= '2022-07-01'
),

PastDueActive AS (
    -- STEP 1: Past-due count, active-status filtered
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
),

IVRDaily AS (
    -- STEP 2, 3, 4, 6: Containment rate, Alberta split, transfer combining, queue reclassification
    SELECT 
        CAST(CallDate AS DATE) AS CallDay,
        COUNT(*) AS TexasCalls,
        SUM(CASE WHEN QueueTime > 0 AND AgentTalkTime = 0 THEN 1 ELSE 0 END) AS AbandonedCalls,
        SUM(CASE WHEN QueueTime > 0 THEN 1 ELSE 0 END) AS QueuedCalls,
        AVG(CASE WHEN AgentTalkTime > 0 THEN AgentTalkTime END) AS AvgTalkTime,
        1.0 - (
            CAST(SUM(CASE WHEN QueueTime > 0 THEN 1 ELSE 0 END) AS FLOAT)
            / NULLIF(SUM(CASE WHEN VerificationStatus = 'Verified' OR QueueTime > 0 THEN 1 ELSE 0 END), 0)
        ) AS IVRContainmentRate_Corrected,
        SUM(CASE 
            WHEN TransferToQueue IS NOT NULL 
                 OR (FinalQueue IS NOT NULL AND FinalQueue <> Queue)
            THEN 1 ELSE 0 END) AS TotalTransfers_Combined,
        CASE 
            WHEN CAST(CallDate AS DATE) < '2024-03-20' THEN 'Alberta data not yet available'
            ELSE 'Alberta data available'
        END AS AlbertaDataAvailability
    FROM dbo.IVR
    WHERE Department = 'Care'
        -- Exclude Alberta / other-market queues
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
        -- Exclude queues Jonathan confirmed should be removed entirely from Care call volume
        AND (Queue IS NULL OR Queue NOT IN (
            'JustEnergy_Compliance_Eng',
            'Tara_Compliance_Eng',
            'Terrapass Enrollments ENG SPA',
            'HudsonCommReAffEng-NewYork',
            'Default Route',
            'RoutingErrorFallbackQueue',
            'SharedPool',
            'SharedPool_Spanish',
            'Pre Flow Retention SPA',
            'z_ResiCSENG-COVID19'
        ))
        AND CallDate >= '2022-07-01'
    GROUP BY CAST(CallDate AS DATE)
),

ActiveDelta AS (
    -- STEP 7: Net-change events (enrollment / cancellation) — avoids a slow per-day join
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
)

-- ============================================================================
-- FINAL OUTPUT: one row per day, July 2022 onward
-- ============================================================================
SELECT
    cal.CallDay, 
    cal.Weekday, 
    cal.IsHoliday,
    ISNULL(pd.PastDueCustomerCount_ActiveOnly, 0) AS PastDueCustomerCount_ActiveOnly,
    bc.BaselineCount + ISNULL((
        SELECT SUM(dd.NetChange) 
        FROM DailyDelta dd 
        WHERE dd.EventDate <= cal.CallDay
    ), 0) AS ActiveCustomerCount,
    ivr.TexasCalls, 
    ivr.IVRContainmentRate_Corrected,
    CAST(ivr.AbandonedCalls AS FLOAT) / NULLIF(ivr.QueuedCalls, 0) AS AbandonRate,
    ivr.AvgTalkTime, 
    ivr.TotalTransfers_Combined, 
    ivr.AlbertaDataAvailability
FROM Calendar cal
CROSS JOIN BaselineCount bc
LEFT JOIN PastDueActive pd ON pd.CallDay = cal.CallDay
LEFT JOIN IVRDaily ivr ON ivr.CallDay = cal.CallDay
ORDER BY cal.CallDay;

-- ============================================================================
-- KNOWN LIMITATIONS (documented, not silently ignored):
--   1. Language field on IVR is not reliable as a standalone signal (see Task 4
--      corrections doc) — not used in this dataset, no dependency here.
--   2. Alberta data does not exist before 2024-03-20 — flagged explicitly via
--      AlbertaDataAvailability rather than presented as a real zero.
--   3. USHoliday captures US holidays only; CDNHoliday exists on vw_calendarWH
--      but is not used here since this dataset is Texas-only.
-- ============================================================================




-- ============================================================================
-- TASK 4 + LONG-TERM FORECAST: Full Baseline Rebuild + Blended Day-of-Week Rates
-- South Mass Market & Canada | Texas Residential Care
-- Prepared by: Momna Ali
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
        DayName AS Weekday,
        CASE WHEN USHoliday IS NOT NULL THEN 1 ELSE 0 END AS IsHoliday
    FROM vw_calendarWH 
    WHERE [Date] >= '2022-07-01'
),

PastDueActive AS (
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
),

IVRDaily AS (
    SELECT 
        CAST(CallDate AS DATE) AS CallDay,
        COUNT(*) AS TexasCalls,
        SUM(CASE WHEN QueueTime > 0 AND AgentTalkTime = 0 THEN 1 ELSE 0 END) AS AbandonedCalls,
        SUM(CASE WHEN QueueTime > 0 THEN 1 ELSE 0 END) AS QueuedCalls,
        AVG(CASE WHEN AgentTalkTime > 0 THEN AgentTalkTime END) AS AvgTalkTime,
        1.0 - (
            CAST(SUM(CASE WHEN QueueTime > 0 THEN 1 ELSE 0 END) AS FLOAT)
            / NULLIF(SUM(CASE WHEN VerificationStatus = 'Verified' OR QueueTime > 0 THEN 1 ELSE 0 END), 0)
        ) AS IVRContainmentRate_Corrected,
        SUM(CASE 
            WHEN TransferToQueue IS NOT NULL 
                 OR (FinalQueue IS NOT NULL AND FinalQueue <> Queue)
            THEN 1 ELSE 0 END) AS TotalTransfers_Combined,
        CASE 
            WHEN CAST(CallDate AS DATE) < '2024-03-20' THEN 'Alberta data not yet available'
            ELSE 'Alberta data available'
        END AS AlbertaDataAvailability
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
        AND (Queue IS NULL OR Queue NOT IN (
            'JustEnergy_Compliance_Eng',
            'Tara_Compliance_Eng',
            'Terrapass Enrollments ENG SPA',
            'HudsonCommReAffEng-NewYork',
            'Default Route',
            'RoutingErrorFallbackQueue',
            'SharedPool',
            'SharedPool_Spanish',
            'Pre Flow Retention SPA',
            'z_ResiCSENG-COVID19'
        ))
        AND CallDate >= '2022-07-01'
    GROUP BY CAST(CallDate AS DATE)
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

FullHistory AS (
    SELECT
        cal.CallDay, 
        cal.Weekday, 
        cal.IsHoliday,
        ISNULL(pd.PastDueCustomerCount_ActiveOnly, 0) AS PastDueCustomerCount_ActiveOnly,
        bc.BaselineCount + ISNULL((
            SELECT SUM(dd.NetChange) 
            FROM DailyDelta dd 
            WHERE dd.EventDate <= cal.CallDay
        ), 0) AS ActiveCustomerCount,
        ivr.TexasCalls, 
        ivr.IVRContainmentRate_Corrected,
        CAST(ivr.AbandonedCalls AS FLOAT) / NULLIF(ivr.QueuedCalls, 0) AS AbandonRate,
        ivr.AvgTalkTime, 
        ivr.TotalTransfers_Combined, 
        ivr.AlbertaDataAvailability
    FROM Calendar cal
    CROSS JOIN BaselineCount bc
    LEFT JOIN PastDueActive pd ON pd.CallDay = cal.CallDay
    LEFT JOIN IVRDaily ivr ON ivr.CallDay = cal.CallDay
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
        AND CallDate >= '2025-01-01'
    GROUP BY CAST(CallDate AS DATE)
),

Recomputed2526 AS (
    SELECT
        DATEPART(WEEKDAY, fh.CallDay) AS DayNum,
        DATENAME(WEEKDAY, fh.CallDay) AS DayOfWeek,
        AVG(CAST(ISNULL(fc.AgentHandledCalls, 0) AS FLOAT)) / NULLIF(AVG(CAST(fh.ActiveCustomerCount AS FLOAT)), 0) * 1000 AS NewRatePer1000
    FROM FullHistory fh
    LEFT JOIN FilteredCalls fc ON fc.CallDay = fh.CallDay
    WHERE fh.IsHoliday = 0
        AND fh.CallDay >= '2025-01-01'
    GROUP BY DATENAME(WEEKDAY, fh.CallDay), DATEPART(WEEKDAY, fh.CallDay)
),

Task1Original AS (
    SELECT * FROM (VALUES
        (2, 'Monday',    6.958),
        (3, 'Tuesday',   5.498),
        (4, 'Wednesday', 5.183),
        (5, 'Thursday',  4.462),
        (6, 'Friday',    4.223),
        (7, 'Saturday',  1.794),
        (1, 'Sunday',    0.000)
    ) AS t(DayNum, DayOfWeek, OriginalRatePer1000)
)

-- ============================================================================
-- STEP 9 FINAL OUTPUT: Blended day-of-week forecast rates
-- 40% weight to Task 1's original 39-day rates, 60% weight to corrected 2025-2026 rates
-- ============================================================================
SELECT
    t1.DayNum,
    t1.DayOfWeek,
    t1.OriginalRatePer1000,
    r.NewRatePer1000,
    ROUND((t1.OriginalRatePer1000 * 0.4) + (r.NewRatePer1000 * 0.6), 3) AS BlendedRatePer1000
FROM Task1Original t1
JOIN Recomputed2526 r ON r.DayNum = t1.DayNum
ORDER BY t1.DayNum;

-- ============================================================================
-- KNOWN LIMITATIONS (documented, not silently ignored):
--   1. Language field on IVR is not reliable as a standalone signal — not used here.
--   2. Alberta data does not exist before 2024-03-20 — flagged via AlbertaDataAvailability.
--   3. USHoliday captures US holidays only; CDNHoliday exists on vw_calendarWH but
--      is not used here since this dataset is Texas-only.
--   4. Blend weighting (40/60) is a starting assumption, not a statistically derived
--      optimum — flag to Jonathan as an open question if he wants a different split.
-- ============================================================================


-- ============================================================================
-- FORECAST-VS-ACTUALS TRACKING VIEW
-- Compares blended day-of-week forecast against actual observed call volume
-- ============================================================================

CREATE OR ALTER VIEW dbo.vw_ForecastVsActuals AS

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
        DayName AS Weekday,
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
        cal.Weekday,
        cal.IsHoliday,
        bc.BaselineCount + ISNULL((
            SELECT SUM(dd.NetChange) 
            FROM DailyDelta dd 
            WHERE dd.EventDate <= cal.CallDay
        ), 0) AS ActiveCustomerCount
    FROM Calendar cal
    CROSS JOIN BaselineCount bc
),

ActualCalls AS (
    SELECT
        CAST(CallDate AS DATE) AS CallDay,
        COUNT(*) AS ActualCalls
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND CallType IN ('Inbound', 'Transfer')
        AND AgentTalkTime > 0
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
        AND CallDate >= '2022-07-01'
    GROUP BY CAST(CallDate AS DATE)
),

BlendedRates AS (
    SELECT * FROM (VALUES
        (1, 'Sunday',    0.000),
        (2, 'Monday',    7.814),
        (3, 'Tuesday',   6.513),
        (4, 'Wednesday', 5.872),
        (5, 'Thursday',  5.188),
        (6, 'Friday',    5.397),
        (7, 'Saturday',  2.162)
    ) AS t(DayNum, DayOfWeek, BlendedRatePer1000)
)

SELECT
    da.CallDay,
    da.Weekday,
    da.IsHoliday,
    da.ActiveCustomerCount,
    br.BlendedRatePer1000,
    ROUND((br.BlendedRatePer1000 / 1000.0) * da.ActiveCustomerCount, 0) AS ForecastedCalls,
    ISNULL(ac.ActualCalls, 0) AS ActualCalls,
    ISNULL(ac.ActualCalls, 0) - ROUND((br.BlendedRatePer1000 / 1000.0) * da.ActiveCustomerCount, 0) AS Variance,
    CASE 
        WHEN ROUND((br.BlendedRatePer1000 / 1000.0) * da.ActiveCustomerCount, 0) = 0 THEN NULL
        ELSE ROUND(
            (ISNULL(ac.ActualCalls, 0) - ROUND((br.BlendedRatePer1000 / 1000.0) * da.ActiveCustomerCount, 0)) 
            / ROUND((br.BlendedRatePer1000 / 1000.0) * da.ActiveCustomerCount, 0) * 100.0
        , 1)
    END AS VariancePct
FROM DailyActive da
JOIN BlendedRates br ON br.DayNum = DATEPART(WEEKDAY, da.CallDay)
LEFT JOIN ActualCalls ac ON ac.CallDay = da.CallDay;

-- STEP 10: Check recent forecast accuracy (last 30 days)
SELECT *
FROM dbo.vw_ForecastVsActuals
WHERE CallDay >= DATEADD(DAY, -30, GETDATE())
ORDER BY CallDay;

