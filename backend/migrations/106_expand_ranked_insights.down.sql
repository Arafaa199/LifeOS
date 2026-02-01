-- Migration 106 down: Restore get_ranked_insights to 3-source version from migration 083
-- The full original function is in 083_insight_quality_gates.up.sql
-- This restores the function without icon/color fields and with only 3 sources

CREATE OR REPLACE FUNCTION insights.get_ranked_insights(target_date DATE DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    d DATE := COALESCE(target_date, life.dubai_today());
    result JSONB;
BEGIN
    WITH candidates AS (
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
