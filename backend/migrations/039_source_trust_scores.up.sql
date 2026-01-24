-- Migration: 039_source_trust_scores.up.sql
-- TASK-A3: Add Source Trust Scores and Adjust Final Confidence
-- Created: 2026-01-24
--
-- Purpose:
-- 1. Create ops.source_trust table to store reliability scores per data source
-- 2. Update life.daily_confidence to use weighted trust scores in confidence calculation
-- 3. Make confidence scoring more nuanced based on source reliability

-- Create source trust table
CREATE TABLE IF NOT EXISTS ops.source_trust (
    source TEXT PRIMARY KEY,
    trust_score NUMERIC(3,2) NOT NULL DEFAULT 1.00 CHECK (trust_score >= 0.0 AND trust_score <= 1.0),
    weight NUMERIC(3,2) NOT NULL DEFAULT 1.00 CHECK (weight >= 0.0 AND weight <= 2.0),
    description TEXT,
    last_updated TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE ops.source_trust IS 'Trust scores and weights per data source for confidence calculations';
COMMENT ON COLUMN ops.source_trust.trust_score IS 'Reliability score 0.0-1.0 (1.0 = highly reliable)';
COMMENT ON COLUMN ops.source_trust.weight IS 'Importance weight 0.0-2.0 for confidence calculation (1.0 = normal)';

-- Populate default trust scores based on source reliability characteristics
INSERT INTO ops.source_trust (source, trust_score, weight, description) VALUES
    -- High trust: automated, consistent
    ('whoop', 1.00, 1.20, 'WHOOP: automated via HA, very reliable, key health metric'),
    ('location', 0.95, 0.80, 'Location: HA automation, occasional GPS drift'),
    ('behavioral', 0.95, 0.80, 'Behavioral: HA motion/TV detection, reliable'),

    -- Medium-high trust: automated but occasional gaps
    ('github', 0.90, 0.60, 'GitHub: API sync every 6h, reliable but low weight for life data'),
    ('finance_summary', 0.95, 0.50, 'Finance summaries: derived data, depends on source quality'),

    -- Medium trust: depends on external triggers
    ('bank_sms', 0.85, 1.30, 'Bank SMS: depends on message receipt, key finance metric'),
    ('receipts', 0.80, 0.90, 'Receipts: Gmail automation, parsing may fail'),

    -- Lower trust: manual or sporadic
    ('healthkit', 0.70, 0.70, 'HealthKit: requires iOS app sync, often stale')
ON CONFLICT (source) DO UPDATE SET
    trust_score = EXCLUDED.trust_score,
    weight = EXCLUDED.weight,
    description = EXCLUDED.description,
    last_updated = NOW();

-- Create view to show trust scores with current health status
CREATE OR REPLACE VIEW ops.source_trust_status AS
SELECT
    st.source,
    st.trust_score,
    st.weight,
    fs.status AS current_status,
    fs.hours_since,
    fs.expected_frequency_hours,
    -- Effective trust: reduced if source is stale/critical
    CASE
        WHEN fs.status = 'OK' THEN st.trust_score
        WHEN fs.status = 'STALE' THEN st.trust_score * 0.7
        WHEN fs.status = 'CRITICAL' THEN st.trust_score * 0.3
        ELSE st.trust_score * 0.5  -- unknown
    END::NUMERIC(3,2) AS effective_trust,
    st.description
FROM ops.source_trust st
LEFT JOIN system.feeds_status fs ON fs.feed_name = st.source
ORDER BY st.weight DESC, st.trust_score DESC;

COMMENT ON VIEW ops.source_trust_status IS 'Source trust scores adjusted by current health status';

-- Create function to calculate weighted confidence for a given day
CREATE OR REPLACE FUNCTION life.calculate_weighted_confidence(p_day DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    day DATE,
    base_confidence NUMERIC(3,2),
    weighted_confidence NUMERIC(3,2),
    trust_adjustment NUMERIC(4,3),
    sources_contributing INT,
    confidence_level TEXT
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_base_confidence NUMERIC(3,2);
    v_total_weight NUMERIC;
    v_weighted_sum NUMERIC;
    v_sources_contributing INT;
    v_trust_adjustment NUMERIC(4,3);
    v_weighted_confidence NUMERIC(3,2);
BEGIN
    -- Get base confidence from existing view
    SELECT dc.confidence_score INTO v_base_confidence
    FROM life.daily_confidence dc
    WHERE dc.day = p_day;

    IF v_base_confidence IS NULL THEN
        v_base_confidence := 0.0;
    END IF;

    -- Calculate weighted trust adjustment based on current source status
    -- Only consider sources that matter for the given day
    SELECT
        COALESCE(SUM(sts.weight), 0),
        COALESCE(SUM(sts.effective_trust * sts.weight), 0),
        COALESCE(COUNT(*), 0)
    INTO v_total_weight, v_weighted_sum, v_sources_contributing
    FROM ops.source_trust_status sts
    WHERE sts.current_status IS NOT NULL;  -- Only count sources we're tracking

    -- Calculate trust adjustment (1.0 = no adjustment, <1.0 = reduce confidence)
    IF v_total_weight > 0 THEN
        v_trust_adjustment := (v_weighted_sum / v_total_weight)::NUMERIC(4,3);
    ELSE
        v_trust_adjustment := 1.0;
    END IF;

    -- Apply trust adjustment to base confidence
    -- This reduces confidence when critical/stale sources have high trust scores
    v_weighted_confidence := GREATEST(0.0, LEAST(1.0, v_base_confidence * v_trust_adjustment))::NUMERIC(3,2);

    RETURN QUERY SELECT
        p_day,
        v_base_confidence,
        v_weighted_confidence,
        v_trust_adjustment,
        v_sources_contributing::INT,
        CASE
            WHEN v_weighted_confidence >= 0.9 THEN 'HIGH'
            WHEN v_weighted_confidence >= 0.7 THEN 'MEDIUM'
            WHEN v_weighted_confidence >= 0.5 THEN 'LOW'
            ELSE 'VERY_LOW'
        END;
END;
$$;

COMMENT ON FUNCTION life.calculate_weighted_confidence IS 'Calculate confidence score weighted by source trust levels';

-- Create view that uses weighted confidence
CREATE OR REPLACE VIEW life.daily_confidence_weighted AS
SELECT
    dc.day,
    dc.has_sms,
    dc.has_receipts,
    dc.has_whoop,
    dc.has_healthkit,
    dc.has_income,
    dc.stale_feeds,
    dc.confidence_score AS base_confidence,
    wc.weighted_confidence AS confidence_score,
    wc.trust_adjustment,
    wc.sources_contributing,
    wc.confidence_level,
    dc.spend_count,
    dc.income_count,
    dc.receipt_count
FROM life.daily_confidence dc
CROSS JOIN LATERAL life.calculate_weighted_confidence(dc.day) wc;

COMMENT ON VIEW life.daily_confidence_weighted IS 'Daily confidence with trust-weighted scoring';

-- Update the get_today_confidence function to use weighted confidence
CREATE OR REPLACE FUNCTION life.get_today_confidence_weighted()
RETURNS JSONB
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'date', day,
        'has_sms', has_sms,
        'has_receipts', has_receipts,
        'has_whoop', has_whoop,
        'has_healthkit', has_healthkit,
        'has_income', has_income,
        'stale_feeds', stale_feeds,
        'base_confidence', base_confidence,
        'confidence_score', confidence_score,
        'trust_adjustment', trust_adjustment,
        'sources_contributing', sources_contributing,
        'confidence_level', confidence_level,
        'spend_count', spend_count,
        'income_count', income_count,
        'receipt_count', receipt_count
    )
    FROM life.daily_confidence_weighted
    WHERE day = CURRENT_DATE;
$$;

COMMENT ON FUNCTION life.get_today_confidence_weighted IS 'Returns today confidence with trust-weighted scoring as JSON';

-- Create ops function to update trust score for a source
CREATE OR REPLACE FUNCTION ops.update_source_trust(
    p_source TEXT,
    p_trust_score NUMERIC DEFAULT NULL,
    p_weight NUMERIC DEFAULT NULL,
    p_description TEXT DEFAULT NULL
)
RETURNS ops.source_trust
LANGUAGE plpgsql AS $$
DECLARE
    v_result ops.source_trust;
BEGIN
    UPDATE ops.source_trust
    SET
        trust_score = COALESCE(p_trust_score, trust_score),
        weight = COALESCE(p_weight, weight),
        description = COALESCE(p_description, description),
        last_updated = NOW()
    WHERE source = p_source
    RETURNING * INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION ops.update_source_trust IS 'Update trust score or weight for a data source';

-- Grant permissions
GRANT SELECT ON ops.source_trust TO nexus;
GRANT SELECT ON ops.source_trust_status TO nexus;
GRANT SELECT ON life.daily_confidence_weighted TO nexus;
GRANT EXECUTE ON FUNCTION life.calculate_weighted_confidence TO nexus;
GRANT EXECUTE ON FUNCTION life.get_today_confidence_weighted TO nexus;
GRANT EXECUTE ON FUNCTION ops.update_source_trust TO nexus;
