# High-Throughput Image Transfer — Design Spec

**Date:** 2026-04-28
**Branch:** `feature/high-throughput-image-transfer`
**Primary goal:** Within-session upload reliability for a single photographer uploading 200–500 large photos (5–30MB each). Silent auto-retry on failure, per-file visibility, no photographer intervention required.

---

## Problem Statement

The current upload pipeline fails silently. When something goes wrong (network blip, timeout, backend crash), the photographer sees no indication of which files failed or why, and has no way to recover without restarting the entire batch. Three specific root causes:

1. **Backend bug:** `get-presigned-upload-part-url` and `complete-multipart-upload` both call `list_multipart_uploads` on S3 for every request to look up the file key. This is O(n) against S3's bucket-wide upload list, expensive, and unreliable under any real load.
2. **All-or-nothing batching:** Both upload paths (direct multipart POST and presigned chunked) treat the batch as a single unit. One failure = silent stop with no per-file feedback.
3. **No retry logic:** There is no exponential backoff or per-file retry anywhere in the current code.

---

## Architecture

Replace the batch-upload model with a **per-file state machine** managed by a new `UploadQueue` class.

```
home_screen.dart
    │  observes queue via ValueNotifier<List<UploadFileState>>
    ▼
UploadQueue  (new — lib/services/upload_queue.dart)
    │  3 concurrent workers (reusing MAX_PARALLEL_UPLOADS constant)
    │  each worker pops next pending file, runs it through UploadService
    ▼
UploadService  (existing — add uploadSingleFile() method)
    │  uploadSingleFile(): presigned PUT in production, direct POST in dev
    ▼
Backend  (existing single-file endpoint + DynamoDB key fix)
    ▼
S3
```

**What does NOT change:** routing, session creation flow, auth flow, `ApiService`, `AppRouter`, all screens except `home_screen.dart`.

---

## Components

### `UploadFileState` (new model)

```dart
enum UploadStatus { pending, uploading, retrying, done, failed }

class UploadFileState {
  final String fileName;
  final CrossPlatformImage image;
  UploadStatus status;
  int attempt;        // 1–3
  String? error;      // last error message
  String? uploadedUrl; // set when done
}
```

### `UploadQueue` (new — `lib/services/upload_queue.dart`)

- Accepts `List<CrossPlatformImage>` and `String eventId`
- Exposes `ValueNotifier<List<UploadFileState>> fileStates` for the UI to observe
- Runs 3 concurrent workers via `Future.wait` over a shared `int _nextIndex` counter. Safe without a mutex because Dart is single-threaded — `async/await` yields only at `await` points, so the index increment between `await` calls is atomic in practice.
- Each worker:
  1. Picks the next `pending` file atomically
  2. Sets status → `uploading`, notifies listeners
  3. Calls `UploadService.uploadSingleFile()`
  4. On success: sets status → `done`, stores URL, notifies
  5. On failure with attempt < 3: sets status → `retrying`, waits `2^attempt` seconds (2s then 4s), increments attempt, retries from step 3
  6. On failure at attempt 3: sets status → `failed`, stores error message, notifies
- After all workers finish, calls `onComplete(List<String> successfulUrls, List<UploadFileState> failedFiles)`
- Exposes `retryFailed()`: resets all `failed` files to `pending` and re-runs the workers

### `UploadService.uploadSingleFile()` (new method on existing class)

Single-file upload method that wraps the existing presigned URL logic:
- In production: calls the existing `POST /api/v1/generate-upload-urls` with `num_photos=1` to get one presigned PUT URL, then PUTs the file bytes directly to S3 (mobile) or via `/api/v1/proxy-upload` (web, to avoid CORS)
- In dev: POSTs to the existing `POST /api/v1/upload-photo` single-file endpoint
- Throws on non-2xx; caller (`UploadQueue`) handles retry

### `home_screen.dart` (modified)

Replace the current `statusMessage` string display with a scrollable per-file status list:
- Each row: filename, status icon (spinner / check / warning), attempt count if retrying
- Summary line at top: "X of Y uploaded · Z failed"
- "Retry failed files" button appears when any file is in `failed` state
- Session link card appears once `onComplete` fires (existing `SessionDetailsCard` widget)

---

## Backend Fix

**File:** `backend/app/api/uploads.py`

**Problem:** `get-presigned-upload-part-url` and `complete-multipart-upload` both call `s3_client.list_multipart_uploads(Bucket=BUCKET_NAME)` and scan the result to find the `file_key` for a given `upload_id`. This is O(n) and expensive.

**Fix:** Store `upload_id → file_key` mapping in DynamoDB when the multipart upload is initiated in `generate-multipart-upload-urls`. On subsequent calls, look up the key from DynamoDB instead of scanning S3.

DynamoDB item structure — stored in a new `upload_parts` table (separate from `photo_sessions_share` because partition key and TTL cleanup patterns differ):
```json
{
  "upload_id": "<S3 upload ID>",
  "file_key": "<S3 object key>",
  "event_id": "<event ID>",
  "created_at": "<ISO timestamp>",
  "ttl": "<unix timestamp 24h from now>"
}
```

Partition key: `upload_id`. TTL attribute: `ttl` — DynamoDB auto-deletes stale incomplete uploads after 24 hours.

---

## Data Flow

1. Photographer selects images → `UploadQueue` is created and started
2. 3 workers begin uploading files in parallel
3. UI shows per-file progress; retries happen silently on network blips
4. When queue drains: session is created with all `done` file URLs
5. If any files failed: "Retry failed files" button is shown; session is created with whatever succeeded
6. Session link + password card is shown (existing `SessionDetailsCard`)

---

## Error Handling

| Failure | Behaviour |
|---|---|
| Network blip (transient) | Auto-retry up to 3 attempts with 2s/4s backoff |
| Backend 5xx | Same retry logic |
| File too large / 413 | Mark as `failed` immediately (no retry — won't succeed) |
| All files fail | No session is created; "Retry failed files" button shown |
| Session creation fails | Existing error handling unchanged |

---

## Out of Scope

- Cross-session resume (file-system state persistence) — already partially built, not touched
- Image compression before upload
- CDN in front of S3
- Multiple concurrent photographers
- Progress percentage per file (the `progress` field on `UploadFileState` is reserved for a future pass)
