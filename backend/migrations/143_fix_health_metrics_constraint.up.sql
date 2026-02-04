-- Migration 143: Fix health.metrics unique constraint
-- Issue: ON CONFLICT (date, source, metric_type) requires matching unique index
-- Solution: Create unique constraint if not exists, drop old if wrong

BEGIN;

-- Check if the correct constraint exists
DO $$
BEGIN
    -- Drop any incorrect constraint on (recorded_at, source, metric_type)
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname LIKE '%metrics%'
        AND conrelid = 'health.metrics'::regclass
        AND contype = 'u'
        AND array_length(conkey, 1) = 3
    ) THEN
        -- Get constraint names and check columns
        FOR r IN (
            SELECT conname, array_agg(a.attname ORDER BY array_position(c.conkey, a.attnum)) as cols
            FROM pg_constraint c
            JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
            WHERE c.conrelid = 'health.metrics'::regclass AND c.contype = 'u'
            GROUP BY c.conname
        ) LOOP
            -- Drop if it's the wrong constraint (recorded_at based)
            IF r.cols @> ARRAY['recorded_at'] THEN
                EXECUTE format('ALTER TABLE health.metrics DROP CONSTRAINT IF EXISTS %I', r.conname);
                RAISE NOTICE 'Dropped incorrect constraint: %', r.conname;
            END IF;
        END LOOP;
    END IF;
END $$;

-- Create the correct unique constraint if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'health'
        AND c.conname = 'health_metrics_date_source_type_key'
        AND c.contype = 'u'
    ) THEN
        -- First check if there are duplicates that need resolution
        IF EXISTS (
            SELECT date, source, metric_type, COUNT(*)
            FROM health.metrics
            GROUP BY date, source, metric_type
            HAVING COUNT(*) > 1
        ) THEN
            -- Keep only the most recent record for each (date, source, metric_type)
            DELETE FROM health.metrics m
            WHERE m.id NOT IN (
                SELECT DISTINCT ON (date, source, metric_type) id
                FROM health.metrics
                ORDER BY date, source, metric_type, recorded_at DESC
            );
            RAISE NOTICE 'Removed duplicate health.metrics rows';
        END IF;

        -- Now create the constraint
        ALTER TABLE health.metrics
        ADD CONSTRAINT health_metrics_date_source_type_key
        UNIQUE (date, source, metric_type);

        RAISE NOTICE 'Created unique constraint on health.metrics(date, source, metric_type)';
    ELSE
        RAISE NOTICE 'Constraint health_metrics_date_source_type_key already exists';
    END IF;
END $$;

-- Verify the constraint
SELECT
    conname as constraint_name,
    array_agg(a.attname ORDER BY array_position(c.conkey, a.attnum)) as columns
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.conrelid = 'health.metrics'::regclass AND c.contype = 'u'
GROUP BY c.conname;

COMMIT;
