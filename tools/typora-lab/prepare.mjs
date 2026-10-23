import { buildRenderer } from '../../spring_note/editor/scripts/renderer.mjs';
import { readFile, writeFile, mkdir, cp } from 'node:fs/promises';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const resources = resolve(process.argv[2] || join(root, '.toolchains/typora-research/1.7.6/app/resources'));
const output = resolve(process.argv[3] || join(root, '.toolchains/typora-lab/web'));
const host = process.argv[4] === 'app' ? 'app' : 'lab';
const source = await readFile(join(resources, 'appsrc/window/frame.js'), 'utf8');
const sha256 = createHash('sha256').update(source).digest('hex');
if (sha256 !== '3a1a1294d840ac7d5fff820426ec272b3cce80ab025c0d925a737775a9ba59ae') throw new Error('Expected the inspected Typora 1.7.6 renderer.');
const inventory = JSON.parse(await readFile(join(root, 'tools/typora-lab/module-index.json'), 'utf8'));
await mkdir(output, { recursive: true });
for (const dir of ['style', 'html', 'locales', 'assets']) await cp(join(resources, dir), join(output, dir), { recursive: true });
await cp(join(resources, 'Docs/License Agreement.md'), join(output, 'Typora-License-Agreement.md'));
await cp(join(resources, 'appsrc/editor'), join(output, 'appsrc/editor'), { recursive: true });
const archive = await readFile(join(resources, 'lib.asar'));
const headerSize = archive.readUInt32LE(4);
const header = JSON.parse(archive.toString('utf8', 16, 16 + archive.readUInt32LE(12)));
async function extract(node, prefix = '') {
  for (const [name, entry] of Object.entries(node.files || {})) {
    if (!/^[\w. -]+$/.test(name) || name === '..') throw new Error('Unsafe archive name');
    const path = join(prefix, name);
    if (entry.files) await extract(entry, path);
    else if (!entry.unpacked && !entry.link) {
      const start = 8 + headerSize + Number(entry.offset), end = start + entry.size;
      if (!Number.isSafeInteger(start) || start < 8 + headerSize || end > archive.length) throw new Error('Invalid archive offset');
      await mkdir(dirname(join(output, 'lib.asar', path)), { recursive: true });
      await writeFile(join(output, 'lib.asar', path), archive.subarray(start, end));
    }
  }
}
await extract(header);
const renderer = buildRenderer(source, inventory);
await writeFile(join(output, 'renderer.js'), renderer);
let html = await readFile(join(resources, 'window.html'), 'utf8');
const mathConfig = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)].find(m => m[2].includes('var mathPackages'))?.[2];
if (mathConfig) await writeFile(join(output, 'math-config.js'), mathConfig);
html = html.replace(/<script\b([^>]*)>[\s\S]*?<\/script>/gi, (whole, attrs) => /text\/x-(?:custom-)?template/.test(attrs) ? whole : '')
  .replaceAll('typora://app/typemark/', './')
  .replace(/<link[^>]+href="(?:typora[^\"]*|)"[^>]*>/g, '')
  .replace('<title>Typora</title>', '<title>SpringNote · Typora 1.7.6 本地测试</title>')
  .replace(/<html\b/, `<html data-editor-host="${host}"`)
  .replace('</head>', '<link rel="stylesheet" href="style/themes/github.css"><link rel="stylesheet" href="editor.css"></head>')
  .replace('</body>', '<script src="preload.js"></script><script src="math-config.js"></script><script src="lib.asar/MathJax3/es5/tex-svg-full.js" defer></script><script src="renderer.js"></script><script src="adapter.js"></script></body>');
if (host === 'app') html = html.replace('<title>SpringNote · Typora 1.7.6 本地测试</title>', '<title>SpringNote</title>');
await writeFile(join(output, 'index.html'), html);
for (const [name, target] of [['preload.js', 'preload.js'], ['host.js', 'adapter.js'], ['editor.css', 'editor.css']]) {
  await cp(join(root, 'spring_note/editor/runtime', name), join(output, target));
}
await writeFile(join(output, 'provenance.json'), JSON.stringify({ version: '1.7.6', rendererSha256: sha256, entry: 'springnote', adaptations: ['Expose module loader', 'Expose original SourceView position mapper'], editorAlgorithmsChanged: false }, null, 2));
console.log(output);
