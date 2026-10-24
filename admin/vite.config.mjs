import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  root: 'ui',
  plugins: [react()],
  // Every Lucide icon is bundled; fine for a site that only ever runs locally.
  build: { outDir: '../dist', emptyOutDir: true, chunkSizeWarningLimit: 1000 },
});
