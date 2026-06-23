'use strict';
// git-branches.js — per-branch intelligence for the Atlas. Pure, zero-dependency.
//
// Both sync.js (precompute the current branch's detail) and server.js (on-demand
// detail for ANY branch) use this. It builds its own git runner from a repoRoot so
// neither caller duplicates git logic. All dates are day-granular (YYYY-MM-DD) so
// the data is idempotent within a day, matching the rest of the atlas.
//
// "What a merge adds/removes" = the three-dot diff `base...branch` (i.e. changes
// since the merge-base) — exactly what merging the branch into base would bring in.

const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

function makeGit(repoRoot) {
  return (args) =>
    execSync('git ' + args, { cwd: repoRoot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
}
function today() {
  return new Date().toISOString().slice(0, 10);
}
function daysSince(dateStr) {
  return Math.round((Date.parse(today()) - Date.parse(dateStr)) / 86400000);
}
function safe(git, args) {
  try {
    return git(args);
  } catch {
    return '';
  }
}
function isGitRepo(git) {
  try {
    git('rev-parse --is-inside-work-tree');
    return true;
  } catch {
    return false;
  }
}

// The branch a merge would target. Prefer local main/master, then origin's.
function detectBase(git) {
  try {
    const h = git('symbolic-ref --short refs/remotes/origin/HEAD');
    if (h) return h.replace(/^origin\//, '');
  } catch {
    /* origin/HEAD not set */
  }
  for (const c of ['main', 'master', 'origin/main', 'origin/master']) {
    try {
      git('rev-parse --verify --quiet ' + c + '^{commit}');
      return c;
    } catch {
      /* not this one */
    }
  }
  try {
    return git('rev-parse --abbrev-ref HEAD');
  } catch {
    return 'HEAD';
  }
}
function currentBranch(git) {
  try {
    return git('rev-parse --abbrev-ref HEAD');
  } catch {
    return '';
  }
}

function aheadBehind(git, base, name) {
  // rev-list --left-right --count base...name → "behind<TAB>ahead"
  const out = safe(git, `rev-list --left-right --count ${base}...${name}`);
  const [behind, ahead] = out.split(/\s+/).map((n) => parseInt(n, 10) || 0);
  return { ahead: ahead || 0, behind: behind || 0 };
}

function diffStat(git, base, name) {
  let filesChanged = 0,
    insertions = 0,
    deletions = 0;
  const out = safe(git, `diff --numstat --no-renames ${base}...${name}`);
  if (out) {
    for (const line of out.split('\n')) {
      if (!line) continue;
      const [ins, del] = line.split('\t');
      filesChanged++;
      insertions += parseInt(ins, 10) || 0; // '-' for binary → NaN → 0
      deletions += parseInt(del, 10) || 0;
    }
  }
  return { filesChanged, insertions, deletions };
}

// The matching BRICKS.md section for a branch (its `## … — on `<branch>`` header).
function matchBricksSection(repoRoot, branch) {
  let lines;
  try {
    lines = fs.readFileSync(path.join(repoRoot, 'BRICKS.md'), 'utf8').split('\n');
  } catch {
    return null;
  }
  let start = -1,
    title = '';
  for (let i = 0; i < lines.length; i++) {
    const h = lines[i].match(/^##\s+(.*)$/);
    if (!h) continue;
    const onBranch = h[1].match(/on\s+`([^`]+)`/);
    if (onBranch && onBranch[1] === branch) {
      start = i;
      title = h[1].replace(/[*`]/g, '').trim();
      break;
    }
  }
  if (start < 0) return null;
  const items = [];
  for (let i = start + 1; i < lines.length && items.length < 12; i++) {
    if (/^##\s/.test(lines[i])) break;
    const cm = lines[i].match(/^\s*-\s*\[([ xX])\]\s+(.*)$/);
    if (!cm) continue;
    const body = cm[2].trim();
    const bold = body.match(/\*\*(.+?)\*\*/);
    items.push({ checked: cm[1].toLowerCase() === 'x', title: bold ? bold[1].trim() : body.slice(0, 80) });
  }
  return { section: title, items };
}

// Overview of every branch (local + origin/*), cheap counts only.
function overview(repoRoot) {
  const git = makeGit(repoRoot);
  if (!isGitRepo(git)) return null;
  const base = detectBase(git);
  const current = currentBranch(git);

  const raw = safe(
    git,
    "for-each-ref --sort=-committerdate --format='%(refname:short)%09%(committerdate:short)%09%(authorname)%09%(contents:subject)' refs/heads refs/remotes/origin"
  );
  const localNames = new Set();
  const rows = [];
  for (const l of raw.split('\n')) {
    if (!l) continue;
    const parts = l.split('\t');
    const name = parts[0];
    if (name === 'origin/HEAD') continue;
    const isRemote = name.startsWith('origin/');
    rows.push({ name, date: parts[1], author: parts[2], subject: parts.slice(3).join('\t'), isRemote });
    if (!isRemote) localNames.add(name);
  }

  const branches = [];
  for (const r of rows) {
    // A pushed branch shows once (local wins); only remote-only branches add a row.
    if (r.isRemote && localNames.has(r.name.replace(/^origin\//, ''))) continue;
    const { ahead, behind } = aheadBehind(git, base, r.name);
    const stat = diffStat(git, base, r.name);
    branches.push({
      name: r.name,
      isCurrent: r.name === current,
      isRemote: r.isRemote,
      tipDate: r.date,
      tipSubject: r.subject,
      author: r.author,
      ahead,
      behind,
      filesChanged: stat.filesChanged,
      insertions: stat.insertions,
      deletions: stat.deletions,
      lastActivityDays: daysSince(r.date),
      bricksSection: (matchBricksSection(repoRoot, r.name.replace(/^origin\//, '')) || {}).section || '',
    });
  }
  return { base: base.replace(/^origin\//, ''), current, branches, generatedAt: today() };
}

// Full detail for one branch: commits since base + the file-level diff + BRICKS story.
function detail(repoRoot, name) {
  const git = makeGit(repoRoot);
  if (!isGitRepo(git)) return null;
  try {
    git('rev-parse --verify --quiet ' + name + '^{commit}');
  } catch {
    return null; // not a real ref
  }
  const base = detectBase(git);
  const { ahead, behind } = aheadBehind(git, base, name);
  const stat = diffStat(git, base, name);

  const commits = [];
  for (const l of safe(git, `log -n 100 --format=%h%09%cd%09%an%09%s --date=format:%Y-%m-%d ${base}..${name}`).split('\n')) {
    if (!l) continue;
    const p = l.split('\t');
    commits.push({ sha: p[0], date: p[1], author: p[2], subject: p.slice(3).join('\t') });
  }

  const lineStat = {};
  for (const l of safe(git, `diff --numstat --no-renames ${base}...${name}`).split('\n')) {
    if (!l) continue;
    const p = l.split('\t');
    lineStat[p.slice(2).join('\t')] = { insertions: parseInt(p[0], 10) || 0, deletions: parseInt(p[1], 10) || 0 };
  }
  const files = [];
  for (const l of safe(git, `diff --name-status --no-renames ${base}...${name}`).split('\n')) {
    if (!l || files.length >= 200) continue;
    const p = l.split('\t');
    const fp = p.slice(1).join('\t');
    files.push({
      status: p[0][0], // A | M | D
      path: fp,
      insertions: (lineStat[fp] || {}).insertions || 0,
      deletions: (lineStat[fp] || {}).deletions || 0,
    });
  }

  return {
    name,
    base: base.replace(/^origin\//, ''),
    ahead,
    behind,
    filesChanged: stat.filesChanged,
    insertions: stat.insertions,
    deletions: stat.deletions,
    commits,
    files,
    bricks: matchBricksSection(repoRoot, name.replace(/^origin\//, '')),
    generatedAt: today(),
  };
}

// Cheap list of valid branch names (local + origin/*) — for endpoint validation.
function branchNames(repoRoot) {
  const git = makeGit(repoRoot);
  if (!isGitRepo(git)) return [];
  return safe(git, "for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin")
    .split('\n')
    .filter((n) => n && n !== 'origin/HEAD');
}

module.exports = { overview, detail, detectBase, branchNames };
