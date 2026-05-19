# Syncra

AI career agent — Flutter + Firebase + Anthropic. Scans roles, tailors resumes, drafts applications.

<img width="500" height="800" alt="image" src="https://github.com/user-attachments/assets/d1244a19-f14f-42de-9558-1e1a3e1f267f" />

## Prerequisites

- **Flutter** `^3.11.0` (`flutter --version` to check)
- **Xcode** for iOS, **Android Studio** SDK for Android
- An **Anthropic API key** (`sk-ant-…`) — without it, the agent falls back to mock services and still runs.

## First-time setup

```bash
git clone <repo>
cd syncra_flutter
flutter pub get
```

Firebase config (`lib/firebase_options.dart`, `ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json`) is already committed — no FlutterFire CLI step needed.

## Run

```bash
flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...
```

Or, if you want to test the mock-only flow (no LLM calls, no token spend):

```bash
flutter run
```

### `--dart-define` keys

| Key | Required? | Source | Used by |
|-----|-----------|--------|---------|
| `ANTHROPIC_API_KEY` | optional (mocks if absent) | [console.anthropic.com](https://console.anthropic.com/) → API Keys | `AnthropicService`, `AnthropicChatService`, `ResumeTailorService`, `ResumeParserService` |

No other build-time env vars. Firebase project + Google Sign-In OAuth client IDs are baked into the committed Firebase config files.

## Targets

| Platform | Status |
|----------|--------|
| iOS Simulator | ✅ primary dev target |
| Android emulator | ✅ |
| Flutter Web | ✅ — resume preview uses `sessionStorage` for PDF cache |

## Common commands

```bash
flutter analyze lib/             # before commit
flutter run -d chrome --dart-define=ANTHROPIC_API_KEY=...
flutter clean && flutter pub get # if pods/gradle get weird
```

## Project structure

```
lib/
  app.dart                   ProviderScope + MaterialApp.router
  main.dart                  Firebase + GoogleSignIn init, then runApp
  core/
    router/                  go_router config + auth-aware redirects
    theme/                   AppTheme (Inter, lime+ink brand)
    constants/               AppColors, AppStrings, AppAssets
    utils/                   motion guard, date/file formatters
  features/
    auth/                    login, signup, onboarding, splash, morning brief
    dashboard/               home screen
    jobs/                    agent pipeline, review, tailor, submitted
    resumes/                 list, preview, tailor (PR-diff model)
    applications/            tracker
    agent/                   PassiveAgentNotifier (brief runs)
    agent_chat/              streaming chat with tool calls
    notifications/           inbox
    profile/                 settings
  data/
    firestore/               repositories
    models/                  shared models (Job, TrackedApplication)
  shared/
    widgets/                 buttons, header, bottom nav, cards
    animations/              agent pulse icon
  fixtures/                  mock data for demo flows
```

## State management

Riverpod `Notifier<T>` with immutable state classes. See [docs/roles/04-app-shell.md](docs/roles/04-app-shell.md) for the pattern; every feature follows it.

## Demo flow

1. Launch app → splash → login.
2. "Continue with Google" — lands on onboarding if it's a new account.
3. Capture `role` (e.g. *Senior UX Designer*) → dashboard.
4. Profile → enable **Show daily brief CTA** → return to dashboard → tap **Run today's brief**.
5. Watch the agent pipeline populate in **Agent** tab. Review, tailor, submit.

## Troubleshooting

- **`Tried to read the state of an uninitialized provider`** during navigation → check that [app_router.dart](lib/core/router/app_router.dart) eagerly reads each `.notifier` referenced in the redirect.
- **iOS simulator runtime missing** → Xcode → Settings → Components → install the iOS runtime that matches the simulator you picked.
- **Google Sign-In hangs** → confirm the iOS URL scheme in `Info.plist` matches the `REVERSED_CLIENT_ID` in `GoogleService-Info.plist`.
- **Web resume preview blank after refresh** → expected; the PDF bytes live in `sessionStorage` and clear on tab close.
