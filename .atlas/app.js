'use strict';
// Project Atlas — redesigned dashboard client (LIGHT theme, glance-first).
// Renders the layers in the locked order: a thin Branch-filter bar -> Vision ->
// Progress (a kanban board, filtered by the selected branch) -> Decisions ->
// AI Operating Context (now at the bottom). Every fact is visible at a single
// glance; color is never the only signal (shape + glyph + word too).
//
// Read-only display: it derives from /api/data only. The edit-in-place and
// Promote write-paths were removed in ATLAS-SIMPLIFY (unused).

const $ = (sel) => document.querySelector(sel);

// Tiny safe DOM builder. el('div', {class:'x'}, [child, 'text'])
function el(tag, attrs, kids) {
  const node = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null) continue;
      if (k === 'class') node.className = v;
      else if (k === 'html') node.innerHTML = v;
      else node.setAttribute(k, v);
    }
  }
  for (const kid of kids || []) {
    if (kid == null) continue;
    node.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return node;
}

function plural(n, one, many) {
  return n + ' ' + (n === 1 ? one : many || one + 's');
}

// Section subtitles ("what this tells you") — one per section, set on render.
const SUBTITLES = {
  'ai-context': 'What intelligence is loaded into Claude right now — and how much of it survives in the cloud.',
  vision: 'The north star and the open questions — the slowest-changing layer.',
  progress: "The build queue for the selected branch — what's in flight, what's queued, what's stuck.",
  decisions: 'The calls already made and why — nothing hidden behind a click.',
};
function setSub(id) {
  const node = $('#' + id + '-sub');
  if (node) node.textContent = SUBTITLES[id] || '';
}

// ============================================================================
// STATUS TOKENS (A2) — four colorblind-safe tokens. Color ALWAYS redundant
// with shape + glyph + word. Glyph rendered in a fixed >=16px box (.sg) with an
// aria-label, independent of the 12px caption text it sits beside.
//   in-cloud = green FILLED CIRCLE + check  | local = amber HOLLOW TRIANGLE
//   promoted = violet UP-ARROW              | bound = red FILLED SQUARE + lock
// ============================================================================
const STATUS = {
  'applies-in-cloud': { key: 'cloud', glyph: '✓', word: 'in cloud', cls: 's-cloud', aria: 'in cloud (filled circle)' },
  'local-only': { key: 'local', glyph: '△', word: 'local', cls: 's-local', aria: 'local (hollow triangle)' },
  promoted: { key: 'promoted', glyph: '↑', word: 'promoted', cls: 's-promoted', aria: 'promoted (up arrow)' },
  'local-only-machine-bound': { key: 'bound', glyph: '■', word: 'bound', cls: 's-bound', aria: 'machine-bound (filled square)' },
};
function statusOf(status) {
  return STATUS[status] || { key: 'other', glyph: '•', word: status || 'unknown', cls: 's-local', aria: status || 'unknown' };
}

// A StatusToken: glyph box (aria-labelled) + short word. Word disambiguates when
// the shape is too small to read (A2).
function statusToken(status, extraWord) {
  const s = statusOf(status);
  return el('span', { class: 'stoken ' + s.cls }, [
    el('span', { class: 'sg', 'aria-label': s.aria, role: 'img' }, [s.glyph]),
    el('span', { class: 'sw' }, [extraWord || s.word]),
  ]);
}

// categoryOf(id) — nine real categories from the id prefix, with the critical
// skill:global: vs skill:<x> split, and an 'other' catch-all so a future/unknown
// id prefix is never silently dropped (D11).
function categoryOf(id) {
  if (id.startsWith('skill:global:')) return 'skill-global';
  if (id.startsWith('skill:')) return 'skill-project';
  const p = (id.split(':')[0] || '').trim();
  if (['command', 'doc', 'hook', 'mcp', 'mem', 'info', 'tool'].includes(p)) return p;
  return 'other';
}

// ============================================================================
// 1) AI OPERATING CONTEXT (hero)
// ============================================================================
function renderEnvironment(e) {
  setSub('ai-context');
  const body = $('#ai-context-body');
  body.replaceChildren();
  if (!e || !e.items) return body.append(emptyState('No AI config found.'));

  const committedOnly = e.generatedTier === 'committed-only';
  const items = e.items;

  // ---- PortabilityStrip (D3) — partition ALL items by portability so reading
  // only this strip tells the truth: 'In cloud N' + 'Local N'. 'Promoted N' is a
  // NON-additive annotation, never a third parallel portability bucket.
  const inCloud = items.filter((it) => it.portable).length;
  const local = items.filter((it) => !it.portable).length;
  const bound = items.filter((it) => it.machineBound).length;
  const promoted = items.filter((it) => it.status === 'promoted').length;

  body.append(
    el('div', { class: 'portability-strip' }, [
      el('span', { class: 'schip s-total' }, [plural(items.length, 'item')]),
      countChip('s-cloud', '✓', 'In cloud', inCloud, 'in cloud (filled circle)'),
      countChip('s-local', '△', 'Local', local, 'local (hollow triangle)'),
      countChip('s-bound', '■', 'Bound', bound, 'machine-bound (filled square)'),
      countChip('s-promoted', '↑', 'Promoted', promoted, 'promoted (up arrow)'),
    ])
  );
  // Honest annotations: where bound/promoted live (never read as portability buckets).
  body.append(
    el('p', { class: 'portability-note' }, [
      'Counts above are totals for all ' + items.length + ' items, not the filtered view. ' +
        'Of the ' + local + ' local, ' + bound + ' is machine-bound. ' +
        'Promoted ' + promoted + ' is a sub-note within local — those global skills already mirror a committed project skill; the committed copy is the one that travels.',
    ])
  );

  // ---- Nine CategoryGroups ordered by re-onboarding actionability; skill-global LAST.
  const ORDER = [
    { cat: 'hook', label: 'Hooks' },
    { cat: 'doc', label: 'Docs' },
    { cat: 'mcp', label: 'MCP servers' },
    { cat: 'mem', label: 'Memory' },
    { cat: 'command', label: 'Commands' },
    { cat: 'info', label: 'Runtime' },
    { cat: 'tool', label: 'Tools' },
    { cat: 'skill-project', label: 'Project skills' },
    { cat: 'skill-global', label: 'Global skills' },
    { cat: 'other', label: 'Other' }, // catch-all, only renders if non-empty (D11)
  ];

  for (const grp of ORDER) {
    const groupItems = items.filter((it) => categoryOf(it.id) === grp.cat);
    if (!groupItems.length) continue; // committed-only or future-id safe (D11/G2)

    const portableCount = groupItems.filter((it) => it.portable).length;

    if (grp.cat === 'skill-global') {
      body.append(renderGlobalSkills(grp.label, groupItems));
    } else {
      // Per-group aggregate data-text so the whole group hides when every row
      // filters out (G2 — no orphan headers).
      const groupText = groupItems.map((it) => it.name + ' ' + it.sourcePath).join(' ').toLowerCase();
      const portNote = portableCount === groupItems.length
        ? 'all travel to cloud'
        : portableCount === 0
        ? 'none travel to cloud'
        : portableCount + ' of ' + groupItems.length + ' travel to cloud';
      body.append(
        el('div', { class: 'env-group', 'data-group': '1', 'data-text': groupText }, [
          el('div', { class: 'group-head' }, [
            grp.label,
            el('span', { class: 'gh-count' }, [String(groupItems.length)]),
            el('span', { class: 'gh-note' }, ['· ' + portNote]),
          ]),
          el('div', { class: 'env-surface' }, groupItems.map((it) => envRow(it, committedOnly))),
        ])
      );
    }
  }
}

function countChip(cls, glyph, word, n, aria) {
  return el('span', { class: 'schip ' + cls }, [
    el('span', { class: 'sg', 'aria-label': aria, role: 'img' }, [glyph]),
    word + ' ' + n,
  ]);
}

function envRow(it, committedOnly) {
  const s = statusOf(it.status);
  // Full status label is VISIBLE DOM text (A3): short word from the token + a
  // longer phrase appended where it adds meaning. No title-only load-bearing info.
  let word = s.word;
  if (committedOnly && it.status.indexOf('local-only') === 0) word += ' · last seen ' + it.lastSeen;

  const main = el('div', { class: 'er-main' }, [
    el('span', { class: 'er-name' }, [it.name]),
    // Source path: full string in the node (middle-truncated by CSS), not title-only (A3).
    el('span', { class: 'er-path', 'aria-label': 'source: ' + it.sourcePath }, [it.sourcePath]),
  ]);

  // data-text includes the visible status word so the existing search reaches it (G2).
  return el('div', { class: 'env-row', 'data-text': (it.name + ' ' + it.sourcePath + ' ' + word).toLowerCase() }, [
    el('div', { class: 'er-token' }, [statusToken(it.status, word)]),
    main,
  ]);
}

// The 35 global skills as a dense name-only chip grid (fully visible, never
// collapsed). D2/A2: the group is NOT homogeneous (29 local + 6 promoted) — give
// EACH chip its own status glyph so the 6 promoted stand out; the header is honest.
function renderGlobalSkills(label, groupItems) {
  const localN = groupItems.filter((it) => it.status === 'local-only').length;
  const promN = groupItems.filter((it) => it.status === 'promoted').length;
  const otherN = groupItems.length - localN - promN;
  const parts = [];
  if (localN) parts.push(localN + ' local');
  if (promN) parts.push(promN + ' promoted');
  if (otherN) parts.push(otherN + ' other');

  // Group-level data-text so the whole group hides when every chip filters out (G2).
  const groupText = groupItems.map((it) => it.name).join(' ').toLowerCase();

  return el('div', { class: 'env-group', 'data-group': '1', 'data-text': groupText }, [
    el('div', { class: 'group-head' }, [
      label,
      el('span', { class: 'gh-count' }, [String(groupItems.length)]),
      el('span', { class: 'gh-note' }, ['· ' + parts.join(', ')]),
    ]),
    el('div', { class: 'chip-grid' }, groupItems.map((it) => {
      const s = statusOf(it.status);
      const shortName = it.name.replace(/^Global skill\s*[—-]\s*/, '');
      return el('div', { class: 'chip ' + s.cls, 'data-text': (it.name + ' ' + s.word).toLowerCase() }, [
        el('span', { class: 'cg-glyph', 'aria-label': s.aria, role: 'img' }, [s.glyph]),
        el('span', { class: 'cg-name', title: it.name }, [shortName]),
      ]);
    })),
  ]);
}

// ============================================================================
// 2) VISION
// ============================================================================
// A4: map the 4 vision statuses to 4 DISTINCT SHAPES + word (the emoji circles
// are color-only — never reach the DOM). D7: capability.status is already a
// glyph+text string and one is COMPOUND ('🟡 Polish proven · 🔵 Drafting vision');
// split on ' · ', decode EACH part, fallback strips the emoji to plain text.
const VISION_SHAPES = [
  { match: ['vision'], glyph: '○', word: 'Vision', cls: 'v-vision', aria: 'Vision (hollow circle)' },
  { match: ['designing', 'proven', 'lab', 'polish'], glyph: '◑', word: 'Designing', cls: 'v-design', aria: 'Designing (half circle)' },
  { match: ['building'], glyph: '▲', word: 'Building', cls: 'v-building', aria: 'Building (filled triangle)' },
  { match: ['shipped'], glyph: '✓', word: 'Shipped', cls: 'v-shipped', aria: 'Shipped (filled check)' },
];
// Decode one status part (may carry an emoji) into a shape+word, by matching the
// legend label keywords. Always strips emoji so no raw colored emoji reaches the DOM.
function decodeVisionPart(part) {
  const text = part.replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}️]/gu, '').trim();
  const low = text.toLowerCase();
  for (const sh of VISION_SHAPES) {
    if (sh.match.some((m) => low.includes(m))) return { glyph: sh.glyph, word: text, cls: sh.cls, aria: sh.aria };
  }
  return { glyph: '•', word: text || part, cls: 'v-vision', aria: text || 'status' };
}
function decodeVisionStatus(status) {
  return String(status).split(' · ').map(decodeVisionPart);
}

function renderVision(v) {
  setSub('vision');
  const body = $('#vision-body');
  body.replaceChildren();
  if (!v) return body.append(emptyState('No vision/README.md found.'));

  if (v.northStar) body.append(el('p', { class: 'north', 'data-text': v.northStar.toLowerCase() }, [v.northStar]));
  if (v.pitch) body.append(el('p', { class: 'pitch', 'data-text': v.pitch.toLowerCase() }, [v.pitch]));

  // Legend as decoded shape+word (A4) — built from the legend labels, not the emoji.
  if (v.legend && v.legend.length) {
    body.append(
      el('ul', { class: 'vlegend' }, v.legend.map((l) => {
        const d = decodeVisionPart(l.label);
        return el('li', null, [
          el('span', { class: 'vshape ' + d.cls, 'aria-label': d.aria, role: 'img' }, [d.glyph]),
          l.label,
        ]);
      }))
    );
  }

  if (v.capabilities && v.capabilities.length) {
    body.append(
      el('div', { class: 'grid cols-2' }, v.capabilities.map((c) =>
        card([
          el('div', { class: 'cap', 'data-text': (c.name + ' ' + c.line + ' ' + c.status).toLowerCase() }, [
            el('span', { class: 'cap-name' }, [c.name]),
            el('div', { class: 'cap-status' }, decodeVisionStatus(c.status).map((d) =>
              el('span', { class: 'vbadge' }, [
                el('span', { class: 'vshape ' + d.cls, 'aria-label': d.aria, role: 'img' }, [d.glyph]),
                d.word,
              ])
            )),
            el('div', { class: 'cap-line' }, [c.line]),
            el('div', { class: 'cap-plat' }, [c.platforms]),
          ]),
        ])
      ))
    );
  }

  if (v.openQuestions && v.openQuestions.length) {
    body.append(
      el('div', { class: 'qs-wrap', 'data-group': '1', 'data-text': v.openQuestions.join(' ').toLowerCase() }, [
        el('div', { class: 'group-head' }, ['Open strategic questions', el('span', { class: 'gh-note' }, ['· verbatim from the source — truncated mid-sentence'])]),
        el('ul', { class: 'qs' }, v.openQuestions.map((q) =>
          el('li', { 'data-text': q.toLowerCase() }, [q, el('span', { class: 'qs-trunc' }, [' …(truncated)']) ])
        )),
      ])
    );
  }
}

// ============================================================================
// BRANCH FILTER BAR + state — the thin top bar that scopes the kanban below.
// The selected branch lives in branchState; selecting one re-applies the
// branch filter (no fetch — it's a pure DOM class toggle on the kanban cards).
// ============================================================================
const ALL_BRANCHES = '__all__'; // sentinel: show every brick (incl. null-branch)
const branchState = { selected: ALL_BRANCHES };

function renderBranchBar(b) {
  const bar = $('#branch-bar');
  if (!bar) return;
  bar.replaceChildren();
  if (!b || !b.branches || !b.branches.length) {
    bar.append(emptyState('Not a git repo, or no branches found.'));
    return;
  }
  const current = b.current || (b.branches.find((br) => br.isCurrent) || {}).name || ALL_BRANCHES;
  branchState.selected = current;
  const base = b.base || 'main';

  // Current-branch label + ahead/behind chips (reuse the status-line chip style).
  const cur = b.branches.find((br) => br.name === current) || b.branches.find((br) => br.isCurrent);
  const ahead = cur ? cur.ahead : 0;
  const behind = cur ? cur.behind : 0;

  // Switcher: All branches + every branch name. Default selection = current.
  const select = el('select', { class: 'branch-switch', 'aria-label': 'Filter the board by branch' }, [
    el('option', { value: ALL_BRANCHES }, ['All branches']),
    ...b.branches.map((br) =>
      el('option', { value: br.name, selected: br.name === current ? 'selected' : null }, [br.name])
    ),
  ]);
  select.addEventListener('change', () => selectBranch(select.value));

  bar.append(
    el('span', { class: 'bb-label' }, ['Branch']),
    el('span', { class: 'bb-name' }, [current]),
    el('span', { class: 'sl-chip', 'aria-label': 'ahead of ' + base }, ['↑' + ahead + ' ahead of ' + base]),
    el('span', { class: 'sl-chip', 'aria-label': 'behind ' + base }, ['↓' + behind + ' behind']),
    el('span', { class: 'bb-spacer' }, []),
    select
  );
}

// Selecting a branch = set state + (re)apply the branch filter. No fetch.
function selectBranch(name) {
  branchState.selected = name;
  const nameNode = $('#branch-bar .bb-name');
  if (nameNode) nameNode.textContent = name === ALL_BRANCHES ? 'All branches' : name;
  const sel = $('#branch-bar .branch-switch');
  if (sel) sel.value = name;
  applyBranchFilter();
}

// ============================================================================
// PROGRESS — kanban board (Doing / Blocked / Next / Done), branch-filtered.
//
// Filter composition (the key correctness point): search owns `.hidden`, the
// branch filter owns a DEDICATED `.b-hidden`. Both set display:none !important;
// a card is VISIBLE iff it has NEITHER class. The two filters never touch each
// other's class. Columns are NOT marked [data-group] so setupSearch's group
// pass can't collapse a whole column.
// ============================================================================
const KANBAN_COLS = [
  { key: 'doing', label: 'Doing', cls: 'col-doing', glyph: '▶', resume: true },
  { key: 'blocked', label: 'Blocked', cls: 'col-blocked', glyph: '■' },
  { key: 'next', label: 'Next', cls: 'col-next', glyph: '○' },
  { key: 'done', label: 'Done', cls: 'col-done', glyph: '✓' },
];

function renderProgress(p) {
  setSub('progress');
  const body = $('#progress-body');
  body.replaceChildren();
  if (!p) return body.append(emptyState('No BRICKS.md found.'));

  const board = el('div', { class: 'kanban' }, KANBAN_COLS.map((g) => {
    const items = p[g.key] || [];
    return el('div', { class: 'col ' + g.cls }, [
      el('div', { class: 'col-head' }, [
        el('span', { class: 'col-glyph', 'aria-label': g.label, role: 'img' }, [g.glyph]),
        el('span', { class: 'col-word' }, [g.label]),
        el('span', { class: 'col-count' }, ['0']),
      ]),
      el('div', { class: 'col-body' }, [
        ...items.map((it) => brick(it)),
        el('p', { class: 'col-empty empty' }, ['—']),
      ]),
    ]);
  }));
  body.append(board);
  // Board-level empty state — shown by recomputeKanban when no card is visible.
  body.append(el('p', { id: 'kanban-empty', class: 'empty kanban-empty' }, ['No bricks on this branch.']));
}

// A single brick card. data-text drives search (unchanged); data-branch drives
// the branch filter (''=null-branch brick, only visible under "All branches").
function brick(it) {
  return el('div', {
    class: 'brick',
    'data-branch': it.branch || '',
    'data-text': (it.title + ' ' + (it.detail || '') + ' ' + (it.section || '')).toLowerCase(),
  }, [
    el('div', { class: 'br-top' }, [
      el('span', { class: 'br-resume' }, ['resume here']), // shown only on .is-resume
      el('span', { class: 'br-title' }, [it.title]),
      it.section ? el('span', { class: 'br-section' }, [it.section]) : null,
    ]),
    it.detail ? el('div', { class: 'br-detail' }, [it.detail]) : null,
  ]);
}

// Toggle the DEDICATED `.b-hidden` class per card, then recompute the board.
function applyBranchFilter() {
  const sel = branchState.selected;
  document.querySelectorAll('.brick[data-branch]').forEach((card) => {
    const b = card.getAttribute('data-branch');
    const show = sel === ALL_BRANCHES || b === sel;
    card.classList.toggle('b-hidden', !show);
  });
  recomputeKanban();
}

// Recompute everything that depends on the COMBINED filter, every change:
// per-column visible counts, per-column "—" placeholder, the board-level empty
// state, and the `.is-resume` marker (first VISIBLE Doing card). A card counts
// as visible iff it has NEITHER `.hidden` (search) NOR `.b-hidden` (branch).
function recomputeKanban() {
  const isVisible = (card) => !card.classList.contains('hidden') && !card.classList.contains('b-hidden');
  let boardVisible = 0;

  document.querySelectorAll('#progress-body .col').forEach((col) => {
    const cards = col.querySelectorAll('.brick');
    let n = 0;
    cards.forEach((c) => { if (isVisible(c)) n++; });
    boardVisible += n;
    const count = col.querySelector('.col-count');
    if (count) count.textContent = String(n);
    const empty = col.querySelector('.col-empty');
    if (empty) empty.classList.toggle('hidden', n !== 0);
  });

  // Resume marker: first VISIBLE card in the Doing column, recomputed live.
  document.querySelectorAll('#progress-body .brick.is-resume').forEach((c) => c.classList.remove('is-resume'));
  const doing = $('#progress-body .col-doing');
  if (doing) {
    for (const c of doing.querySelectorAll('.brick')) {
      if (isVisible(c)) { c.classList.add('is-resume'); break; }
    }
  }

  const boardEmpty = $('#kanban-empty');
  if (boardEmpty) boardEmpty.classList.toggle('hidden', boardVisible !== 0);
}

// ============================================================================
// 5) DECISIONS — static cards (flip-cards removed; G1)
// ============================================================================
function renderDecisions(d) {
  setSub('decisions');
  const body = $('#decisions-body');
  body.replaceChildren();
  if (!d || (!d.decisions.length && !d.notes.length)) return body.append(emptyState('No decisions recorded yet.'));

  if (d.decisions.length) {
    // D9 — all 7 share the same source: ONE shared 'Source:' line for the grid.
    const sources = Array.from(new Set(d.decisions.map((x) => x.source).filter(Boolean)));
    // Aggregate data-text so the whole block (source line + grid) hides together
    // when every card filters out — no orphan 'Source:' label (G2).
    const decText = d.decisions.map((dec) => dec.decision + ' ' + dec.choice + ' ' + dec.why).join(' ').toLowerCase();
    body.append(
      el('div', { class: 'decisions-group', 'data-group': '1', 'data-text': decText }, [
        sources.length === 1 ? el('p', { class: 'decisions-source' }, ['Source: ' + sources[0]]) : null,
        el('div', { class: 'dgrid' }, d.decisions.map((dec) =>
          el('div', { class: 'decision-card', 'data-text': (dec.decision + ' ' + dec.choice + ' ' + dec.why).toLowerCase() }, [
            el('div', { class: 'd-label' }, [dec.decision]),
            el('div', { class: 'd-choice' }, [
              el('span', { class: 'd-check', 'aria-label': 'the call' }, ['✓']),
              dec.choice,
            ]),
            el('div', { class: 'd-why' }, [dec.why]),
            // Per-card source only if it differs from the shared one (D9).
            sources.length !== 1 && dec.source ? el('div', { class: 'd-src' }, [dec.source]) : null,
          ])
        )),
      ])
    );
  }

  if (d.notes.length) {
    // Aggregate data-text so the heading hides with its notes (G2 — no orphan h3).
    const notesText = d.notes.map((n) => n.context + ' ' + n.text).join(' ').toLowerCase();
    body.append(
      el('div', { class: 'notes', 'data-group': '1', 'data-text': notesText }, [
        el('h3', null, ['Decision notes from the build log']),
        ...d.notes.map((n) =>
          el('p', { class: 'note', 'data-text': (n.context + ' ' + n.text).toLowerCase() }, [
            el('b', null, [n.context + ' — ']),
            el('span', null, [n.text]),
          ])
        ),
      ])
    );
  }
}

// ============================================================================
// STATUS LINE (D10) — quiet top reference: branch, ahead/behind vs main,
// 'snapshot <date>' (date-only — never 'synced'), tree state from cleanTree bool
// only ('uncommitted changes' / 'clean tree', never 'N uncommitted').
// ============================================================================
function renderStatusLine(git, branches) {
  const line = $('#status-line');
  if (!line) return;
  line.replaceChildren();
  if (!git) {
    line.append('Could not reach the atlas server.');
    return;
  }
  let ahead = 0, behind = 0, base = (branches && branches.base) || 'main';
  if (branches && branches.branches) {
    const cur = branches.branches.find((b) => b.isCurrent);
    if (cur) { ahead = cur.ahead; behind = cur.behind; }
  }
  line.append(
    el('span', { class: 'sl-branch' }, [git.branch]),
    el('span', { class: 'sl-chip', 'aria-label': 'ahead of ' + base }, ['↑' + ahead + ' ahead of ' + base]),
    el('span', { class: 'sl-chip', 'aria-label': 'behind ' + base }, ['↓' + behind + ' behind']),
    el('span', { class: 'sl-sep' }, ['|']),
    el('span', null, ['snapshot ' + (git.generatedAt || git.lastCommitDate)]),
    el('span', { class: 'sl-sep' }, ['|']),
    el('span', { class: 'sl-tree ' + (git.cleanTree ? 'clean' : 'dirty') }, [git.cleanTree ? 'clean tree' : 'uncommitted changes'])
  );
}

// ============================================================================
// shared
// ============================================================================
function card(kids) {
  return el('div', { class: 'card' }, kids);
}
function emptyState(msg) {
  return el('p', { class: 'empty' }, [msg]);
}

// ============================================================================
// search / filter — group-aware (G2). Hide a row when it does not match; then
// hide any [data-group] container whose every [data-text] child is hidden, so
// no orphan headers and no gap-toothed chip reflow are left behind.
// ============================================================================
function setupSearch() {
  const input = $('#search');
  if (!input) return;
  input.addEventListener('input', () => {
    const q = input.value.trim().toLowerCase();

    // 1) toggle individual rows/chips (everything with data-text that is NOT a group)
    document.querySelectorAll('[data-text]').forEach((node) => {
      if (node.hasAttribute('data-group')) return; // groups handled in pass 2
      const hit = !q || node.getAttribute('data-text').includes(q);
      node.classList.toggle('hidden', !hit);
    });

    // 2) hide a whole group only when NONE of its data-text children survive.
    // A group's own data-text can be incomplete (e.g. name-only, missing the
    // status word), so we never gate on the group matching — any surviving child
    // keeps the group visible. This keeps every item reachable (G2) while still
    // collapsing label-only headers when nothing under them matches.
    // Kanban columns are NOT [data-group], so a column is never collapsed here.
    document.querySelectorAll('[data-group]').forEach((group) => {
      const children = group.querySelectorAll('[data-text]');
      let anyVisible = false;
      children.forEach((c) => { if (c !== group && !c.classList.contains('hidden')) anyVisible = true; });
      group.classList.toggle('hidden', !(!q || anyVisible));
    });

    // 3) recompute the kanban so its counts / per-column + board empty states /
    // resume marker reflect the COMBINED (search AND branch) filter.
    recomputeKanban();
  });
}

async function boot() {
  let data;
  try {
    data = await fetch('/api/data').then((r) => r.json());
  } catch (err) {
    renderStatusLine(null, null);
    return;
  }
  renderStatusLine(data.git, data.branches);
  renderBranchBar(data.branches);
  renderVision(data.vision);
  renderProgress(data.progress);
  renderDecisions(data.decisions);
  renderEnvironment(data.environment);
  setupSearch();
  applyBranchFilter(); // last: DOM exists, board opens scoped to the current branch
  $('#foot').textContent =
    'Project Atlas — a reflection of vision/, BRICKS.md, the specs, and .claude/. Refresh with `node .atlas/sync.js`.';
}

boot();
