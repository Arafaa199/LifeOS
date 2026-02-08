# Documents & Reminders Contracts

## GET /webhook/nexus-documents

Fetches all documents.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |

### Response

```json
{
  "success": true,
  "documents": [
    {
      "id": 1,
      "client_id": "uuid-v4",
      "doc_type": "passport",
      "label": "UAE Passport",
      "issuer": "UAE",
      "issuing_country": "AE",
      "doc_number": "P12345678",
      "issue_date": "2023-05-15",
      "expiry_date": "2028-05-15",
      "notes": null,
      "reminders_enabled": true,
      "status": "active",
      "days_until_expiry": 820,
      "urgency": "ok",
      "renewal_count": 0
    }
  ],
  "count": 5
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DocumentModels.swift` → `DocumentsResponse`, `Document` |
| n8n Workflow | `document-crud-webhooks.json` |
| DB Table | `life.documents` |
| Schema | `_schemas/nexus-documents.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-document

Creates a new document.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "client_id": "uuid-v4",
  "doc_type": "passport",
  "label": "UAE Passport",
  "issuer": "UAE",
  "issuing_country": "AE",
  "doc_number": "P12345678",
  "issue_date": "2023-05-15",
  "expiry_date": "2028-05-15",
  "notes": null,
  "reminders_enabled": true
}
```

### Response

```json
{
  "success": true,
  "document": { "id": 5, ... },
  "reminders_created": 3
}
```

### Idempotency

`client_id` UUID.

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DocumentModels.swift` → `CreateDocumentRequest`, `SingleDocumentResponse` |
| n8n Workflow | `document-crud-webhooks.json` |
| DB Table | `life.documents` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `CONFLICT`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-document-update

Updates an existing document.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "id": 5,
  "label": "Updated Label",
  "notes": "Updated notes",
  "reminders_enabled": false
}
```

### Response

```json
{
  "success": true,
  "document": { "id": 5, ... }
}
```

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DocumentModels.swift` → `UpdateDocumentRequest` |
| n8n Workflow | `document-crud-webhooks.json` |
| DB Table | `life.documents` |

---

## DELETE /webhook/nexus-document

Deletes a document.

| Field | Value |
|-------|-------|
| Method | DELETE |
| Auth | X-API-Key header |
| Query Params | `id` (document ID) |

### Delete Semantics

**SOFT DELETE** — Sets `deleted_at = NOW()` and `status = 'expired'`. Row remains in `life.documents` for history.

### Response

```json
{
  "success": true,
  "message": "Document deleted"
}
```

### Error Responses

`UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DocumentModels.swift` → `DeleteDocumentResponse` |
| n8n Workflow | `document-crud-webhooks.json` |
| DB Table | `life.documents` |

---

## POST /webhook/nexus-document-renew

Renews a document with new expiry date.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "id": 5,
  "new_expiry_date": "2033-05-15",
  "new_doc_number": "P87654321",
  "notes": "Renewed at MOI"
}
```

### Response

```json
{
  "success": true,
  "document": { "id": 5, "renewal_count": 1, ... }
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DocumentModels.swift` → `RenewDocumentRequest` |
| n8n Workflow | `document-crud-webhooks.json` |
| DB Tables | `life.documents`, `life.document_renewals` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-document-recreate-reminders

Recreates reminders for a document.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "id": 5
}
```

### Response

```json
{
  "success": true,
  "reminders_created": 3
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DocumentModels.swift` → `RecreateRemindersResponse` |
| n8n Workflow | `document-crud-webhooks.json` |
| DB Table | `raw.reminders` |

### Error Responses

`UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## GET /webhook/nexus-reminders

Fetches reminders in date range.

| Field | Value |
|-------|-------|
| Method | GET |
| Auth | X-API-Key header |
| Query Params | `start` (ISO date), `end` (ISO date) |

### Response

```json
{
  "success": true,
  "reminders": [
    {
      "id": 1,
      "reminder_id": "eventkit-uuid",
      "title": "Pay rent",
      "notes": "Transfer to landlord",
      "due_date": "2026-02-10",
      "is_completed": false,
      "completed_date": null,
      "priority": 1,
      "list_name": "Bills"
    }
  ]
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `DocumentsAPI.swift` → `fetchReminders()` |
| n8n Workflow | `reminder-crud-webhooks.json` |
| DB Table | `raw.reminders` |
| Schema | `_schemas/nexus-reminders.json` |

### Error Responses

`UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-reminder-create

Creates a new reminder.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "title": "Pay rent",
  "notes": "Transfer to landlord",
  "due_date": "2026-02-10",
  "priority": 1,
  "list_name": "Bills"
}
```

### Response

```json
{
  "success": true,
  "reminder": {
    "id": 5,
    "reminder_id": "eventkit-uuid",
    "title": "Pay rent",
    "sync_status": "pending"
  },
  "timestamp": "2026-02-08T12:00:00Z"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `ReminderModels.swift` → `ReminderCreateRequest`, `ReminderCreateResponse` |
| n8n Workflow | `reminder-upsert-webhook.json` |
| DB Table | `raw.reminders` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-reminder-update

Updates an existing reminder.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "id": 5,
  "reminder_id": "eventkit-uuid",
  "title": "Updated title",
  "notes": "Updated notes",
  "due_date": "2026-02-15",
  "is_completed": true,
  "completed_date": "2026-02-08",
  "priority": 2
}
```

### Response

```json
{
  "success": true,
  "updated": {
    "id": 5,
    "reminder_id": "eventkit-uuid",
    "sync_status": "synced"
  },
  "timestamp": "2026-02-08T12:00:00Z"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `ReminderModels.swift` → `ReminderUpdateRequest`, `ReminderUpdateResponse` |
| n8n Workflow | `reminder-crud-webhooks.json` |
| DB Table | `raw.reminders` |

### Error Responses

`VALIDATION_ERROR`, `UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## POST /webhook/nexus-reminder-delete

Deletes a reminder.

| Field | Value |
|-------|-------|
| Method | POST |
| Auth | X-API-Key header |

### Request

```json
{
  "id": 5,
  "reminder_id": "eventkit-uuid"
}
```

### Delete Semantics

**SOFT DELETE** — Sets `deleted_at = NOW()` and `sync_status = 'deleted_local'`. Row remains in `raw.reminders` for sync tracking.

### Response

```json
{
  "success": true,
  "deleted": {
    "id": 5,
    "reminder_id": "eventkit-uuid",
    "sync_status": "deleted"
  },
  "timestamp": "2026-02-08T12:00:00Z"
}
```

### References

| Type | Reference |
|------|-----------|
| iOS Model | `ReminderModels.swift` → `ReminderDeleteRequest`, `ReminderDeleteResponse` |
| n8n Workflow | `reminder-crud-webhooks.json` |
| DB Table | `raw.reminders` |

### Error Responses

`UNAUTHORIZED`, `NOT_FOUND`, `INTERNAL_ERROR`

---

## Document Types

| Type | API Value | Display |
|------|-----------|---------|
| Passport | `passport` | Passport |
| National ID | `national_id` | National ID |
| Driver's License | `drivers_license` | Driver's License |
| Visa | `visa` | Visa |
| Residence Permit | `residence_permit` | Residence Permit |
| Insurance | `insurance` | Insurance |
| Card | `card` | Card |
| Other | `other` | Other |

## Urgency Levels

| Level | Days Until Expiry | Color |
|-------|-------------------|-------|
| `ok` | > 90 days | Green |
| `warning` | 30-90 days | Yellow |
| `urgent` | 7-30 days | Orange |
| `critical` | < 7 days | Red |
| `expired` | Past expiry | Red |
