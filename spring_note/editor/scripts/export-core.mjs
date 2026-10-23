import { cp, mkdir, readFile, writeFile, readdir } from 'node:fs/promises';
import { resolve, join, relative, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const editor = fileURLToPath(new URL('..', import.meta.url));
const root = resolve(editor, '../..');
const destination = resolve(root, '.toolchains/exports');
await mkdir(destination, { recursive: true });
const name = `springnote-live-markdown-${new Date().toISOString().replace(/[-:.]/g, '')}`;
const output = join(destination, name);
await mkdir(output);
await cp(join(editor, 'dist-core'), join(output, 'web'), { recursive: true });
for (const path of ['src', 'vendor', 'scripts', 'examples', 'tests', 'docs', 'package.json', 'package-lock.json', 'vite.config.ts', 'vite.core.config.ts', 'index.html', 'README.md']) {
  await cp(join(editor, path), join(output, 'source', path), { recursive: true });
}
await cp(join(root, 'LICENSE'), join(output, 'LICENSE'));
await cp(join(root, 'LICENSE'), join(output, 'source/LICENSE'));
await cp(join(editor, 'docs/reusable-core.zh-CN.md'), join(output, 'README.md'));
await cp(join(editor, '../lib/core/editor'), join(output, 'flutter/lib/core/editor'), { recursive: true });
const files = [];
async function collect(directory) {
  for (const entry of (await readdir(directory, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) await collect(path);
    else {
      const data = await readFile(path);
      files.push({ path: relative(output, path).replaceAll('\\', '/'), size: data.length, sha256: createHash('sha256').update(data).digest('hex') });
    }
  }
}
await collect(output);
await writeFile(join(output, 'manifest.json'), JSON.stringify({
  name: 'SpringNote live Markdown core',
  implementation: 'Open Typora 0.13.4 (MIT), existing SpringNote patches and reusable API (AGPL-3.0-only)',
  upstreamCommit: '6c80997cbc1d98dc6a38adf38ea6839490d59801',
  files,
}, null, 2) + '\n');
const archive = output + (process.platform === 'win32' ? '.zip' : '.tar.gz');
const result = process.platform === 'win32'
  ? spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
    "$ErrorActionPreference = 'Stop'; Compress-Archive -LiteralPath $env:SPRINGNOTE_EXPORT_SOURCE -DestinationPath $env:SPRINGNOTE_EXPORT_ARCHIVE -CompressionLevel Optimal"],
    { windowsHide: true, encoding: 'utf8', env: { ...process.env, SPRINGNOTE_EXPORT_SOURCE: output, SPRINGNOTE_EXPORT_ARCHIVE: archive } })
  : spawnSync('tar', ['-czf', archive, '-C', destination, basename(output)], { encoding: 'utf8' });
if (result.error || result.status !== 0) throw result.error || new Error(result.stderr);
console.log(JSON.stringify({ output, archive, files: files.length }));
