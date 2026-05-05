# AGENTS.md

This file provides guidance to Codex when working with code in this repository.

## Language

- Please provide all answers in Japanese.

## Project Overview

BiteLog is an iOS application for meal tracking and nutrition management. Built with SwiftUI, it manages food nutrition data and records daily meals.

The app has been migrated away from local SwiftData storage toward a Cloudflare Workers + D1 backend. iOS uses `URLSession` and sign-in tokens to access the backend API.

## Development Environment & Build Commands

### Required Tools

- Xcode 16.1+
- VS Code (Universal) + SweetPad extension
- xcode-build-server
- swift-format (code formatting)
- xcbeautify (build output formatting)

### Common Commands

**Build & Run**

```bash
# Run from VS Code command palette
SweetPad: Build & Run (Launch)
```

**Debug**

```bash
# Use "Run and Debug" button from VS Code debug view
```

**Run Tests**

```bash
# Run from SweetPad Test view
```

**Build Server Setup (Initial Setup)**

```bash
# Run from VS Code command palette
SweetPad: Generate Build Server Config
```

**CLI Build Check**

```bash
xcodebuild -project BiteLog.xcodeproj -scheme BiteLog -configuration Debug -destination generic/platform=iOS build
```

## Architecture & Structure

### Data Models / DTOs

- **FoodMasterDTO**: Food master data. Manages nutrition info (calories, protein, fat, carbs, fiber) and usage frequency.
- **LogItemDTO**: Meal records. References FoodMaster data with nutrition snapshot fallback.
- **MealType**: Meal types (breakfast, lunch, dinner, snack, other).
- **NutritionGoalsDTO**: User-specific daily nutrition goals.

### Main View Structure

- **ContentView**: Tab-based navigation (Log tab, Food tab)
- **DayContentView**: Display and manage meal records by date
- **AddItemView/EditItemView**: Add/edit meal records
- **FoodMasterManagementView**: Manage food master data
- **LoginView**: Apple / Google sign-in entry point
- **SettingsView**: Language, nutrition goals, CSV import/export, data deletion, and sign-out

### Backend / Auth Structure

- **AuthManager**: Manages Apple / Google sign-in and stores the session JWT in Keychain.
- **APIClient**: Calls the Cloudflare Workers API and attaches `Authorization: Bearer <session_jwt>`.
- **Cloudflare Workers**: Verifies Apple / Google identity tokens and issues app session JWTs.
- **Cloudflare D1**: Stores food masters, log items, and nutrition goals.

### Key Implementation Details

- LogItem nutrition info persists even if FoodMaster is deleted by using nutrition snapshots.
- FoodMaster data is global, while LogItem and NutritionGoals are separated by user.
- Multi-language support (Japanese/English) with dynamic switching via LanguageManager.
- CSV import/export functionality.
- Copy previous day's meals feature.
- Bulk delete multiple items.
- AdMob initialization should not block initial app launch; defer it until after the main signed-in UI is shown.

### Project Settings

- Bundle ID: `com.watahiki.BiteLog`
- Minimum iOS version: iOS 18.2
- Supported devices: iPhone only
- Current version: 2.2

## Testing Strategy

### t-wada's TDD Approach

This project follows the Test-Driven Development (TDD) approach advocated by Takuto Wada (t-wada).

**Core Principles:**

1. **Red-Green-Refactor**: Write a failing test -> implement minimal code to pass -> refactor
2. **TODO List**: List all required test cases before implementation
3. **Triangulation**: Derive generalization from multiple specific examples
4. **Obvious Implementation**: Start with simple, obvious implementations
5. **Fake It**: Pass tests with constants first, then generalize gradually

**Test Writing Guidelines:**

- Write tests as readable specifications.
- Test names can be descriptive and should clearly state what is being tested.
- Use Arrange-Act-Assert pattern.
- One test method should test only one thing.

**Development Process:**

1. Create a TODO list of test cases.
2. Start with the simplest test case.
3. Follow test-first approach (test -> implementation order).
4. Keep each step in a committable state.
5. Ensure tests pass during refactoring.

## Commit Message Guidelines

### t-wada's Philosophy

- **Code**: How (implementation details)
- **Test code**: What (what is being tested)
- **Commit log**: Why (reason for change)
- **Code comments**: Why not (why other approaches weren't used)

### Commit Granularity

- コミットは意味のある単位に分ける。
- 複数の関心事をまとめて1つのコミットにしない。
- 例: 認証設定、ログアウト導線、起動改善、リファクタリングはそれぞれ別コミットにする。

### Format

```text
<type>: <subject>

<body>
```

**type**: feat, fix, docs, style, refactor, test, chore

**subject**:

- 50 chars max.
- Imperative mood.
- Japanese OK.

**body**:

- Explain why this change is needed.
- Describe the previous behavior or problem.
- Describe what changed.
- Describe how the change improves the behavior or maintainability.
- Omit the body only for truly trivial changes.

### Example

```text
fix: Debug ビルドに Apple サインイン権限を追加

Debug 構成では entitlements が設定されておらず、実機確認時に
ASAuthorizationController が認可エラーを返していた。

Debug にも Release と同じ Sign in with Apple entitlement を渡すことで、
実機デバッグ中でも Apple サインインを実行できるようにする。
```

## Gemini Search

`gemini` is google gemini cli. **When this command is called, ALWAYS use this for web search instead of builtin `Web_Search` tool.**

When web search is needed, you MUST use `gemini --prompt` via Task Tool.

Run web search via Task Tool with `gemini --prompt 'WebSearch: <query>'`

Run:

```bash
gemini --prompt "WebSearch: <query>"
```
