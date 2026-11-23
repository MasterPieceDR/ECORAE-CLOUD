import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

// En desarrollo, /api va al backend FastAPI local (en AWS lo enruta CloudFront hacia el ALB).
export default defineConfig({
  base: './',
  plugins: [react()],
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  server: { port: 5171, proxy: { '/api': { target: process.env.VITE_PROXY ?? 'http://localhost:8000', changeOrigin: true } } },
  preview: { port: 5171, proxy: { '/api': { target: process.env.VITE_PROXY ?? 'http://localhost:8000', changeOrigin: true } } },
});
