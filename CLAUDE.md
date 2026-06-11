# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BiteLog is an iOS application for meal tracking and nutrition management. Built with SwiftUI and SwiftData, it manages food nutrition data and records daily meals.

The repository also contains a web admin console: `frontend/` (React SPA on Cloudflare Pages) and `cloudflare/` (Hono API on Cloudflare Workers + D1). See "Web Admin Console" below.

## Development Environment & Build Commands

### Required Tools

- Xcode 16.1+
- VS Code (Universal) + SweetPad extension
- xcode-build-server
- swift-format (code formatting)
- xcbeautify (build output formatting)

### Common Commands

**Build & Run**

```
# Run from VS Code command palette
SweetPad: Build & Run (Launch)
```

**Debug**

```
# Use "Run and Debug" button from VS Code debug view
```

**Run Tests**

```
# Run from SweetPad Test view
```

**Build Server Setup (Initial Setup)**

```
# Run from VS Code command palette
SweetPad: Generate Build Server Config
```

## Architecture & Structure

### Data Models (SwiftData)

- **FoodMaster**: Food master data. Manages nutrition info (calories, protein, fat, carbs, fiber) and usage frequency
- **LogItem**: Meal records. References FoodMaster with backup data (protection on deletion)
- **MealType**: Meal types (breakfast, lunch, dinner, snack, other)

### Main View Structure

- **ContentView**: Tab-based navigation (Log tab, Food tab)
- **DayContentView**: Display and manage meal records by date
- **AddItemView/EditItemView**: Add/edit meal records
- **FoodMasterManagementView**: Manage food master data

### Key Implementation Details

- LogItem nutrition info persists even if FoodMaster is deleted (uses backup fields)
- Multi-language support (Japanese/English) with dynamic switching via LanguageManager
- CSV import/export functionality
- Copy previous day's meals feature
- Bulk delete multiple items

### Project Settings

- Bundle ID: `com.watahiki.BiteLog`
- Minimum iOS version: iOS 18.2
- Supported devices: iPhone only
- Current version: 1.6

## Web Admin Console (frontend / cloudflare)

### Structure

- Bun workspaces monorepo: `frontend/` + `cloudflare/`
- `frontend/`: React 19 + Vite + Tailwind CSS v4. Deployed to Cloudflare Pages (`bitelog-admin.pages.dev`)
- `cloudflare/`: Hono on Cloudflare Workers + D1. Deployed to `bitelog-workers.v10acdict.workers.dev`
- Type-safe API calls via Hono RPC: `cloudflare/src/index.ts` exports `AppType`, consumed by `frontend/src/lib/api.ts`
- Admin auth: password is checked against the `ADMIN_API_KEY` Worker secret via `GET /api/auth/verify` (sent as `Authorization: Bearer` on every request)
- User auth (social login): the login screen also offers Sign in with Apple / Google. The identity token goes to `POST /api/auth/signin`, which returns a 30-day session JWT tied to the same `userId` as the iOS app. Regular users see and edit only their own data (`isAdmin: false`)
  - Worker secrets: `GOOGLE_WEB_CLIENT_ID` (web OAuth client in the same Google Cloud project as iOS), `APPLE_WEB_SERVICE_ID` (Apple Services ID, e.g. `com.watahiki.BiteLog.web`)
  - Frontend build-time vars: `VITE_GOOGLE_CLIENT_ID`, `VITE_APPLE_SERVICE_ID` (see `frontend/.env.example`). Buttons are hidden when unset; Apple is also hidden on non-https origins (localhost) because Apple return URLs cannot point to localhost

### Local Development

```bash
# API (port 8787). Local secrets live in cloudflare/.dev.vars (gitignored)
cd cloudflare && npm run dev

# Frontend (port 5173). Connects to the production Worker by default;
# to use the local Worker, copy .env.development.local.example to .env.development.local
cd frontend && bun run dev
```

### Test & Build

```bash
cd cloudflare && npm test        # vitest
cd frontend && bun run build     # includes tsc type check
```

### Deploy (manual — no git integration)

Deploy the Worker first when the frontend depends on new API endpoints.

```bash
# 1. Worker
cd cloudflare && npm run deploy

# 2. Pages (--branch main is required; otherwise it becomes a preview deployment)
cd frontend && bun run build
cd ../cloudflare && npx wrangler pages deploy ../frontend/dist --project-name bitelog-admin --branch main
```

### Development Flow

1. Create a GitHub issue describing the problem (why)
2. Branch from up-to-date main — run `git fetch origin main` first; local main may be stale
3. Open a PR with `Closes #N`. Verify the actual diff with `gh pr diff` before writing the description

## Testing Strategy

### t-wada's TDD Approach

This project follows the Test-Driven Development (TDD) approach advocated by Takuto Wada (t-wada).

**Core Principles:**
1. **Red-Green-Refactor**: Write a failing test → Implement minimal code to pass → Refactor
2. **TODO List**: List all required test cases before implementation
3. **Triangulation**: Derive generalization from multiple specific examples
4. **Obvious Implementation**: Start with simple, obvious implementations
5. **Fake It**: Pass tests with constants first, then generalize gradually

**Test Writing Guidelines:**
- Write tests as readable specifications
- Test names can be descriptive (clearly state what is being tested)
- Use Arrange-Act-Assert pattern
- One test method should test only one thing

**Development Process:**
1. Create a TODO list of test cases
2. Start with the simplest test case
3. Follow test-first approach (test → implementation order)
4. Keep each step in a committable state
5. Ensure tests pass during refactoring

## Commit Message Guidelines

### t-wada's Philosophy
- **Code**: How (implementation details)
- **Test code**: What (what is being tested)
- **Commit log**: Why (reason for change)
- **Code comments**: Why not (why other approaches weren't used)

### Format
```
<type>: <subject>

<body: explain why this change is needed>
```

**type**: feat, fix, docs, style, refactor, test, chore
**subject**: 50 chars max, imperative mood, Japanese OK

## Gemini Search

`gemini` is google gemini cli. **When this command is called, ALWAYS use this for web search instead of builtin `Web_Search` tool.**

When web search is needed, you MUST use `gemini --prompt` via Task Tool.

Run web search via Task Tool with `gemini --prompt 'WebSearch: <query>'`

Run

```bash
gemini --prompt "WebSearch: <query>"
```