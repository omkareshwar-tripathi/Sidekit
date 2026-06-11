# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 2a. Brick-Led Approach & Sizing

**Build in bricks. A brick is one small, self-contained change: make it, review it, test it, verify it, then proceed to the next.**

The loop for every brick:

1. Make the smallest change that delivers one coherent piece of the goal.
2. Review the diff (own it — every line traces to the goal).
3. Test it (write/run tests proving the change works).
4. Verify it (confirm the expected behavior, not just that tests pass).
5. Only then move to the next brick.

**Brick size is not fixed — it scales with the project.** Early on, bricks are tiny (a couple of files, a handful of tests). As the project grows and changes touch more surface area, brick size grows with the scope of the change. Don't artificially shrink a brick to hit an old number, and don't bloat one to do more at once. Size the brick to the change in front of you, within these bounds:

- **Soft ceiling:** about **4 source files / ~80 source LOC / ~8 tests**. If a change naturally fits in that box, ship it as one brick — don't split for the sake of smallness.
- **Hard ceiling:** about **150 source LOC or more than 5 source files.** Past that, a single brick is too big to review and test reliably — split it.
- **Bundle peer-mirror changes.** When the same change must be applied to a near-identical sibling (e.g., one view model that mirrors another), do both in one brick rather than leaving the mirror half-done. Check for these siblings while scoping the brick.

This approach does NOT change: TDD discipline, surgical scope (section 3), and verify-before-done (section 4).

### 2b. Brick History & Session Handoff

**`BRICKS.md` is the handoff layer between sessions. Read it at the start of every session; update it at the end of every brick.**

A fresh session has no memory of past work — `BRICKS.md` is how it learns what's done and what's next. It is the first file to read when starting work.

The file has two sections:

- **Next up** — the planned/pending bricks, in order. The top item is what to work on now.
- **Done** — completed bricks, newest first. One entry per brick.

When you **finish a brick** (reviewed, tested, verified), before moving on:

1. Add a `Done` entry at the top with: brick number + title, date, what it does, files touched, how it was verified, and any notes a future session needs (decisions, gotchas, follow-ups).
2. Remove the brick you just finished from `Next up`, and add any new follow-up bricks the work revealed.

**Archiving (keep `BRICKS.md` small).** A fresh session reads this whole file, so don't let it bloat. Keep only the **3 most recent** `Done` entries in `BRICKS.md`. When `Done` grows past 3, move the oldest entries (verbatim) into `BRICKS-ARCHIVE.md` (append-only, newest-first, rarely read). The active file always shows: all pending bricks + the last 3 completed.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

### 5. Communication & Planning Style

**Explain like you're talking to a non-technical product manager.**

- Plain language first. Define jargon the first time you use it (one short phrase, not a paragraph).
- Lead with **what changes / why it matters / what the user sees**. Implementation detail second, and only when it changes a decision.
- A 3-sentence summary the PM can repeat back beats a 10-bullet technical brief.
- This applies to chat messages, design docs, brick plans, /simplify summaries, and STATUS.md updates — anywhere the user reads prose.

**Inject the applicable skill into every plan step.**

When writing a brick plan, a /simplify follow-up, or any multi-step task list, each step must name the skill(s) that apply on a dedicated `Skill:` line — e.g. `Skill: dotnet-best-practices`, `Skill: dotnet-xunit`, `Skill: run-tests`. If no skill applies, write `Skill: none` so the absence is intentional, not an oversight. Skills live in `.claude/skills/` (project) and `~/.claude/skills/` (user); the up-to-date list is surfaced by the UserPromptSubmit hook.

### 6. Skills for this project

The installed skills below are the ones suited to Sidekit (a **C# / .NET Windows desktop** app). Use them per §5 — name the relevant one on each plan step's `Skill:` line.

**Domain (C#/.NET) — use these for the actual app:**

- **`dotnet-best-practices`** — modern C#/.NET code quality. Use when writing or reviewing any production code.
- **`dotnet-xunit`** — writing xUnit tests (Fact/Theory, fixtures, async lifetime). Use for the test-first step of every brick (pairs with §2a TDD).
- **`run-tests`** — picks the correct `dotnet test` command/filter syntax for the project's test platform. Use for the test/verify step of every brick.

**Process (language-agnostic) — these enforce the discipline in §1–§4:**

- Superpowers skills (`brainstorming`, `test-driven-development`, `systematic-debugging`, `verification-before-completion`, `writing-plans` / `executing-plans`, `requesting-code-review` / `receiving-code-review`, `using-git-worktrees`, `finishing-a-development-branch`). Plus `grill-me` to stress-test a design before committing to it.

**Known gap — transcription/audio has NO suitable skill.** Every speech-to-text skill in the ecosystem is a cloud-API wrapper, which violates the §"fully on-device" constraint. There is no skill for running **Whisper locally in C#** (e.g. Whisper.NET / whisper.cpp) or for audio capture. For those bricks, write `Skill: none` and work against the library's own docs.
