# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BiteLog is an iOS application for meal tracking and nutrition management. Built with SwiftUI and SwiftData, it manages food nutrition data and records daily meals.

The repository also contains a web admin console: `frontend/` (React SPA on Cloudflare Pages) and `cloudflare/` (Hono API on Cloudflare Workers + D1).

### Project Settings

- Bundle ID: `com.watahiki.BiteLog`
- Minimum iOS version: iOS 18.2
- Supported devices: iPhone only
- Current version: 1.6

## Situation-specific guides (skills)

Detailed, situational guidance lives in skills under `.claude/skills/` and is
loaded on demand. Use the matching skill when the work calls for it:

- **ios-development** — building/running/debugging the iOS app (SweetPad commands, required tools), data models and view structure
- **web-admin-console** — working under `frontend/` or `cloudflare/` (local dev, auth, Hono RPC, tests, Cloudflare deploy)
- **tdd-testing** — writing tests / implementing features test-first (t-wada's TDD)

## Development Flow

1. Create a GitHub issue describing the problem (why)
2. Branch from up-to-date main — run `git fetch origin main` first; local main may be stale
3. Open a PR with `Closes #N`. Verify the actual diff with `gh pr diff` before writing the description

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
