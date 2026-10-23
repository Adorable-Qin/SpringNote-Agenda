import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  base: './',
  plugins: [react()],
  resolve: { alias: { '../host': fileURLToPath(new URL('./src/host.ts', import.meta.url)) } },
  build: {
    target: 'es2022',
    outDir: '../assets/open_typora',
    assetsDir: '',
    emptyOutDir: true,
    chunkSizeWarningLimit: 2200,
  },
});
