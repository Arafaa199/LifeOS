-- TASK-C1: Sleep vs Spending Correlation Views
-- Objective: Answer "Do I spend more when I sleep poorly?"

-- View 1: Daily sleep quality with next-day spending
-- (Do I spend more the day AFTER poor sleep?)
CREATE OR REPLACE VIEW insights.sleep_spend_daily AS
SELECT
  ldf.day AS sleep_day,
  (ldf.day + INTERVAL '1 day')::DATE AS spend_day,
  -- Sleep metrics
  ldf.sleep_minutes,
  ROUND(ldf.sleep_minutes::NUMERIC / 60, 2) AS sleep_hours,
  ldf.sleep_performance,
  ldf.recovery_score,
  -- Classify sleep quality
  CASE
    WHEN ldf.sleep_minutes >= 420 THEN 'good'    -- >= 7 hours
    WHEN ldf.sleep_minutes >= 360 THEN 'fair'   -- 6-7 hours
    ELSE 'poor'                                  -- < 6 hours
  END AS sleep_bucket,
  -- Next day spending
  next.spend_total AS next_day_spend,
  next.transaction_count AS next_day_tx_count
FROM life.daily_facts ldf
LEFT JOIN life.daily_facts next ON next.day = ldf.day + INTERVAL '1 day'
WHERE ldf.sleep_minutes IS NOT NULL
ORDER BY ldf.day DESC;

COMMENT ON VIEW insights.sleep_spend_daily IS 'Daily sleep quality linked to next-day spending';

-- View 2: Aggregated correlation by sleep bucket
CREATE OR REPLACE VIEW insights.sleep_spend_correlation AS
WITH stats AS (
  SELECT
    sleep_bucket,
    COUNT(*) AS sample_count,
    ROUND(AVG(next_day_spend), 2) AS avg_spend,
    ROUND(STDDEV(next_day_spend), 2) AS stddev_spend,
    ROUND(MIN(next_day_spend), 2) AS min_spend,
    ROUND(MAX(next_day_spend), 2) AS max_spend,
    ROUND(AVG(sleep_hours)::NUMERIC, 2) AS avg_sleep_hours,
    ROUND(AVG(recovery_score)::NUMERIC, 0) AS avg_recovery
  FROM insights.sleep_spend_daily
  WHERE next_day_spend IS NOT NULL
  GROUP BY sleep_bucket
),
global AS (
  SELECT
    AVG(next_day_spend) AS global_avg_spend,
    STDDEV(next_day_spend) AS global_stddev_spend
  FROM insights.sleep_spend_daily
  WHERE next_day_spend IS NOT NULL
)
SELECT
  s.sleep_bucket,
  s.sample_count,
  s.avg_spend,
  s.avg_sleep_hours,
  s.avg_recovery,
  -- Z-score: how many standard deviations from global mean
  CASE
    WHEN g.global_stddev_spend > 0 THEN
      ROUND((s.avg_spend - g.global_avg_spend) / g.global_stddev_spend, 2)
    ELSE 0
  END AS z_score,
  -- Statistical significance indicator
  CASE
    WHEN s.sample_count < 10 THEN 'insufficient_data'
    WHEN s.sample_count < 30 THEN 'low_confidence'
    WHEN ABS((s.avg_spend - g.global_avg_spend) / NULLIF(g.global_stddev_spend, 0)) >= 2 THEN 'significant'
    WHEN ABS((s.avg_spend - g.global_avg_spend) / NULLIF(g.global_stddev_spend, 0)) >= 1 THEN 'notable'
    ELSE 'within_normal'
  END AS significance,
  s.stddev_spend,
  s.min_spend,
  s.max_spend
FROM stats s
CROSS JOIN global g
ORDER BY
  CASE s.sleep_bucket
    WHEN 'poor' THEN 1
    WHEN 'fair' THEN 2
    WHEN 'good' THEN 3
  END;

COMMENT ON VIEW insights.sleep_spend_correlation IS 'Spending patterns by sleep quality bucket - answers "Do I spend more when I sleep poorly?"';

-- View 3: Same-day correlation (sleep quality vs same-day spending)
CREATE OR REPLACE VIEW insights.sleep_spend_same_day AS
WITH stats AS (
  SELECT
    CASE
      WHEN sleep_minutes >= 420 THEN 'good'
      WHEN sleep_minutes >= 360 THEN 'fair'
      ELSE 'poor'
    END AS sleep_bucket,
    COUNT(*) AS sample_count,
    ROUND(AVG(spend_total), 2) AS avg_spend,
    ROUND(STDDEV(spend_total), 2) AS stddev_spend,
    ROUND(AVG(sleep_minutes::NUMERIC / 60), 2) AS avg_sleep_hours
  FROM life.daily_facts
  WHERE sleep_minutes IS NOT NULL AND spend_total IS NOT NULL
  GROUP BY 1
),
global AS (
  SELECT
    AVG(spend_total) AS global_avg,
    STDDEV(spend_total) AS global_stddev
  FROM life.daily_facts
  WHERE sleep_minutes IS NOT NULL AND spend_total IS NOT NULL
)
SELECT
  s.sleep_bucket,
  s.sample_count,
  s.avg_spend,
  s.avg_sleep_hours,
  CASE
    WHEN g.global_stddev > 0 THEN
      ROUND((s.avg_spend - g.global_avg) / g.global_stddev, 2)
    ELSE 0
  END AS z_score,
  CASE
    WHEN s.sample_count < 10 THEN 'insufficient_data'
    WHEN s.sample_count < 30 THEN 'low_confidence'
    WHEN ABS((s.avg_spend - g.global_avg) / NULLIF(g.global_stddev, 0)) >= 2 THEN 'significant'
    WHEN ABS((s.avg_spend - g.global_avg) / NULLIF(g.global_stddev, 0)) >= 1 THEN 'notable'
    ELSE 'within_normal'
  END AS significance
FROM stats s
CROSS JOIN global g
ORDER BY
  CASE s.sleep_bucket
    WHEN 'poor' THEN 1
    WHEN 'fair' THEN 2
    WHEN 'good' THEN 3
  END;

COMMENT ON VIEW insights.sleep_spend_same_day IS 'Same-day sleep quality vs spending correlation';

-- View 4: Summary for dashboard
CREATE OR REPLACE VIEW insights.sleep_spend_summary AS
SELECT
  (SELECT COUNT(*) FROM insights.sleep_spend_daily WHERE next_day_spend IS NOT NULL) AS days_analyzed,
  (SELECT ROUND(AVG(avg_spend), 2) FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'poor') AS poor_sleep_avg_spend,
  (SELECT ROUND(AVG(avg_spend), 2) FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'good') AS good_sleep_avg_spend,
  CASE
    WHEN (SELECT COUNT(*) FROM insights.sleep_spend_daily WHERE next_day_spend IS NOT NULL) < 10 THEN
      'insufficient_data'
    WHEN (SELECT avg_spend FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'poor') >
         (SELECT avg_spend FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'good') * 1.2 THEN
      'poor_sleep_increases_spend'
    WHEN (SELECT avg_spend FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'poor') <
         (SELECT avg_spend FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'good') * 0.8 THEN
      'poor_sleep_decreases_spend'
    ELSE
      'no_clear_pattern'
  END AS finding,
  -- Percent difference
  CASE
    WHEN (SELECT avg_spend FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'good') > 0 THEN
      ROUND(
        ((SELECT avg_spend FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'poor') -
         (SELECT avg_spend FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'good')) /
        (SELECT avg_spend FROM insights.sleep_spend_correlation WHERE sleep_bucket = 'good') * 100,
        1
      )
    ELSE NULL
  END AS poor_vs_good_pct_diff;

COMMENT ON VIEW insights.sleep_spend_summary IS 'Summary finding for sleep-spending correlation';
