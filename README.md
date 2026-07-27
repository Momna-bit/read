	
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
