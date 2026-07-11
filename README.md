-- A) What values does Instance take? (the multi-instance issue Jonathan flagged)
SELECT Instance, COUNT(*) AS customers
FROM dbo.iSigma_Customer_Master
GROUP BY Instance;

-- B) What values does Market take?
SELECT Market, COUNT(*) AS customers
FROM dbo.iSigma_Customer_Master
GROUP BY Market
ORDER BY customers DESC;

-- C) What values does CustomerType take?
SELECT CustomerType, COUNT(*) AS customers
FROM dbo.iSigma_Customer_Master
GROUP BY CustomerType
ORDER BY customers DESC;

-- D) How many rows have a null FlowStart? (the "pre-flow cancels" junk Jonathan warned about)
SELECT
    SUM(CASE WHEN FlowStart IS NULL THEN 1 ELSE 0 END) AS null_flowstart,
    SUM(CASE WHEN FlowStart IS NOT NULL THEN 1 ELSE 0 END) AS has_flowstart,
    COUNT(*) AS total_rows
FROM dbo.iSigma_Customer_Master;

-- E) Date range sanity check
SELECT MIN(FlowStart) AS earliest_start, MAX(FlowStart) AS latest_start,
       MIN(FlowEnd) AS earliest_end, MAX(FlowEnd) AS latest_end,
       SUM(CASE WHEN FlowEnd IS NULL THEN 1 ELSE 0 END) AS still_active_null_end
FROM dbo.iSigma_Customer_Master;
