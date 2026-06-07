import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'
import { copyFileSync, existsSync } from 'fs'

function copyHeadersPlugin() {
  return {
    name: 'copy-headers',
    closeBundle() {
      const src = path.resolve(__dirname, '../pages/_headers')
      const dest = path.resolve(__dirname, 'dist/_headers')
      if (existsSync(src)) copyFileSync(src, dest)
    },
  }
}

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    copyHeadersPlugin(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173,
    cors: true,
  },
})
