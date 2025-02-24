# VS Code iOS開発環境セットアップ

VS CodeでiOSアプリ開発を行うための環境構築手順

## 前提条件

- macOS Sequoia 15.2以降
- Xcode 16.1以降
- Visual Studio Code (Universal)

## インストール手順

### 1. 必要な拡張機能のインストール

VS Codeで以下の拡張機能をインストール：

- SweetPad
- Swift

### 2. 必須ツールのインストール

1. VS CodeのアクティビティバーからSweetPadを選択
2. Toolsビューから以下をインストール：
   - Homebrew
   - xcode-build-server
   - swift-format (コードフォーマット用)
   - xcbeautify (ビルド出力の整形用)

### 3. プロジェクト設定

1. VS Codeでプロジェクトを開く
1. コマンドパレットから`SweetPad: Generate Build Server Config`を実行
   - スキーマを選択
   - プロジェクトルートに`buildServer.json`が生成される

### 4. フォーマッター設定

`.vscode/settings.json`に以下を追加：

```json
{
"[swift]": {
"editor.defaultFormatter": "sweetpad.sweetpad",
"editor.formatOnSave": true
}
}
```

### 5. デバッグ設定

`.vscode/launch.json`に以下を追加：

```json
{
"version": "0.2.0",
"configurations": [
{
"type": "sweetpad-lldb",
"request": "launch",
      "name": "Attach to running app (SweetPad)",
      "preLaunchTask": "sweetpad: launch"
    }
  ]
}
```

## 使用方法

### ビルド＆実行

- コマンドパレットから`SweetPad: Build & Run (Launch)`を実行
- または、SweetPadのBuildビューでスキーマ名の右側の▶️をクリック

### デバッグ

- デバッグビューからRun and Debugボタンを使用
- ブレークポイントを設定して通常通りデバッグ可能

### テスト実行

- SweetPadのTestビューからテストを実行

## 参考リンク

- [SweetPad公式サイト](https://sweetpad.hyzyla.dev)
- [SweetPad VS Code拡張機能](https://marketplace.visualstudio.com/items?itemName=SweetPad.sweetpad)
- [xcode-build-serverリポジトリ](https://github.com/SolaWing/xcode-build-server)
