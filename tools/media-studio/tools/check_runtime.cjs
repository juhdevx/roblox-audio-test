// A bounded local dependency check; this never opens or uploads a media file.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

async function main() {
  for (const name of ['local_media.cjs', 'decode_video.cjs', 'audio/decode_audio.cjs', 'native_video.py', 'conversion_checkpoint.py']) {
    if (!fs.existsSync(path.join(__dirname, name))) throw Error('Converter package is incomplete: missing ' + name);
  }
  const media = require('./local_media.cjs');
  if (typeof media.withLocalMediaPage !== 'function') throw Error('Update the local media decoder helper.');
  let playwright;
  for (const root of [process.env.NODE_PATH,
    path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules')].filter(Boolean)) {
    try { playwright = require(path.join(root, 'playwright')); break; } catch {}
  }
  if (!playwright) {
    try { playwright = require('playwright'); }
    catch { throw Error('Playwright is missing. Use the complete converter runtime.'); }
  }
  const base = path.join(os.homedir(), 'AppData/Local/ms-playwright');
  const executablePath = fs.existsSync(base) ? fs.readdirSync(base)
    .filter(name => name.startsWith('chromium-'))
    .map(name => path.join(base, name, 'chrome-win64/chrome.exe'))
    .filter(filename => fs.existsSync(filename)).sort().at(-1) : undefined;
  const browser = await playwright.chromium.launch({headless: true, timeout: 20000,
    ...(executablePath ? {executablePath} : {})});
  try { console.log(browser.version()); } finally { await browser.close(); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
