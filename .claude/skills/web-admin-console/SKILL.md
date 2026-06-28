---
name: web-admin-console
description: Reference for BiteLog's web apps (apps/web/ React SPA + apps/docs/ React SSG) and cloudflare/ Hono Worker on D1. Use when working on anything under apps/ or cloudflare/ — local dev, auth, Hono RPC, tests, or deploying to Cloudflare Pages/Workers.
---

# Web Apps (apps/) & API (cloudflare/)

The repository contains web apps under `apps/` and an API worker, in addition to the iOS app:
`apps/web/` (React SPA on Cloudflare Pages), `apps/docs/` (React SSG on Cloudflare Pages),
`apps/shared/` (design tokens), and `cloudflare/` (Hono API on Cloudflare Workers + D1).

## Structure

- Bun workspaces monorepo: `apps/web` + `apps/docs` + `cloudflare`
- `apps/web/`: React 19 + Vite + Tailwind CSS v4. Deployed to Cloudflare Pages (`bitelog-web.pages.dev`)
- `apps/docs/`: React 19 + Vite + Tailwind CSS v4 + vite-react-ssg (SSG). Deployed to Cloudflare Pages (`bitelog-docs.pages.dev`)
- `apps/shared/theme.css`: デザイントークンの単一ソース。apps/web と apps/docs が `../../shared/theme.css` で @import する
- `cloudflare/`: Hono on Cloudflare Workers + D1. Deployed to `bitelog-workers.v10acdict.workers.dev`
- Type-safe API calls via Hono RPC: `cloudflare/src/index.ts` exports `AppType`, consumed by `apps/web/src/lib/api.ts`
- Auth (social login only): the login screen offers Sign in with Apple / Google. The identity token goes to `POST /api/auth/signin`, which returns a 30-day session JWT tied to the same `userId` as the iOS app. Regular users see and edit only their own data (`isAdmin: false`); the user whose `userId` matches the `ADMIN_USER_ID` Worker secret gets `isAdmin: true`
  - Worker secrets: `GOOGLE_WEB_CLIENT_ID` (web OAuth client in the same Google Cloud project as iOS), `APPLE_WEB_SERVICE_ID` (Apple Services ID, e.g. `com.watahiki.BiteLog.web`)
  - Frontend build-time vars: `VITE_GOOGLE_CLIENT_ID`, `VITE_APPLE_SERVICE_ID` (see `apps/web/.env.example`). Buttons are hidden when unset; Apple is also hidden on non-https origins (localhost) because Apple return URLs cannot point to localhost

## Local Development

```bash
# API (port 8787). Local secrets live in cloudflare/.dev.vars (gitignored)
cd cloudflare && npm run dev

# Web app (port 5173). Connects to the production Worker by default;
# to use the local Worker, copy .env.development.local.example to .env.development.local
cd apps/web && bun run dev

# Docs (port 5174)
cd apps/docs && bun run dev
```

## Test & Build

```bash
cd cloudflare && npm test            # vitest
cd apps/web && bun run build         # includes tsc type check
cd apps/docs && bun run build        # SSG: tsc + vite-react-ssg build → apps/docs/dist/
```

## Deploy (manual — no git integration)

Deploy the Worker first when the web app depends on new API endpoints.

```bash
# 1. Worker
cd cloudflare && npm run deploy

# 2. Web app Pages (--branch main is required; otherwise it becomes a preview deployment)
cd apps/web && bun run build
cd ../../cloudflare && npx wrangler pages deploy ../apps/web/dist --project-name bitelog-web --branch main

# 3. Docs Pages (4 static HTML pages: /, /support, /privacy, /terms)
cd apps/docs && bun run build
cd ../../cloudflare && npx wrangler pages deploy ../apps/docs/dist --project-name bitelog-docs --branch main
```

### First-time docs deployment
The `bitelog-docs` Cloudflare Pages project is created automatically on the first
`wrangler pages deploy` call. After deployment:
1. **Disable GitHub Pages** in the repo settings (Settings → Pages → Source: None).
   If left enabled it will serve the Vite source files from `apps/docs/` as raw HTML, which breaks the site.
2. **Update App Store Connect** privacy and support URLs to the new `bitelog-docs.pages.dev` URL.
