
-- check if balance filter explains drop in unique users in commision

-- See currnet list (567)
select count(DISTINCT(unique_id)) 
from metrics.user_activity_stats

-- See previous list
-- Note if you add extran where criteria to remove balance then users drop
WITH daily_agg AS (
    SELECT date, unique_id, COUNT(*) AS transactions
    FROM metrics.transaction_idx
    WHERE unique_id IS NOT NULL
    GROUP BY date, unique_id
),

-- list of distinct unique ids
users AS (
    SELECT DISTINCT (unique_id) from daily_agg
)

select count(*)
from users
