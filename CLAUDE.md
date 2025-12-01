# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lovablee is an iOS SwiftUI app for couples to care for a shared virtual pet ("Bubba"). The app features:
- Sign-in with Apple authentication flow
- Push notifications via APNs
- Supabase backend for user/pet state, pairing codes, and activity feeds
- Lottie animations for interactive pet graphics
- Partner pairing via unique codes to share a pet

## Build & Development Commands

**Open project:**
```bash
open lovablee.xcodeproj
```

**Build from CLI:**
```bash
xcodebuild -scheme lovablee -destination 'platform=iOS Simulator,name=iPhone 15' build
```

**Run tests (unit + UI):**
```bash
xcodebuild test -scheme lovablee -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Run unit tests only:**
```bash
xcodebuild test -scheme lovablee -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:lovableeTests
```

**Common development workflow:**
- Run the app in Xcode simulator (`⌘R`)
- Use SwiftUI preview canvas for rapid UI iteration
- Test push notifications require a physical device or simulator with APNs configured

## Architecture & Code Organization

### App Flow & Navigation

The app uses a stage-based navigation flow managed in `ContentView.swift`:
1. **Onboarding** → visual intro with lights-out toggle
2. **Name Entry** → user enters display name
3. **Preferences** → user selects initial preferences
4. **Auth** → Sign in with Apple via `AuthFlowView`
5. **Notifications** → request APNs permissions via `NotificationPermissionView`
6. **Dashboard** → main app experience with tabbed navigation

`ContentView.swift` is the orchestrator (~2760 lines) that manages session state, authentication, and backend sync. It holds:
- `SupabaseSession` and `SupabaseUserRegistrationResult` for auth/user state
- Session restore logic (`SupabaseSessionStore`)
- User registration, pairing, and account deletion flows
- Pet status and activity feed fetching

### Dashboard & Pet Care

`DashboardView.swift` (~3100 lines) is the main UI after login. It contains:
- **Tabbed navigation:** Home, Care, Activity, Profile
- **CozyDecorLayer:** Interactive room decorations with lights toggle
- **Pet interactions:** Water and play actions with cooldown timers
- **Partner pairing:** Join/leave partner via pairing codes
- **Activity feed:** Shows recent partner/pet interactions
- **Profile management:** Upload photos, view pairing code, logout/delete account

Pet state is managed via `SupabasePetStatus` model (`PetCareModels.swift`):
- `hydrationLevel`, `playfulnessLevel`, `hearts`, `streakCount`
- Cooldown timestamps for water/play actions
- Pet mood and name

### Supabase Backend Integration

All backend API calls are made via custom URLSession requests in `ContentView.swift`:
- **Auth:** `signInWithApple()`, `refreshSession()`, `signOut()`, `deleteUserAccount()`
- **User management:** `registerUser()`, `fetchUserRecord()`, `joinPartner()`, `leavePartner()`
- **Pet actions:** `fetchPetStatus()`, `performPetAction()`, `updatePetName()`
- **Activity feed:** `fetchCoupleActivity()`

**Important patterns:**
- All requests use `SupabaseSession.accessToken` for authorization
- Session refresh logic (`refreshSupabaseSession()`) retries on 401 errors
- API base URL is hardcoded in each function (look for `https://ahtkqcaxeycxvwntjcxp.supabase.co`)
- User profile photos stored in Supabase Storage at `profile-photos/{userId}/avatar.jpg`

### Push Notifications

Push notifications handled via:
- **Client:** `PushNotificationManager.swift` requests permissions, registers APNs token
- **Backend:** `supabase/functions/send-push/index.ts` sends notifications via APNs HTTP/2 API
- Device tokens stored in `users.apns_token` column
- Currently configured for APNs **sandbox** environment

`AppDelegate` bridges device token to `PushNotificationManager` via `@UIApplicationDelegateAdaptor`.

### Database Schema

See `supabase/schema.sql` for full schema. Key tables:
- **users:** Apple ID, display name, partner links, pairing codes, APNs tokens
- **pet_status:** Per-user pet state (mood, levels, timestamps)
- **couple_activity:** Shared activity feed for paired users

Pairing codes are auto-generated 8-character hex strings (see `generate_pairing_code()` function).

## Key Dependencies

- **Lottie:** Used for animated pet graphics (`import Lottie`, `LottieView`)
  - Animations stored as JSON: `water.json`, `paws.json`
- **SwiftUI:** Entire UI layer
- **Sign in with Apple:** `AuthenticationServices` framework
- **Supabase:** Backend (no official Swift SDK used; custom URLSession calls)

## File Structure

```
lovablee/
├── lovableeApp.swift          # App entry point, injects PushNotificationManager
├── ContentView.swift          # Main orchestrator: auth, session, backend sync
├── DashboardView.swift        # Tabbed dashboard UI
├── ProfileView.swift          # Profile tab UI (~509 lines)
├── PetCareModels.swift        # Data models for pet status & activity
├── PushNotificationManager.swift  # APNs registration & permissions
├── Assets.xcassets/           # Images, colors, app icon
├── *.json                     # Lottie animation files
└── Info.plist                 # Bundle config, APNs entitlements

lovableeTests/         # Unit tests (Swift Testing framework)
lovableeUITests/       # UI tests (XCTest)

supabase/
├── config.toml        # Supabase project config
├── schema.sql         # Database schema & functions
└── functions/
    └── send-push/     # APNs push notification edge function
```

## Testing

- **Unit tests:** Use Swift Testing framework (`#expect` assertions) in `lovableeTests/`
- **UI tests:** Use XCTest framework (`XCUIApplication`) in `lovableeUITests/`
- Keep preview data lightweight; see `#if DEBUG` extensions in `PetCareModels.swift`

## Important Configuration Notes

- **Hardcoded Supabase URL:** API calls use `https://ahtkqcaxeycxvwntjcxp.supabase.co` directly
- **APNs environment:** Currently sandbox; production push requires changing `api.sandbox.push.apple.com` to `api.push.apple.com` in `send-push/index.ts`
- **AuthKey file:** `AuthKey_LHA3T3F24P.p8` in root (Apple Push Notification auth key; do not commit to version control)
- **Bundle ID:** Configured in Xcode project (used for APNs topic)

## Code Style (from AGENTS.md)

- Swift 5/SwiftUI, 4-space indent
- Favor `struct` + immutable `let`; use `@State` sparingly
- Types in `PascalCase`, variables/functions in `camelCase`
- Use `// MARK:` sections for organization in large files
- `guard` for early exits

## Common Patterns

**Async operations with error handling:**
```swift
Task {
    do {
        let result = try await someBackendCall()
        // update state
    } catch {
        print("Error: \(error)")
    }
}
```

**Session-aware API calls:**
All backend operations use `performWithFreshSession()` wrapper to handle token refresh automatically.

**Profile photo URLs:**
- Format: `https://{supabase_url}/storage/v1/object/public/profile-photos/{userId}/avatar.jpg?v={version}`
- Version param prevents caching; regenerated via `UUID().uuidString` on upload
