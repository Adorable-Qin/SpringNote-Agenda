import { copyFile } from 'node:fs/promises';
await copyFile('examples/core.html', 'dist-core/index.html');
