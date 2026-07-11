-- STEP 6: Day-of-week averages (using only real, completed data through July 9)
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
    WHERE DATEADD(DAY, n, CAST('2026-06-01' AS DATE)) <= '2026-07-09'
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
        AND CallDate < '2026-07-10'
        AND (Queue IS NULL
             OR (Queue NOT LIKE '%Alberta%'
                 AND Queue NOT LIKE '%California%'
                 AND Queue NOT LIKE '%NorthCanada%'))
    GROUP BY CAST(CallDate AS DATE)
),
Daily AS (
    SELECT
        ac.the_date,
        DATENAME(WEEKDAY, ac.the_date) AS day_name,
        ac.active_customers,
        COALESCE(cv.total_calls, 0) AS total_calls,
        COALESCE(cv.total_calls, 0) * 1000.0 / NULLIF(ac.active_customers, 0) AS calls_per_1000
    FROM ActiveCustomers ac
    LEFT JOIN CallVolume cv ON ac.the_date = cv.the_date
)
SELECT
    day_name,
    COUNT(*) AS days_counted,
    ROUND(AVG(calls_per_1000), 3) AS avg_calls_per_1000,
    ROUND(MIN(calls_per_1000), 3) AS min_calls_per_1000,
    ROUND(MAX(calls_per_1000), 3) AS max_calls_per_1000
FROM Daily
GROUP BY day_name
ORDER BY avg_calls_per_1000 DESC;



-- STEP 7: Forecast for the next 14 days using the day-of-week rates
WITH DayRates AS (
    SELECT day_name, avg_calls_per_1000
    FROM (
        VALUES
            ('Monday', 6.959),
            ('Tuesday', 5.498),
            ('Wednesday', 5.183),
            ('Thursday', 4.407),
            ('Friday', 4.223),
            ('Saturday', 1.793),
            ('Sunday', 0.000)
    ) AS t(day_name, avg_calls_per_1000)
),
Ones AS (SELECT v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS t(v)),
Numbers AS (SELECT v AS n FROM Ones),
ForecastDates AS (
    SELECT DATEADD(DAY, n, CAST('2026-07-11' AS DATE)) AS the_date
    FROM Numbers
    WHERE n <= 13
)
SELECT
    f.the_date,
    DATENAME(WEEKDAY, f.the_date) AS day_name,
    639000 AS assumed_active_customers,
    dr.avg_calls_per_1000,
    ROUND(639000 * dr.avg_calls_per_1000 / 1000.0, 0) AS predicted_calls
FROM ForecastDates f
JOIN DayRates dr ON dr.day_name = DATENAME(WEEKDAY, f.the_date)
ORDER BY f.the_date;



-- STEP 8: Predicted vs actual accuracy check (using real historical data)
WITH DayRates AS (
    SELECT day_name, avg_calls_per_1000
    FROM (VALUES
        ('Monday', 6.959), ('Tuesday', 5.498), ('Wednesday', 5.183),
        ('Thursday', 4.407), ('Friday', 4.223), ('Saturday', 1.793), ('Sunday', 0.000)
    ) AS t(day_name, avg_calls_per_1000)
),
Ones AS (SELECT v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS t(v)),
Tens AS (SELECT v FROM (VALUES (0),(10),(20),(30),(40),(50),(60)) AS t(v)),
Numbers AS (SELECT o.v + t.v AS n FROM Ones o CROSS JOIN Tens t WHERE o.v + t.v <= 38),
DateRange AS (SELECT DATEADD(DAY, n, CAST('2026-06-01' AS DATE)) AS the_date FROM Numbers),
ActiveCustomers AS (
    SELECT d.the_date, COUNT(c.cust_id) AS active_customers
    FROM DateRange d
    LEFT JOIN dbo.iSigma_Customer_Master c
        ON c.Market = 'Texas' AND c.CustomerType = 'Residential'
        AND c.FlowStart IS NOT NULL
        AND d.the_date >= c.FlowStart
        AND (d.the_date <= c.FlowEnd OR c.FlowEnd IS NULL)
    GROUP BY d.the_date
),
ActualCalls AS (
    SELECT CAST(CallDate AS DATE) AS the_date, COUNT(*) AS actual_calls
    FROM dbo.IVR
    WHERE Department = 'Care' AND CallType IN ('Inbound','Transfer') AND AgentTalkTime > 0
        AND CallDate >= '2026-06-01' AND CallDate < '2026-07-10'
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
    GROUP BY CAST(CallDate AS DATE)
)
SELECT
    ac.the_date,
    DATENAME(WEEKDAY, ac.the_date) AS day_name,
    COALESCE(act.actual_calls, 0) AS actual_calls,
    ROUND(ac.active_customers * dr.avg_calls_per_1000 / 1000.0, 0) AS predicted_calls,
    ROUND(COALESCE(act.actual_calls, 0) - (ac.active_customers * dr.avg_calls_per_1000 / 1000.0), 0) AS error,
    ROUND(ABS(COALESCE(act.actual_calls, 0) - (ac.active_customers * dr.avg_calls_per_1000 / 1000.0)) * 100.0
        / NULLIF(COALESCE(act.actual_calls, 0), 0), 1) AS pct_error
FROM ActiveCustomers ac
JOIN DayRates dr ON dr.day_name = DATENAME(WEEKDAY, ac.the_date)
LEFT JOIN ActualCalls act ON ac.the_date = act.the_date
ORDER BY ac.the_date;



-- Quick summary: average % error, excluding the July 4-8 holiday disruption
WITH DayRates AS (
    SELECT day_name, avg_calls_per_1000
    FROM (VALUES
        ('Monday', 6.959), ('Tuesday', 5.498), ('Wednesday', 5.183),
        ('Thursday', 4.407), ('Friday', 4.223), ('Saturday', 1.793), ('Sunday', 0.000)
    ) AS t(day_name, avg_calls_per_1000)
),
Ones AS (SELECT v FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS t(v)),
Tens AS (SELECT v FROM (VALUES (0),(10),(20),(30),(40),(50),(60)) AS t(v)),
Numbers AS (SELECT o.v + t.v AS n FROM Ones o CROSS JOIN Tens t WHERE o.v + t.v <= 38),
DateRange AS (SELECT DATEADD(DAY, n, CAST('2026-06-01' AS DATE)) AS the_date FROM Numbers),
ActiveCustomers AS (
    SELECT d.the_date, COUNT(c.cust_id) AS active_customers
    FROM DateRange d
    LEFT JOIN dbo.iSigma_Customer_Master c
        ON c.Market = 'Texas' AND c.CustomerType = 'Residential'
        AND c.FlowStart IS NOT NULL
        AND d.the_date >= c.FlowStart
        AND (d.the_date <= c.FlowEnd OR c.FlowEnd IS NULL)
    GROUP BY d.the_date
),
ActualCalls AS (
    SELECT CAST(CallDate AS DATE) AS the_date, COUNT(*) AS actual_calls
    FROM dbo.IVR
    WHERE Department = 'Care' AND CallType IN ('Inbound','Transfer') AND AgentTalkTime > 0
        AND CallDate >= '2026-06-01' AND CallDate < '2026-07-10'
        AND (Queue IS NULL OR (Queue NOT LIKE '%Alberta%' AND Queue NOT LIKE '%California%' AND Queue NOT LIKE '%NorthCanada%'))
    GROUP BY CAST(CallDate AS DATE)
)
SELECT
    ROUND(AVG(ABS(act.actual_calls - (ac.active_customers * dr.avg_calls_per_1000/1000.0))
        * 100.0 / NULLIF(act.actual_calls,0)), 1) AS avg_pct_error_excl_holiday
FROM ActiveCustomers ac
JOIN DayRates dr ON dr.day_name = DATENAME(WEEKDAY, ac.the_date)
JOIN ActualCalls act ON ac.the_date = act.the_date
WHERE ac.the_date NOT BETWEEN '2026-07-04' AND '2026-07-08';
