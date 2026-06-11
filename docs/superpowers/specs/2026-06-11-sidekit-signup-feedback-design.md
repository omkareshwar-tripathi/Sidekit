# Sidekit for Mac — Sign-up (soft gate) + feedback channel

**Date:** 2026-06-11
**Status:** Design approved in brainstorm, pending spec review
**Scope:** Pre-ship user identity + communication. A skippable first-launch **welcome sheet** that
asks for an email (no password, no OAuth, no verification), and a **"Send Feedback…"** form for bug
reports / feature requests. Both submit to a free **Supabase** project (hosted Postgres + dashboard)
— the only network calls the app makes. Dictation and all existing features stay 100% on-device.

Builds on the existing ports-and-adapters split (`SidekitCore` pure + tested, `SidekitApp` adapters)
and the floating-pill design system (`DesignSystem.swift`).

---

## 1. Goal & non-goals

**Goal.** Before shipping, know *who* is using Sidekit and give users a built-in way to reach the
developer. Concretely: collect an email at first launch (politely, skippably), accept feedback from
inside the app, and land both in a dashboard the developer can read, query, and export — without
building or operating any auth system or server.

**Resolved product decisions (from the brainstorm, 2026-06-11):**

| # | Decision | Resolution |
|---|---|---|
| 1 | **Sign-up gate** | **Soft gate.** First-launch welcome sheet with email field + "Skip for now". If skipped, re-shown **once** at the 5th launch, then never again. Email field also lives in Settings. |
| 2 | **No OAuth / no auth** | "Sign in with Google" is **deliberately cut** — it is auth infrastructure. A plain email field, format-checked only. No verification, no password, no account object in the app. |
| 3 | **Backend** | **Supabase free tier.** Two tables (`signups`, `feedback`), written via the REST endpoint with the public **anon key**, locked to **insert-only** by row-level security. No server of our own. |
| 4 | **Comms back to users** | **Email list only.** Export emails from the Supabase dashboard; replies/updates go from the developer's own inbox. Nothing extra in the app (no announcements feed, no community link). |
| 5 | **Privacy posture** | These two endpoints are the **only** network calls in the app, both user-initiated and fully visible. The welcome sheet and feedback form say exactly what is sent. |

**Non-goals (v1).**
- No accounts, sessions, log-in state, or "Sign in with Google/Apple".
- No email verification or double-opt-in.
- No analytics/telemetry beyond the two explicit submissions (no usage pings, no crash reporting).
- No in-app announcements or update checker.
- No Windows parity yet (the C# app picks this up in its catch-up phase).

---

## 2. Sign-up UX (the welcome sheet)

A SwiftUI sheet over the main window on first launch (or its own small centered window if no main
window is open — Sidekit is menu-bar-centric): app icon, one-line product blurb, an email
field, one honest sentence of *why* ("so I can send you updates and help when something breaks —
nothing else, ever"), and two actions:

- **Continue** — enabled when the text plausibly looks like an email (single minimal check:
  `something@something.something`). Saves the email locally and queues a `signups` submission.
- **Skip for now** — closes the sheet, remembers the skip.

**Re-ask rule.** Track a launch counter. If the user skipped and has not since added an email, show
the sheet one more time on the **5th launch**, then never auto-show again. Two appearances max,
lifetime.

**Settings.** The settings panel gains a "Your email" field showing the stored email (editable).
Entering/changing an email there queues a `signups` submission the same way. Clearing it only clears
locally (no delete call — the developer prunes the table by hand if asked).

The sheet ends with one small fixed line: *"Sidekit runs fully on your Mac. This email — and
feedback you choose to send — are the only things that ever leave it."*

---

## 3. Feedback UX (the "Send Feedback…" form)

A **"Send Feedback…"** item in the menu-bar menu opens a small form (sheet over the main window, or
its own little window if the main window is closed):

- **Type** — segmented picker: `Bug` / `Feature request` / `Other`.
- **Message** — multiline text, required (non-empty after trimming), client-capped at 4 000 chars.
- **Email** — optional; pre-filled from the stored sign-up email, editable per-submission.
- **Auto-attached, shown in a footer line** — app version + macOS version
  (e.g. *"Will include: Sidekit 1.0 (12) · macOS 15.5"*). Nothing else is collected.

**Send** queues a `feedback` submission and closes with a brief "Thanks — sent!" (or "Saved — will
send when you're online", see §6). No screenshots, logs, or attachments in v1.

---

## 4. Backend: Supabase project (one-time setup)

One free Supabase project, two tables, REST inserts only.

```sql
create table signups (
  id          uuid primary key default gen_random_uuid(),
  email       text not null unique,
  app_version text,
  platform    text not null default 'mac',
  created_at  timestamptz not null default now()
);

create table feedback (
  id          uuid primary key default gen_random_uuid(),
  type        text not null check (type in ('bug','feature','other')),
  message     text not null check (char_length(message) <= 4000),
  email       text,
  app_version text,
  os_version  text,
  created_at  timestamptz not null default now()
);

alter table signups  enable row level security;
alter table feedback enable row level security;
create policy anon_insert_signups  on signups  for insert to anon with check (true);
create policy anon_insert_feedback on feedback for insert to anon with check (true);
-- No select/update/delete policies: the shipped anon key can only ever INSERT.
```

**Key safety.** The anon key ships inside the app and is treated as public. Because RLS grants
insert-only, an extracted key cannot read, list, or modify anything — worst case is spam rows,
acceptable at this scale. Inserts use `Prefer: return=minimal` so no select permission is needed.

**Duplicate sign-ups.** `email` is unique; a repeat submission returns HTTP 409, which the app
treats as success (the goal — "this email is on the list" — is already met).

**Config.** Project URL + anon key live in a small `SupabaseConfig` constant in `SidekitApp`
(checked in; the key is public-by-design). No secrets management needed.

---

## 5. Architecture (ports-and-adapters)

The pure core decides *what* to send and *when*; one adapter knows *how*. New pieces, following the
existing `SidekitCore` / `SidekitApp` split:

**Core (`SidekitCore`, fully unit-tested with fakes):**
- `IdentityState` — value type: stored email (optional), launch count, whether the welcome sheet was
  skipped / re-shown. Pure function `shouldShowWelcome()` encodes the soft-gate + 5th-launch rule.
- `IdentityStore` — owns `IdentityState`, persists via an `IdentityPersisting` port (JSON file under
  the app container, same pattern as `NotesStore`/`ShelfStore`).
- `RemoteSubmission` — enum: `.signup(email:appVersion:)` or
  `.feedback(type:message:email:appVersion:osVersion:)`, each rendering its own JSON payload + target
  table. Email format check and feedback validation (non-empty, ≤4 000 chars) live here.
- `SubmissionSpool` — a tiny persistent outbox. `enqueue(_:)` saves then tries to send via a
  `SubmissionSending` port; failures stay queued; `retryAll()` runs at every launch. Capped at 50
  pending entries (oldest dropped) so it can never grow unbounded. Persisted via a
  `SubmissionPersisting` port (JSON, same pattern).

**Adapters (`SidekitApp`):**
- `SupabaseSubmissionSender: SubmissionSending` — the app's first and only network adapter. One
  `URLSession` POST to `{projectURL}/rest/v1/{table}` with `apikey` / `Authorization: Bearer` headers
  and `Prefer: return=minimal`. 2xx → sent; 409 on `signups` → sent; anything else / no network →
  "keep queued". ~10 s timeout.
- JSON persistence adapters for identity + spool (mirroring `JSONShelfStore` / `JSONHistoryStore`).

**UI (`SidekitApp`):** `WelcomeSheet`, `FeedbackView`, the menu item, and the Settings email field —
all thin, calling into `IdentityStore` / `SubmissionSpool`.

---

## 6. Error handling & offline behavior

- **Offline / request fails:** the submission is already in the spool — UI says
  *"Saved — will send when you're online"*; the spool retries on next launch. No spinners, no
  blocking, no error dialogs for network problems.
- **Validation fails:** inline (Continue/Send disabled + short hint). Never sends invalid payloads.
- **Supabase rejects (4xx other than 409):** drop the entry after 3 attempts (a poison payload must
  not clog the spool); log to `Diag`.
- The dictation pipeline is completely untouched by any of this — a broken backend can never affect
  core functionality.

---

## 7. Testing

- **Core unit tests (fakes, existing pattern):** soft-gate rule (first launch / skip / 5th-launch
  re-ask / never again), email + feedback validation, payload JSON rendering, spool enqueue → send →
  remove, spool retry-on-launch, 409-as-success, 3-strikes drop, 50-entry cap.
- **Adapter:** manual verification against the real Supabase project (insert lands in dashboard),
  plus a `curl` smoke test documented in the setup notes.
- **Manual pass:** new `M9` item in `TESTING.md` — fresh-container first launch shows sheet; skip →
  no sheet until 5th launch; sign up → row appears in dashboard; send feedback offline → queued →
  appears after relaunch online; verify anon key cannot `select` (curl returns error).

## 8. What the developer does once (~20 min, walked through)

1. Create the free Supabase account + project.
2. Paste the §4 SQL into the SQL editor (tables + RLS).
3. Hand the project URL + anon key over for `SupabaseConfig`.
4. Bookmark the two table views — that's the user list and the feedback inbox. Export = CSV button.
