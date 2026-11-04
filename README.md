# Finance Tracker

A finance tracker with a React web frontend, a Flutter mobile app for Android and iOS, and a shared FastAPI backend backed by PostgreSQL. Both clients use the same expense data.

## Features

- Dashboard with all-time spending, monthly spending, daily average, and active category totals.
- Daily spending chart, recent expenses, and monthly and yearly category breakdowns.
- Add, edit, and delete expenses with amount, category, description, and date.
- Search and category filters, plus month and year selection.
- Amount privacy toggle and Indian rupee formatting.
- Mobile navigation, pull-to-refresh, and foreground refresh every 15 seconds.
- Mobile opens directly into the tracker without login or Google authentication.

## Project structure

```text
Finance_Tracker/
├── backend/                 # FastAPI routes and PostgreSQL operations
├── frontend/                # React / Vite web app
├── mobile/
│   ├── android/             # Android project
│   ├── ios/                 # iOS project
│   ├── assets/              # Public endpoint configuration and bundled fonts
│   ├── lib/                 # API client, models, state, and Flutter screens
│   ├── test/                # API and widget tests
│   └── tool/configure.dart  # Extracts PUBLIC_URL from the root .env
├── .env.example             # Environment configuration template
├── docker-compose.yml       # Backend and web frontend containers
├── requirements.txt         # Backend dependencies
└── README.md
```

## Configuration

Copy `.env.example` to `.env` in the repository root and set:

```dotenv
POSTGRES_URL=postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres
PUBLIC_URL=https://your-backend.example.com
```

`POSTGRES_URL` is the server-side PostgreSQL connection string. `PUBLIC_URL` is the backend's public origin used by the mobile app. Use an address reachable from the phone; `localhost` on a phone refers to the phone itself.

The mobile configuration tool copies only `PUBLIC_URL` into `mobile/assets/public_config.json`. The API client adds `/api` when needed. Run the tool again and rebuild after changing the backend URL. The generated public configuration is versioned; database credentials and the root `.env` are excluded from Git and the mobile bundle.

## Run the mobile app

Install Flutter compatible with the Dart SDK constraint in [mobile/pubspec.yaml](mobile/pubspec.yaml), and connect an Android device or start an emulator. The app was built with Flutter 3.47.8 and Dart 3.13.7.

From the repository root:

```sh
cd mobile
dart tool/configure.dart
flutter pub get
flutter run
```

The mobile app does not call an authentication endpoint. It uses `google_varun_123`, the existing web frontend's default profile ID, to access the same expenses. This is an existing record identifier. To use another existing backend profile:

```sh
flutter run --dart-define=TRACKER_USER_ID=your_existing_user_id
```

The current backend falls back to its first user when an unknown ID is supplied, so use the exact profile ID when selecting another profile.

### Check and build

From `mobile`:

```sh
flutter analyze
flutter test
dart tool/configure.dart
flutter build apk --debug
```

The installable debug APK is generated at `mobile/build/app/outputs/flutter-apk/app-debug.apk` relative to the repository root. Android builds need a configured Android SDK and compatible JDK. Kotlin incremental compilation is disabled because the project and package cache can reside on different Windows drives.

Release distribution requires your signing configuration; the Android scaffold currently uses debug signing for release builds. iOS builds require macOS, Xcode, and the appropriate signing setup:

```sh
flutter build ios --no-codesign
```

API and widget tests use a mock HTTP backend without changing the live database. They cover request payloads, refresh races, errors, startup without authentication, privacy, search, validation, add/edit/delete, and narrow mobile layouts. Capture screen previews with:

```sh
flutter test test/app_test.dart --dart-define=CAPTURE_SCREENSHOTS=true
```

Previews are written to `mobile/build/screenshots`. Device launch and iOS signing still require testing on the target platforms. See [mobile/README.md](mobile/README.md) for more details.

## Run the web app and backend

### Docker Compose

With Docker installed and `.env` configured, run from the repository root:

```sh
docker compose up --build
```

- Web app: <http://localhost:3000>
- Backend: <http://localhost:8000>
- API docs: <http://localhost:8000/docs>

Compose runs the web frontend and backend. Run the Flutter app separately using the mobile instructions above.

### Local development

With Python, Node.js, and npm installed, start the backend from the repository root so it can load the root `.env`:

```sh
python -m venv venv
```

Activate the environment with `venv\Scripts\Activate.ps1` in PowerShell, or `source venv/bin/activate` on macOS/Linux, then run:

```sh
python -m pip install -r requirements.txt
python -m uvicorn backend.main:app --reload --port 8000
```

In another terminal, start the web frontend:

```sh
cd frontend
npm ci
npm run dev
```

The web app runs at <http://localhost:5173> and defaults to `http://localhost:8000/api`. Set `VITE_API_BASE_URL` in `frontend/.env.local` to use a different backend, including the `/api` suffix. The frontend uses Vite configuration separately from the mobile app's `PUBLIC_URL`.

Web checks:

```sh
npm run lint
npm run build
```

## API

| Method | Endpoint | Purpose |
| --- | --- | --- |
| GET | `/api/health` | Backend and database health |
| GET | `/api/dashboard/stats` | Statistics for `user_id`, `month`, and `year` |
| GET | `/api/expenses` | Expenses for `user_id`, with optional month, year, and category filters |
| POST | `/api/expenses` | Create an expense, including `user_id` in the body |
| PUT | `/api/expenses/{id}` | Update an expense with `user_id` in the query |
| DELETE | `/api/expenses/{id}` | Delete an expense with `user_id` in the query |
| POST | `/api/auth/google` | Existing web profile lookup/creation endpoint; unused by mobile |

The existing profile endpoint accepts an email; it does not verify Google credentials. The mobile application follows the backend's current user-ID-based contract.

## Files in Git

Commit application source, native project files, font licenses, public mobile configuration, and dependency lockfiles (`frontend/package-lock.json` and `mobile/pubspec.lock`). Ignore local environment files, signing credentials, dependency caches, generated native files, test coverage, and build output. See [.gitignore](.gitignore) and the platform-specific ignore files under `mobile`.
