-- STEP 3: Daily active Texas Residential customer count
WITH Ones AS (
    SELECT v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS t(v)
),
Tens AS (
    SELECT v FROM (VALUES (0),(10),(20),(30),(40),(50),(60)) AS t(v)
),
Numbers AS (
    SELECT o.v + t.v AS n
    FROM Ones o
    CROSS JOIN Tens t
    WHERE o.v + t.v <= 60
),
DateRange AS (
    SELECT DATEADD(DAY, n, CAST('2026-06-01' AS DATE)) AS the_date
    FROM Numbers
)
SELECT
    d.the_date,
    COUNT(c.cust_id) AS active_customers
FROM DateRange d
LEFT JOIN dbo.iSigma_Customer_Master c
    ON c.Market = 'Texas'
    AND c.CustomerType = 'Residential'
    AND c.FlowStart IS NOT NULL
    AND d.the_date >= c.FlowStart
    AND (d.the_date <= c.FlowEnd OR c.FlowEnd IS NULL)
GROUP BY d.the_date
ORDER BY d.the_date;



-- STEP 4: Daily agent call volume (Texas-scoped, same date range)
SELECT
    CAST(CallDate AS DATE) AS the_date,
    COUNT(*) AS total_calls
FROM dbo.IVR
WHERE Department = 'Care'
    AND CallType IN ('Inbound','Transfer')
    AND AgentTalkTime > 0
    AND CallDate >= '2026-06-01'
    AND CallDate < '2026-08-01'
    AND (Queue IS NULL
         OR Queue NOT LIKE '%Alberta%'
         AND Queue NOT LIKE '%California%'
         AND Queue NOT LIKE '%NorthCanada%')
GROUP BY CAST(CallDate AS DATE)
ORDER BY the_date;



-- STEP 5: Calls per 1,000 active customers per day (Sundays included as true zero)
WITH Ones AS (
    SELECT v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS t(v)
),
Tens AS (
    SELECT v FROM (VALUES (0),(10),(20),(30),(40),(50),(60)) AS t(v)
),
Numbers AS (
    SELECT o.v + t.v AS n
    FROM Ones o CROSS JOIN Tens t
    WHERE o.v + t.v <= 60
),
DateRange AS (
    SELECT DATEADD(DAY, n, CAST('2026-06-01' AS DATE)) AS the_date
    FROM Numbers
),
ActiveCustomers AS (
    SELECT d.the_date, COUNT(c.cust_id) AS active_customers
    FROM DateRange d
    LEFT JOIN dbo.iSigma_Customer_Master c
        ON c.Market = 'Texas'
        AND c.CustomerType = 'Residential'
        AND c.FlowStart IS NOT NULL
        AND d.the_date >= c.FlowStart
        AND (d.the_date <= c.FlowEnd OR c.FlowEnd IS NULL)
    GROUP BY d.the_date
),
CallVolume AS (
    SELECT CAST(CallDate AS DATE) AS the_date, COUNT(*) AS total_calls
    FROM dbo.IVR
    WHERE Department = 'Care'
        AND CallType IN ('Inbound','Transfer')
        AND AgentTalkTime > 0
        AND CallDate >= '2026-06-01'
        AND CallDate < '2026-08-01'
        AND (Queue IS NULL
             OR (Queue NOT LIKE '%Alberta%'
                 AND Queue NOT LIKE '%California%'
                 AND Queue NOT LIKE '%NorthCanada%'))
    GROUP BY CAST(CallDate AS DATE)
)
SELECT
    ac.the_date,
    DATENAME(WEEKDAY, ac.the_date) AS day_name,
    ac.active_customers,
    COALESCE(cv.total_calls, 0) AS total_calls,
    ROUND(COALESCE(cv.total_calls, 0) * 1000.0 / NULLIF(ac.active_customers, 0), 3) AS calls_per_1000
FROM ActiveCustomers ac
LEFT JOIN CallVolume cv ON ac.the_date = cv.the_date
ORDER BY ac.the_date;
