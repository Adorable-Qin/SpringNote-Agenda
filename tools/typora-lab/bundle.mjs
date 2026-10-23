// Flatten the prepared renderer into Flutter's single-directory asset bundle.
// Browser-relative URLs are mapped by manifest.json in OpenTyporaServer.
import { readFile, writeFile, mkdir, readdir, copyFile, unlink } from 'node:fs/promises';
import { resolve, dirname, join, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { buildRenderer } from '../../spring_note/editor/scripts/renderer.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const prepared = join(root, '.toolchains/typora-release/web');
const output = join(root, 'spring_note/assets/typora_editor');
await mkdir(output, { recursive: true });
let files;
try { files = JSON.parse(await readFile(join(output, 'manifest.json'), 'utf8')).files; }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const importing = !!process.argv[2] || !files;
if (importing) {
  const resources = resolve(process.argv[2] || join(root, '.toolchains/typora-research/1.7.6/app/resources'));
  execFileSync(process.execPath, [join(root, 'tools/typora-lab/prepare.mjs'), resources, prepared, 'app'], { stdio: 'inherit' });
  files = {};
}
async function writeAsset(path, content) {
  const extension = extname(path).toLowerCase();
  const asset = createHash('sha256').update(path).digest('hex').slice(0, 24) + (/^\.[a-z0-9]+$/.test(extension) ? extension : '.bin');
  files[path] = { asset, sha256: createHash('sha256').update(content).digest('hex'), bytes: content.length };
  await writeFile(join(output, asset), content);
}
async function collect(directory, prefix = '') {
  const entries = await readdir(directory, { withFileTypes: true });
  entries.sort((a, b) => a.name.localeCompare(b.name, 'en'));
  for (const entry of entries) {
    if (entry.isSymbolicLink()) throw new Error('Asset symlinks are unsupported');
    const source = join(directory, entry.name), path = prefix + entry.name;
    if (entry.isDirectory()) await collect(source, path + '/');
    else {
      const extension = extname(entry.name).toLowerCase();
      const asset = createHash('sha256').update(path).digest('hex').slice(0, 24) + (/^\.[a-z0-9]+$/.test(extension) ? extension : '.bin');
      const content = await readFile(source);
      files[path] = { asset, sha256: createHash('sha256').update(content).digest('hex'), bytes: content.length };
      await copyFile(source, join(output, asset));
    }
  }
}
if (importing) await collect(prepared);
const inventory = JSON.parse(await readFile(join(root, 'tools/typora-lab/module-index.json'), 'utf8'));
const source = await readFile(join(root, 'spring_note/editor/vendor/typora-engine/frame.js'), 'utf8');
await writeAsset('renderer.js', Buffer.from(buildRenderer(source, inventory)));
for (const [source, target] of [['view.html', 'index.html'], ['host.js', 'adapter.js'], ['preload.js', 'preload.js'], ['editor.css', 'editor.css']]) {
  await writeAsset(target, await readFile(join(root, 'spring_note/editor/runtime', source)));
}
const generated = new Set(Object.values(files).map(entry => entry.asset));
for (const name of await readdir(output)) {
  if (/^[a-f0-9]{24}\.[a-z0-9]+$/.test(name) && !generated.has(name)) await unlink(join(output, name));
}
await writeFile(join(output, 'manifest.json'), JSON.stringify({ format: 1, engine: 'typora-1.7.6', files }, null, 2) + '\n');
console.log(`Bundled ${Object.keys(files).length} editor assets into ${output}`);
