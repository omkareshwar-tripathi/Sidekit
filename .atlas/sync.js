'use strict';
// Project Atlas — sync: derive the dashboard view from the repo's real sources.
//
// Adapter-shaped by design (plan §G, "seam now, generalize later"): every source
// is a small adapter — { id, layer, detect(), read() } — and the driver just runs
// every adapter whose detect() is true and writes the union to .atlas/data/<layer>.json.
// Adding a new source later (or supporting a different repo) means appending an
// adapter to ADAPTERS, never rewriting the driver.
//
// Idempotent at day granularity: same repo state on the same day → byte-identical
// output. All atlas dates are YYYY-MM-DD so two consecutive runs don't churn.
//
// Zero dependencies — Node built-ins only. Run from anywhere: `node .atlas/sync.js`.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execSync } = require('node:child_process');

const ATLAS_DIR = __dirname;
const REPO_ROOT = path.resolve(ATLAS_DIR, '..');
const DATA_DIR = path.join(ATLAS_DIR, 'data');

function repoPath(...p) {
  return path.join(REPO_ROOT, ...p);
}
function today() {
  return new Date().toISOString().slice(0, 10);
}
function truncate(s, n) {
  const t = s.replace(/\s+/g, ' ').trim();
  return t.length > n ? t.slice(0, n - 1).trimEnd() + '…' : t;
}
function git(args) {
  return execSync('git ' + args, {
    cwd: REPO_ROOT,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  }).trim();
}

// --- markdown helpers (shared by the doc-reading adapters) ---

// Flatten inline markdown to plain text: links → their text, drop emphasis/code.
function stripInline(s) {
  return s
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/[*_`]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

// Lines between a heading matching `headingRe` and the next heading of any level.
function sectionBody(lines, headingRe) {
  const start = lines.findIndex((l) => headingRe.test(l));
  if (start < 0) return [];
  const out = [];
  for (let i = start + 1; i < lines.length; i++) {
    if (/^#{1,6}\s/.test(lines[i])) break;
    out.push(lines[i]);
  }
  return out;
}

function tableCells(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim());
}

// Data rows (cell-arrays) of every pipe-table in `lines`; skips header separators.
function parseTable(lines) {
  const rows = [];
  for (const l of lines) {
    if (!/^\s*\|.*\|\s*$/.test(l)) continue;
    if (/^\s*\|[\s:|-]+\|\s*$/.test(l)) continue;
    rows.push(tableCells(l));
  }
  return rows;
}

// Data rows of the table whose header is `| Decision | Choice | Why |`.
function findDecisionTable(lines) {
  const hdr = lines.findIndex((l) => /\|\s*Decision\s*\|\s*Choice\s*\|\s*Why\s*\|/i.test(l));
  if (hdr < 0) return [];
  const rows = [];
  for (let i = hdr + 2; i < lines.length; i++) {
    if (!/^\s*\|.*\|\s*$/.test(lines[i])) break;
    if (/^\s*\|[\s:|-]+\|\s*$/.test(lines[i])) continue;
    rows.push(tableCells(lines[i]));
  }
  return rows;
}

// ---------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------

// git — universal: present in any git repo. Feeds the welcome-back ribbon.
const gitAdapter = {
  id: 'git',
  layer: 'git',
  detect() {
    try {
      git('rev-parse --is-inside-work-tree');
      return true;
    } catch {
      return false;
    }
  },
  read() {
    const iso = git('log -1 --format=%cI');
    const commitDay = iso.slice(0, 10);
    const daysAway = Math.round((Date.parse(today()) - Date.parse(commitDay)) / 86400000);
    return {
      branch: git('rev-parse --abbrev-ref HEAD'),
      lastCommitISO: iso,
      lastCommitDate: commitDay,
      lastCommitSubject: git('log -1 --format=%s'),
      lastCommitAuthor: git('log -1 --format=%an'),
      cleanTree: git('status --porcelain') === '',
      daysAway,
      generatedAt: today(),
    };
  },
};

// Items that read as parked/waiting rather than actionable land in "Blocked".
const BLOCKED_RE = /\b(blocked|deferred|gated|hardware|awaiting|parked|pending a human)\b/i;

// bricks — this repo's BRICKS.md checkbox log → a Done/Doing/Next/Blocked kanban.
// Derivation (plan §B): `- [x]` → Done; the FIRST open, non-blocked `- [ ]` in
// document order → Doing (the current brick, per the session-start convention);
// remaining open items → Next, except those whose text reads as parked → Blocked.
const bricksAdapter = {
  id: 'bricks',
  layer: 'progress',
  detect() {
    return fs.existsSync(repoPath('BRICKS.md'));
  },
  read() {
    const lines = fs.readFileSync(repoPath('BRICKS.md'), 'utf8').split('\n');
    let section = '';
    const items = [];
    for (const line of lines) {
      const h = line.match(/^#{2,4}\s+(.*)$/);
      if (h) {
        section = h[1].replace(/[*_`]/g, '').trim();
        continue;
      }
      const m = line.match(/^\s*-\s*\[([ xX])\]\s+(.*)$/);
      if (!m) continue;
      const body = m[2].trim();
      const bold = body.match(/\*\*(.+?)\*\*/);
      items.push({
        checked: m[1].toLowerCase() === 'x',
        title: bold ? bold[1].trim() : truncate(body, 80),
        detail: truncate(body.replace(/\*\*/g, ''), 240),
        section,
      });
    }

    const done = [];
    const next = [];
    const blocked = [];
    let doing = null;
    for (const it of items) {
      if (it.checked) {
        done.push(it);
      } else if (BLOCKED_RE.test(it.title) || BLOCKED_RE.test(it.detail)) {
        blocked.push(it);
      } else if (!doing) {
        doing = it; // first actionable open item = current focus
      } else {
        next.push(it);
      }
    }
    return {
      doing: doing ? [doing] : [],
      next,
      blocked,
      done: done.slice(0, 8), // recent few, document order (newest workstreams first)
      generatedAt: today(),
    };
  },
};

// vision-readme — vision/README.md → north star, pitch, the capability table
// with the 🔵🟡🟠🟢 maturity legend (a Vision concept, per §B), and open questions.
const visionAdapter = {
  id: 'vision-readme',
  layer: 'vision',
  detect() {
    return fs.existsSync(repoPath('vision/README.md'));
  },
  read() {
    const lines = fs.readFileSync(repoPath('vision/README.md'), 'utf8').split('\n');

    // North star: the blockquote that starts with **North star:**
    let northStar = '';
    const nsIdx = lines.findIndex((l) => /\*\*North star:\*\*/.test(l));
    if (nsIdx >= 0) {
      const buf = [];
      for (let i = nsIdx; i < lines.length; i++) {
        if (!/^\s*>/.test(lines[i])) break;
        buf.push(lines[i].replace(/^\s*>\s?/, ''));
      }
      northStar = stripInline(buf.join(' ')).replace(/^North star:\s*/i, '');
    }

    const pitch = stripInline(sectionBody(lines, /^##\s+The one-paragraph pitch/).join(' '));

    let legend = [];
    const legendLine = lines.find((l) => /\*\*Status legend:\*\*/.test(l));
    if (legendLine) {
      legend = stripInline(legendLine)
        .replace(/^Status legend:\s*/i, '')
        .split('·')
        .map((seg) => {
          const m = seg.trim().match(/^(\S+)\s+(.*)$/);
          return m ? { emoji: m[1], label: m[2].trim() } : null;
        })
        .filter(Boolean);
    }

    const capabilities = parseTable(sectionBody(lines, /^##\s+What's inside the Sidekit bracket/))
      .filter((r) => r.length >= 4 && !/^Capability$/i.test(r[0]))
      .map((r) => ({
        name: stripInline(r[0]),
        line: stripInline(r[1]),
        platforms: stripInline(r[2]),
        status: r[3].trim(), // keep the emoji — it ties back to the legend
      }));

    const openQuestions = sectionBody(lines, /^##\s+Open strategic questions/)
      .filter((l) => /^\s*-\s+/.test(l))
      .map((l) => stripInline(l.replace(/^\s*-\s+/, '')));

    return { northStar, pitch, legend, capabilities, openQuestions, generatedAt: today() };
  },
};

// specs-decisions — the locked decision tables in docs/superpowers/specs/*.md
// become what/why flip-cards; the `**Notes / decisions:**` blocks in BRICKS.md
// Done entries become secondary decision notes.
const decisionsAdapter = {
  id: 'specs-decisions',
  layer: 'decisions',
  detect() {
    return fs.existsSync(repoPath('docs/superpowers/specs')) || fs.existsSync(repoPath('BRICKS.md'));
  },
  read() {
    const decisions = [];
    const specsDir = repoPath('docs/superpowers/specs');
    if (fs.existsSync(specsDir)) {
      for (const file of fs.readdirSync(specsDir).filter((f) => f.endsWith('.md')).sort()) {
        const lines = fs.readFileSync(path.join(specsDir, file), 'utf8').split('\n');
        for (const r of findDecisionTable(lines)) {
          if (r.length >= 3 && r[0]) {
            decisions.push({
              decision: stripInline(r[0]),
              choice: stripInline(r[1]),
              why: stripInline(r[2]),
              source: 'specs/' + file,
            });
          }
        }
      }
    }

    const notes = [];
    if (fs.existsSync(repoPath('BRICKS.md'))) {
      const lines = fs.readFileSync(repoPath('BRICKS.md'), 'utf8').split('\n');
      let context = '';
      let inBlock = false;
      for (const l of lines) {
        const h = l.match(/^#{2,4}\s+(.*)$/);
        if (h) {
          context = stripInline(h[1]);
          inBlock = false;
          continue;
        }
        if (/^\s*-\s*\*\*Notes\s*\/\s*decisions:\*\*/i.test(l)) {
          inBlock = true;
          continue;
        }
        if (!inBlock) continue;
        const b = l.match(/^\s{2,}-\s+(.*)$/);
        if (b) notes.push({ context, text: stripInline(b[1]), source: 'BRICKS.md' });
        else if (l.trim() !== '') inBlock = false;
      }
    }

    return { decisions, notes: notes.slice(0, 12), generatedAt: today() };
  },
};

// --- AI Operating Context (Layer 6) — two-tier environment model (plan §F) ---
//
// Two tiers: COMMITTED (.claude/* — travels with the repo, always renderable) and
// MACHINE-LOCAL (~/.claude/* — only visible where the user actually works). The
// cloud container can never read the user's ~/.claude, so we "commit the view":
// environment.json is committed, and we PRESERVE-DON'T-DELETE machine-local items
// when that tier isn't visible (§F.0). A run is treated as machine-local only when
// NOT in the cloud and the user's global config dir exists — the cloud's own
// harness ~/.claude must never be mistaken for the user's (§A).

function inCloud() {
  return !!process.env.CLAUDE_CODE_REMOTE;
}
function homeClaudeVisible() {
  return !inCloud() && fs.existsSync(path.join(os.homedir(), '.claude'));
}
function safeIsDir(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}
function mkItem(o) {
  return {
    id: o.id,
    name: o.name,
    tier: o.tier,
    sourcePath: o.sourcePath,
    portable: !!o.portable,
    status: o.status,
    lastSeen: o.lastSeen || today(),
    promoteHint: o.promoteHint || '',
    machineBound: !!o.machineBound,
  };
}

// Committed tier — always present, always applies in the cloud.
function buildCommitted() {
  const items = [];
  const add = (id, name, sourcePath) =>
    items.push(mkItem({ id, name, tier: 'committed', sourcePath, portable: true, status: 'applies-in-cloud' }));

  if (fs.existsSync(repoPath('CLAUDE.md'))) add('doc:CLAUDE', 'CLAUDE.md — working agreement', 'CLAUDE.md');
  if (fs.existsSync(repoPath('BRICKS.md'))) add('doc:BRICKS', 'BRICKS.md — session handoff log', 'BRICKS.md');

  const enumerate = (rel, suffix, idPrefix, label, dirsOnly) => {
    const dir = repoPath(rel);
    if (!fs.existsSync(dir)) return;
    for (const e of fs.readdirSync(dir).sort()) {
      const full = path.join(dir, e);
      if (dirsOnly ? !safeIsDir(full) : !e.endsWith(suffix)) continue;
      const base = dirsOnly ? e : e.replace(suffix, '');
      add(idPrefix + base, label + base, rel + '/' + e);
    }
  };
  enumerate('.claude/hooks', '.sh', 'hook:', 'Hook — ', false);
  enumerate('.claude/skills', '', 'skill:', 'Skill — ', true);
  enumerate('.claude/commands', '.md', 'command:', 'Command — /', false);
  return items;
}

function globalMcpServers() {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8'));
    return j.mcpServers ? Object.keys(j.mcpServers).sort() : [];
  } catch {
    return [];
  }
}
function gitnexusPresent() {
  try {
    execSync('command -v gitnexus', { stdio: 'ignore', shell: '/bin/bash' });
    return true;
  } catch {
    /* not on PATH */
  }
  try {
    return /gitnexus/i.test(fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8'));
  } catch {
    return false;
  }
}

// Machine-local tier — read from the user's real ~/.claude (only when visible).
function buildMachineLocal() {
  const items = [];
  const hc = path.join(os.homedir(), '.claude');

  if (fs.existsSync(path.join(hc, 'CLAUDE.md'))) {
    items.push(mkItem({
      id: 'mem:global', name: 'Global memory — ~/.claude/CLAUDE.md', tier: 'machine-local',
      sourcePath: '~/.claude/CLAUDE.md', portable: false, status: 'local-only',
      promoteHint: 'Promote → .claude/global-memory.md, @import from CLAUDE.md',
    }));
  }
  const gskills = path.join(hc, 'skills');
  if (fs.existsSync(gskills)) {
    for (const d of fs.readdirSync(gskills).filter((d) => safeIsDir(path.join(gskills, d))).sort()) {
      items.push(mkItem({
        id: 'skill:global:' + d, name: 'Global skill — ' + d, tier: 'machine-local',
        sourcePath: '~/.claude/skills/' + d, portable: false, status: 'local-only',
        promoteHint: 'Promote → .claude/skills/' + d + '/',
      }));
    }
  }
  for (const name of globalMcpServers()) {
    items.push(mkItem({
      id: 'mcp:' + name, name: 'Global MCP — ' + name, tier: 'machine-local',
      sourcePath: '~/.claude.json', portable: false, status: 'local-only',
      promoteHint: 'Promote → .mcp.json (project scope, ${ENV} secrets)',
    }));
  }
  if (gitnexusPresent()) {
    items.push(mkItem({
      id: 'tool:gitnexus', name: 'GitNexus — local git query backend', tier: 'machine-local',
      sourcePath: '(global hook / binary)', portable: false, status: 'local-only-machine-bound', machineBound: true,
    }));
  }
  items.push(mkItem({
    id: 'info:node', name: 'Node ' + process.version + ' (local runtime)', tier: 'machine-local',
    sourcePath: '(local)', portable: false, status: 'local-only',
  }));
  return items;
}

function readPriorEnvironment() {
  try {
    return JSON.parse(fs.readFileSync(path.join(DATA_DIR, 'environment.json'), 'utf8'));
  } catch {
    return null;
  }
}

// If a promotion artifact now exists committed, flip its machine-local source to "promoted".
function markPromoted(byId) {
  const mem = byId.get('mem:global');
  if (mem && fs.existsSync(repoPath('.claude/global-memory.md'))) mem.status = 'promoted';
  const mcpExists = fs.existsSync(repoPath('.mcp.json'));
  for (const it of byId.values()) {
    if (it.id.startsWith('mcp:') && mcpExists) it.status = 'promoted';
    if (it.id.startsWith('skill:global:')) {
      const name = it.id.slice('skill:global:'.length);
      if (fs.existsSync(repoPath('.claude/skills/' + name))) it.status = 'promoted';
    }
  }
}

// The merge: rebuild committed fresh; rebuild OR preserve machine-local; union by id.
function mergeEnvironment() {
  const prior = readPriorEnvironment();
  const priorItems = (prior && prior.items) || [];
  const byId = new Map(buildCommitted().map((it) => [it.id, it]));

  let generatedTier;
  if (homeClaudeVisible()) {
    generatedTier = 'machine-local';
    for (const it of buildMachineLocal()) byId.set(it.id, it);
  } else {
    generatedTier = 'committed-only';
    for (const it of priorItems) {
      if (it.tier !== 'machine-local' || byId.has(it.id)) continue;
      const carried = { ...it };
      if (carried.status === 'applies-in-cloud') carried.status = 'local-only';
      byId.set(it.id, carried); // preserve verbatim; lastSeen stays as last recorded
    }
  }
  markPromoted(byId);

  const items = [...byId.values()].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return { generatedAt: today(), generatedTier, items };
}

// claude-context — Layer 6. detect() is true wherever there's any AI config to show.
const claudeContextAdapter = {
  id: 'claude-context',
  layer: 'environment',
  detect() {
    return fs.existsSync(repoPath('.claude')) || readPriorEnvironment() != null;
  },
  read() {
    return mergeEnvironment();
  },
};

// branches — per-branch view (commits since main, the merge add/remove diff, and
// the matching BRICKS section). Overview for all branches + embedded detail for the
// current one; other branches load on demand via server.js's /api/branch/:name.
const gitBranches = require('./git-branches');
const branchesAdapter = {
  id: 'branches',
  layer: 'branches',
  detect() {
    try {
      git('rev-parse --is-inside-work-tree');
      return true;
    } catch {
      return false;
    }
  },
  read() {
    const ov = gitBranches.overview(REPO_ROOT);
    if (!ov) return { base: '', current: '', branches: [], detail: null, generatedAt: today() };
    ov.detail = ov.current ? gitBranches.detail(REPO_ROOT, ov.current) : null;
    return ov;
  },
};

// Ordered registry. Future adapters (other repos' sources) append here — the
// driver below never changes.
const ADAPTERS = [gitAdapter, bricksAdapter, visionAdapter, decisionsAdapter, claudeContextAdapter, branchesAdapter];

// ---------------------------------------------------------------------------
// Promotion scaffolder (plan §F.2) — runs on the user's machine only.
// Turns a machine-local item into a committed artifact that applies in the cloud.
// Safety: Atlas-authored regions are fenced with sentinels and only those are
// rewritten; a whole-file target that isn't atlas-authored is left untouched
// (we back up before regenerating); operations are idempotent.
// ---------------------------------------------------------------------------

function backup(file) {
  if (fs.existsSync(file)) fs.copyFileSync(file, file + '.bak');
}
function reEscape(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Replace the content between markdown sentinels for `id`, or append the block.
// Human prose outside the sentinels is never touched.
function upsertSentinelRegion(file, id, inner) {
  const begin = '<!-- atlas:begin ' + id + ' -->';
  const end = '<!-- atlas:end ' + id + ' -->';
  const block = begin + '\n' + inner + '\n' + end;
  let text = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  if (text.includes(begin) && text.includes(end)) {
    text = text.replace(new RegExp(reEscape(begin) + '[\\s\\S]*?' + reEscape(end)), block);
  } else {
    text = text.replace(/\s*$/, '') + '\n\n' + block + '\n';
  }
  backup(file);
  fs.writeFileSync(file, text);
}

function promoteMemory() {
  const src = path.join(os.homedir(), '.claude/CLAUDE.md');
  if (!fs.existsSync(src)) return { ok: false, message: 'No ~/.claude/CLAUDE.md to promote.' };
  const target = repoPath('.claude/global-memory.md');
  backup(target);
  const header = '<!-- Atlas-owned: generated from ~/.claude/CLAUDE.md. Edit the source there, then re-run promote. -->\n\n';
  fs.writeFileSync(target, header + fs.readFileSync(src, 'utf8'));
  upsertSentinelRegion(repoPath('CLAUDE.md'), 'global-memory', '@.claude/global-memory.md');
  return { ok: true, message: 'Promoted global memory → .claude/global-memory.md (+ sentinel @import in CLAUDE.md).' };
}

function promoteSkill(name) {
  const src = path.join(os.homedir(), '.claude/skills', name);
  if (!fs.existsSync(src)) return { ok: false, message: 'No ~/.claude/skills/' + name + ' to promote.' };
  const target = repoPath('.claude/skills', name);
  if (fs.existsSync(target)) return { ok: true, message: '.claude/skills/' + name + ' already committed — skipped (committed wins).' };
  fs.cpSync(src, target, { recursive: true });
  return { ok: true, message: 'Promoted skill → .claude/skills/' + name + '/.' };
}

function sanitizeMcp(cfg, name, requiredEnv) {
  const out = { ...cfg };
  if (out.env && typeof out.env === 'object') {
    const env = {};
    for (const k of Object.keys(out.env)) {
      const v = '${' + (name + '_' + k).toUpperCase().replace(/[^A-Z0-9]/g, '_') + '}';
      env[k] = v;
      requiredEnv.add(v.slice(2, -1));
    }
    out.env = env;
  }
  return out;
}

function promoteMcp() {
  const file = repoPath('.mcp.json');
  if (fs.existsSync(file)) {
    let existing;
    try {
      existing = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch {
      existing = null;
    }
    if (!existing || existing._atlas !== true) {
      return { ok: false, message: '.mcp.json exists and is hand-edited (no atlas marker) — aborting, nothing clobbered.' };
    }
  }
  let servers = {};
  try {
    servers = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8')).mcpServers || {};
  } catch {
    /* none */
  }
  if (!Object.keys(servers).length) return { ok: false, message: 'No global MCP servers in ~/.claude.json to promote.' };

  const requiredEnv = new Set();
  const mcpServers = {};
  for (const [name, cfg] of Object.entries(servers)) mcpServers[name] = sanitizeMcp(cfg, name, requiredEnv);
  backup(file);
  const out = {
    _atlas: true,
    _comment: 'Generated by Project Atlas from ~/.claude.json. Set these env vars in the cloud: ' + ([...requiredEnv].join(', ') || '(none)'),
    mcpServers,
  };
  fs.writeFileSync(file, JSON.stringify(out, null, 2) + '\n');
  return { ok: true, message: 'Promoted ' + Object.keys(mcpServers).length + ' MCP server(s) → .mcp.json. Required env: ' + ([...requiredEnv].join(', ') || '(none)') };
}

function promote(id) {
  if (inCloud()) return { ok: false, message: 'Promotion runs on your machine — the cloud cannot see ~/.claude.' };
  if (id === 'mem:global') return promoteMemory();
  if (id.startsWith('skill:global:')) return promoteSkill(id.slice('skill:global:'.length));
  if (id.startsWith('mcp:')) return promoteMcp();
  return { ok: false, message: 'Nothing promotable for id: ' + id };
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

function writeLayer(layer, payload) {
  fs.writeFileSync(path.join(DATA_DIR, layer + '.json'), JSON.stringify(payload, null, 2) + '\n');
}

function run() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  // --env-only: refresh just the environment layer. Used by the cloud SessionStart
  // hook so the preserve-don't-delete merge runs without touching the rest (§F.2d).
  const envOnly = process.argv.includes('--env-only');
  const adapters = envOnly ? ADAPTERS.filter((a) => a.layer === 'environment') : ADAPTERS;
  console.log('Project Atlas — sync' + (envOnly ? ' (env-only)' : ''));
  for (const a of adapters) {
    let present = false;
    try {
      present = a.detect();
    } catch {
      present = false;
    }
    if (!present) {
      console.log(`  · ${a.id}: source absent — skipped`);
      continue;
    }
    try {
      writeLayer(a.layer, a.read());
      console.log(`  · ${a.id} → data/${a.layer}.json`);
    } catch (err) {
      console.log(`  · ${a.id}: read failed (${err.message}) — skipped`);
    }
  }
}

const promoteArg = process.argv.find((a) => a.startsWith('--promote='));
if (promoteArg) {
  const result = promote(promoteArg.slice('--promote='.length));
  console.log(result.message);
  process.exit(result.ok ? 0 : 1);
} else {
  run();
}
