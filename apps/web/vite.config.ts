import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
    // recharts は依存チェーン経由で React を別エントリ解決し、本番ビルドで
    // React が二重バンドルされる（dispatcher が null になり useContext で落ちる）。
    // 単一インスタンスに固定して回避する。
    dedupe: ['react', 'react-dom'],
  },
  server: {
    port: 5173,
    cors: true,
  },
})
