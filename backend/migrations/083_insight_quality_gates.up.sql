-- Migration: 083_insight_quality_gates
-- Adds data-quality gating to all insights surfaced in the dashboard
-- Requirements:
--   - Minimum sample size (>=7 days) for patterns
--   - Minimum overlap (>=3 spend days) for correlations
--   - confidence_level (low|medium|high) on all insight types
--   - Ranked insights function (max 3, by confidence then impact)
--   - Suppress low-confidence insights from dashboard payload

BEGIN;

-- ============================================================================
-- 1. Patch insights.spending_by_recovery_level — add quality metadata
--    Changes: avg_spend now excludes zero-spend days, adds days_with_spend
--    and confidence level
--    Note: DROP required because column list changes (PG can't rename via CREATE OR REPLACE)
-- ============================================================================

DROP VIEW IF EXISTS insights.spending_by_recovery_level;
CREATE VIEW insights.spending_by_recovery_level AS
SELECT
    CASE
        WHEN recovery_score >= 70 THEN 'high_recovery'
        WHEN recovery_score >= 40 THEN 'medium_recovery'
        ELSE 'low_recovery'
    END AS recovery_level,
    COUNT(*) AS days,
    COUNT(*) FILTER (WHERE spend_total > 0) AS days_with_spend,
    ROUND((AVG(spend_total) FILTER (WHERE spend_total > 0))::numeric, 2) AS avg_spend,
    ROUND((AVG(transaction_count) FILTER (WHERE transaction_count > 0))::numeric, 1) AS avg_transactions,
    ROUND((STDDEV(spend_total) FILTER (WHERE spend_total > 0))::numeric, 2) AS spend_stddev,
    CASE
        WHEN COUNT(*) FILTER (WHERE spend_total > 0) >= 7 THEN 'high'
        WHEN COUNT(*) FILTER (WHERE spend_total > 0) >= 3 THEN 'medium'
        ELSE 'low'
    END AS confidence
FROM life.daily_facts
WHERE recovery_score IS NOT NULL
  AND day >= NOW() - INTERVAL '90 days'
GROUP BY 1
ORDER BY avg_spend DESC NULLS LAST;

-- ============================================================================
-- 2. Patch insights.pattern_detector — add quality metadata
--    Changes: avg_spend excludes zero-spend days, pattern_flag gated on
--    minimum days_with_spend, adds confidence level
--    Note: DROP required because column list changes
-- ============================================================================

DROP VIEW IF EXISTS insights.pattern_detector;
CREATE VIEW insights.pattern_detector AS
WITH day_patterns AS (
    SELECT
        EXTRACT(DOW FROM day) AS day_of_week,
        AVG(spend_total) FILTER (WHERE spend_total > 0) AS avg_spend,
        AVG(recovery_score) AS avg_recovery,
        AVG(sleep_hours) AS avg_sleep,
        COUNT(*) AS sample_size,
        COUNT(*) FILTER (WHERE spend_total > 0) AS days_with_spend
    FROM life.daily_facts
    WHERE day >= NOW() - INTERVAL '60 days'
    GROUP BY EXTRACT(DOW FROM day)
)
SELECT
    CASE day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    ROUND(avg_spend::numeric, 2) AS avg_spend,
    ROUND(avg_recovery::numeric, 1) AS avg_recovery,
    ROUND(avg_sleep::numeric, 2) AS avg_sleep,
    sample_size,
    days_with_spend,
    CASE
        WHEN days_with_spend >= 3
             AND avg_spend > (SELECT AVG(dp2.avg_spend) * 1.5 FROM day_patterns dp2 WHERE dp2.days_with_spend >= 3)
             THEN 'high_spend_day'
        WHEN sample_size >= 3
             AND avg_recovery < (SELECT AVG(dp2.avg_recovery) * 0.7 FROM day_patterns dp2 WHERE dp2.sample_size >= 3)
             THEN 'low_recovery_day'
        WHEN sample_size >= 3
             AND avg_sleep < (SELECT AVG(dp2.avg_sleep) * 0.8 FROM day_patterns dp2 WHERE dp2.sample_size >= 3)
             THEN 'poor_sleep_day'
        ELSE 'normal'
    END AS pattern_flag,
    CASE
        WHEN sample_size >= 14 THEN 'high'
        WHEN sample_size >= 7 THEN 'medium'
        ELSE 'low'
    END AS confidence
FROM day_patterns
ORDER BY day_of_week;

-- ============================================================================
-- 3. Create insights.get_ranked_insights() — server-side ranking
--    Returns max 3 quality-gated insights ranked by confidence then impact
--    Suppresses anything with score=0 (low confidence)
-- ============================================================================

CREATE OR REPLACE FUNCTION insights.get_ranked_insights(target_date DATE DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    d DATE := COALESCE(target_date, life.dubai_today());
    result JSONB;
BEGIN
    WITH candidates AS (
        -- Source 1: Cross-domain alerts for today (always high confidence)
        SELECT
            'alert'::text AS insight_type,
            'high'::text AS confidence,
            a.description::text,
            7 AS days_sampled,
            7 AS days_with_data,
            CASE a.severity
                WHEN 'warning' THEN 90
                WHEN 'info' THEN 70
                ELSE 50
            END AS score
        FROM insights.cross_domain_alerts a
        WHERE a.day = d

        UNION ALL

        -- Source 2: Day-of-week pattern for today (gated: sample >= 7)
        SELECT
            'pattern',
            p.confidence,
            p.day_name || 's tend to be ' ||
                REPLACE(p.pattern_flag, '_', ' ') ||
                CASE WHEN p.avg_spend IS NOT NULL
                    THEN ' (avg ' || ROUND(p.avg_spend::numeric, 0)::text || ' AED)'
                    ELSE ''
                END,
            p.sample_size::int,
            p.days_with_spend::int,
            CASE p.confidence
                WHEN 'high' THEN 60
                WHEN 'medium' THEN 40
                ELSE 0
            END
        FROM insights.pattern_detector p
        WHERE p.day_name = to_char(d, 'FMDay')
          AND p.pattern_flag != 'normal'
          AND p.sample_size >= 7

        UNION ALL

        -- Source 3: Recovery-spend correlation (gated: both buckets >= 3 spend days, ratio >= 2x)
        SELECT
            'correlation',
            CASE
                WHEN hi.days_with_spend >= 7 AND lo.days_with_spend >= 7 THEN 'high'
                WHEN hi.days_with_spend >= 3 AND lo.days_with_spend >= 3 THEN 'medium'
                ELSE 'low'
            END,
            'On ' || REPLACE(hi.recovery_level, '_', ' ') ||
                ' days you spend ' ||
                ROUND((hi.avg_spend / lo.avg_spend)::numeric, 0)::text || 'x more',
            (hi.days + lo.days)::int,
            (hi.days_with_spend + lo.days_with_spend)::int,
            CASE
                WHEN hi.days_with_spend >= 7 AND lo.days_with_spend >= 7 THEN 50
                WHEN hi.days_with_spend >= 3 AND lo.days_with_spend >= 3 THEN 30
                ELSE 0
            END
        FROM (
            SELECT * FROM insights.spending_by_recovery_level
            WHERE avg_spend IS NOT NULL
            ORDER BY avg_spend DESC
            LIMIT 1
        ) hi
        CROSS JOIN (
            SELECT * FROM insights.spending_by_recovery_level
            WHERE avg_spend IS NOT NULL AND avg_spend > 0
            ORDER BY avg_spend ASC
            LIMIT 1
        ) lo
        WHERE hi.recovery_level != lo.recovery_level
          AND hi.days_with_spend >= 3
          AND lo.days_with_spend >= 3
          AND (hi.avg_spend / NULLIF(lo.avg_spend, 0)) >= 2
    ),
    ranked AS (
        SELECT * FROM candidates WHERE score > 0 ORDER BY score DESC LIMIT 3
    )
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'type', insight_type,
                'confidence', confidence,
                'description', description,
                'days_sampled', days_sampled,
                'days_with_data', days_with_data
            ) ORDER BY score DESC
        ),
        '[]'::jsonb
    ) INTO result
    FROM ranked;

    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION insights.get_ranked_insights IS 'Returns max 3 quality-gated insights ranked by confidence then impact. Low-confidence signals suppressed.';

-- ============================================================================
-- 4. Update dashboard.get_payload() — gate insights + add ranked_insights
--    Changes: patterns/spending_by_recovery gated to exclude low confidence,
--    today_is gated on sample_size >= 7, new ranked_insights key
-- ============================================================================

CREATE OR REPLACE FUNCTION dashboard.get_payload(for_date DATE DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    target_date DATE := COALESCE(for_date, life.dubai_today());
    payload JSONB;
BEGIN
    SELECT jsonb_build_object(
        'meta', jsonb_build_object(
            'schema_version', 3,
            'generated_at', NOW(),
            'for_date', target_date,
            'timezone', 'Asia/Dubai'
        ),
        'today_facts', (
            SELECT to_jsonb(t.*) - 'schema_version' - 'generated_at' - 'for_date'
            FROM dashboard.v_today t
        ),
        'trends', (
            SELECT jsonb_agg(to_jsonb(t.*) - 'schema_version' - 'generated_at')
            FROM dashboard.v_trends t
        ),
        'feed_status', (
            SELECT jsonb_agg(to_jsonb(f.*))
            FROM ops.feed_status f
        ),
        'recent_events', (
            SELECT COALESCE(jsonb_agg(to_jsonb(e.*)), '[]'::jsonb)
            FROM dashboard.v_recent_events e
        ),
        'stale_feeds', (
            SELECT COALESCE(jsonb_agg(feed), '[]'::jsonb)
            FROM ops.feed_status
            WHERE status IN ('stale', 'critical')
        ),
        'daily_insights', jsonb_build_object(
            'alerts', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'alert_type', alert_type,
                    'severity', severity,
                    'description', description
                )), '[]'::jsonb)
                FROM insights.cross_domain_alerts
                WHERE day = target_date
            ),
            'patterns', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'day_name', day_name,
                    'pattern_flag', pattern_flag,
                    'avg_spend', avg_spend,
                    'avg_recovery', avg_recovery,
                    'sample_size', sample_size,
                    'days_with_spend', days_with_spend,
                    'confidence', confidence
                )), '[]'::jsonb)
                FROM insights.pattern_detector
                WHERE pattern_flag != 'normal'
                  AND confidence != 'low'
            ),
            'spending_by_recovery', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'recovery_level', recovery_level,
                    'days', days,
                    'days_with_spend', days_with_spend,
                    'avg_spend', avg_spend,
                    'confidence', confidence
                )), '[]'::jsonb)
                FROM insights.spending_by_recovery_level
                WHERE confidence != 'low'
            ),
            'today_is', (
                SELECT pattern_flag
                FROM insights.pattern_detector
                WHERE day_name = to_char(target_date, 'FMDay')
                  AND sample_size >= 7
            ),
            'ranked_insights', insights.get_ranked_insights(target_date)
        )
    ) INTO payload;

    RETURN payload;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dashboard.get_payload IS 'Complete dashboard payload as JSONB with quality-gated insights. Schema v3. Deterministic for caching.';

COMMIT;
