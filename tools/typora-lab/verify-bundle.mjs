import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { buildRenderer } from '../../spring_note/editor/scripts/renderer.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const directory = resolve(process.argv[2] || join(root, 'spring_note/assets/typora_editor'));
const manifest = JSON.parse(await readFile(join(directory, 'manifest.json'), 'utf8'));
assert.equal(manifest.format, 1); assert.equal(manifest.engine, 'typora-1.7.6');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const expected = new Set(['manifest.json']);
for (const [path, entry] of Object.entries(manifest.files)) {
  assert.ok(!path.split('/').some(part => !part || part === '..' || part.includes('\\')));
  assert.match(entry.asset, /^[a-f0-9]{24}\.[a-z0-9]+$/);
  const content = await readFile(join(directory, entry.asset));
  assert.equal(content.length, entry.bytes, path);
  assert.equal(digest(content), entry.sha256, path);
  expected.add(entry.asset);
}
assert.deepEqual(new Set(await readdir(directory)), expected, 'Unexpected files in editor bundle');
for (const [source, path] of [['host.js', 'adapter.js'], ['preload.js', 'preload.js'], ['editor.css', 'editor.css'], ['view.html', 'index.html']]) {
  assert.equal(digest(await readFile(join(root, 'spring_note/editor/runtime', source))), manifest.files[path].sha256, `${path}: run node tools/typora-lab/bundle.mjs`);
}
const source = await readFile(join(root, 'spring_note/editor/vendor/typora-engine/frame.js'), 'utf8');
const inventory = JSON.parse(await readFile(join(root, 'tools/typora-lab/module-index.json'), 'utf8'));
assert.equal(digest(buildRenderer(source, inventory)), manifest.files['renderer.js'].sha256);
const html = await readFile(join(directory, manifest.files['index.html'].asset), 'utf8');
assert.match(html, /data-editor-host="app"/);
assert.ok(manifest.files['Typora-License-Agreement.md']);
console.log(`Verified ${expected.size - 1} bundled editor assets.`);
