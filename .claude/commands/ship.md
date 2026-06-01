---
description: "Autonomously ship the next N bricks (default 1): pick brick → lock a plan (recommended options, no grilling) → sub-agent implements → loop test+simplify+review until clean → commit & push. Usage: /ship [N=1]"
argument-hint: "[N=1]"
---

Ship the next **${1:-1}** brick(s) from `BRICKS.md`, fully autonomously, one brick at a time in a single loop. This command is **explicit authorization to commit and push** for the bricks it ships.

## Operating principles (non-negotiable)
- Obey `CLAUDE.md` throughout: brick-led (§2a), surgical scope (§3), TDD, verify-before-done (§4), plain-language summaries (§5).
- **Pick recommended options yourself — do NOT grill the user.** Every design decision should be resolved from `SpeakType-v1-spec.md` (it has a fully resolved "Resolved Decisions" appendix) and sensible defaults. Only **HALT** (see below) if you hit a genuinely blocking ambiguity with no answer in the spec — never guess on something irreversible.
- Use **sub-agents (Agent tool)** for the implementation work so the orchestrator's context stays lean. The orchestrator (you) owns planning, the verify loop, docs, and git.
- One brick = one logical unit = its own commit(s) + push. Never work ahead of the current brick.

## Pre-flight gates (run once, before brick 1 — HALT + report on any failure, no auto-fix)
1. **Git repo exists.** If `.git` is absent → HALT: "Run `git init` + create a GitHub remote first (Git is the bridge to the Windows laptop/CI)."
2. **Clean tree:** `git status --porcelain` is empty.
3. **On `main`.** (This command commits to `main` by design — that's the brick-by-brick trunk the Windows laptop/CI pulls from.)
4. **A brick is queued:** `BRICKS.md` "Next up" has at least one unchecked `- [ ]` item. The top one is the current brick.
5. **Baseline green:** `dotnet test` passes for the cross-platform projects (`SpeakType.Core` + `SpeakType.Tests`). If the solution doesn't exist yet, the current brick must be Brick 0 (scaffold) — skip this gate for Brick 0 only.

## Per-brick loop (repeat ${1:-1} times, sequential)

### Phase A — Plan (orchestrator; Skill: brainstorming, writing-plans)
- Read the current brick in `BRICKS.md` + the matching `SpeakType-v1-spec.md` section + its `TESTING.md` M# items.
- Lock a concrete plan: the exact files to add/edit, the tests to write first (TDD), and the acceptance check. Resolve every option from the spec's decisions appendix.
- **Peer-mirror check (§2a):** if a near-identical sibling exists (e.g. a second adapter mirroring one you're touching), include it in this brick.
- **Platform routing — decide where this brick can be verified:**
  - **Cross-platform brick** (work lives in `SpeakType.Core` and/or `SpeakType.Tests`, TFM `net8.0`): the full loop runs **locally on this Mac**.
  - **Windows-only brick** (work lives in `SpeakType.App`, TFM `net8.0-windows` — hotkey hook, NAudio, WinForms, clipboard, tray): **this Mac cannot build or test it.** Implement + write any Core-side tests, then rely on CI:
    - If the GitHub Actions `windows-latest` workflow exists (Brick 0b): commit, push, and **poll the Actions run** (`gh run watch` / `gh run list`); treat a green x64 CI run as the verify step, fix-and-repush on red.
    - If CI does **not** exist yet: implement + commit + push, then **HALT** for this brick with: "Windows-only brick — verify on the Windows Intel laptop (`git pull`, `dotnet test`, run manual M# items) or add Brick 0b CI first."

### Phase B — Implement (sub-agent; Skill: dotnet-best-practices, dotnet-xunit)
- Dispatch a sub-agent (Agent tool, general-purpose) with the locked plan. Instruct it: **tests first**, then the minimum code to pass them; match existing style; touch only what the plan names (§3); behind the port interfaces where applicable.
- The sub-agent returns the diff summary. The orchestrator owns verification — never trust "done" without running it.

### Phase C — Verify loop (orchestrator; Skill: run-tests) — loop until clean, max 4 rounds
Repeat until all three pass (or hit the round cap → HALT + report):
1. **Test:** `dotnet test` (cross-platform brick) or the CI run (Windows-only brick). On failure → dispatch a fix sub-agent with the failing output, then re-test.
2. **Simplify:** run `/simplify` on the brick's diff (quality-only cleanup). Re-run `dotnet test` after.
3. **Code review:** run `/code-review` on the diff. Triage findings: fix every **must-fix / correctness** finding (dispatch a sub-agent if non-trivial), re-test. Note (don't necessarily fix) nice-to-haves.
- The loop is "done" when: tests green **and** `/simplify` yields no further changes **and** `/code-review` reports no must-fix findings.

### Phase D — Docs (orchestrator; Skill: none)
- Update `BRICKS.md`: add the `Done` entry (what / files / **Verified** with the M# items or CI run / notes), remove the finished item from `Next up`, add any follow-up bricks the work revealed.
- **Archive** if `Done` now exceeds 3 entries: move the oldest verbatim to `BRICKS-ARCHIVE.md` (§2b).
- Update `TESTING.md` if tests/M# steps changed; update the spec's stack section if build/deps changed.

### Phase E — Commit & push (orchestrator)
- Stage and commit with **Conventional Commits** (this also satisfies the `check-bricks-updated` Stop hook). Reasonable split: a `feat`/`test` commit for the code, a `docs(bricks): mark brick-NN done` commit for the handoff update. End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- `git push`. (Per-brick push lets the Windows laptop/CI pick up each brick immediately.)
- If `run_in_background` CI was used, confirm the pushed commit's run is green before moving on.

### Brick boundary
- Emit a one-line status: `Brick NN shipped — n/${1:-1} — proceeding` (or the HALT reason). Then start the next brick from a clean tree.

## HALT conditions (stop the whole run, report, do NOT auto-recover)
- Any pre-flight gate fails.
- The verify loop hits its round cap with tests red or an unresolved must-fix review finding.
- A blocking design ambiguity with no answer in the spec (don't guess).
- A Windows-only brick with no CI to verify it (implement + push, then halt for the laptop).
- Tree-state mismatch (expected-clean tree is dirty, wrong commit count, etc.).
- Any destructive/irreversible operation would be needed — never do these without asking.

## Hard rules
- Never `git push --force`, amend pushed commits, or use `--no-verify`.
- Never delete or overwrite files you didn't create as part of the brick.
- Never skip the test or review phase to "save time" — the loop *is* the point.
- If all N land clean with zero must-fix, you may optionally offer to continue to N+1, but do not auto-continue past the requested N.

## Final report (after the run)
Plain-language summary (§5): which bricks shipped, what each does/what the user sees, how each was verified (local `dotnet test` vs CI vs deferred-to-laptop), any follow-up bricks added, and anything that HALTED.
