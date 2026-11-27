# Finance Tracker

A finance tracker with a React web frontend, a Flutter mobile app for Android and iOS, and a shared FastAPI backend backed by PostgreSQL. Both clients share expense records and a separate borrowing/lending ledger.

## Features

- Dashboard with all-time spending, monthly spending, daily average, and active category totals.
- Daily spending chart, recent expenses, and monthly and yearly category breakdowns.
- Add, edit, and delete expenses with amount, category, description, and date.
- Track borrowed and lent money separately on mobile and web. Record a person, amount, date, and optional note; settle entries to remove them from outstanding balances while keeping their history.
- Separate all-date borrowed/lent balances on the mobile Loans screen and web dashboard. These entries and repayments never count as expenses.
- Mobile design follows `context/design system/Finance Tracker Mobile.zip`: Home, Activity, and Loans, floating add buttons, bottom sheets, light/dark themes, Lucide icons, spending bars, and a category donut.
- Search and category filters, plus month and year selection.
- Amount privacy toggle and Indian rupee formatting.
- Mobile navigation, pull-to-refresh, and foreground refresh every 15 seconds.
- Mobile opens directly into the tracker without login or Google authentication.
- Mobile caches expenses, loan entries, and the last 12 dashboard periods while connecting to the backend.
- Android voice entry fills an expense draft or accepts expense assistant commands. Review and confirm changes before saving.

## Track borrowed and lent money

On mobile, open **Loans** and tap **+**. On web, open **Borrow & Lend**. Choose a type and enter the person's name, amount, date, and an optional note:

| Type | Meaning | Outstanding balance |
| --- | --- | --- |
| Borrowed | Money you received and must repay | You owe |
| Lent | Money you gave and expect back | Owed to you |

On mobile, swipe an open loan left or open its edit sheet and select **Mark settled**. The entry moves from **Open** to **Settled** and its amount is removed from the outstanding balance. The snackbar's **Undo** cancels the pending change; open a settled entry and choose **Reopen loan** to restore it later. Tap an entry to edit its details or delete it, also with an Undo window.

On web, **Mark refunded** strikes through the person's name and removes the amount from outstanding balances. **Undo refund** restores the balance. **Delete entry** removes an incorrect record after confirmation.

Balances include outstanding entries from all dates, regardless of the selected expense month or year. Loan entries and repayments do not affect expense totals, daily averages, charts, or category breakdowns. Refunds settle an entire entry; partial repayments are not tracked. The amount privacy toggle also hides loan amounts.

## Project structure

```text
Finance_Tracker/
├── backend/                 # FastAPI, PostgreSQL, Whisper transcription, and tests
├── context/                 # Mobile design reference and project file guide
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
├── render.yaml              # Hosted backend and web frontend deployment
├── requirements.txt         # Backend dependencies
└── README.md
```

See the [project file guide](context/file/project-file-guide.md) for the folder map and the purpose of the Android, iOS, and deployment file formats.

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

### Mobile navigation

- **Home:** the selected month's spending hero, daily spending bars, and recent expenses. Use the header month pill to change the period; pull down to refresh.
- **Activity:** searchable expenses grouped by day, Month/Year/All scope, category chips, and a category donut whose slices and legend filter the list.
- **Loans:** separate outstanding balances and Open/Settled history, excluded from spending.
- **+ button:** opens an expense sheet on Home/Activity or a loan sheet on Loans. Tap an existing row to edit it. Expense categories use a one-tap grid and remember the last saved selection; notes are optional.

Mobile initially uses the system's light/dark preference. The header's **Dark theme** switch overrides it and remembers your choice when you reopen the app. Swipe expense rows left to delete with Undo; swipe open loans left to settle with Undo. Changes wait until the snackbar's Undo window closes before being sent. If the app closes before that, the pending action is cancelled.

### Android voice entry

Open **Enter by voice** on the new expense form, or open the **Voice expense assistant**. The app sends up to 20 seconds of audio to the Python backend, which transcribes English with Whisper `base.en`. Voice input requires a connection to the tracker server. Assistant replies use an installed offline Android voice when available.

Docker and Render provision the Whisper model during the backend build. For a local backend, run the model setup command below before using voice entry. Deploy the updated backend before distributing the Android app.

### Check and build

From `mobile`:

```sh
flutter analyze
flutter test
dart tool/configure.dart
flutter clean
flutter pub get
flutter build apk
```

The release APK is generated at `mobile/build/app/outputs/flutter-apk/app-release.apk` relative to the repository root. For a debug APK, run `flutter build apk --debug`; its output is `mobile/build/app/outputs/flutter-apk/app-debug.apk`. Android builds need a configured Android SDK and compatible JDK. Kotlin incremental compilation is disabled because the project and package cache can reside on different Windows drives.

Release distribution requires your signing configuration; the Android scaffold currently uses debug signing for release builds. iOS builds require macOS, Xcode, and the appropriate signing setup:

```sh
flutter build ios --no-codesign
```

API and widget tests use a mock HTTP backend without changing the live database. They cover request payloads, refresh races, errors, startup without authentication, privacy, search, validation, add/edit/delete, loan balances, refunds and undo, expense isolation, and narrow mobile layouts. Run only the loan screen tests with `flutter test test/loans_test.dart`. Capture screen previews with:

```sh
flutter test test/app_test.dart test/loans_test.dart --dart-define=CAPTURE_SCREENSHOTS=true
```

Previews are written to `mobile/build/screenshots`, including Home, Activity, loan sheets and settlement history, dark mode, and 320px layouts with normal and 150% text. The suite also verifies that the theme switch overrides the system preference and persists across reopening. Device launch and iOS signing still require testing on the target platforms. See [mobile/README.md](mobile/README.md) for more details.

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
python backend/setup_voice_model.py
python -m uvicorn backend.main:app --reload --port 8000
```

PowerShell can also run the environment's Python directly without activation:

```powershell
.\venv\Scripts\python.exe -m pip install -r requirements.txt
.\venv\Scripts\python.exe backend\setup_voice_model.py
.\venv\Scripts\python.exe -m uvicorn backend.main:app --reload --port 8000
```

If the environment reports a missing Python executable after moving the project or changing Python installations, recreate the virtual environment with an installed Python and reinstall dependencies. Virtual environments are local and are not stored in Git.

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

### Backend tests

From the repository root, with backend dependencies installed in the active Python environment:

```sh
python -m pip install httpx
python -m unittest backend.test_loans backend.test_voice -v
```

Loan tests use an isolated in-memory SQLite adapter. Voice tests mock inference to check the upload and response contract without loading model weights. PostgreSQL deployment still needs a configured database.

### Enable borrowing and lending on an existing installation

Deploy or restart the updated backend before using the new clients. Backend startup creates the separate `loans` table and its user index with `CREATE ... IF NOT EXISTS`; existing expense records remain unchanged. Then rebuild the web frontend and install the updated mobile APK. Both clients use the same backend URL and profile ID to share loan entries.

For a Compose installation, run `docker compose up --build -d` from the repository root. For a local installation, restart the Uvicorn process with the updated code. For a hosted backend, deploy the updated backend source. If the clients cannot load the ledger, check `/api/health` and the backend startup logs.

## API

| Method | Endpoint | Purpose |
| --- | --- | --- |
| GET | `/api/health` | Backend and database health |
| POST | `/api/voice/transcribe` | Transcribe up to 20 seconds of raw 16 kHz mono 16-bit PCM and return a JSON transcript |
| GET | `/api/dashboard/stats` | Statistics for `user_id`, `month`, and `year` |
| GET | `/api/expenses` | Expenses for `user_id`, with optional month, year, and category filters |
| POST | `/api/expenses` | Create an expense, including `user_id` in the body |
| PUT | `/api/expenses/{id}` | Update an expense with `user_id` in the query |
| DELETE | `/api/expenses/{id}` | Delete an expense with `user_id` in the query |
| GET | `/api/loans` | Borrowed/lent entries and repayment history for `user_id` |
| POST | `/api/loans` | Record `user_id`, `person`, `direction` (`borrowed`/`lent`), positive `amount` (up to two decimals), `date`, and optional `note` |
| PUT | `/api/loans/{id}` | Edit person, direction, amount, date, and note with `user_id` in the query; preserves settlement status |
| PATCH | `/api/loans/{id}` | Set `refunded` to true/false, with `user_id` in the query |
| DELETE | `/api/loans/{id}` | Remove an incorrect entry with `user_id` in the query |
| POST | `/api/auth/google` | Existing web profile lookup/creation endpoint; unused by mobile |

The existing profile endpoint accepts an email; it does not verify Google credentials. The mobile application follows the backend's current user-ID-based contract.

## Files in Git

Commit application source, tests, database schema/migration scripts, documentation, the mobile design reference archive, native project files, font licenses, public mobile configuration, environment examples, and dependency lockfiles (`frontend/package-lock.json` and `mobile/pubspec.lock`).

The root [.gitignore](.gitignore) and platform-specific files under `mobile` exclude local environment files, signing credentials, virtual environments, dependency caches, generated native files, test reports, coverage, APKs/app bundles, build output, SQLite files, and JVM crash dumps. Keep local financial exports in `/exports/` and database backups in `/backups/`; both root folders are ignored. Store the actual shared ledger in the backend database rather than a repository file.
