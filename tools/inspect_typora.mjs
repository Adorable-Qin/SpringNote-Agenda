// Static inspection only: the supplied application code is parsed, never loaded.
// node tools/inspect_typora.mjs <resources-dir> <new-output-dir> <tooling-node_modules>
import { readFile, writeFile, mkdir, readdir, stat } from 'node:fs/promises';
import { resolve, join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const [resourcesArg, outputArg, toolingArg] = process.argv.slice(2);
if (!resourcesArg || !outputArg || !toolingArg) {
  throw new Error('Usage: node tools/inspect_typora.mjs <resources-dir> <new-output-dir> <tooling-node_modules>');
}
const resources = resolve(resourcesArg), output = resolve(outputArg);
const parser = await import(pathToFileURL(resolve(toolingArg, '@babel/parser/lib/index.js')));
const prettier = await import(pathToFileURL(resolve(toolingArg, 'prettier/index.mjs')));
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const frameBytes = await readFile(join(resources, 'appsrc/window/frame.js'));
const source = frameBytes.toString('utf8');
const tree = parser.parse(source, { sourceType: 'script' });
const calls = [], stack = [tree];
while (stack.length) {
  const node = stack.pop();
  if (!node || typeof node !== 'object') continue;
  if (node.type === 'CallExpression' && node.callee.type === 'MemberExpression'
      && !node.callee.computed && ['System', '$__System'].includes(node.callee.object.name)
      && ['register', 'registerDynamic'].includes(node.callee.property.name)
      && node.arguments[0]?.type === 'StringLiteral') calls.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) stack.push(...value.filter(v => v && typeof v === 'object'));
    else if (value && typeof value === 'object') stack.push(value);
  }
}
calls.sort((a, b) => a.start - b.start);
if (!calls.length) throw new Error('No named System.register modules found; this extractor targets Typora 1.7.6.');
// An existing output is an error, so a rerun cannot silently replace research.
await mkdir(output);
await mkdir(join(output, 'modules'));
const modules = [];
for (const call of calls) {
  const id = call.arguments[0].value;
  if (!/^[a-zA-Z0-9_-]+$/.test(id)) throw new Error(`Unexpected module ID: ${id}`);
  const raw = source.slice(call.start, call.end);
  const formatted = await prettier.format(raw + ';', { parser: 'babel' });
  parser.parse(formatted, { sourceType: 'script' });
  const path = `modules/module-${id}.js`;
  await writeFile(join(output, path), formatted);
  modules.push({ id, path, dependencies: call.arguments[1].elements.map(e => e.value),
    start: call.start, end: call.end, rawSha256: sha256(raw), formattedSha256: sha256(formatted),
    lines: formatted.split('\n').length - 1 });
}
const archives = {};
for (const name of ['app.asar', 'lib.asar', 'node_modules.asar']) {
  const bytes = await readFile(join(resources, name));
  const headerSize = bytes.readUInt32LE(4), jsonSize = bytes.readUInt32LE(12);
  if (16 + jsonSize > 8 + headerSize || 8 + headerSize > bytes.length) throw new Error(`Invalid ASAR header: ${name}`);
  const header = JSON.parse(bytes.toString('utf8', 16, 16 + jsonSize));
  const files = [];
  const walk = (node, prefix = '') => {
    for (const [key, value] of Object.entries(node.files || {})) {
      const path = prefix + key;
      if (value.files) walk(value, path + '/');
      else {
        const offset = Number(value.offset);
        if (!value.unpacked && !value.link && (!Number.isSafeInteger(offset) || offset < 0
          || !Number.isSafeInteger(value.size) || value.size < 0
          || 8 + headerSize + offset + value.size > bytes.length)) throw new Error(`Invalid ASAR entry: ${path}`);
        files.push({ path, size: value.size, unpacked: !!value.unpacked, ...(value.link ? { link: value.link } : {}) });
      }
    }
  };
  walk(header);
  archives[name] = { size: bytes.length, sha256: sha256(bytes), files };
}
const assets = [];
async function inventory(directory) {
  for (const item of await readdir(directory, { withFileTypes: true })) {
    const fullPath = join(directory, item.name);
    if (item.isDirectory()) await inventory(fullPath);
    else if (item.isFile()) assets.push({ path: relative(resources, fullPath).replaceAll('\\', '/'), size: (await stat(fullPath)).size });
  }
}
await inventory(resources);
const report = { version: JSON.parse(await readFile(join(resources, 'package.json'), 'utf8')).version,
  frame: { path: 'appsrc/window/frame.js', size: frameBytes.length, sha256: sha256(frameBytes),
    offsets: 'UTF-16 character offsets in decoded frame.js, end exclusive', modules }, archives, assets };
await writeFile(join(output, 'inventory.json'), JSON.stringify(report, null, 2) + '\n');
await writeFile(join(output, 'README.txt'), 'Typora renderer static inspection\n\n'
  + 'These files are formatted copies of modules from the user-supplied installer.\n'
  + 'They retain their original ownership and licensing. Formatting does not recover original source names, comments or source maps.\n'
  + 'This directory is research material, not the SpringNote reusable editor distribution.\n'
  + 'inventory.json records exact source ranges, hashes, dependencies and archive contents.\n'
  + 'No application code was executed.\n');
console.log(JSON.stringify({ output, version: report.version, modules: modules.length, assets: assets.length, frameSha256: report.frame.sha256 }));
