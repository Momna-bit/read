-- F) Check for sentinel dates hiding among "non-null" rows, scoped to what we'll actually use
SELECT
    SUM(CASE WHEN FlowStart IS NULL THEN 1 ELSE 0 END) AS null_flowstart,
    SUM(CASE WHEN FlowStart = '1900-01-01' THEN 1 ELSE 0 END) AS sentinel_1900_flowstart,
    SUM(CASE WHEN FlowStart IS NOT NULL AND FlowStart <> '1900-01-01' THEN 1 ELSE 0 END) AS valid_flowstart,
    COUNT(*) AS total_rows
FROM dbo.iSigma_Customer_Master
WHERE Market = 'Texas' AND CustomerType = 'Residential';

-- G) Check what FlowEnd values are most common (looking for a recurring "sentinel" future date)
SELECT TOP 10 FlowEnd, COUNT(*) AS cnt
FROM dbo.iSigma_Customer_Master
WHERE Market = 'Texas' AND CustomerType = 'Residential' AND FlowEnd IS NOT NULL
GROUP BY FlowEnd
ORDER BY cnt DESC;
