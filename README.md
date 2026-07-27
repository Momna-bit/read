	
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





-- STEP 1 (Long-Term Forecast): Recompute day-of-week rates using full corrected history
WITH BaselineCount AS (
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),
Calendar AS (
    SELECT CAST([Date] AS DATE) AS CallDay, DayName AS Weekday,
        CASE WHEN USHoliday IS NOT NULL THEN 1 ELSE 0 END AS IsHoliday
    FROM vw_calendarWH WHERE [Date] >= '2022-07-01'
),
IVRDaily AS (
    SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS TexasCalls
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
        AND (Queue IS NULL OR Queue NOT IN (
            'JustEnergy_Compliance_Eng','Tara_Compliance_Eng','Terrapass Enrollments ENG SPA',
            'HudsonCommReAffEng-NewYork','Default Route','RoutingErrorFallbackQueue',
            'SharedPool','SharedPool_Spanish','Pre Flow Retention SPA','z_ResiCSENG-COVID19'
        ))
        AND CallDate >= '2022-07-01'
    GROUP BY CAST(CallDate AS DATE)
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
DailyDelta AS (
    SELECT EventDate, SUM(Delta) AS NetChange FROM ActiveDelta GROUP BY EventDate
),
FullHistory AS (
    SELECT
        cal.CallDay, cal.Weekday, cal.IsHoliday,
        bc.BaselineCount + ISNULL((SELECT SUM(dd.NetChange) FROM DailyDelta dd WHERE dd.EventDate <= cal.CallDay), 0) AS ActiveCustomerCount,
        ivr.TexasCalls
    FROM Calendar cal
    CROSS JOIN BaselineCount bc
    LEFT JOIN IVRDaily ivr ON ivr.CallDay = cal.CallDay
    WHERE cal.CallDay < CAST(GETDATE() AS DATE)  -- only completed days
)
SELECT
    Weekday,
    COUNT(*) AS DaysObserved,
    AVG(CAST(TexasCalls AS FLOAT) / NULLIF(ActiveCustomerCount, 0) * 1000) AS AvgCallsPer1000_NonHoliday
FROM FullHistory
WHERE IsHoliday = 0  -- exclude holidays, since Task 1 found these are a known weak spot
    AND TexasCalls IS NOT NULL
GROUP BY Weekday
ORDER BY 
    CASE Weekday 
        WHEN 'Sunday' THEN 1 WHEN 'Monday' THEN 2 WHEN 'Tuesday' THEN 3 
        WHEN 'Wednesday' THEN 4 WHEN 'Thursday' THEN 5 WHEN 'Friday' THEN 6 WHEN 'Saturday' THEN 7 
    END;


-- STEP 1 (corrected): Day-of-week rates, matching Task 1's original call definition
WITH BaselineCount AS (
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),
Calendar AS (
    SELECT CAST([Date] AS DATE) AS CallDay, DayName AS Weekday,
        CASE WHEN USHoliday IS NOT NULL THEN 1 ELSE 0 END AS IsHoliday
    FROM vw_calendarWH WHERE [Date] >= '2022-07-01'
),
IVRDaily AS (
    SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS TexasCalls
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND CallType IN ('Inbound','Transfer')
        AND AgentTalkTime > 0
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
        AND (Queue IS NULL OR Queue NOT IN (
            'JustEnergy_Compliance_Eng','Tara_Compliance_Eng','Terrapass Enrollments ENG SPA',
            'HudsonCommReAffEng-NewYork','Default Route','RoutingErrorFallbackQueue',
            'SharedPool','SharedPool_Spanish','Pre Flow Retention SPA','z_ResiCSENG-COVID19'
        ))
        AND CallDate >= '2022-07-01'
    GROUP BY CAST(CallDate AS DATE)
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
DailyDelta AS (
    SELECT EventDate, SUM(Delta) AS NetChange FROM ActiveDelta GROUP BY EventDate
),
FullHistory AS (
    SELECT
        cal.CallDay, cal.Weekday, cal.IsHoliday,
        bc.BaselineCount + ISNULL((SELECT SUM(dd.NetChange) FROM DailyDelta dd WHERE dd.EventDate <= cal.CallDay), 0) AS ActiveCustomerCount,
        ivr.TexasCalls
    FROM Calendar cal
    CROSS JOIN BaselineCount bc
    LEFT JOIN IVRDaily ivr ON ivr.CallDay = cal.CallDay
    WHERE cal.CallDay < CAST(GETDATE() AS DATE)
)
SELECT
    Weekday,
    COUNT(*) AS DaysObserved,
    AVG(CAST(ISNULL(TexasCalls,0) AS FLOAT) / NULLIF(ActiveCustomerCount, 0) * 1000) AS AvgCallsPer1000_NonHoliday
FROM FullHistory
WHERE IsHoliday = 0
GROUP BY Weekday
ORDER BY 
    CASE Weekday 
        WHEN 'Sunday' THEN 1 WHEN 'Monday' THEN 2 WHEN 'Tuesday' THEN 3 
        WHEN 'Wednesday' THEN 4 WHEN 'Thursday' THEN 5 WHEN 'Friday' THEN 6 WHEN 'Saturday' THEN 7 
    END;


-- Sanity check: pull raw numbers for one specific day to manually verify the rate
SELECT 
    COUNT(*) AS RawCallCount
FROM dbo.IVR
WHERE Department = 'Care'
    AND CallType IN ('Inbound','Transfer')
    AND AgentTalkTime > 0
    AND CallDate >= '2026-07-01' AND CallDate < '2026-07-02'
    AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
    AND (Queue IS NULL OR Queue NOT IN (
        'JustEnergy_Compliance_Eng','Tara_Compliance_Eng','Terrapass Enrollments ENG SPA',
        'HudsonCommReAffEng-NewYork','Default Route','RoutingErrorFallbackQueue',
        'SharedPool','SharedPool_Spanish','Pre Flow Retention SPA','z_ResiCSENG-COVID19'
    ));



-- Diagnostic (fixed): average rate by year, computed via a clean intermediate CTE
WITH BaselineCount AS (
    SELECT COUNT(*) AS BaselineCount
    FROM iSigma_Customer_Master
    WHERE Market = 'Texas' AND CustomerType = 'Residential'
        AND FlowStart < '2022-07-01'
        AND (FlowEnd IS NULL OR FlowEnd >= '2022-07-01')
),
Calendar AS (
    SELECT CAST([Date] AS DATE) AS CallDay,
        CASE WHEN USHoliday IS NOT NULL THEN 1 ELSE 0 END AS IsHoliday
    FROM vw_calendarWH WHERE [Date] >= '2022-07-01'
),
IVRDaily AS (
    SELECT CAST(CallDate AS DATE) AS CallDay, COUNT(*) AS TexasCalls
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND CallType IN ('Inbound','Transfer')
        AND AgentTalkTime > 0
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
        AND (Queue IS NULL OR Queue NOT IN (
            'JustEnergy_Compliance_Eng','Tara_Compliance_Eng','Terrapass Enrollments ENG SPA',
            'HudsonCommReAffEng-NewYork','Default Route','RoutingErrorFallbackQueue',
            'SharedPool','SharedPool_Spanish','Pre Flow Retention SPA','z_ResiCSENG-COVID19'
        ))
        AND CallDate >= '2022-07-01'
    GROUP BY CAST(CallDate AS DATE)
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
DailyDelta AS (
    SELECT EventDate, SUM(Delta) AS NetChange FROM ActiveDelta GROUP BY EventDate
),
FullHistory AS (
    SELECT
        cal.CallDay,
        cal.IsHoliday,
        bc.BaselineCount + ISNULL((SELECT SUM(dd.NetChange) FROM DailyDelta dd WHERE dd.EventDate <= cal.CallDay), 0) AS ActiveCustomerCount,
        ISNULL(ivr.TexasCalls, 0) AS TexasCalls
    FROM Calendar cal
    CROSS JOIN BaselineCount bc
    LEFT JOIN IVRDaily ivr ON ivr.CallDay = cal.CallDay
)
SELECT
    YEAR(CallDay) AS CallYear,
    COUNT(*) AS DaysObserved,
    AVG(CAST(ActiveCustomerCount AS FLOAT)) AS AvgActiveCustomers,
    AVG(CAST(TexasCalls AS FLOAT)) AS AvgDailyCalls,
    AVG(CAST(TexasCalls AS FLOAT) / NULLIF(ActiveCustomerCount, 0) * 1000) AS AvgRatePer1000
FROM FullHistory
WHERE IsHoliday = 0
GROUP BY YEAR(CallDay)
ORDER BY CallYear;


-- STEP 5a: Confirm actual column names in dbo.IVR
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
    AND TABLE_NAME = 'IVR'
ORDER BY ORDINAL_POSITION;
