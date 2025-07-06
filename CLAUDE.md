# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BiteLog is an iOS application for meal tracking and nutrition management. Built with SwiftUI and SwiftData, it manages food nutrition data and records daily meals.

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