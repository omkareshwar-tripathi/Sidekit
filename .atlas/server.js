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
const { execFileSync } = require('node:child_process');
const sm2 = require('./sm2');

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
const LAYERS = ['git', 'vision', 'progress', 'decisions', 'learning', 'environment', 'pending', 'branches'];

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

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 1e6) req.destroy(); // refuse oversized bodies
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(data || '{}'));
      } catch {
        resolve(null);
      }
    });
  });
}

// Append an in-place edit as a proposal. Canonical docs (vision/, specs, BRICKS)
// are never touched here — Claude folds these into the real docs during a session.
function appendPending(body) {
  const file = path.join(DATA_DIR, 'pending.json');
  let pending;
  try {
    pending = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    pending = { proposals: [] };
  }
  pending.proposals.push({
    layer: body.layer || 'unknown',
    field: body.field || '',
    original: body.original || '',
    text: body.text,
    at: new Date().toISOString(),
  });
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(file, JSON.stringify(pending, null, 2) + '\n');
  return pending.proposals.length;
}

// --- Learning: atlas-owned flashcards + SM-2 review state (data/learning.json) ---
const LEARNING_FILE = path.join(DATA_DIR, 'learning.json');

function readLearning() {
  try {
    return JSON.parse(fs.readFileSync(LEARNING_FILE, 'utf8'));
  } catch {
    return { cards: [] };
  }
}
function writeLearning(model) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(LEARNING_FILE, JSON.stringify(model, null, 2) + '\n');
}
function today() {
  return new Date().toISOString().slice(0, 10);
}

// Apply an SM-2 grade to a card and persist. Returns the updated card or null.
function gradeCard(id, grade) {
  const model = readLearning();
  const i = model.cards.findIndex((c) => c.id === id);
  if (i < 0) return null;
  model.cards[i] = sm2.review(model.cards[i], grade, today());
  writeLearning(model);
  return model.cards[i];
}

// Add a new card or edit an existing one's text; persist. Returns the card.
function upsertCard(body) {
  const model = readLearning();
  if (body.id) {
    const i = model.cards.findIndex((c) => c.id === body.id);
    if (i >= 0) {
      if (body.front != null) model.cards[i].front = body.front;
      if (body.back != null) model.cards[i].back = body.back;
      writeLearning(model);
      return model.cards[i];
    }
  }
  const card = {
    id: 'c-' + Date.now().toString(36),
    front: body.front,
    back: body.back,
    ease: 2.5,
    interval: 0,
    reps: 0,
    lapses: 0,
    due: today(),
  };
  model.cards.push(card);
  writeLearning(model);
  return card;
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

  if (req.method === 'POST' && route === '/api/pending') {
    const body = await readBody(req);
    if (!body || !body.text) {
      sendJson(res, 400, { error: 'expected { text, layer, field, original }' });
      return;
    }
    sendJson(res, 200, { ok: true, count: appendPending(body) });
    return;
  }

  if (req.method === 'POST' && route === '/api/review') {
    const body = await readBody(req);
    if (!body || !body.id || !sm2.Q[body.grade]) {
      sendJson(res, 400, { error: 'expected { id, grade: again|hard|good|easy }' });
      return;
    }
    const card = gradeCard(body.id, body.grade);
    if (!card) {
      sendJson(res, 404, { error: 'no such card' });
      return;
    }
    sendJson(res, 200, { ok: true, card });
    return;
  }

  if (req.method === 'POST' && route === '/api/card') {
    const body = await readBody(req);
    if (!body || !body.front || !body.back) {
      sendJson(res, 400, { error: 'expected { front, back, id? }' });
      return;
    }
    sendJson(res, 200, { ok: true, card: upsertCard(body) });
    return;
  }

  if (req.method === 'POST' && route.startsWith('/api/promote/')) {
    const id = decodeURIComponent(route.slice('/api/promote/'.length));
    if (process.env.CLAUDE_CODE_REMOTE) {
      sendJson(res, 200, { ok: false, message: 'Run locally — the cloud cannot see ~/.claude.' });
      return;
    }
    try {
      const out = execFileSync('node', [path.join(ROOT, 'sync.js'), '--promote=' + id], { encoding: 'utf8' });
      sendJson(res, 200, { ok: true, message: out.trim() });
    } catch (e) {
      sendJson(res, 200, { ok: false, message: (e.stdout || '').trim() || e.message });
    }
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
