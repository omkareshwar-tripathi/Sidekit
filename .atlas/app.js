'use strict';
// Project Atlas — dashboard client. Fetches the derived data and renders the
// six layers. Read-only display in this brick; edit-in-place and flashcard
// review are layered on by later bricks.

const $ = (sel) => document.querySelector(sel);

// Tiny safe DOM builder. el('div', {class:'x'}, [child, 'text'])
function el(tag, attrs, kids) {
  const node = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
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

// ---- Welcome-back ribbon ----
function renderRibbon(git, progress, branches) {
  const inner = $('#ribbon-inner');
  inner.replaceChildren();
  if (!git) {
    inner.append(el('h1', null, ['Project Atlas']));
    return;
  }
  const days = git.daysAway;
  const away = days <= 0 ? 'Picking up where you left off' : plural(days, 'day') + ' away';
  const doing = progress && progress.doing && progress.doing[0] ? progress.doing[0].title : git.lastCommitSubject;

  // Branch-aware: how far the current branch is ahead of the base.
  let branchBit = '';
  if (branches && branches.branches) {
    const cur = branches.branches.find((b) => b.isCurrent);
    if (cur) branchBit = ' · ' + plural(cur.ahead, 'commit') + ' ahead of ' + branches.base;
  }

  inner.append(
    el('p', { class: 'eyebrow' }, ['Welcome back']),
    el('h1', { html: '<b>' + escapeHtml(away) + '</b> — you were working on this branch.' }),
    el('p', { class: 'resume' }, ['Resume here → ', el('span', { class: 'pill' }, [doing])]),
    el('p', { class: 'meta' }, [
      el('code', null, [git.branch]),
      branchBit + ' · last commit ' + git.lastCommitDate + ' · ' + (git.cleanTree ? 'clean tree' : 'uncommitted changes'),
    ])
  );
}

// ---- Branches ----
let branchData = null;

function renderBranches(b) {
  const body = $('#branches-body');
  if (!body) return;
  body.replaceChildren();
  branchData = b;
  if (!b || !b.branches || !b.branches.length) {
    body.append(emptyState('Not a git repo, or no branches found.'));
    return;
  }
  body.append(el('div', { class: 'branch-picker' }, b.branches.map((br) => branchChip(br))));
  body.append(el('div', { id: 'branch-detail', class: 'branch-detail' }, []));
  renderBranchDetail(b.detail);
}

function branchChip(br) {
  const cls = 'bchip' + (br.isCurrent ? ' current active' : '') + (br.isRemote ? ' remote' : '');
  const chip = el('button', { type: 'button', class: cls, 'data-text': (br.name + ' ' + br.bricksSection).toLowerCase() }, [
    el('span', { class: 'bchip-name' }, [br.name]),
    el('span', { class: 'bchip-meta' }, [
      '↑' + br.ahead + ' ↓' + br.behind,
      el('span', { class: 'bchip-stat add' }, ['+' + br.insertions]),
      el('span', { class: 'bchip-stat del' }, ['−' + br.deletions]),
      el('span', { class: 'bchip-age' }, [br.lastActivityDays + 'd']),
    ]),
  ]);
  chip.addEventListener('click', () => selectBranch(br.name));
  return chip;
}

async function selectBranch(name) {
  document.querySelectorAll('.bchip').forEach((c) =>
    c.classList.toggle('active', c.querySelector('.bchip-name').textContent === name)
  );
  if (branchData && branchData.detail && branchData.detail.name === name) {
    renderBranchDetail(branchData.detail);
    return;
  }
  const panel = $('#branch-detail');
  panel.replaceChildren(el('p', { class: 'empty' }, ['Loading ' + name + '…']));
  try {
    const d = await fetch('/api/branch/' + encodeURIComponent(name)).then((r) => r.json());
    if (d && d.name) renderBranchDetail(d);
    else panel.replaceChildren(el('p', { class: 'empty' }, ['No detail for ' + name + '.']));
  } catch {
    panel.replaceChildren(el('p', { class: 'empty' }, ['Could not load ' + name + '.']));
  }
}

function renderBranchDetail(d) {
  const panel = $('#branch-detail');
  if (!panel) return;
  panel.replaceChildren();
  if (!d) {
    panel.append(emptyState('Select a branch.'));
    return;
  }
  panel.append(
    el('div', { class: 'bd-head' }, [
      el('span', { class: 'bd-name' }, ['On ', el('code', null, [d.name])]),
      el('span', { class: 'bd-stat' }, [
        d.ahead + ' ahead of ' + d.base + ' · ' + plural(d.commits.length, 'commit') + ' · +' + d.insertions + '/−' + d.deletions + ' across ' + plural(d.filesChanged, 'file'),
      ]),
    ])
  );

  panel.append(el('div', { class: 'env-group-title' }, ['What was done — ' + plural(d.commits.length, 'commit')]));
  panel.append(
    d.commits.length
      ? el('div', { class: 'commit-list' }, d.commits.map((c) =>
          el('div', { class: 'commit', 'data-text': c.subject.toLowerCase() }, [
            el('span', { class: 'c-sha' }, [c.sha]),
            el('span', { class: 'c-subj' }, [c.subject]),
            el('span', { class: 'c-date' }, [c.date]),
          ])
        ))
      : emptyState('Nothing ahead of ' + d.base + '.')
  );

  panel.append(el('div', { class: 'env-group-title' }, ['What a merge into ' + d.base + ' adds / removes']));
  panel.append(
    d.files.length
      ? el('div', { class: 'file-list' }, d.files.map((f) => {
          const sc = f.status === 'A' ? 'add' : f.status === 'D' ? 'del' : 'mod';
          const label = f.status === 'A' ? 'added' : f.status === 'D' ? 'removed' : 'modified';
          return el('div', { class: 'frow ' + sc, 'data-text': f.path.toLowerCase() }, [
            el('span', { class: 'f-status' }, [label]),
            el('span', { class: 'f-path' }, [f.path]),
            el('span', { class: 'f-stat' }, ['+' + f.insertions + ' −' + f.deletions]),
          ]);
        }))
      : emptyState('No file changes vs ' + d.base + '.')
  );

  if (d.bricks && d.bricks.items && d.bricks.items.length) {
    panel.append(el('div', { class: 'env-group-title' }, ['The story — ' + d.bricks.section]));
    panel.append(
      el('ul', { class: 'story' }, d.bricks.items.map((it) =>
        el('li', { class: it.checked ? 'done' : 'open', 'data-text': it.title.toLowerCase() }, [(it.checked ? '✓ ' : '○ ') + it.title])
      ))
    );
  }
}

// ---- Vision ----
function renderVision(v) {
  const body = $('#vision-body');
  body.replaceChildren();
  if (!v) return body.append(emptyState('No vision/README.md found.'));

  if (v.northStar) body.append(makeEditable(el('p', { class: 'north' }, [v.northStar]), v.northStar, 'vision', 'northStar'));
  if (v.pitch) body.append(makeEditable(el('p', { class: 'pitch' }, [v.pitch]), v.pitch, 'vision', 'pitch'));

  if (v.legend && v.legend.length) {
    body.append(el('ul', { class: 'legend' }, v.legend.map((l) => el('li', null, [l.emoji + ' ' + l.label]))));
  }

  if (v.capabilities && v.capabilities.length) {
    body.append(
      el('div', { class: 'grid cols-2' }, v.capabilities.map((c) =>
        card([
          el('div', { class: 'cap' }, [
            el('div', { class: 'cap-top' }, [
              el('span', { class: 'cap-name' }, [c.name]),
              el('span', { class: 'cap-status' }, [c.status]),
            ]),
            el('div', { class: 'cap-line' }, [c.line]),
            el('div', { class: 'cap-plat' }, [c.platforms]),
          ]),
        ])
      ))
    );
  }

  if (v.openQuestions && v.openQuestions.length) {
    body.append(
      el('div', { class: 'qs-wrap' }, [
        el('div', { class: 'env-group-title' }, ['Open strategic questions']),
        el('ul', { class: 'qs' }, v.openQuestions.map((q, i) =>
          makeEditable(el('li', { 'data-text': q }, [q]), q, 'vision', 'openQuestion[' + i + ']')
        )),
      ])
    );
  }
}

// ---- Progress kanban ----
function renderProgress(p) {
  const body = $('#progress-body');
  body.replaceChildren();
  if (!p) return body.append(emptyState('No BRICKS.md found.'));

  const columns = [
    { key: 'doing', label: 'Doing', cls: 'col-doing' },
    { key: 'next', label: 'Next', cls: 'col-next' },
    { key: 'blocked', label: 'Blocked', cls: 'col-blocked' },
    { key: 'done', label: 'Recently done', cls: 'col-done' },
  ];
  body.append(
    el('div', { class: 'kanban' }, columns.map((col) => {
      const items = p[col.key] || [];
      return el('div', { class: 'col ' + col.cls }, [
        el('h3', null, [col.label, el('span', { class: 'count' }, [String(items.length)])]),
        ...items.map((it) =>
          el('div', { class: 'brick', 'data-text': (it.title + ' ' + (it.detail || '')).toLowerCase() }, [
            el('div', { class: 'b-title' }, [it.title]),
            it.detail ? el('div', { class: 'b-detail' }, [it.detail]) : null,
            it.section ? el('div', { class: 'b-section' }, [it.section]) : null,
          ])
        ),
      ]);
    }))
  );
}

// ---- Decisions flip-cards ----
function renderDecisions(d) {
  const body = $('#decisions-body');
  body.replaceChildren();
  if (!d || (!d.decisions.length && !d.notes.length)) return body.append(emptyState('No decisions recorded yet.'));

  if (d.decisions.length) {
    body.append(
      el('div', { class: 'grid cols-3' }, d.decisions.map((dec) => {
        const flip = el('div', { class: 'flip', 'data-text': (dec.decision + ' ' + dec.choice + ' ' + dec.why).toLowerCase() }, [
          el('div', { class: 'flip-inner' }, [
            el('div', { class: 'flip-face flip-front' }, [
              el('div', { class: 'd-q' }, [dec.decision]),
              el('div', { class: 'd-hint' }, ['Click to see the call →']),
            ]),
            el('div', { class: 'flip-face flip-back' }, [
              el('div', { class: 'd-choice' }, [dec.choice]),
              el('div', { class: 'd-why' }, [dec.why]),
              el('div', { class: 'd-src' }, [dec.source]),
            ]),
          ]),
        ]);
        flip.addEventListener('click', () => flip.classList.toggle('flipped'));
        return flip;
      }))
    );
  }

  if (d.notes.length) {
    body.append(
      el('div', { class: 'notes' }, [
        el('h3', null, ['Decision notes from the build log']),
        ...d.notes.map((n) => {
          const span = el('span', null, [n.text]);
          makeEditable(span, n.text, 'decisions', 'note:' + n.context);
          return el('p', { class: 'note', 'data-text': (n.context + ' ' + n.text).toLowerCase() }, [
            el('b', null, [n.context + ' — ']),
            span,
          ]);
        }),
      ])
    );
  }
}

// ---- Learning: flashcards + in-dashboard SM-2 review ----
function todayStr() {
  return new Date().toISOString().slice(0, 10);
}
function button(label, onclick, cls) {
  const b = el('button', { type: 'button', class: 'btn ' + (cls || '') }, [label]);
  b.addEventListener('click', onclick);
  return b;
}

let learnCards = [];
let review = { queue: [], i: 0, showBack: false, active: false };

function renderLearning(l) {
  learnCards = (l && l.cards) || [];
  const body = $('#learning-body');
  body.replaceChildren();

  const due = learnCards.filter((c) => !c.due || c.due <= todayStr());
  body.append(
    el('div', { class: 'learn-head' }, [
      el('span', { class: 'due-count' }, [learnCards.length ? plural(due.length, 'card') + ' due today' : 'No cards yet']),
      due.length ? button('Review now ▶', () => startReview(due), 'accent') : null,
    ]),
    el('div', { id: 'review-panel', class: 'review-panel' }, [])
  );

  if (learnCards.length) {
    body.append(
      el('div', { class: 'env-group-title' }, ['All cards']),
      el('div', { class: 'grid cols-3' }, learnCards.map(cardTile))
    );
  }
  body.append(addCardForm());
  if (review.active) renderReviewPanel();
}

function cardTile(c) {
  const mastery = c.reps >= 3 ? 'strong' : c.reps >= 1 ? 'learning' : 'new';
  return el('div', { class: 'card tile', 'data-text': (c.front + ' ' + c.back).toLowerCase() }, [
    el('div', { class: 'tile-front' }, [c.front]),
    el('div', { class: 'tile-meta' }, [
      el('span', { class: 'badge ' + mastery }, [mastery]),
      el('span', { class: 'tile-due' }, ['due ' + (c.due || todayStr()) + ' · ' + plural(c.reps || 0, 'rep')]),
    ]),
  ]);
}

function startReview(due) {
  review = { queue: due.slice(), i: 0, showBack: false, active: true };
  renderReviewPanel();
  $('#review-panel').scrollIntoView({ block: 'nearest' });
}

function renderReviewPanel() {
  const panel = $('#review-panel');
  if (!panel) return;
  panel.replaceChildren();
  if (!review.active) return;

  if (review.i >= review.queue.length) {
    panel.append(el('div', { class: 'review-done' }, ['Review complete ✦ — ' + plural(review.queue.length, 'card') + ' reviewed']));
    review.active = false;
    return;
  }
  const c = review.queue[review.i];
  const face = el('div', { class: 'review-card' }, [
    el('div', { class: 'review-progress' }, [review.i + 1 + ' / ' + review.queue.length]),
    el('div', { class: 'rc-front' }, [c.front]),
  ]);
  if (!review.showBack) {
    face.append(button('Show answer', () => { review.showBack = true; renderReviewPanel(); }, 'wide'));
  } else {
    face.append(
      el('div', { class: 'rc-back' }, [c.back]),
      el('div', { class: 'grade-row' }, [
        button('Again', () => grade(c, 'again'), 'g-again'),
        button('Hard', () => grade(c, 'hard'), 'g-hard'),
        button('Good', () => grade(c, 'good'), 'g-good'),
        button('Easy', () => grade(c, 'easy'), 'g-easy'),
      ])
    );
  }
  panel.append(face);
}

async function grade(c, g) {
  try {
    const j = await fetch('/api/review', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: c.id, grade: g }),
    }).then((r) => r.json());
    if (j && j.ok) {
      const idx = learnCards.findIndex((x) => x.id === c.id);
      if (idx >= 0) learnCards[idx] = j.card;
    }
  } catch {
    /* keep advancing even if the write failed */
  }
  review.i += 1;
  review.showBack = false;
  renderReviewPanel();
}

function addCardForm() {
  const front = el('input', { class: 'fld', type: 'text', placeholder: 'Front (the prompt)' });
  const back = el('input', { class: 'fld', type: 'text', placeholder: 'Back (the answer)' });
  const add = button('Add card', async () => {
    if (!front.value.trim() || !back.value.trim()) return;
    const j = await fetch('/api/card', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ front: front.value.trim(), back: back.value.trim() }),
    }).then((r) => r.json()).catch(() => null);
    if (j && j.ok) {
      front.value = '';
      back.value = '';
      showToast('Card added');
      reloadLearning();
    }
  }, 'accent');
  return el('div', { class: 'add-card' }, [
    el('div', { class: 'env-group-title' }, ['Add a card']),
    el('div', { class: 'add-row' }, [front, back, add]),
  ]);
}

async function reloadLearning() {
  try {
    const data = await fetch('/api/data').then((r) => r.json());
    renderLearning(data.learning);
  } catch {
    /* leave current view */
  }
}

// ---- AI Operating Context / portability ----
const VERDICT = {
  'applies-in-cloud': '✅',
  'local-only': '⚠️',
  'local-only-machine-bound': '⚠️',
  'promoted': '✅',
};
const STATUS_LABEL = {
  'applies-in-cloud': 'portable · applies in cloud',
  'local-only': 'machine-local',
  'local-only-machine-bound': 'local-only · machine-bound',
  'promoted': 'promoted → now committed',
};

function renderEnvironment(e) {
  const sub = $('#environment-sub');
  const body = $('#environment-body');
  body.replaceChildren();
  if (!e) {
    sub.textContent = '';
    return body.append(emptyState('No AI config found.'));
  }
  const committedOnly = e.generatedTier === 'committed-only';
  sub.textContent = committedOnly
    ? 'Generated where ~/.claude was not visible (cloud / fresh clone) — machine-local items show their last-seen snapshot.'
    : 'Generated on the machine where your global ~/.claude is visible.';

  const tiers = [
    { tier: 'committed', label: 'Committed — travels with the repo' },
    { tier: 'machine-local', label: 'Machine-local — lives on your computer' },
  ];
  for (const t of tiers) {
    const items = e.items.filter((it) => it.tier === t.tier);
    if (!items.length) continue;
    body.append(el('div', { class: 'env-group-title' }, [t.label]));
    body.append(el('div', { class: 'card', style: 'padding:4px' }, items.map((it) => envRow(it, committedOnly))));
  }
}

function envRow(it, committedOnly) {
  let statusText = STATUS_LABEL[it.status] || it.status;
  // Append "· last seen <date>" to any local-only* status in a committed-only snapshot (§F.1).
  if (committedOnly && it.status.startsWith('local-only')) statusText += ' · last seen ' + it.lastSeen;

  const kids = [
    el('div', { class: 'env-name' }, [it.name]),
    el('div', { class: 'env-path' }, [it.sourcePath]),
    el('div', { class: 'env-status ' + it.status }, [statusText]),
  ];
  if (it.promoteHint && it.status !== 'promoted') kids.push(el('div', { class: 'env-hint' }, ['↳ ' + it.promoteHint]));

  // A Promote action where it makes sense: not for machine-bound/promoted/committed
  // items, and only enabled when machine-local is live (cloud can't see ~/.claude).
  const promotable = it.promoteHint && !it.machineBound && it.status !== 'promoted' && it.tier === 'machine-local';
  let action = null;
  if (promotable) {
    if (committedOnly) {
      action = el('button', { type: 'button', class: 'btn promote', disabled: 'true', title: 'Run the atlas locally — the cloud cannot see ~/.claude' }, ['Promote']);
    } else {
      action = button('Promote', () => doPromote(it.id), 'promote');
    }
  }

  return el('div', { class: 'env-item', 'data-text': (it.name + ' ' + statusText).toLowerCase() }, [
    el('div', { class: 'env-verdict' }, [VERDICT[it.status] || '•']),
    el('div', { class: 'env-main' }, kids),
    action,
  ]);
}

async function doPromote(id) {
  const j = await fetch('/api/promote/' + encodeURIComponent(id), { method: 'POST' })
    .then((r) => r.json())
    .catch(() => null);
  if (j) showToast(j.message);
  // Refresh the environment layer so a freshly-promoted item flips to ✅.
  try {
    const data = await fetch('/api/data').then((r) => r.json());
    renderEnvironment(data.environment);
  } catch {
    /* leave current view */
  }
}

// ---- edit-in-place: edits become proposals, never touch canonical docs ----
async function postPending(payload) {
  try {
    const r = await fetch('/api/pending', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    return await r.json();
  } catch {
    return null;
  }
}

function makeEditable(node, originalString, layer, field) {
  node.setAttribute('contenteditable', 'true');
  node.setAttribute('spellcheck', 'false');
  node.classList.add('editable');
  let original = originalString;
  node.addEventListener('blur', async () => {
    const text = (node.textContent || '').trim();
    if (!text || text === (original || '').trim()) return;
    const j = await postPending({ layer, field, original, text });
    if (j && j.ok) {
      original = text;
      showToast(plural(j.count, 'proposal') + ' pending — Claude folds these into the docs');
    }
  });
  return node;
}

let toastTimer = null;
function showToast(msg) {
  let t = $('#toast');
  if (!t) {
    t = el('div', { id: 'toast', class: 'toast' }, []);
    document.body.append(t);
  }
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 2600);
}

// ---- shared ----
function card(kids) {
  return el('div', { class: 'card' }, kids);
}
function emptyState(msg) {
  return el('p', { class: 'empty' }, [msg]);
}
function escapeHtml(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

// ---- search / filter ----
function setupSearch() {
  const input = $('#search');
  if (!input) return;
  input.addEventListener('input', () => {
    const q = input.value.trim().toLowerCase();
    document.querySelectorAll('[data-text]').forEach((node) => {
      const hit = !q || node.getAttribute('data-text').includes(q);
      node.classList.toggle('hidden', !hit);
    });
  });
}

async function boot() {
  let data;
  try {
    data = await fetch('/api/data').then((r) => r.json());
  } catch (err) {
    $('#ribbon-inner').append(el('h1', null, ['Could not reach the atlas server.']));
    return;
  }
  renderRibbon(data.git, data.progress, data.branches);
  renderBranches(data.branches);
  renderVision(data.vision);
  renderProgress(data.progress);
  renderDecisions(data.decisions);
  renderLearning(data.learning);
  renderEnvironment(data.environment);
  setupSearch();
  $('#foot').textContent =
    'Project Atlas — a reflection of vision/, BRICKS.md, the specs, and .claude/. Refresh with `node .atlas/sync.js`.';
}

boot();
