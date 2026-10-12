# Repository Guidelines

## Project Overview

Rhythm (节律) is an Android-first, offline Flutter planner: Today timeline, seven-column weekly calendar, inbox, execution history, and weekly review. No account or server is required. Keep application code in `app/`; `docs/goal.md` defines product behavior and non-goals. Its suggested libraries are not mandates to replace the existing architecture.

## Architecture & Data Flow

- Startup loads `Planner`, initializes `ReminderService`, and constructor-injects both into the app. One `Planner extends ChangeNotifier` owns durable state; `RhythmShell` rebuilds through `AnimatedBuilder`. Widgets retain only local interaction state—do not introduce per-screen task stores.
- UI actions build `TaskDraft` or invoke planner operations. `Planner._mutate()` serializes changes, copies the snapshot, awaits persistence, then publishes state and notifies listeners. Failed writes must not publish success or poison subsequent operations.
- `core/models.dart` defines tasks, versioned rules, overrides, and immutable execution snapshots. `core/recurrence.dart` derives occurrences for half-open query windows; do not pre-generate years of instances. `core/planner.dart` owns edits, history, summaries, and strict backup validation.
- `core/snapshot_store.dart` persists one versioned JSON document: native SQLite transactions with WAL/FULL synchronization; Web uses `SharedPreferencesAsync` browser storage. Do not move native task/history storage into preferences. Restore is validated, confirmed **full replacement**, never merge.
- `core/reminders.dart` derives Android alarms from the same occurrences, refreshes on planner changes/app resume, and renews a rolling 30-day window through WorkManager. Notification errors are reported separately from durable planner state.

Preserve these compatibility-sensitive invariants:

- Occurrence IDs use the rule and **original UTC start**; postponement changes effective time, not identity. Cross-midnight segments share one occurrence/execution.
- `ScheduleRule.start` carries wall-clock components in a UTC `DateTime`; it is **not** the resolved instant. Apply the saved rule timezone through `Recurrence.resolve()`. Existing rules retain their timezone; folds choose the earlier instant, gaps advance to the first valid time, and duration is elapsed minutes. UTC uses `tz.UTC` explicitly.
- Rule versions share `seriesId`; edits/deletes retain completed/skipped snapshots. Keep single, future, and entire-series scopes distinct. Overdue does not automatically skip; skipping does not roll forward.
- Plans belong to their original rule-zone week; actual completions belong to the device-local execution week. Skips stay in the rate denominator; inbox completions affect actual counts only. No plans means no percentage.

## Key Directories

- `app/lib/core/`: shared business rules and platform/data services.
- `app/lib/features/`: `calendar.dart` (Today/Week), `lists.dart` (Inbox/Review), editor/detail/settings, and shared UI helpers.
- `app/test/`: deterministic planner behavior and real SQLite-file tests.
- `app/android/`, `app/web/`: platform configuration, not alternate business implementations.
- `app/docs/`: QA evidence; `app/assets/fonts/`: bundled Noto font and OFL license. Generated `app/build/` and `.dart_tool/` are not source.

## Development Commands

Run from `app/`:

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter test test/planner_test.dart
flutter test test/sqlite_persistence_test.dart
flutter run -d <android-device-id>
flutter build apk --release --split-per-abi
flutter build web --target lib/main.dart --no-web-resources-cdn --no-wasm-dry-run
python3 -m http.server 18080 --directory build/web
```

APKs are emitted under `app/build/app/outputs/flutter-apk/`. Only for container engine-unpacking ownership failures, prefix the build with `env TAR_OPTIONS=--no-same-owner`.

## Code Conventions & Common Patterns

- Use `dart format` and the `flutter_lints` preset in `app/analysis_options.yaml`. Follow `snake_case.dart`, `UpperCamelCase` types, `lowerCamelCase` members, and `_private` implementation details.
- Pass dependencies through constructors. Test seams include `Planner.memory(clock:, persist:, timezone:)`, `Planner.load(store:, clock:)`, and `SnapshotStore.open(factory:, path:)`; reuse these rather than adding a DI framework.
- Await mutations. Shared UI helper `features/common.dart::perform()` presents failures; editor failures retain the form. Check `mounted` after async work before using widget context, and dispose observers/listeners/controllers.
- Keep business calculations and JSON relationship validation in core, not widgets. Never silently reset corrupt storage or swallow mutation failures; reminder status uses `statusText`/`lastError` without discarding tasks.
- Preserve Chinese UI, system theme/text scaling, and accessible alternatives for dense calendar blocks. Update behavior tests and relevant docs when changing contracts; avoid unrelated architectural rewrites.

## Important Files

- `app/lib/main.dart`: startup, load-error recovery, localization, and `rhythmTheme()`.
- `app/lib/core/backup_files.dart`: actual file-picker JSON import/export; confirmation lives in `features/settings.dart`.
- `app/pubspec.yaml` / `app/pubspec.lock`: dependency declarations and resolved versions.
- `app/android/app/build.gradle.kts`: Flutter-derived SDK levels, Java/Kotlin target 17, desugaring, and signing.
- `app/android/app/src/main/AndroidManifest.xml`: notification/exact-alarm/boot permissions and receivers.
- `app/android/app/src/main/res/raw/keep.xml`: retain `drawable/ic_notification`, loaded by name. Removing this caused a real release-only `invalid_icon` failure.
- `app/README.md`, `app/docs/android-verification.md`, `app/CHANGELOG.md`: current workflows and native evidence; `app/docs/verification.md` includes earlier, explicitly historical Web evidence.

## Runtime/Tooling Preferences

Use Flutter/Dart and Pub, not npm/Bun/Node; there is no repository-owned script runner. Dart requires `^3.13.5`; documented validation used Flutter 3.47.7 stable, OpenJDK 21, and Android SDK 36. Retain the lockfile and reverify upgrades, especially the documented `workmanager_android` Kotlin migration warning.

Release builds currently use **debug signing** for sideload validation, not production distribution. Never commit signing keys, `local.properties`, caches, or build outputs. Setup/builds need network; installed core functionality does not. Headless Chromium is suitable for Web UI checks; `--no-sandbox` is an isolated-container workaround, not a general browser preference.

## Testing & QA

The permanent suites use `flutter_test`; there is currently no widget/integration suite. `planner_test.dart` exercises recurrence, identity, scopes, DST, statistics, backup validation, and serialized/failing writes. `sqlite_persistence_test.dart` uses `sqflite_common_ffi`, temporary files, connection reopen, and real transaction aborts. Inject clocks instead of sleeping; close stores, delete temporary databases, and clear mocked timezone-channel handlers.

Test consumer-visible boundaries and state transitions, not source text or forwarding. There is no configured numeric coverage threshold. For changes, run focused tests plus analysis and smoke the affected UI/API; native changes require a release APK check as well.

Evidence is platform-specific: Web does not prove Android plugins/notifications, SQLite FFI does not prove Android platform channels, and APK/manifest inspection does not prove delivery. Android 11 device evidence exists, including notifications after reboot and large-font/soft-keyboard actions; Android 12+ exact-alarm permission UI, Android 13+ notification prompts, and airplane-mode testing remain uncovered. Do not promote historical results into claims about new edits. Preserve user data and obtain permission before disruptive device operations such as reboot or radio changes.
