-- ============================================================
-- INTERVAL FORECAST REBUILD — ENG vs. SPA Aggregation
-- Follow-up task from Jonathan (8/19 meeting): "Backtest and compare
-- forecast accuracy at 15-minute versus 30-minute intervals for
-- English and Spanish frontline Texas queues, prepare side-by-side
-- results for review with Lou."
--
-- Also implements Jonathan's earlier scope redirect: aggregate to
-- ENG vs. SPA level only (not per-queue), filtered to
-- CallType IN ('Inbound', 'Transfer') only.
-- ============================================================

-- ------------------------------------------------------------
-- CLEANUP: drop leftover temp tables from any previous run
-- ------------------------------------------------------------
IF OBJECT_ID('tempdb..#IVRRaw') IS NOT NULL DROP TABLE #IVRRaw;
IF OBJECT_ID('tempdb..#IVR15min') IS NOT NULL DROP TABLE #IVR15min;
IF OBJECT_ID('tempdb..#IVR30min') IS NOT NULL DROP TABLE #IVR30min;

-- ------------------------------------------------------------
-- STEP 0 (ALREADY DONE): Real dbo.IVR column names confirmed:
-- CallDate, Queue, CallType, Language. No need to re-run this
-- verification — the query below is already updated to match.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- STEP 1: Pull raw call-level records for the 17 confirmed Texas
-- South Care queues, filtered to Inbound/Transfer only (excludes
-- outbound-campaign-driven queues per Jonathan's redirect).
--
-- CONFIRMED real column names (checked against dbo.IVR directly):
--   CallDate  — the call timestamp (was guessed as CallDateTime)
--   Queue     — the queue name field (was guessed as QueueName)
--   CallType  — confirmed correct as originally guessed
--   Language  — a REAL column already exists for this, so there's
--               no need to guess ENG/SPA from the queue name at
--               all. Using the real field directly below.
-- ------------------------------------------------------------
SELECT
      Queue
    , CallDate
    , CallType
    , Language
INTO #IVRRaw
FROM Analytics_ConstellationWH.dbo.IVR
WHERE CallType IN ('Inbound', 'Transfer')
    AND Queue IN (
        -- Paste the 17 confirmed real queue names here, exactly as
        -- they appear in dbo.IVR (minor naming/spacing differences
        -- were already reconciled during the original validation —
        -- reuse that confirmed list rather than re-guessing).
        'PLACEHOLDER_QUEUE_1',
        'PLACEHOLDER_QUEUE_2'
        -- ... remaining confirmed queue names
    );

-- Plain English: pulls every individual Inbound/Transfer call
-- record for the confirmed queue list, keeping the real Language
-- field as-is rather than guessing it from the queue name.

-- WORTH CHECKING: run this once to see what values actually exist
-- in the Language column before trusting it downstream — e.g.
-- confirm it's consistently 'ENG'/'SPA' (or similar) and not
-- inconsistently populated or NULL for some rows:
--   SELECT DISTINCT Language, COUNT(*) FROM #IVRRaw GROUP BY Language;


-- ------------------------------------------------------------
-- STEP 2: Aggregate to 15-minute buckets, by language only (not
-- per-queue) — this is the core of Jonathan's redirect.
-- ------------------------------------------------------------
SELECT
      Language
    , DATEADD(MINUTE, (DATEDIFF(MINUTE, CAST('1900-01-01' AS datetime2(0)), CallDate) / 15) * 15, CAST('1900-01-01' AS datetime2(0))) AS Interval15Min
    , COUNT(*) AS CallCount
INTO #IVR15min
FROM #IVRRaw
GROUP BY
      Language
    , DATEADD(MINUTE, (DATEDIFF(MINUTE, CAST('1900-01-01' AS datetime2(0)), CallDate) / 15) * 15, CAST('1900-01-01' AS datetime2(0)));

-- Plain English: rounds each call's timestamp down to the nearest
-- 15-minute mark, then counts how many ENG calls and how many SPA
-- calls happened in each 15-minute window.


-- ------------------------------------------------------------
-- STEP 3: Aggregate to 30-minute buckets, same logic, for the
-- side-by-side comparison.
-- ------------------------------------------------------------
SELECT
      Language
    , DATEADD(MINUTE, (DATEDIFF(MINUTE, CAST('1900-01-01' AS datetime2(0)), CallDate) / 30) * 30, CAST('1900-01-01' AS datetime2(0))) AS Interval30Min
    , COUNT(*) AS CallCount
INTO #IVR30min
FROM #IVRRaw
GROUP BY
      Language
    , DATEADD(MINUTE, (DATEDIFF(MINUTE, CAST('1900-01-01' AS datetime2(0)), CallDate) / 30) * 30, CAST('1900-01-01' AS datetime2(0)));


-- ------------------------------------------------------------
-- STEP 4: Final export — run each of these separately and export
-- both (SSMS "Save Results As CSV", add header row, plain UTF-8,
-- no BOM — same as every other pull on this project).
-- ------------------------------------------------------------
SELECT * FROM #IVR15min ORDER BY Language, Interval15Min ASC;
-- SELECT * FROM #IVR30min ORDER BY Language, Interval30Min ASC;  -- run this one separately

-- ------------------------------------------------------------
-- NEXT STEP AFTER EXPORTING BOTH:
-- Feed both CSVs into the same backtest pipeline used for the
-- original per-queue analysis (zero-fill missing intervals →
-- day-of-week/time-slot baseline → leave-one-out backtest), run
-- separately for ENG and SPA, at both 15-min and 30-min. That
-- gives the real side-by-side comparison Jonathan and Lou asked
-- for, at the new aggregation level.
-- ------------------------------------------------------------
