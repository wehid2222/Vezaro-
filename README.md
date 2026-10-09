# Vezaro

Flutter-based direct-file downloader with Arabic and English UI.

## Current implementation

- Direct HTTP/HTTPS downloads using Dio.
- App-private storage or Android's public Downloads collection, selected by the user.
- Download progress and cancellation.
- Persistent download history with a file-existence check at startup.
- Basic validation for URL format, HTTP response status, empty files, HTML responses, and server-provided file names.
- Plain HTTP links trigger a user warning because traffic is not encrypted; HTTPS is preferred.
- Android MediaStore support on Android 10+; legacy public Downloads writing requests storage permission on Android 6–9.
- Platform page links are detected and clearly reported as requiring a platform-specific extractor. Extractors are not included or claimed to be supported yet.

## Build and test

Run these commands in an environment with the Flutter SDK and Android SDK installed:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The uploaded source archive did not include Gradle wrapper binaries; the CI workflow generates a clean wrapper template and copies only the wrapper files without overwriting Vezaro native code.

The current repository does not include a release signing key. The Gradle release configuration must be connected to a securely managed release keystore before publishing. Never commit keystore files or passwords to source control.

## Important validation note

This source archive was updated in an environment without the Flutter/Dart SDK. The source changes and project configuration must still pass `flutter pub get`, `flutter analyze`, `flutter test`, and an Android build on a configured Flutter machine before the APK can be treated as verified.
