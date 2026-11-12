// Serves exactly one local media file without building an integral base64 string.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const crypto = require('node:crypto');

function byteRange(value, length) {
  const match = /^bytes=(\d*)-(\d*)$/.exec(value);
  if (!match || (!match[1] && !match[2])) return null;
  let first, last;
  if (!match[1]) {
    const suffix = Number(match[2]);
    if (!Number.isSafeInteger(suffix) || suffix <= 0) return null;
    first = Math.max(0, length - suffix); last = length - 1;
  } else {
    first = Number(match[1]); last = match[2] ? Number(match[2]) : length - 1;
    if (!Number.isSafeInteger(first) || !Number.isSafeInteger(last) || first > last || first >= length) return null;
    last = Math.min(last, length - 1);
  }
  return {first, last};
}

async function openLocalMedia(input) {
  const filename = path.resolve(input);
  const info = await fs.promises.stat(filename);
  if (!info.isFile() || info.size <= 0) throw Error('Select a non-empty local media file');
  const token = crypto.randomBytes(24).toString('hex');
  const pageRoute = '/' + token + '/', mediaRoute = pageRoute + 'media';
  const sockets = new Set(), streams = new Set();
  let origin = '';
  const mime = {'.mp4':'video/mp4','.m4v':'video/mp4','.mov':'video/quicktime','.webm':'video/webm',
    '.mp3':'audio/mpeg','.m4a':'audio/mp4','.wav':'audio/wav','.ogg':'audio/ogg'}[path.extname(filename).toLowerCase()] || 'application/octet-stream';
  const server = http.createServer((request, response) => {
    const finish = (status, text) => {response.removeHeader('Content-Length');response.writeHead(status, {'Content-Type':'text/plain','Cache-Control':'no-store'});response.end(text);};
    if (request.headers.host !== origin.slice('http://'.length)
      || (request.headers.origin && request.headers.origin !== origin)
      || (request.headers['sec-fetch-site'] && !['same-origin','none'].includes(request.headers['sec-fetch-site']))) {
      finish(403, 'Local media access only'); return;
    }
    if (!['GET','HEAD'].includes(request.method)) {response.setHeader('Allow','GET, HEAD');finish(405,'Method not allowed');return;}
    if (request.url !== pageRoute && request.url !== mediaRoute) {finish(404,'Not found');return;}
    response.setHeader('Cache-Control','no-store');
    response.setHeader('X-Content-Type-Options','nosniff');
    response.setHeader('Cross-Origin-Resource-Policy','same-origin');
    if (request.url === pageRoute) {
      response.setHeader('Content-Type','text/html; charset=utf-8');
      response.setHeader('Content-Security-Policy',"default-src 'self'; media-src 'self' blob:; connect-src 'self'; script-src 'none'");
      response.end(request.method === 'HEAD' ? undefined : '<!doctype html><meta charset="utf-8"><title>Local media decoder</title>'); return;
    }
    response.setHeader('Content-Type', mime);
    response.setHeader('Accept-Ranges','bytes');
    let first = 0, last = info.size - 1;
    if (request.method === 'GET' && request.headers.range) {
      const range = byteRange(request.headers.range, info.size);
      if (!range) {response.setHeader('Content-Range','bytes */' + info.size);finish(416,'Requested range is unavailable');return;}
      ({first, last} = range);
      response.statusCode = 206;
      response.setHeader('Content-Range',`bytes ${first}-${last}/${info.size}`);
    }
    response.setHeader('Content-Length', last - first + 1);
    if (request.method === 'HEAD') {response.end();return;}
    const stream = fs.createReadStream(filename, {start:first,end:last});
    streams.add(stream);
    stream.on('close', () => streams.delete(stream));
    stream.on('error', () => {if (!response.headersSent) finish(500,'Local media read failed');else response.destroy();});
    response.on('close', () => stream.destroy());
    stream.pipe(response);
  });
  server.on('connection', socket => {sockets.add(socket);socket.on('close', () => sockets.delete(socket));});
  await new Promise((resolve, reject) => {server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  origin = 'http://127.0.0.1:' + server.address().port;
  let closed = false;
  return {origin, pageUrl:origin + pageRoute, url:origin + mediaRoute,
    async close() {
      if (closed) return; closed = true;
      for (const stream of streams) stream.destroy();
      for (const socket of sockets) socket.destroy();
      await new Promise(resolve => server.close(resolve));
    }};
}

function chromium() {
  let playwright;
  for (const root of [process.env.NODE_PATH,path.join(os.homedir(),'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules')].filter(Boolean)) {
    try {playwright = require(path.join(root,'playwright'));break;} catch {}
  }
  if (!playwright) playwright = require('playwright');
  const realRoot = path.join(os.homedir(),'AppData/Local/ms-playwright');
  const base = fs.existsSync(realRoot) ? realRoot : path.join(process.env.LOCALAPPDATA || '','ms-playwright');
  const executablePath = fs.existsSync(base) ? fs.readdirSync(base).filter(name=>name.startsWith('chromium-'))
    .map(name=>path.join(base,name,'chrome-win64/chrome.exe')).filter(name=>fs.existsSync(name)).sort().at(-1) : undefined;
  return playwright.chromium.launch({headless:true,timeout:20000,...(executablePath?{executablePath}:{})});
}

async function withLocalMediaPage(input, callback) {
  const media = await openLocalMedia(input);
  let browser;
  try {
    browser = await chromium();
    const page = await browser.newPage();
    await page.goto(media.pageUrl,{waitUntil:'domcontentloaded',timeout:15000});
    return await callback(page,media.url);
  } finally {
    await Promise.allSettled([media.close(),...(browser?[browser.close()]:[])]);
  }
}

module.exports = {byteRange,openLocalMedia,withLocalMediaPage};
