# Notes Contracts

Obsidian vault indexing and search.

## GET /webhook/nexus-notes-search

Searches Obsidian notes index.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `q` (search query), `tag` (filter by tag), `limit` (default 20) |

### Response

```json
{
  "success": true,
  "notes": [
    {
      "id": 1,
      "relative_path": "Projects/LifeOS.md",
      "title": "LifeOS",
      "tags": ["project", "active"],
      "word_count": 1500,
      "file_modified_at": "2026-02-08T10:00:00Z",
      "indexed_at": "2026-02-08T11:00:00Z"
    }
  ],
  "count": 15
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NoteModels.swift` → `NotesSearchResponse`, `Note` |
| n8n Workflow | `notes-index-webhook.json` |
| DB Table | `raw.notes_index` |
| Schema | `_schemas/nexus-notes-search.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## PUT /webhook/nexus-note-update

Updates note metadata (title, tags).

| Field | Value |
|-------|-------|
| Method | PUT |
| Auth | X-API-Key header |
| Query Params | `id` (note ID) |

### Request

```json
{
  "title": "Updated Title",
  "tags": ["project", "active", "priority"]
}
```

### Response

```json
{
  "success": true,
  "message": "Note updated"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NoteModels.swift` → `NoteUpdateResponse` |
| n8n Workflow | `note-update-webhook.json` |
| DB Table | `raw.notes_index` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## DELETE /webhook/nexus-note-delete

Removes note from index (does not delete actual file).

| Field | Value |
|-------|-------|
| Method | DELETE |
| Auth | X-API-Key header |
| Query Params | `id` (note ID) |

### Delete Semantics

**SOFT DELETE** — Sets `deleted_at = NOW()` in `raw.notes_index`. The actual Obsidian file is unchanged.

### Response

```json
{
  "success": true,
  "message": "Note removed from index"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `NoteModels.swift` → `NoteDeleteResponse` |
| n8n Workflow | `note-delete-webhook.json` |
| DB Table | `raw.notes_index` |

### Error Responses

`UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## Indexing

Notes are indexed by `backend/scripts/index-obsidian-vault.py`:

```bash
python backend/scripts/index-obsidian-vault.py
```

The script:
1. Scans `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/RafaVault`
2. Extracts YAML frontmatter (title, tags)
3. Counts words
4. Upserts to `raw.notes_index`

Indexing runs:
- Manually via script
- Via n8n workflow `notes-index-webhook.json` (triggered by POST)
