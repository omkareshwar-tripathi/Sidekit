'use strict';
// Project Atlas — zero-dependency local dashboard server.
//
// Serves the static dashboard from .atlas/ and exposes the derived data as JSON.
// Run:  node .atlas/server.js   →  open the printed http://127.0.0.1:7842 URL.
//
// No npm, no package.json — only Node's built-in modules (works on Node 18+,
// so it runs the same on the user's machine, a fresh clone, or the cloud container).

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const HOST = '127.0.0.1';
const PORT = 7842;
const ROOT = __dirname; // the .atlas/ directory
const REPO_ROOT = path.resolve(ROOT, '..');
const DATA_DIR = path.join(ROOT, 'data');
const gitBranches = require('./git-branches');

const CONTENT_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
};

// The data layers sync.js writes; GET /api/data returns their union.
// A layer that hasn't been generated yet is reported as null (the UI degrades).
const LAYERS = ['git', 'vision', 'progress', 'decisions', 'environment', 'branches'];

function readLayer(name) {
  try {
    return JSON.parse(fs.readFileSync(path.join(DATA_DIR, name + '.json'), 'utf8'));
  } catch {
    return null; // not generated yet / unreadable — layer simply absent
  }
}

function sendJson(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function serveStatic(req, res) {
  // Map "/" to index.html; resolve within ROOT and refuse path traversal.
  const rel = req.url === '/' ? 'index.html' : decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '');
  const filePath = path.join(ROOT, rel);
  if (filePath !== ROOT && !filePath.startsWith(ROOT + path.sep)) {
    res.writeHead(403);
    res.end('forbidden');
    return;
  }
  fs.readFile(filePath, (err, buf) => {
    if (err) {
      res.writeHead(404);
      res.end('not found');
      return;
    }
    const type = CONTENT_TYPES[path.extname(filePath)] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': type });
    res.end(buf);
  });
}

const server = http.createServer(async (req, res) => {
  const route = req.url.split('?')[0];

  if (req.method === 'GET' && route === '/api/data') {
    const data = {};
    for (const layer of LAYERS) data[layer] = readLayer(layer);
    sendJson(res, 200, data);
    return;
  }

  // On-demand detail for any branch (the picker loads non-current branches here).
  if (req.method === 'GET' && route.startsWith('/api/branch/')) {
    const name = decodeURIComponent(route.slice('/api/branch/'.length));
    if (!gitBranches.branchNames(REPO_ROOT).includes(name)) {
      sendJson(res, 404, { error: 'unknown branch' });
      return;
    }
    const d = gitBranches.detail(REPO_ROOT, name);
    if (!d) {
      sendJson(res, 404, { error: 'no detail' });
      return;
    }
    sendJson(res, 200, d);
    return;
  }

  if (req.method === 'GET') {
    serveStatic(req, res);
    return;
  }

  res.writeHead(405);
  res.end('method not allowed');
});

server.listen(PORT, HOST, () => {
  console.log(`Project Atlas → http://${HOST}:${PORT}`);
});
