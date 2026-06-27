/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL?: string;
  // Google Cloud ConsoleのWebアプリ用OAuthクライアントID(未設定ならGoogleログイン非表示)
  readonly VITE_GOOGLE_CLIENT_ID?: string;
  // Apple DeveloperのServices ID(未設定ならAppleログイン非表示)
  readonly VITE_APPLE_SERVICE_ID?: string;
  // AppleのReturn URL(省略時はwindow.location.origin)
  readonly VITE_APPLE_REDIRECT_URI?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
