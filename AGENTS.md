# Repository Guidelines

## Project Structure & Module Organization
- Entry point: `lib/main.dart`.
- Source layout under `lib/`:
  - `lib/pages/` UI screens
  - `lib/widgets/` reusable widgets
  - `lib/services/` app services (settings, navigation, WebView backend, HTTP overrides)
  - `lib/api/` network clients (e.g., `linuxdo_api.dart`)
  - `lib/models/` data models
- Tests in `test/` as `*_test.dart`.
- Platform targets: `android/`, `ios/`, `macos/`, `linux/`, `web/`, `windows/`.

## Build, Test, and Development Commands
- Install deps: `flutter pub get`
- Analyze lints: `flutter analyze`
- Format code: `dart format .`
- Run app: `flutter run -d chrome` (or `-d android`, `-d macos`, etc.)
- Run tests: `flutter test`
- Build artifacts: `flutter build apk --release`, `flutter build ios`, `flutter build web`

## Coding Style & Naming Conventions
- Linting: uses `flutter_lints` (see `analysis_options.yaml`). Fix all analyzer issues.
- Indentation: 2 spaces; include trailing commas on multiline args/collections.
- Prefer `const` constructors and widgets where possible; avoid `print` (use `debugPrint` or a logger).
- File names: `snake_case.dart`; types: `PascalCase`; variables/functions: `lowerCamelCase`.
- Document public APIs with `///` summaries when non-trivial.

## Testing Guidelines
- Framework: `flutter_test` with `testWidgets` for UI and `test` for units.
- Location/naming: place under `test/`, end with `_test.dart`.
- Aim to cover services and complex widgets; add smoke tests for main pages.
- Run `flutter test` and ensure `flutter analyze` is clean before pushing.

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat(scope): summary`, `fix(api): ...`. Chinese or English is acceptable; keep scope concise (`pages`, `services`, `api`, `widgets`).
- One logical change per commit; keep diffs focused.
- PRs include: clear description, linked issues, screenshots/screen recordings for UI changes, and platforms tested (Android/iOS/Web/Desktop).
- Ensure builds/tests pass; avoid unrelated refactors.

## Security & Configuration Tips
- Don’t commit secrets/tokens. Persist local prefs via `SettingsService`.
- Keep network/cookie behavior in `lib/services/http_overrides.dart` and `lib/services/webview_backend.dart`.

## Agent-Specific Instructions
- Preserve existing structure and naming; prefer additive changes over large refactors.
- Before proposing changes, run: `flutter analyze` and `flutter test`.
