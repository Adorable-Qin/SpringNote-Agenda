import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  base: './',
  build: {
    target: 'es2022',
    outDir: 'dist-core',
    assetsDir: '',
    emptyOutDir: true,
    chunkSizeWarningLimit: 2200,
    lib: {
      entry: fileURLToPath(new URL('./src/live-markdown-core.ts', import.meta.url)),
      formats: ['es'],
      fileName: 'live-markdown',
      cssFileName: 'live-markdown',
    },
  },
});
