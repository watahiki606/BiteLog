# 体組成計測データ（body_measurements）機能

HealthPlanet 由来の体組成計測データ（体重・体脂肪率・筋肉量など17列）を
ユーザーに紐づけて保存し、web画面から CSV一括 + 手動1件追加で登録できるようにする。

## 方針（ユーザー確認済み）
- 登録方法: CSV一括アップロード + 手動1件追加フォーム
- 保存カラム: CSV全17カラム
- 重複防止: UNIQUE(user_id, measured_at)

## タスク
- [x] schema.sql に body_measurements テーブル追加
- [x] types.ts に BodyMeasurementRow + bodyMeasurementToResponse
- [x] routes/bodyMeasurements.ts (GET / POST / DELETE /:id / POST /import)
- [x] index.ts にルート登録
- [x] routes/bodyMeasurements.test.ts（10件パス）
- [x] hooks/useBodyMeasurements.ts (SWR)
- [x] pages/BodyMeasurementPage.tsx (一覧 + 手動追加 + CSVアップロード)
- [x] Sidebar.tsx / App.tsx に BODY タブ追加
- [x] npm test（52件パス）/ bun run build（成功）で検証
- [x] ローカルD1へスキーマ適用済み（npx wrangler d1 execute bitelog --local --file=schema.sql）

## レビュー
- `body_measurements` テーブルを新設。CSV全17列 + id + user_id を保存し、
  UNIQUE(user_id, measured_at) で再インポート/手動追加の重複を防止。
- API: GET一覧（measured_at降順）/ POST手動1件 / DELETE 1件 / POST import（CSV一括・
  バッチ100件・INSERT OR IGNORE）。すべて authMiddleware でユーザー分離。
- Web: BODY タブを追加。一覧テーブル + 手動追加モーダル + CSVアップロード。
- 既存パターン（Hono RPC, SWR, FoodMasterPage のモーダル/テーブル）に踏襲。

## 残作業（デプロイ時・ユーザー操作）
- 本番D1へのスキーマ適用: cd cloudflare && npx wrangler d1 execute bitelog --remote --file=schema.sql
- Worker デプロイ: cd cloudflare && npm run deploy
- Web Pages デプロイ: bun run build → npx wrangler pages deploy ../apps/web/dist --project-name bitelog-web --branch main
