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



SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'vw_calendarWH';


SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'iSigma_Customer_Notices';



SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'JESouth_CollectionAR_DailyDue';


SELECT DISTINCT [call.reason]
FROM Care_CallAI
WHERE [call.reason] LIKE '%autopay%' OR [call.reason] LIKE '%auto pay%' OR [call.reason] LIKE '%recurring%';

