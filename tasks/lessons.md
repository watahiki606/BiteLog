# Lessons

## recharts 3 を Vite に入れたら React が二重バンドルされる

- **症状**: 本番ビルド（`bun run build` → デプロイ）で recharts を使うページを開くと
  `Uncaught TypeError: Cannot read properties of null (reading 'useContext')` でクラッシュ。
  dev では出ないことがある。
- **原因**: recharts 3 は内部で react-redux を使う。Vite が依存チェーン経由で `react` を
  別エントリ解決し、バンドル内に React が2コピー入る。2つ目の React は dispatcher
  （`ReactSharedInternals.H`）が null のまま → `React.useContext` 呼び出しで落ちる。
  node_modules 上は React 1コピーでも、バンドル後に二重化しうる。
- **切り分け方**: 本番ビルド済み `dist/assets/index-*.js` を `grep -c '.useContext=function'`。
  2 以上なら React 二重バンドル。
- **修正**: `apps/web/vite.config.ts` の `resolve.dedupe: ['react', 'react-dom']`。
  rebuild 後に上記 grep が 1 になることを確認。
- **やりがちな的外れ修正**: `package.json` の `overrides: { "react-is": "^19.0.0" }`。
  react-redux 9 は react-is を実行時に使わないので無意味。dedupe で直るので不要なら消す。
- **検証**: ログインがソーシャルログインのみで Playwright 自動化が難しいときは、
  `sessionStorage` に `bitelog_session_token` / `bitelog_session_user` を直接注入すれば
  認証を回避してページをマウントできる（recharts のクラッシュは描画時なのでデータ取得失敗は無関係）。
