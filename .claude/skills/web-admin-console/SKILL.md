---
name: web-admin-console
description: Reference for BiteLog's web admin console (frontend/ React SPA + cloudflare/ Hono Worker on D1) and docs site (docs/ React SSG). Use when working on anything under frontend/, cloudflare/, or docs/ — local dev, auth, Hono RPC, tests, or deploying to Cloudflare Pages/Workers.
---

# Web Admin Console (frontend / cloudflare) & Docs (docs/)

The repository contains a web admin console and a docs site in addition to the iOS app:
`frontend/` (React SPA on Cloudflare Pages), `cloudflare/` (Hono API on
Cloudflare Workers + D1), and `docs/` (React SSG on Cloudflare Pages).

## Structure

- Bun workspaces monorepo: `frontend/` + `cloudflare/` + `docs/`
- `frontend/`: React 19 + Vite + Tailwind CSS v4. Deployed to Cloudflare Pages (`bitelog-admin.pages.dev`)
- `docs/`: React 19 + Vite + Tailwind CSS v4 + vite-react-ssg (SSG). Deployed to Cloudflare Pages (`bitelog-docs.pages.dev`). Shares design tokens with frontend via `shared/theme.css`.
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
cd docs && bun run build         # SSG: tsc + vite-react-ssg build → docs/dist/
```

## Deploy (manual — no git integration)

Deploy the Worker first when the frontend depends on new API endpoints.

```bash
# 1. Worker
cd cloudflare && npm run deploy

# 2. Admin Pages (--branch main is required; otherwise it becomes a preview deployment)
cd frontend && bun run build
cd ../cloudflare && npx wrangler pages deploy ../frontend/dist --project-name bitelog-admin --branch main

# 3. Docs Pages (4 static HTML pages: /, /support, /privacy, /terms)
cd docs && bun run build
cd ../cloudflare && npx wrangler pages deploy ../docs/dist --project-name bitelog-docs --branch main
```

### First-time docs deployment
The `bitelog-docs` Cloudflare Pages project is created automatically on the first
`wrangler pages deploy` call. After deployment:
1. **Disable GitHub Pages** in the repo settings (Settings → Pages → Source: None).
   If left enabled it will serve the Vite source files from `docs/` as raw HTML, which breaks the site.
2. **Update App Store Connect** privacy and support URLs to the new `bitelog-docs.pages.dev` URL.
