-- Migration 118: Notes index table for Obsidian vault metadata
-- Indexes Obsidian note metadata without duplicating note bodies

CREATE TABLE IF NOT EXISTS raw.notes_index (
    id SERIAL PRIMARY KEY,
    vault VARCHAR(100) NOT NULL,
    relative_path TEXT NOT NULL,
    title VARCHAR(500),
    tags TEXT[],
    frontmatter JSONB,
    word_count INT,
    file_modified_at TIMESTAMPTZ,
    indexed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    removed_at TIMESTAMPTZ,
    CONSTRAINT uq_notes_vault_path UNIQUE (vault, relative_path)
);

CREATE INDEX idx_notes_tags ON raw.notes_index USING GIN (tags) WHERE removed_at IS NULL;
CREATE INDEX idx_notes_frontmatter ON raw.notes_index USING GIN (frontmatter) WHERE removed_at IS NULL;
CREATE INDEX idx_notes_vault ON raw.notes_index (vault) WHERE removed_at IS NULL;
CREATE INDEX idx_notes_file_modified ON raw.notes_index (file_modified_at) WHERE removed_at IS NULL;
