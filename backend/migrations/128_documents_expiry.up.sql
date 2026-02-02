-- Migration 128: Documents & Expiry Tracking
-- Adds life.documents table for tracking passports, IDs, cards, visas, etc.
-- Auto-creates reminders in raw.reminders (pending_push) for expiry notifications.
-- Renewal function provides atomic update with audit trail.

BEGIN;

-- ============================================================================
-- 1. Core tables
-- ============================================================================

CREATE TABLE life.documents (
    id              SERIAL PRIMARY KEY,
    client_id       UUID UNIQUE,
    doc_type        VARCHAR(50) NOT NULL,
    label           VARCHAR(255) NOT NULL,
    issuer          VARCHAR(255),
    issuing_country VARCHAR(100),
    doc_number      VARCHAR(100),
    issue_date      DATE,
    expiry_date     DATE NOT NULL,
    notes           TEXT,
    reminders_enabled BOOLEAN DEFAULT true,
    status          VARCHAR(20) DEFAULT 'active',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_documents_expiry ON life.documents (expiry_date)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_documents_status ON life.documents (status)
    WHERE deleted_at IS NULL;

COMMENT ON TABLE life.documents IS
'Personal documents with expiry tracking. Linked to raw.reminders for push notifications. Migration 128.';


CREATE TABLE life.document_reminders (
    id              SERIAL PRIMARY KEY,
    document_id     INT NOT NULL REFERENCES life.documents(id) ON DELETE CASCADE,
    reminder_id     INT NOT NULL REFERENCES raw.reminders(id) ON DELETE CASCADE,
    offset_days     INT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (document_id, offset_days)
);

COMMENT ON TABLE life.document_reminders IS
'Junction table linking documents to their auto-generated reminders in raw.reminders. Migration 128.';


CREATE TABLE life.document_renewals (
    id              SERIAL PRIMARY KEY,
    document_id     INT NOT NULL REFERENCES life.documents(id),
    old_expiry_date DATE NOT NULL,
    new_expiry_date DATE NOT NULL,
    old_doc_number  VARCHAR(100),
    new_doc_number  VARCHAR(100),
    renewed_at      TIMESTAMPTZ DEFAULT NOW(),
    notes           TEXT
);

COMMENT ON TABLE life.document_renewals IS
'Audit trail for document renewals. Each row records an expiry date change. Migration 128.';


-- ============================================================================
-- 2. Updated_at trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION life.set_documents_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_documents_updated_at ON life.documents;
CREATE TRIGGER trg_documents_updated_at
    BEFORE UPDATE ON life.documents
    FOR EACH ROW
    EXECUTE FUNCTION life.set_documents_updated_at();


-- ============================================================================
-- 3. Create document reminders function
-- ============================================================================

CREATE OR REPLACE FUNCTION life.create_document_reminders(p_document_id INT)
RETURNS INT AS $$
DECLARE
    v_doc RECORD;
    v_offset INT;
    v_due DATE;
    v_reminder_id INT;
    v_count INT := 0;
    v_priority INT;
BEGIN
    SELECT * INTO v_doc FROM life.documents WHERE id = p_document_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Document % not found or deleted', p_document_id;
    END IF;

    IF NOT v_doc.reminders_enabled THEN
        RETURN 0;
    END IF;

    FOREACH v_offset IN ARRAY ARRAY[30, 7, 5, 1]
    LOOP
        v_due := v_doc.expiry_date - v_offset;

        -- Skip if due date is in the past
        IF v_due <= CURRENT_DATE THEN
            CONTINUE;
        END IF;

        -- High priority for <=5 days, normal otherwise
        IF v_offset <= 5 THEN
            v_priority := 1;
        ELSE
            v_priority := 5;
        END IF;

        INSERT INTO raw.reminders (
            reminder_id, title, notes, due_date, is_completed,
            priority, list_name, source, origin, sync_status
        ) VALUES (
            'nexus-doc-' || p_document_id || '-' || v_offset || '-' || gen_random_uuid()::text,
            v_doc.label || ' expires in ' || v_offset || ' day' || CASE WHEN v_offset > 1 THEN 's' ELSE '' END,
            'Document: ' || v_doc.doc_type || COALESCE(' | Issuer: ' || v_doc.issuer, ''),
            v_due::timestamptz,
            false,
            v_priority,
            'LifeOS Documents',
            'nexus',
            'nexus',
            'pending_push'
        )
        RETURNING id INTO v_reminder_id;

        INSERT INTO life.document_reminders (document_id, reminder_id, offset_days)
        VALUES (p_document_id, v_reminder_id, v_offset);

        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.create_document_reminders IS
'Creates up to 4 reminders (30d, 7d, 5d, 1d before expiry) in raw.reminders with pending_push status. '
'ReminderSyncService pushes them to EventKit on next sync. Migration 128.';


-- ============================================================================
-- 4. Clear document reminders function
-- ============================================================================

CREATE OR REPLACE FUNCTION life.clear_document_reminders(p_document_id INT)
RETURNS INT AS $$
DECLARE
    v_count INT;
BEGIN
    -- Mark linked reminders for deletion in EventKit
    UPDATE raw.reminders
    SET sync_status = 'deleted_local',
        deleted_at = CURRENT_TIMESTAMP
    WHERE id IN (
        SELECT reminder_id FROM life.document_reminders
        WHERE document_id = p_document_id
    )
    AND deleted_at IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Remove junction rows
    DELETE FROM life.document_reminders WHERE document_id = p_document_id;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.clear_document_reminders IS
'Marks linked reminders as deleted_local (sync will remove from EventKit) and removes junction rows. Migration 128.';


-- ============================================================================
-- 5. Renew document function
-- ============================================================================

CREATE OR REPLACE FUNCTION life.renew_document(
    p_document_id INT,
    p_new_expiry DATE,
    p_new_doc_number VARCHAR DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS SETOF life.documents AS $$
DECLARE
    v_old_doc RECORD;
BEGIN
    SELECT * INTO v_old_doc FROM life.documents
    WHERE id = p_document_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Document % not found or deleted', p_document_id;
    END IF;

    -- Audit trail
    INSERT INTO life.document_renewals (document_id, old_expiry_date, new_expiry_date, old_doc_number, new_doc_number, notes)
    VALUES (p_document_id, v_old_doc.expiry_date, p_new_expiry, v_old_doc.doc_number, p_new_doc_number, p_notes);

    -- Clear old reminders
    PERFORM life.clear_document_reminders(p_document_id);

    -- Update document
    UPDATE life.documents
    SET expiry_date = p_new_expiry,
        doc_number = COALESCE(p_new_doc_number, doc_number),
        status = 'active'
    WHERE id = p_document_id;

    -- Create new reminders
    PERFORM life.create_document_reminders(p_document_id);

    RETURN QUERY SELECT * FROM life.documents WHERE id = p_document_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION life.renew_document IS
'Atomic renewal: logs audit trail, clears old reminders, updates document, creates new reminders. Migration 128.';


-- ============================================================================
-- 6. View with computed status
-- ============================================================================

CREATE OR REPLACE VIEW life.v_documents_with_status AS
SELECT
    d.id,
    d.client_id,
    d.doc_type,
    d.label,
    d.issuer,
    d.issuing_country,
    d.doc_number,
    d.issue_date,
    d.expiry_date,
    d.notes,
    d.reminders_enabled,
    d.status,
    d.created_at,
    d.updated_at,
    (d.expiry_date - CURRENT_DATE) AS days_until_expiry,
    CASE
        WHEN d.expiry_date < CURRENT_DATE THEN 'expired'
        WHEN (d.expiry_date - CURRENT_DATE) <= 7 THEN 'critical'
        WHEN (d.expiry_date - CURRENT_DATE) <= 30 THEN 'warning'
        ELSE 'ok'
    END AS urgency,
    COALESCE(r.renewal_count, 0) AS renewal_count
FROM life.documents d
LEFT JOIN (
    SELECT document_id, COUNT(*) AS renewal_count
    FROM life.document_renewals
    GROUP BY document_id
) r ON r.document_id = d.id
WHERE d.deleted_at IS NULL
ORDER BY d.expiry_date ASC;

COMMENT ON VIEW life.v_documents_with_status IS
'Documents with computed days_until_expiry, urgency (expired/critical/warning/ok), and renewal_count. Migration 128.';


-- ============================================================================
-- 7. Grants
-- ============================================================================

GRANT SELECT, INSERT, UPDATE ON life.documents TO nexus;
GRANT USAGE, SELECT ON SEQUENCE life.documents_id_seq TO nexus;
GRANT SELECT, INSERT, DELETE ON life.document_reminders TO nexus;
GRANT USAGE, SELECT ON SEQUENCE life.document_reminders_id_seq TO nexus;
GRANT SELECT, INSERT ON life.document_renewals TO nexus;
GRANT USAGE, SELECT ON SEQUENCE life.document_renewals_id_seq TO nexus;
GRANT SELECT ON life.v_documents_with_status TO nexus;

COMMIT;
