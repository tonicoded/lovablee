# Repository Guidelines

## Project Structure & Module Organization
- App code lives in `lovablee/`. `lovableeApp.swift` is the entry point; `ContentView.swift` drives the onboarding/name/preferences flow; `Assets.xcassets` stores images and colors; `Info.plist` holds bundle metadata.
- Tests sit alongside the app target: `lovableeTests/` (Swift `Testing` for logic) and `lovableeUITests/` (XCTest UI harness). The Xcode project is `lovablee.xcodeproj`.
- Keep new SwiftUI views modular; group related views/helpers together and keep assets under `Assets.xcassets` with clear names (e.g., `background`, `icon/heart_fill`).

## Build, Test, and Development Commands
- Open in Xcode: `open lovablee.xcodeproj`.
- Run in simulator from Xcode (`⌘R`) using the `lovablee` scheme.
- CLI build: `xcodebuild -scheme lovablee -destination 'platform=iOS Simulator,name=iPhone 15' build`.
- CLI tests (unit + UI): `xcodebuild test -scheme lovablee -destination 'platform=iOS Simulator,name=iPhone 15'`. For a quick unit-only pass, disable UI tests in the scheme or use `-only-testing:lovableeTests`.
- Regenerate previews by running the app or using the SwiftUI preview canvas; keep preview data lightweight.

## Coding Style & Naming Conventions
- Swift 5/SwiftUI, 4-space indent, trailing commas for multiline collections, and `guard` for early exits.
- Favor `struct` + immutable `let` where possible; keep state in the smallest scope (`@State` in views, pure helpers elsewhere).
- Naming: types in `PascalCase`, variables/functions in `camelCase`, assets in lowercase with underscores if needed. Keep view names descriptive of their role (e.g., `PreferenceSelectionView`).
- Organize larger files with `// MARK:` sections. Limit comments to non-obvious logic; prefer clear function names.

## Testing Guidelines
- Unit tests use the new `Testing` package (`#expect` assertions). UI tests use XCTest with `XCUIApplication`.
- Name tests descriptively (`test<Behavior>`); keep UI tests resilient by avoiding hard-coded waits—prefer existence checks.
- Run tests before pushing: `xcodebuild test -scheme lovablee -destination 'platform=iOS Simulator,name=iPhone 15'`.
- Add fixtures/mocks near the tests that consume them; avoid hitting live network/services.

## Commit & Pull Request Guidelines
- Commit messages: present tense, concise, scoped to one change (e.g., `Add preference picker layout`).
- PRs should describe the user-facing change, include simulator/device tested, and mention any new assets/configuration.
- Link issues when applicable and attach screenshots or screen recordings for UI changes (light and dark variants if relevant).
- Ensure tests pass locally; note any skipped tests and justify them.

## Security & Configuration Tips
- Do not commit secrets, certificates, or provisioning profiles. Use environment-specific configuration via Xcode build settings or ignored `.xcconfig` files if needed.
- Keep assets and generated files out of version control unless they are required at runtime.***
