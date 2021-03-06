-- Get max date in data set
with max_date as (
    select max(date)
    from metrics.user_activity_stats
),


-- Calculate Assessment type, based on days actice
df_assessment_type as (
select 
    CASE
        WHEN age +1 < 7 THEN 'under_7_days_unassigned'
        WHEN age +1 < 28 THEN 'under_28_days_prorated'
        ELSE '28_days' 
    END AS assessment_type,
    *
from max_date
join metrics.user_activity_stats on max_date.max = metrics.user_activity_stats.date
order by age
), 

-- Cacluate Average performace on Commission metrics
df_assessment_type_calcs as (
select 
    -- Cacluate Av Tran per day, Calc used depends on Assessment type
    CASE
        WHEN assessment_type = '28_days' THEN (transactions_4wks / 28)
        WHEN assessment_type = 'under_28_days_prorated' THEN (transactions_4wks / (age+1))
        WHEN assessment_type = 'under_7_days_unassigned' THEN (transactions_4wks / (age+1))
        ELSE 0
    END AS averge_tx_per_day_in_period,
    -- Caclulate Active rate, Calc used depends on Assessment type
    CASE
        WHEN assessment_type = '28_days' THEN ndays_4wks / (age - age + 28) -- Age twice as otherwise calc doesn't seem to work
        WHEN assessment_type = 'under_28_days_prorated' THEN ndays_4wks / (age+1)
        WHEN assessment_type = 'under_7_days_unassigned' THEN ndays_4wks / (age+1)
        ELSE 0
    END AS days_active_per_in_period,
    *
from df_assessment_type
order by age
),


-- Calculate agent category based on Commision Rules set
df_assessment_type_category as (
    select
    -- Is agent 'Unassigned'? i.e. below 7 days old?
    CASE 
        WHEN age +1 < 7 THEN 1 -- 1 = 'Unassigned'
        ELSE 7 -- 7 = Use 7 here as it ranks higher than other numeric fileds used for other categories
    END AS unassigned_or_not,
    -- Transaction, criteria met LABEL
    CASE 
        WHEN averge_tx_per_day_in_period IS NULL THEN 'Inactive'
        ELSE 
            CASE
                WHEN averge_tx_per_day_in_period <= 2 THEN 'Bronze'
                WHEN averge_tx_per_day_in_period <= 10 THEN 'Silver'
                WHEN averge_tx_per_day_in_period <= 20 THEN 'Gold'
                ELSE 'Platinum'
                END
    END AS trn_criteria_met_label,
    -- Transaction, criteria met NUMERIC_VALUE
        CASE 
        WHEN averge_tx_per_day_in_period IS NULL THEN 2
        ELSE 
            CASE
                WHEN averge_tx_per_day_in_period <= 2 THEN 3
                WHEN averge_tx_per_day_in_period <= 10 THEN 4
                WHEN averge_tx_per_day_in_period <= 20 THEN 5
                ELSE 6
                END
    END AS trn_criteria_met_numeric,
    -- Actice rate, criteria met LABEL
    CASE 
        WHEN days_active_per_in_period >= .70 THEN 'Platinum'
        WHEN days_active_per_in_period >= .55 THEN 'Gold'
        WHEN days_active_per_in_period >= .40 THEN 'Silver'
        WHEN days_active_per_in_period >= .14 THEN 'Bronze'
        ELSE 'Inactive'
    END AS active_rate_criteria_met_label,
    -- Actice rate, criteria met NUMERIC_VALUE
    CASE 
        WHEN days_active_per_in_period >= .70 THEN 6
        WHEN days_active_per_in_period >= .55 THEN 5
        WHEN days_active_per_in_period >= .40 THEN 4
        WHEN days_active_per_in_period >= .14 THEN 3
        ELSE 2
    END AS active_rate_criteria_met_numeric,
    *
from df_assessment_type_calcs
),


-- Calculate Agent final category
-- Rule, take the lowest scoring category & apply this. Also, if Agent is >7 days then they have no category (are Unassigned) see rulebook
df_agent_category as (
select 
    unique_id,
    least(
        trn_criteria_met_numeric,
        active_rate_criteria_met_numeric,
        unassigned_or_not
        ) as final_category_numeric,
    CASE
        WHEN least(trn_criteria_met_numeric,active_rate_criteria_met_numeric,unassigned_or_not) = 6 THEN 'Platinum'
        WHEN least(trn_criteria_met_numeric,active_rate_criteria_met_numeric,unassigned_or_not) = 5 THEN 'Gold'
        WHEN least(trn_criteria_met_numeric,active_rate_criteria_met_numeric,unassigned_or_not) = 4 THEN 'Silver'
        WHEN least(trn_criteria_met_numeric,active_rate_criteria_met_numeric,unassigned_or_not) = 3 THEN 'Bronze'
        WHEN least(trn_criteria_met_numeric,active_rate_criteria_met_numeric,unassigned_or_not) = 2 THEN 'Inactive'
        WHEN least(trn_criteria_met_numeric,active_rate_criteria_met_numeric,unassigned_or_not) = 1 THEN 'Unassigned'
        ELSE 'Error, should not happen'
    END AS final_category_label
from df_assessment_type_category
),

-- Final results
df_results as (
    select
        -- Backgroud info on agent & category they are assesed by
        df_agent_category.unique_id,
        first_activity,
        age +1 as agent_days_on_platform,
        assessment_type,
        -- Transaction criteria
        COALESCE(transactions_4wks, 0) as transactions_in_last_4wks,
        COALESCE(averge_tx_per_day_in_period, 0) as averge_tx_per_day_in_period,
        trn_criteria_met_label,
        trn_criteria_met_numeric,
        -- Activity rate
        ndays_4wks as nday_active_in_last_4wks,
        days_active_per_in_period,
        active_rate_criteria_met_label,
        active_rate_criteria_met_numeric,
        -- Final category
        final_category_label,
        final_category_numeric
    from df_agent_category
    join df_assessment_type_category on df_assessment_type_category.unique_id = df_agent_category.unique_id
    order by first_activity desc
)

select *
from df_results

/* 
-- Some specific agents with which we can QA results
where df_agent_category.unique_id in (
    '570c24a1-4060-41f8-9b85-d75b4f07c1da', -- Example someone who joined 12th April (1 days)
    'c858acec-c2f2-485b-83ad-e4baa60a5a1d', -- Example someone who joined 7th April (6 days)
    '5e2d1989-6f33-4531-8cf8-7d65672f3ece', -- Example someone who joined 5th April (8 days)
    '000f763c-5f97-403a-b827-8081304dcd75', -- Example someone who joined 21st Dec 2021 (114 days), Hasn't used the app
    '97214677-1ebb-4759-8247-d504dc14db6d') -- Example someone who joined 14th Jul 2021 (274 days), Uses app frequently
*/