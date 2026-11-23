---
name: ios-development
description: Reference for building, running, and navigating the BiteLog iOS app (SwiftUI + SwiftData) — required tools, SweetPad build/run/test/debug commands, data models, and view structure. Use when building, running, debugging, or modifying the iOS app.
---

# iOS Development (BiteLog app)

BiteLog is an iOS app for meal tracking and nutrition management, built with
SwiftUI and SwiftData.

## Required Tools

- Xcode 16.1+
- VS Code (Universal) + SweetPad extension
- xcode-build-server
- swift-format (code formatting)
- xcbeautify (build output formatting)

## Common Commands

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

### Nutrient definitions

- The list of nutrients lives in `shared/nutrients.json`. The Xcode project cannot read files outside `BiteLog/`, so the iOS side uses generated files: `BiteLog/Generated/NutrientDefinitions.swift` and `BiteLog/Resources/{ja,en}.lproj/Nutrients.strings`
- After editing the JSON, run `bun run generate:nutrients` from the repo root and commit the generated files with it. Never edit the generated files by hand
- `NutrientDefinitionsTests` fails when the JSON and the generated files disagree. CI does not run the iOS tests, so run it before opening a PR

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
