# Supabase setup (one-time, ~20 min)

The backend for Sidekit's sign-up + feedback feature (spec:
`docs/superpowers/specs/2026-06-11-sidekit-signup-feedback-design.md`). One free project,
two tables, insert-only security. After this, the app's welcome sheet and feedback box
write straight into your dashboard.

## 1. Create the project

1. Sign up / log in at <https://supabase.com> (free tier).
2. **New project** → name it `sidekit` (any region near your users). Wait for it to provision.

## 2. Create the tables + lock them down

Dashboard → **SQL Editor** → paste and run:

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

## 3. Bake the keys into the app

Dashboard → **Project Settings → API**: copy the **Project URL** and the **anon public** key
into `mac/Sources/SidekitNet/SupabaseClient.swift`:

```swift
    private static let defaultURL = "https://YOURPROJECT.supabase.co"
    private static let defaultAnonKey = "eyJ…your anon key…"
```

(The anon key is public-by-design — row-level security above makes it insert-only.)
Rebuild: `cd mac && ./Scripts/build-app.sh release`.

## 4. Smoke test

```bash
cd mac
swift run SubmissionSelftest          # uses the baked-in values
```

Expect `signup: sent  feedback: sent`, exit 0, and one row in each table
(Dashboard → **Table Editor**). A second run shows `signup: sent` again (duplicate email
→ HTTP 409, treated as success) without adding a row.

## 5. Verify the key really is insert-only

```bash
curl "https://YOURPROJECT.supabase.co/rest/v1/signups?select=*" \
  -H "apikey: YOURANONKEY" -H "Authorization: Bearer YOURANONKEY"
```

Must return `[]` or a permission error — never rows. If you ever see rows, a select
policy snuck in; drop it.

## 6. Day-to-day

- **User list** = Table Editor → `signups` (CSV export button top-right).
- **Feedback inbox** = Table Editor → `feedback`, newest first via `created_at`.
- Reply to people from your own email; nothing in the app needs touching.
