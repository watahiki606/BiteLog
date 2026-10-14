# #180 ログイン画面を自前のボタンで作り直す

Google / Apple の公式ボタン部品は中身を相手が描くため、形を揃えられず、CSP やフォントの影響で崩れる。
調べたサービスはどこも公式部品を使わず、同じ形の自前ボタンを並べていた。両社とも条件付きで自前ボタンを認めている。
PR #181 はまだマージ前なので、同じブランチに積む。

## 画面

暗い背景・装飾なし。走査線・グリッド・四隅の飾り・ACCESS TERMINAL は外す。

```
          BiteLog
   食事と体の記録をひとつに

 [ G  Google でログイン   ]  白・同じ部品
 [   Apple でサインイン  ]  白・同じ部品

   利用規約 · プライバシー
```

## 守る規約

- Google: 色付きの「G」はそのまま使い、白地に置く。白は Fill #FFFFFF / Stroke #747775 1px。文言は「Google でログイン」系
- Apple: 公式 JS の `renderButton` に描かせる。ロゴ素材は使用許諾への同意が要り、公開リポジトリに置くと
  単体での再配布にあたりうるため、自前では持たない。暗い背景なので白、枠線なし
- 両方: 同じ大きさ・同じ重みで並べる。Google の自前ボタンを Apple の見た目に合わせる

## 仕組み

- Google: GIS の `initCodeClient` をポップアップモードで使い、認可コードを Worker に送る。
  Worker はクライアントシークレットでコードを ID トークンに交換し、既存の `verifyGoogleToken` で検証する。
  `redirect_uri` は呼び出し元ページのオリジン
- Apple: 公式ボタンのまま。崩れた原因は、CSP が埋め込みフォント (`data:`) を止めていたこと、
  左寄せモードで `width: 100%` にすると折り返すこと。中央寄せにし、`font-src` に `data:` を足す

## TODO

- [x] Worker: `/api/auth/signin` が `{ provider: 'google', authorizationCode }` を受け、交換して検証する。テスト先行
- [x] Worker: `GOOGLE_WEB_CLIENT_SECRET` を Bindings と wrangler.toml の説明に足す
- [x] Web: `initCodeClient` でコードを取り、Worker へ送る
- [x] Web: Google の自前ボタンを Apple 公式ボタンの見た目に合わせる
- [x] Web: ログイン画面を作り直す
- [x] CSP: 今回の変更で必要な許可を確かめる。`wrangler pages dev` で `_headers` を当てて確認する
- [ ] お手元: Google Cloud Console からクライアントシークレットを取り、`wrangler secret put GOOGLE_WEB_CLIENT_SECRET`
- [ ] 本番デプロイして、Google / Apple の両方でサインインできることを確認

## レビュー

- `wrangler pages dev` で本番と同じ CSP を当て、デスクトップ幅と 375px 幅で表示を確認。CSP 違反は 0 件
- Google ボタンを押すと `accounts.google.com` のポップアップが開く。手元のオリジンは未登録なので `origin_mismatch` で止まる。
  コード交換は本番で確かめる
- Google の自前ボタンの書体は、Apple 公式ボタンに揃えるため Google Sans ではなくシステムフォントにした
