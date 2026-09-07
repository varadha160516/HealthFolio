import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Capacitor serves the built app from a file:// / capacitor:// origin on Android, so asset URLs
// must be relative (base: './') — an absolute base would 404 every asset inside the native shell.
export default defineConfig({
  plugins: [react()],
  base: './',
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:4000',
    },
  },
});
