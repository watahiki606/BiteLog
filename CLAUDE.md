# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

BiteLogは、食事記録と栄養管理を行うiOSアプリケーションです。SwiftUIとSwiftDataを使用して構築されており、食品の栄養成分を管理し、日々の食事を記録できます。

## 開発環境とビルドコマンド

### 必要なツール

- Xcode 16.1以降
- VS Code (Universal) + SweetPad拡張機能
- xcode-build-server
- swift-format（コードフォーマット）
- xcbeautify（ビルド出力整形）

### よく使うコマンド

**ビルド＆実行**

```
# VS Codeのコマンドパレットから実行
SweetPad: Build & Run (Launch)
```

**デバッグ**

```
# VS Codeのデバッグビューから「Run and Debug」ボタンを使用
```

**テスト実行**

```
# SweetPadのTestビューから実行
```

**ビルドサーバー設定（初回セットアップ時）**

```
# VS Codeのコマンドパレットから実行
SweetPad: Generate Build Server Config
```

## アーキテクチャと構造

### データモデル（SwiftData使用）

- **FoodMaster**: 食品マスターデータ。栄養成分（カロリー、タンパク質、脂質、糖質、食物繊維）と使用頻度を管理
- **LogItem**: 食事記録。FoodMasterへの参照とバックアップデータ（削除時の保護）を持つ
- **MealType**: 食事タイプ（朝食、昼食、夕食、間食、その他）

### 主要なビュー構造

- **ContentView**: タブベースのナビゲーション（ログタブ、フードタブ）
- **DayContentView**: 日付ごとの食事記録表示と管理
- **AddItemView/EditItemView**: 食事記録の追加・編集
- **FoodMasterManagementView**: 食品マスターデータの管理

### 重要な実装詳細

- 食品マスターが削除されてもLogItemの栄養情報は保持される（backupフィールド使用）
- 複数言語対応（日本語/英語）はLanguageManagerで動的切り替え
- CSV形式でのデータインポート/エクスポート機能
- 前日の食事をコピーする機能
- 複数アイテムの一括削除機能

### プロジェクト設定

- Bundle ID: `com.watahiki.BiteLog`
- 最小iOSバージョン: iOS 18.2
- 対応デバイス: iPhone のみ
- 現在のバージョン: 1.3

## Gemini Search

`gemini` is google gemini cli. **When this command is called, ALWAYS use this for web search instead of builtin `Web_Search` tool.**

When web search is needed, you MUST use `gemini --prompt` via Task Tool.

Run web search via Task Tool with `gemini --prompt 'WebSearch: <query>'`

Run

```bash
gemini --prompt "WebSearch: <query>"
```
