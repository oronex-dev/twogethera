# Twogethera · CP-001

A premium, private couples planner for Android, iOS, and responsive web. The approved screens remain public visual previews. CP-005A adds a debug-only, local, memory-only authentication proof at `/#/auth/local` and a protected account-context screen; it does not enable production authentication, planner data or partner linking.

## Toolchain and setup

Developed with **Flutter 3.47.7 stable / Dart 3.13.5**. `pubspec.yaml` declares the Dart constraint; `pubspec.lock` records exact resolved packages. Use this Flutter version to reproduce the verified environment. No credentials or paid services are required.

```sh
cd ~/Developer/twogethera
flutter doctor -v
flutter pub get
flutter run -d chrome
```

For a fixed local browser URL:

```sh
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

Open http://127.0.0.1:8080 after the server prints its ready message. Web URLs use Flutter's default hash routing (for example `/#/settings`), avoiding host rewrite requirements. A production host must serve HTTPS and the correct base path.

## Native platforms

Generated Android and iOS projects are preserved. Android requires Android Studio, an SDK, accepted licenses, and a device or emulator. iOS requires macOS, Xcode, its simulator runtimes, and CocoaPods where plugins require it.

```sh
flutter devices
flutter emulators
flutter run -d <device-id>
flutter build apk --debug
flutter build ios --simulator --debug
```

Physical iOS deployment additionally requires your own bundle identifier, Apple signing team, provisioning, and device trust. `com.example.twogethera` is a development identifier and must be replaced before release. No signing account was configured. macOS, Linux, and Windows applications are outside this milestone.

## Technical decisions

- Flutter Material 3: platform-compatible controls, generated color schemes, rose/lavender accents, soft neutral surfaces, and light/dark themes. Uses Flutter/platform typography with no remotely loaded font dependency.
- `flutter_riverpod` **3.4.3**: a root ProviderScope, router lifecycle, configuration injection, and session-only theme state. No code generation required.
- `go_router` **18.1.1**: `/` and `/settings`, direct URLs, and a safe unknown-route screen with a home action.
- Flutter SDK `flutter_test` and `flutter_lints` **6.0.0** for validation. No storage or cloud packages have been installed.
- Responsive bounded content, SafeArea, scrolling, flexible chips, accessible labels and native radio controls. System text scaling is preserved.
- Framework, platform asynchronous, and zone errors have local diagnostic handlers. Error UI avoids exposing exception details. Release diagnostics omit exception payloads; production crash reporting/recovery is future work.

Package documentation: [Riverpod](https://pub.dev/packages/flutter_riverpod) and [go_router](https://pub.dev/packages/go_router).

## Structure

```text
lib/
  main.dart                         entry point
  app/
    bootstrap.dart                  error hooks and ProviderScope
    twogethera_app.dart              MaterialApp.router
    routing/app_router.dart         routes and router disposal
    theme/                          Material 3 and theme state
  core/
    config/app_config.dart          public build environment
    errors/app_error_handler.dart   local diagnostics
  features/
    authentication/
    couple_linking/
    dashboard/
    bucket_list/
    important_dates/
    savings_tracker/
    plans/
    global_search/
    memories/
    settings/
  shared/widgets/responsive_page.dart
```

Each feature has `data/`, `domain/`, and `presentation/` directories. Only dashboard and appearance settings have screens. `.gitkeep` files preserve intentionally empty layers. See [feature boundaries](lib/features/README.md). Presentation depends on domain contracts; data implements those contracts; the app composes providers. No speculative repositories or fake backends are included.

## Configuration

`APP_ENV` accepts `development` (default), `staging`, or `production`:

```sh
flutter run -d chrome --dart-define=APP_ENV=development
```

This is a public environment label only; it currently does not switch services. Invalid values fail configuration validation. Dart defines are embedded in client builds: never use them for server secrets. No Supabase project, credentials, or analytics are configured.

## Verification

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
```

Widget tests cover 320/768/1440 logical-pixel widths at 200% text scale, scrolling, appearance navigation, light/dark/system behavior, unknown-route recovery, and home-screen tap targets, labels, and contrast. See [CP-001 verification](docs/CP-001.md) for actual build results and file inventory.

## Planned modules and dependencies

Future milestones will introduce authentication and secure couple linking, bucket lists, important dates and shared calendars, savings goals, plans, global search, memories, notifications, widgets, and personalization.

- Drift/SQLite: local schema, migrations, repositories, and web-compatible persistence; choose and verify web workers/WASM and browser storage behavior when implementing offline storage.
- Supabase Auth/PostgreSQL/Storage/Realtime: couple authorization, row-level security, private media policies, cross-device events, and synchronization.
- Offline queue/reconciliation: conflict rules, retries, deletion semantics, and reconnect behavior before making any sync guarantees.
- Platform notification/widget integrations: select packages when permission and background execution requirements are defined.
- PWA installation/offline application shell: later milestone; the generated manifest alone is not a verified offline PWA.

## Known limitations

This is a functional foundation preview. Accounts, partner linking, planner operations, persistence, sync, notifications, calendars, photos, and search are not implemented. Theme selection resets on restart. App icons are Flutter placeholders. Localization and production crash reporting are deferred. No physical-device run, release signing, app-store readiness, or PWA/offline support is claimed.

## Next milestone

**CP-002:** agree on the domain model, data ownership and couple-link lifecycle, authorization/security requirements, and offline conflict policy before implementing persistence and real authentication. Stop here until CP-002 is authorized.

## CP-002 architecture blueprint

The proposed data model, security policies, partner linking, offline protocol, lifecycle, and application contracts are documented in [docs/architecture/README.md](docs/architecture/README.md). These are planning specifications only; no backend or authentication is implemented. See the decision register and CP-003 approval gate before implementation.

## CP-003A visual system

The app now includes an original glossy-gradient identity, adaptive Home/Studio/Appearance navigation, reusable UI components, and refined light/dark themes. The Studio at `/#/studio` provides working ephemeral interaction previews. Architecture decision status is maintained in the architecture register; visual approval does not approve product data policies.

See [visual system](docs/design/VISUAL_SYSTEM.md), [preview gallery](docs/design/PREVIEWS.md), and [implementation report](docs/CP-003A.md). No authentication, backend, database, or persistent preferences have been introduced.

## CP-003B · D01–D03 resolution

D01 is approved; D02 is approved with safeguards; D03 records a revised minimal-audit-history policy with implementation-level privacy choices unresolved. D04–D11 remain pending. See [decision record and open P01–P09](docs/architecture/D01_D03_RESOLUTION.md) and [current approval register](docs/architecture/APPROVAL_REVIEW.md). Earlier milestone reports/design documentation describe their historical approval state; the current architecture register takes precedence for product-policy status. CP-003B Part 1 is documentation only and preserves the approved visual design.


## CP-005A local authentication foundation

See [docs/CP-005A.md](docs/CP-005A.md) for current architecture, test evidence, limitations and local preview commands. Historical milestone sections above retain their original scope statements. The new proof uses the pure Dart Supabase client with explicit memory-only PKCE storage, an explicitly accepted in-memory session, disabled refresh and a private account-context adapter. No hosted project, persistent login, registration/recovery UI or shared-data implementation is enabled. Local development controls/routes are absent from release builds.
