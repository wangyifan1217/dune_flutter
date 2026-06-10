import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const files = [
  'lib/features/prototype/mobile_injection.dart',
  'lib/features/im/im_chat_injection.dart',
];

const root = path.resolve(import.meta.dirname, '..');
const outDir = path.join(root, 'build', 'js-check');
fs.mkdirSync(outDir, { recursive: true });

function extractBlocks(content) {
  const blocks = [];
  const re = /(?:static const (?:\w+\s*=\s*)?|const String \w+\s*=\s*)r'''([\s\S]*?)'''/g;
  let m;
  while ((m = re.exec(content)) !== null) {
    blocks.push(m[1]);
  }
  return blocks;
}

let failed = false;
for (const rel of files) {
  const file = path.join(root, rel);
  const content = fs.readFileSync(file, 'utf8');
  const blocks = extractBlocks(content);
  blocks.forEach((js, i) => {
    const out = path.join(outDir, `${path.basename(rel, '.dart')}-${i}.js`);
    fs.writeFileSync(out, js);
    const r = spawnSync(process.execPath, ['--check', out], { encoding: 'utf8' });
    if (r.status === 0) {
      console.log(`OK ${rel} block ${i}`);
    } else {
      failed = true;
      console.log(`FAIL ${rel} block ${i}: ${out}`);
      console.log(r.stderr || r.stdout || 'syntax error');
    }
  });
}

process.exit(failed ? 1 : 0);
