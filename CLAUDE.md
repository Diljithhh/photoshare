# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PhotoShare is a cross-platform Flutter app (iOS, Android, Web, macOS, Windows, Linux) paired with a FastAPI backend. Photographers upload photos to AWS S3, create password-protected viewing sessions stored in DynamoDB, and clients browse/select photos via a shared link.

## Commands

### Backend (in `backend/`)

```bash
# Install dependencies
poetry install

# Run dev server
uvicorn app.main:app --host localhost --port 8000 --reload

# Run tests
pytest

# Format / lint
black .
flake8
```

### Frontend (repo root)

```bash
flutter pub get
flutter run -d chrome          # web
flutter run                    # mobile (connected device)
flutter run -d macos           # desktop
flutter test                   # unit/widget tests
flutter test test/widget_test.dart  # single test file
flutter analyze
dart format .
flutter build web              # production web build
firebase deploy --only hosting # deploy to Firebase Hosting
```

## Environment Setup

**Backend** — copy `backend/.env.example` to `backend/.env`:
```
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=ap-south-1
JWT_SECRET_KEY=...
ENVIRONMENT=development
ALLOWED_ORIGINS=http://localhost:3000
FRONTEND_URL=http://localhost:3000
```

**Frontend** — copy `.env.example` to `.env`. Variables actually read at runtime:
```
API_URL=http://localhost:8000
FRONTEND_URL=http://localhost:3000
ENVIRONMENT=development
```

The `.env` file is bundled as a Flutter asset (declared in `pubspec.yaml`) and loaded at startup via `flutter_dotenv`.

**Gotcha — hardcoded URL in `lib/utils/utils.dart`**: This file exports `const String apiBaseUrl = 'https://photoshare-dn8f.onrender.com'` which is NOT `.env`-driven. `sessionModels.dart` imports this constant for the `createSession` call. `ApiService` and `UploadService` correctly read `dotenv.env['API_URL']` instead — so for local dev, edit `utils.dart` or use those services directly.

## Architecture

### Data flow
1. **Photographer** (home screen) picks images → `UploadService` uploads via multipart to `POST /api/v1/upload-multiple-photos` → S3.
2. `sessionModels.dart::createSession()` calls `POST /api/v1/session/create` → DynamoDB record with hashed password and S3 URLs → returns `session_link` + plaintext password.
3. **Client** opens `session_link` (`/session/:sessionId`) → enters password → `POST /api/v1/session/:sessionId/auth` → receives JWT.
4. Client fetches photo list with JWT → selects photos → `POST /api/v1/session/:sessionId/select` saves selections back to DynamoDB.

### Image proxying
Direct S3 presigned URLs cause CORS errors in browsers. The backend `/api/v1/direct-access?url=<encoded-s3-url>` endpoint proxies S3 objects with correct CORS headers. `SessionView._transformImageUrl()` rewrites all photo URLs through this proxy in production.

### Frontend structure
- `lib/main.dart` → loads `.env`, sets path URL strategy, runs `MyApp`
- `lib/app.dart` → `MaterialApp.router` wired to `AppRouter`
- `lib/utils/router.dart` — three routes: `/` (home), `/session/:sessionId`, and `/api/v1/session/:sessionId/auth` (handles direct backend URL clicks by redirecting to SessionView)
- `lib/utils/utils.dart` — exports hardcoded `apiBaseUrl` constant (see gotcha above)
- `lib/screens/home_screen.dart` — upload UI
- `lib/screens/session_view.dart` — password auth + masonry photo grid + selection saving (all state via `setState`, no state management library)
- `lib/screens/sessionModels.dart` — `SessionResponse` model + `createSession()` function called after upload
- `lib/services/upload_service.dart` — two upload modes: direct multipart (dev) and presigned-URL multipart with chunking/resume (production, triggered by file size)
- `lib/services/api_service.dart` — thin wrapper for auth, photo fetch, and selection save; reads `API_URL` from dotenv
- `lib/models/cross_platform_image.dart` — abstracts image picking differences between web and mobile
- `lib/widgets/session_details_card.dart` — displays session link + password after upload
- `lib/debug/` — auth testing utilities for development only

**Dead code**: `lib/screens/sessions_view.dart`, `lib/screens/auth_view.dart`, `lib/screens/photo_grid.dart`, and `backend/app/core/config.py` are entirely commented out and can be ignored.

### Backend structure
- `backend/app/main.py` — FastAPI app, CORS middleware, S3 client init on startup
- `backend/app/api/uploads.py` — `/api/v1/upload-*`, `/api/v1/generate-*`, `/api/v1/direct-access`, `/api/v1/proxy-image` (dev only)
- `backend/app/api/sessions.py` — `/api/v1/session/create`, `/api/v1/session/:id/auth`, `/api/v1/session/:id/photos`, `/api/v1/session/:id/select`
- `backend/app/api/jwt.py` — JWT utilities exposed as an API router
- `backend/app/core/security.py` — password hashing; `backend/app/utils/password.py` — password utilities
- `backend/app/services/dynamodb.py` — DynamoDB client factory + `save_upload_key`, `get_file_key_for_upload`, `ensure_upload_parts_table_exists` helpers
- `backend/app/models/session.py` — Pydantic models: `CreateSessionRequest`, `SessionResponse`
- AWS resources: S3 bucket `screenmirror-canvas-storage`, DynamoDB table `photo_sessions_share` (partition key: `session_id`), DynamoDB table `upload_parts` (partition key: `upload_id`, TTL on `ttl` attribute — auto-created on startup)

## In-Progress Work (branch: feature/high-throughput-image-transfer)

**Status as of 2026-04-29:** Backend tasks complete, Flutter frontend tasks pending.

**Plan file:** `docs/superpowers/plans/2026-04-28-high-throughput-image-transfer.md`
**Spec file:** `docs/superpowers/specs/2026-04-28-high-throughput-image-transfer-design.md`

### Completed tasks (Tasks 1–5)
- Test infrastructure added: `mockito`/`build_runner` in Flutter, `moto`/`pytest-asyncio` in backend
- `backend/app/services/dynamodb.py`: new helpers `save_upload_key`, `get_file_key_for_upload`, `ensure_upload_parts_table_exists` (with TTL enabled)
- `backend/app/main.py`: calls `ensure_upload_parts_table_exists` on startup
- `backend/app/api/uploads.py`: `generate_multipart_upload_urls` now stores `upload_id→file_key` in DynamoDB; `get_presigned_upload_part_url` and `complete_multipart_upload` look it up from DynamoDB instead of calling `list_multipart_uploads` (O(n)→O(1))
- `backend/tests/`: 8 passing tests covering DynamoDB helpers and all three fixed endpoints

### Pending tasks (pick up here next session)

**Task 6** — Create `lib/models/upload_file_state.dart` (`UploadStatus` enum + `UploadFileState` class)

**Task 7** — Add `uploadSingleFile()` and `_uploadSingleFileDev()` to `lib/services/upload_service.dart`

**Task 8** — Create `lib/services/upload_queue.dart` (3-worker concurrent queue with retry/backoff) + `test/services/upload_queue_test.dart` (5 unit tests using mockito)

**Task 9** — Update `lib/screens/home_screen.dart`: replace progress bar with per-file status list + retry button using `UploadQueue`

**Task 10** — Manual smoke test: run `flutter test`, run `pytest backend/tests/ -v`, verify browser upload flow

To continue: read the plan file for full step-by-step instructions, then invoke `superpowers:subagent-driven-development`.

---

### Deployment
- Backend → Render (configured in `render.yaml`); `backend/Procfile` runs `uvicorn`
- Frontend → Firebase Hosting (`firebase.json`); `deploy_web.sh` runs `flutter build web --release && firebase deploy --only hosting`
- Docker available for both via `Dockerfile` / `backend/docker-compose.yml`
