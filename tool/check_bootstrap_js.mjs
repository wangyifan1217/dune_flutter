import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const mobile = fs.readFileSync(path.join(root, 'lib/features/prototype/mobile_injection.dart'), 'utf8');
const im = fs.readFileSync(path.join(root, 'lib/features/im/im_chat_injection.dart'), 'utf8');

function extractOne(content, name) {
  const re = new RegExp(`static const ${name} = r'''([\\s\\S]*?)'''`);
  const m = content.match(re);
  if (!m) throw new Error(`missing ${name}`);
  return m[1];
}

function extractImJs(content) {
  const m = content.match(/static const js = r'''([\s\S]*?)'''/);
  if (!m) throw new Error('missing im js');
  return m[1];
}

function escapeJsString(s) {
  return `'${s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n').replace(/\r/g, '')}'`;
}

const bootstrapJs = extractOne(mobile, 'bootstrapJs');
const css = extractOne(mobile, 'css');
const profile = extractOne(mobile, '_profileJs');
const contacts = extractOne(mobile, '_contactsJs');
const inbox = extractOne(mobile, '_inboxJs');
const imJs = extractImJs(im);

let out = bootstrapJs
  .replaceAll('__DUNES_CSS__', escapeJsString(css))
  .replaceAll('__DUNES_PROFILE_JS__', profile)
  .replaceAll('__DUNES_CONTACTS_JS__', contacts)
  .replaceAll('__DUNES_INBOX_JS__', inbox)
  .replaceAll('__DUNES_IM_JS__', imJs);

const outPath = path.join(root, 'build', 'js-check', 'bootstrap-assembled.js');
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, out);

const r = spawnSync(process.execPath, ['--check', outPath], { encoding: 'utf8' });
if (r.status === 0) {
  console.log('OK assembled bootstrap', outPath);
} else {
  console.log('FAIL assembled bootstrap');
  console.log(r.stderr || r.stdout);
  process.exit(1);
}
