#!/usr/bin/env node
// Serves a built web app and a fixture-driven fake API on one port, so a page can be opened and screenshotted
// without the real backend.
//
//   node mock-api.js <dist-dir> <fixtures.json> [port] [--api-prefix <prefix>]
//
// --api-prefix controls how API requests are told apart from static ones:
//   <prefix> (default `api.`)  requests whose Host starts with the prefix get fixtures; Chromium resolves
//                              `api.localhost` to loopback, so an app calling `<protocol>//api.<host>/...` works.
//   none                       the app calls its own origin; any path matching a fixture gets the fixture.
// Everything else is the static app, falling back to index.html for client-side routes.
//
// fixtures.json is an array of { "match": "<regex on the path>", "body": <json>, "status": 200 }; the first match
// wins and anything unmatched is a 404 with `{}` (for hosts treated as the API). Match with anchors, since
// `/items/1` also matches `/items/1/details` without them.
const http = require('http');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
let apiPrefix = 'api.';
const prefixAt = args.indexOf('--api-prefix');
if (prefixAt !== -1) {
    apiPrefix = args[prefixAt + 1];
    args.splice(prefixAt, 2);
}

const [root, fixturesFile, port = '5055'] = args;
if (!root || !fixturesFile || !apiPrefix) {
    console.error('usage: node mock-api.js <dist-dir> <fixtures.json> [port] [--api-prefix <prefix>|none]');
    process.exit(1);
}
const sameOrigin = apiPrefix === 'none';

const fixtures = JSON.parse(fs.readFileSync(fixturesFile, 'utf8')).map(f => ({ ...f, match: new RegExp(f.match) }));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.woff2': 'font/woff2', '.json': 'application/json', '.ico': 'image/x-icon' };

http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    const fixture = fixtures.find(f => f.match.test(url.pathname));

    if (sameOrigin ? fixture : (req.headers.host || '').startsWith(apiPrefix)) {
        const headers = { 'Access-Control-Allow-Origin': req.headers.origin || '*', 'Access-Control-Allow-Headers': '*', 'Content-Type': 'application/json' };
        if (req.method === 'OPTIONS') {
            res.writeHead(204, headers);
            return res.end();
        }
        res.writeHead(fixture ? fixture.status ?? 200 : 404, headers);
        return res.end(JSON.stringify(fixture ? fixture.body : {}));
    }

    let file = path.join(root, decodeURIComponent(url.pathname));
    if (!path.resolve(file).startsWith(path.resolve(root)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        file = path.join(root, 'index.html');
    }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
}).listen(Number(port), () => console.log(`http://localhost:${port}/`));
