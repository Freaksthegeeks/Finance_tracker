# Finance Tracker mobile

Flutter application for Android and iOS, based on `../frontend`. Opens directly into the tracker without Google authentication or a login screen.

Includes dashboard totals, interactive daily spending chart, recent expenses, monthly and yearly category breakdowns, amount privacy, adding expenses, searching/filtering history, editing, and confirmed deletion. Pull down to refresh; foreground data also refreshes every 15 seconds. Amount privacy is saved on the device.

## Run

From this folder, with Flutter installed and an emulator or phone connected:

```powershell
dart tool/configure.dart
flutter pub get
flutter run
```

`tool/configure.dart` reads **PUBLIC_URL from the repository root `.env`** and writes only that value to `assets/public_config.json`. Run it again after changing the endpoint, then rebuild. The root `.env` and database credentials are never bundled. The API client appends `/api` when needed and handles trailing slashes. The generated public config is included so ordinary `flutter run` works with the last configured endpoint.

No authentication endpoint is called. Requests use `google_varun_123`, the existing frontend's default profile ID, to share its expenses. The `google_` prefix is only an existing data identifier. To target a different existing backend profile:

```powershell
flutter run --dart-define=TRACKER_USER_ID=your_existing_user_id
```

The current backend resolves unknown IDs to its first user. Configure the exact ID when using a different profile. This app follows the existing backend contract; it does not add user authentication or change backend access rules.

## Check and build

```powershell
flutter analyze
flutter test
dart tool/configure.dart
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. Android builds require a configured Android SDK and compatible JDK. For Play Store distribution, configure your release signing key in `android/app/build.gradle.kts` (the scaffold currently uses debug signing), then build an app bundle. iOS builds require macOS, Xcode, your development team, and signing configuration:

```sh
dart tool/configure.dart
flutter pub get
flutter build ios --no-codesign
```

Automated tests use an in-memory HTTP backend, never the live database. They cover API ownership/payloads, out-of-order refreshes, failures, no-auth startup, privacy, search, form validation, add/edit/delete, and narrow screen layout. Optional screenshots:

```powershell
flutter test test/app_test.dart --dart-define=CAPTURE_SCREENSHOTS=true
```

Screenshots are saved under `build/screenshots`. Native platform launch and store signing still need validation on the target devices.

## Code

- `lib/config.dart`, `tool/configure.dart`: public endpoint configuration.
- `lib/api.dart`, `lib/models.dart`: typed REST client and backend data.
- `lib/tracker_controller.dart`: refresh state, period selection, privacy, and mutations.
- `lib/ui/`: mobile screens, form, theme, and interactive chart.

The networking setup follows [Flutter's networking guide](https://docs.flutter.dev/cookbook/networking/fetch-data), including the Android release internet permission. See [Flutter's Android deployment guide](https://docs.flutter.dev/deployment/android) for production signing.
