BEGIN;

DROP FUNCTION IF EXISTS insights.detect_spending_anomaly(DATE);

-- Restore original get_ranked_insights (8 sources, no spending anomaly)
CREATE OR REPLACE FUNCTION insights.get_ranked_insights(target_date date DEFAULT NULL::date)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
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
        UNION ALL
        SELECT * FROM (
            SELECT
                'anomaly'::text,
                'high'::text,
                CASE
                    WHEN 'spend' = ANY(da.anomalies) AND da.spend_z_score > 0
                        THEN 'Spending ' || ROUND(da.spend_total) || ' AED is unusually high (top 5% of days)'
                    WHEN 'spend' = ANY(da.anomalies) AND da.spend_z_score < 0
                        THEN 'Unusually low spending today'
                    WHEN 'recovery' = ANY(da.anomalies) AND da.recovery_z_score < 0
                        THEN 'Recovery significantly below your baseline'
                    WHEN 'hrv' = ANY(da.anomalies) AND da.hrv_z_score < 0
                        THEN 'HRV dropped to ' || ROUND(da.hrv) || ' — well below your norm'
                    ELSE 'Unusual pattern detected today'
                END::text,
                30,
                30,
                80
            FROM insights.daily_anomalies da
            WHERE da.day = d AND array_length(da.anomalies, 1) > 0
            LIMIT 1
        ) anomaly_sub
        UNION ALL
        SELECT
            'sleep_spend',
            CASE WHEN ss.days_analyzed >= 21 THEN 'high' WHEN ss.days_analyzed >= 10 THEN 'medium' ELSE 'low' END,
            CASE ss.finding
                WHEN 'poor_sleep_decreases_spend'
                    THEN 'After poor sleep you spend ' || ABS(ROUND(ss.poor_vs_good_pct_diff))::text || '% less than after good sleep'
                WHEN 'poor_sleep_increases_spend'
                    THEN 'Poor sleep nights lead to ' || ABS(ROUND(ss.poor_vs_good_pct_diff))::text || '% more spending next day'
                ELSE ss.finding
            END,
            ss.days_analyzed,
            ss.days_analyzed,
            CASE
                WHEN ss.days_analyzed >= 21 THEN 45
                WHEN ss.days_analyzed >= 10 THEN 25
                ELSE 0
            END
        FROM insights.sleep_spend_summary ss
        WHERE ss.days_analyzed >= 10
          AND ss.finding IN ('poor_sleep_decreases_spend', 'poor_sleep_increases_spend')
          AND ABS(ss.poor_vs_good_pct_diff) >= 30
        UNION ALL
        SELECT
            'tv_sleep',
            CASE WHEN tv.days_analyzed >= 21 THEN 'high' WHEN tv.days_analyzed >= 10 THEN 'medium' ELSE 'low' END,
            tv.finding,
            tv.days_analyzed,
            tv.days_analyzed,
            CASE
                WHEN tv.correlation_strength IN ('strong', 'very_strong') THEN 50
                WHEN tv.correlation_strength = 'moderate' THEN 30
                ELSE 0
            END
        FROM insights.tv_sleep_summary tv
        WHERE tv.correlation_strength NOT IN ('no_variation', 'none', 'weak', 'negligible', 'insufficient_data')
          AND tv.days_analyzed >= 10
        UNION ALL
        SELECT
            'productivity',
            CASE WHEN cnt >= 14 THEN 'high' WHEN cnt >= 7 THEN 'medium' ELSE 'low' END,
            'On high-recovery days you push ' ||
                ROUND(avg_recovered)::text ||
                ' commits vs ' ||
                ROUND(avg_tired)::text ||
                ' on low-recovery days',
            cnt,
            cnt,
            CASE WHEN cnt >= 14 THEN 40 WHEN cnt >= 7 THEN 20 ELSE 0 END
        FROM (
            SELECT
                COUNT(*)::int AS cnt,
                AVG(commits) FILTER (WHERE pattern = 'recovered_productive') AS avg_recovered,
                AVG(commits) FILTER (WHERE pattern IN ('tired_productive', 'tired_unproductive')) AS avg_tired
            FROM insights.productivity_recovery_correlation
        ) prc
        WHERE prc.cnt >= 7
          AND prc.avg_recovered IS NOT NULL
          AND prc.avg_tired IS NOT NULL
          AND prc.avg_tired > 0
          AND prc.avg_recovered > prc.avg_tired * 1.3
        UNION ALL
        SELECT
            'sleep_recovery',
            CASE WHEN cnt >= 14 THEN 'high' WHEN cnt >= 7 THEN 'medium' ELSE 'low' END,
            'After 7+ hours sleep your recovery averages ' ||
                ROUND(avg_good)::text || '%' ||
                ' vs ' ||
                ROUND(avg_poor)::text || '% after poor sleep',
            cnt,
            cnt,
            CASE WHEN cnt >= 14 THEN 45 WHEN cnt >= 7 THEN 25 ELSE 0 END
        FROM (
            SELECT
                COUNT(*)::int AS cnt,
                AVG(next_day_recovery) FILTER (WHERE pattern LIKE 'good_sleep%') AS avg_good,
                AVG(next_day_recovery) FILTER (WHERE pattern LIKE 'poor_sleep%') AS avg_poor
            FROM insights.sleep_recovery_correlation
        ) src
        WHERE src.cnt >= 7
          AND src.avg_good IS NOT NULL
          AND src.avg_poor IS NOT NULL
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
                'days_with_data', days_with_data,
                'icon', CASE insight_type
                    WHEN 'alert' THEN 'exclamationmark.triangle.fill'
                    WHEN 'anomaly' THEN 'chart.line.uptrend.xyaxis'
                    WHEN 'pattern' THEN 'calendar.badge.clock'
                    WHEN 'correlation' THEN 'arrow.left.arrow.right'
                    WHEN 'sleep_spend' THEN 'bed.double.fill'
                    WHEN 'tv_sleep' THEN 'tv.fill'
                    WHEN 'productivity' THEN 'hammer.fill'
                    WHEN 'sleep_recovery' THEN 'moon.fill'
                    ELSE 'lightbulb.fill'
                END,
                'color', CASE insight_type
                    WHEN 'alert' THEN 'red'
                    WHEN 'anomaly' THEN 'orange'
                    WHEN 'pattern' THEN 'blue'
                    WHEN 'correlation' THEN 'purple'
                    WHEN 'sleep_spend' THEN 'indigo'
                    WHEN 'tv_sleep' THEN 'indigo'
                    WHEN 'productivity' THEN 'green'
                    WHEN 'sleep_recovery' THEN 'purple'
                    ELSE 'yellow'
                END
            ) ORDER BY score DESC
        ),
        '[]'::jsonb
    ) INTO result
    FROM ranked;

    RETURN result;
END;
$$;

COMMENT ON FUNCTION insights.get_ranked_insights(target_date date) IS 'Returns max 3 quality-gated insights from 8 sources, ranked by score. Includes icon/color for iOS rendering.';

DELETE FROM ops.schema_migrations WHERE filename = '161_spending_anomaly_insight.up.sql';

COMMIT;
