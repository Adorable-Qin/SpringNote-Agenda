import { readFile, readdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const lock = JSON.parse(await readFile('package-lock.json', 'utf8'));
const notices = ['Open Typora 0.13.4\nhttps://github.com/AniChikage/open-typora\n' + await readFile('vendor/open-typora/LICENSE', 'utf8')];
for (const [path, info] of Object.entries(lock.packages).sort()) {
  if (!path || info.dev) continue;
  const metadata = JSON.parse(await readFile(join(path, 'package.json'), 'utf8'));
  const files = (await readdir(path)).filter(name => /^(?:licen[cs]e|copying|notice)(?:$|[.-])/i.test(name));
  const texts = [];
  for (const name of files) {
    try { texts.push(await readFile(join(path, name), 'utf8')); } catch {}
  }
  notices.push(`${metadata.name} ${metadata.version}\nLicense: ${JSON.stringify(metadata.license)}\n${texts.join('\n')}`);
}
await writeFile(process.argv[2] || '../assets/open_typora/THIRD_PARTY_NOTICES.txt', notices.join('\n\n========================================\n\n'));
