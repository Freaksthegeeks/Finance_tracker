# Finance Tracker file guide

Finance Tracker has three parts. The Python backend handles the API, PostgreSQL access, and voice transcription. The React frontend runs in a web browser. The Flutter app runs on Android and iOS, with voice entry currently available on Android.

## Folder structure

This tree groups repeated images and lists the main source and configuration files. Package contents, virtual environments, build outputs, and caches are omitted. Flutter's `mobile/lib/` is included because it contains the app's own Dart source.

```text
Finance_Tracker/
├── README.md
├── render.yaml
├── docker-compose.yml
├── requirements.txt
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py
│   ├── voice.py
│   ├── setup_voice_model.py
│   ├── test_loans.py
│   └── test_voice.py
├── frontend/
│   ├── README.md
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── package.json
│   ├── package-lock.json
│   ├── vite.config.js
│   ├── eslint.config.js
│   ├── index.html
│   ├── public/vite.svg
│   └── src/
│       ├── main.jsx
│       ├── App.jsx
│       ├── App.css
│       ├── index.css
│       ├── Loans.jsx
│       └── useLoans.js
├── mobile/
│   ├── README.md
│   ├── pubspec.yaml
│   ├── pubspec.lock
│   ├── analysis_options.yaml
│   ├── assets/
│   │   ├── public_config.json
│   │   └── fonts/                     # Roboto .ttf files and LICENSE.txt
│   ├── lib/
│   │   ├── main.dart
│   │   ├── api.dart
│   │   ├── config.dart
│   │   ├── cache.dart
│   │   ├── models.dart
│   │   ├── tracker_controller.dart
│   │   ├── expense_speech.dart
│   │   ├── voice_expense_commands.dart
│   │   ├── voice_recording.dart
│   │   └── ui/                       # Expense form, assistant, home, loans, chart, theme (.dart)
│   ├── test/                         # Widget, startup, API, loan, and voice tests (.dart)
│   ├── tool/configure.dart
│   ├── android/
│   │   ├── settings.gradle.kts
│   │   ├── build.gradle.kts
│   │   ├── gradle.properties
│   │   ├── gradle/wrapper/gradle-wrapper.properties
│   │   └── app/
│   │       ├── build.gradle.kts
│   │       └── src/
│   │           ├── debug/AndroidManifest.xml
│   │           ├── profile/AndroidManifest.xml
│   │           └── main/
│   │               ├── AndroidManifest.xml
│   │               ├── kotlin/       # MainActivity.kt and ExpensePlayback.kt
│   │               └── res/          # Themes and launch XML, launcher PNGs
│   └── ios/
│       ├── Flutter/                  # Debug/Release .xcconfig and AppFrameworkInfo.plist
│       ├── Runner.xcodeproj/          # .pbxproj, shared .xcscheme, project workspace metadata
│       ├── Runner.xcworkspace/        # Workspace metadata and settings
│       ├── RunnerTests/RunnerTests.swift
│       └── Runner/                   # .swift, .h, .plist, .storyboard, icons and asset catalogs
└── context/
    ├── design system/Finance Tracker Mobile.zip
    └── file/project-file-guide.md
```

## Deployment and dependencies

| File | Language or format | What reads it and why this project uses it |
| --- | --- | --- |
| `render.yaml` | YAML configuration | Render uses it to define two hosted services. It installs Python dependencies, downloads the Whisper model, and starts FastAPI with Uvicorn. It separately builds and serves the Vite frontend, gives it the hosted API URL, and sends browser routes to `index.html`. |
| `docker-compose.yml` | YAML configuration | Docker Compose starts the backend and frontend containers together for local use. It passes the database configuration to FastAPI and points the frontend's Nginx proxy at the backend container. |
| `backend/Dockerfile` | Dockerfile build syntax with shell commands | Docker builds a Python image, installs dependencies, provisions Whisper, and starts the API. The file has no extension. |
| `frontend/Dockerfile` | Dockerfile build syntax with shell commands | Docker builds the React site and packages the static files with Nginx. |
| `frontend/nginx.conf` | Nginx configuration syntax | Nginx serves the built site and forwards `/api/` calls to FastAPI when running in Docker. |
| Root and backend `requirements.txt` | pip requirements syntax | The root list supports local backend setup. The backend copy is used by Render and by Docker's backend build context. Keep the dependency lists aligned. |
| `frontend/package.json` | JSON | npm reads the web app's JavaScript dependencies and commands such as the development server and production build. |
| `frontend/package-lock.json` | JSON lockfile | npm records the exact resolved dependency tree, including indirect dependencies. This keeps fresh frontend installs consistent. Commit it when npm updates it. |
| `frontend/vite.config.js`, `frontend/eslint.config.js` | JavaScript configuration | Vite configures the React development and build tool. ESLint configures code checks for the web source. |
| `mobile/pubspec.yaml` | YAML configuration | Flutter reads the app's dependencies, SDK requirements, version, bundled public API configuration, and fonts. |
| `mobile/pubspec.lock` | Pub's YAML lockfile | Dart Pub records the exact dependency versions installed for the mobile app, including indirect packages such as the Android recorder implementation. Update it through Pub after changing dependencies. |
| `mobile/analysis_options.yaml` | YAML configuration | The Dart analyzer reads it to apply Flutter lint rules to the app source. |
| `mobile/assets/public_config.json` | JSON | Flutter bundles the generated public backend URL so it can reach the right API. `mobile/tool/configure.dart` refreshes this file from the root environment configuration. |

## Android files in detail

Paths in this section start at `mobile/android/`.

| File | Language or format | What reads it and why this project uses it |
| --- | --- | --- |
| `app/src/main/kotlin/…/MainActivity.kt` | Kotlin | Android starts this activity to host the Flutter engine. It registers the native playback bridge and stops playback when the activity pauses. |
| `app/src/main/kotlin/…/ExpensePlayback.kt` | Kotlin | Bridges the Flutter assistant to Android's installed text-to-speech engine. It selects an offline English voice to read replies aloud. Speech recognition runs in Python on the backend. |
| `settings.gradle.kts` | Kotlin DSL for Gradle | Locates the Flutter SDK build integration, declares build plugins, and includes the Android `:app` module. |
| `build.gradle.kts` | Kotlin DSL for Gradle | Configures build settings shared by the Android Gradle project. |
| `app/build.gradle.kts` | Kotlin DSL for Gradle | Defines how to build and package the Android app, including its application ID, SDK settings, version, and signing setup. |
| `gradle.properties` | Java properties, written as `key=value` | Sets project-wide options for Gradle and Android tooling. |
| `gradle/wrapper/gradle-wrapper.properties` | Java properties | Tells the Gradle Wrapper which Gradle distribution to use. The local `gradlew` and `gradlew.bat` launch it on Unix-style shells and Windows. The wrapper `.jar` is a Java archive containing the bootstrap code. |
| `app/src/main/AndroidManifest.xml` | Android manifest XML | Declares the app's entry activity, microphone and internet access, and discovery of installed text-to-speech engines. Android and Gradle use it when building and running the APK. |
| `app/src/debug/AndroidManifest.xml`, `app/src/profile/AndroidManifest.xml` | Android manifest XML | Gradle merges these with the main manifest for debug and profiling builds. They declare internet access for Flutter development tooling in those variants. |
| `app/src/main/res/values/styles.xml`, `res/values-night/styles.xml` | Android resource XML | Configure the native window themes used around Flutter startup, with a night-mode variant. |
| `app/src/main/res/drawable/launch_background.xml`, `res/drawable-v21/launch_background.xml` | Android drawable XML | Define the native background displayed while Flutter loads. Android selects the compatible resource variant. |
| `app/src/main/res/mipmap-*/ic_launcher.png` | PNG images | Android chooses the launcher icon at the appropriate screen density. |

### What `.iml` files do

`.iml` means **IntelliJ module file**. It is XML metadata used by IntelliJ IDEA or Android Studio. Local copies are ignored by Git.

- `mobile/finance_tracker.iml` identifies Flutter source and test directories, Dart and Flutter libraries, and folders the IDE should exclude from indexing.
- `mobile/android/finance_tracker_android.iml` describes the Android module to the IDE, including where it can find the manifest and Android resources.

These files support editor features such as navigation and indexing. Gradle and Flutter can recreate the IDE metadata when the project is imported. The Android build uses the Gradle scripts and Android manifests.

## iOS files

| File or extension | Language or format | Why it is used here |
| --- | --- | --- |
| `Runner/AppDelegate.swift`, `Runner/SceneDelegate.swift`, `RunnerTests/RunnerTests.swift` | Swift | Native iOS application and scene setup, plus the iOS test target. |
| `Runner/Runner-Bridging-Header.h` | Objective-C header | Exposes the generated Flutter plugin registrant to Swift. |
| `Runner/Info.plist`, `Flutter/AppFrameworkInfo.plist` | XML property lists | Supply iOS app metadata and Flutter framework bundle metadata. |
| `Flutter/*.xcconfig` | Xcode build settings syntax | Connect Flutter-generated build settings to the debug and release Xcode configurations. |
| `Runner.xcodeproj/project.pbxproj` | Xcode project format | Defines targets, resource lists, build phases, and settings used to build the iOS app. |
| `*.xcscheme`, `*.xcworkspacedata`, `*.xcsettings` | Xcode XML and property-list formats | Store shared run and build actions, workspace project references, and workspace preferences. |
| `Runner/Base.lproj/*.storyboard` | Interface Builder XML | Describe the native launch screen and the initial Flutter view host. |
| `Assets.xcassets/**/Contents.json` and `.png` images | JSON and PNG | Xcode maps icon and launch images to supported sizes and display scales. |

## Application source and supporting files

| File or group | Language or format | Role in Finance Tracker |
| --- | --- | --- |
| `backend/main.py`, `backend/test_*.py` | Python | FastAPI routes, database operations, and tests for loan and transcription APIs. |
| `backend/voice.py`, `backend/setup_voice_model.py` | Python | Load the pinned Whisper model and turn uploaded microphone audio into text. The setup script downloads the model used by the server. |
| `frontend/src/*.jsx`, `frontend/src/useLoans.js` | JSX and JavaScript | Render the browser dashboard and loans UI, and coordinate web API calls for loans. |
| `frontend/index.html`, `frontend/src/*.css`, `frontend/public/vite.svg` | HTML, CSS, and SVG XML | Start the React app in the browser, define web styles, and supply the currently referenced browser-tab icon. |
| `mobile/lib/main.dart`, `ui/*.dart` | Dart with Flutter widgets | Launch the mobile app and render its screens, forms, charts, and voice assistant. |
| `mobile/lib/api.dart`, `config.dart`, `cache.dart`, `models.dart`, `tracker_controller.dart` | Dart | Connect to the backend, cache data locally, represent API data, and coordinate app state. |
| `mobile/lib/voice_recording.dart`, `expense_speech.dart`, `voice_expense_commands.dart` | Dart | Capture audio and upload it to FastAPI, then interpret returned text as expense amounts, notes, and assistant commands. |
| `mobile/test/*.dart`, `mobile/tool/configure.dart` | Dart | Verify mobile behavior and generate the public backend URL configuration. |
| `mobile/assets/fonts/*.ttf`, `LICENSE.txt` | TrueType font and plain text | Bundle the Roboto typefaces and their license for the mobile UI. |
| `README.md`, `mobile/README.md`, `frontend/README.md` | Markdown | Provide project and component instructions. |
| `context/design system/Finance Tracker Mobile.zip` | ZIP archive | Stores the mobile UI design reference. |
