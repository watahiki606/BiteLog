---
name: web-admin-console
description: Reference for BiteLog's web admin console (frontend/ React SPA + cloudflare/ Hono Worker on D1). Use when working on anything under frontend/ or cloudflare/ — local dev, auth, Hono RPC, tests, or deploying to Cloudflare Pages/Workers.
---

# Web Admin Console (frontend / cloudflare)

The repository contains a web admin console in addition to the iOS app:
`frontend/` (React SPA on Cloudflare Pages) and `cloudflare/` (Hono API on
Cloudflare Workers + D1).

## Structure

- Bun workspaces monorepo: `frontend/` + `cloudflare/`
- `frontend/`: React 19 + Vite + Tailwind CSS v4. Deployed to Cloudflare Pages (`bitelog-admin.pages.dev`)
- `cloudflare/`: Hono on Cloudflare Workers + D1. Deployed to `bitelog-workers.v10acdict.workers.dev`
- Type-safe API calls via Hono RPC: `cloudflare/src/index.ts` exports `AppType`, consumed by `frontend/src/lib/api.ts`
- Auth (social login only): the login screen offers Sign in with Apple / Google. The identity token goes to `POST /api/auth/signin`, which returns a 30-day session JWT tied to the same `userId` as the iOS app. Regular users see and edit only their own data (`isAdmin: false`); the user whose `userId` matches the `ADMIN_USER_ID` Worker secret gets `isAdmin: true`
  - Worker secrets: `GOOGLE_WEB_CLIENT_ID` (web OAuth client in the same Google Cloud project as iOS), `APPLE_WEB_SERVICE_ID` (Apple Services ID, e.g. `com.watahiki.BiteLog.web`)
  - Frontend build-time vars: `VITE_GOOGLE_CLIENT_ID`, `VITE_APPLE_SERVICE_ID` (see `frontend/.env.example`). Buttons are hidden when unset; Apple is also hidden on non-https origins (localhost) because Apple return URLs cannot point to localhost

## Local Development

```bash
# API (port 8787). Local secrets live in cloudflare/.dev.vars (gitignored)
cd cloudflare && npm run dev

# Frontend (port 5173). Connects to the production Worker by default;
# to use the local Worker, copy .env.development.local.example to .env.development.local
cd frontend && bun run dev
```

## Test & Build

```bash
cd cloudflare && npm test        # vitest
cd frontend && bun run build     # includes tsc type check
```

## Deploy (manual — no git integration)

Deploy the Worker first when the frontend depends on new API endpoints.

```bash
# 1. Worker
cd cloudflare && npm run deploy

# 2. Pages (--branch main is required; otherwise it becomes a preview deployment)
cd frontend && bun run build
cd ../cloudflare && npx wrangler pages deploy ../frontend/dist --project-name bitelog-admin --branch main
```
