# mently-database

Single source of truth for the Supabase project shared by `mently-app` and `mently-web`.

This repo owns schema, migrations, and the Supabase CLI link. It contains no
application code. If you're looking for the mobile app, see `mently-app`. If
you're looking for the marketing site, see `mently-web`.

---

## Why this repo exists

`mently-app` and `mently-web` are two independently-deployed codebases
(different release cycles, different frameworks) that intentionally share one
Postgres database — because a waitlist signup in `marketing.waitlist` is
meant to eventually become a real row in `app.profiles` during onboarding.
Splitting into two separate Supabase projects would turn that into a
cross-database export/import step; keeping one project keeps that conversion
a single SQL statement (or eventually a function/trigger).

The problem: Supabase's CLI tracks migration history in one shared table
(`supabase_migrations.schema_migrations`) *per project*, not per repo. When
two repos both ran `supabase db push` against the same project, their
independently-numbered migrations collided and silently failed to apply.

The fix is organizational, not a CLI workaround: **exactly one repo owns
migrations for this project.** `mently-app` and `mently-web` never run
`supabase db push` or hold a CLI link — they only hold connection env vars
(`NEXT_PUBLIC_SUPABASE_URL`, anon key) and consume the database at runtime,
same as they'd consume any external API.

---

## Folder structure

```
mently-database/
│
├── README.md
│
├── supabase/
│   ├── config.toml            # exposed schemas, local dev config
│   ├── migrations/
│   │   ├── 20250201120000_init_app_schema.sql
│   │   ├── 20250312090000_add_onboarding_fields.sql
│   │   ├── 20260712194500_init_marketing_schema.sql
│   │   └── ...
│   └── seed.sql                # optional local dev seed data
│
├── types/
│   └── database.types.ts       # generated, see "Generated types" below
│
└── docs/
    └── schema-notes.md         # non-obvious schema decisions, gotchas
```

No app code, no `package.json` build step beyond what the Supabase CLI
needs. This repo should be readable by opening the `migrations/` folder
top to bottom.

---

## Conventions

- **Never hand-number migration files.** Always generate them with
  `supabase migration new <name>` so the filename is timestamp-based
  (`20260712194500_...`). Timestamp-based names can't collide; sequential
  `0001`, `0002` numbering can and did.
- **One schema per concern.** `app` for the mobile product (profiles,
  matches, sessions), `marketing` for the public site (waitlist). Never mix
  concerns inside one schema — it's what makes `Exposed schemas` and RLS
  policies reasoning stay simple.
- **Every table gets RLS enabled, plus explicit grants.** RLS controls which
  *rows* a role sees; Postgres grants control whether a role can reach the
  *table* at all. Both are required — a migration that adds a table should
  include both in the same file, not as a follow-up.
- **New schemas must be added in two places, not one:** `supabase/config.toml`
  (for local dev) *and* the dashboard's **Project Settings → Data API →
  Exposed schemas** (for the hosted project). `db push` succeeding does not
  guarantee the dashboard reflects it — always verify in the dashboard after
  pushing.
- **Reserved words:** avoid Postgres reserved words as column names (e.g.
  `current_role` → use `current_position` instead). Check before naming a
  new column.
- **Migrations are additive history, not editable.** Once a migration has
  been pushed to the shared remote project, don't edit the file — write a
  new migration that alters the previous state. Editing a pushed migration
  file makes local files and remote-applied SQL diverge invisibly.

---

## Key commands

```bash
# Link this repo to the shared Supabase project (one-time setup)
npx supabase link --project-ref <project-ref>

# Create a new migration (always use this, never hand-name a file)
npx supabase migration new <descriptive_name>

# Check local vs. remote migration state before pushing
npx supabase migration list

# Apply pending local migrations to the remote project
npx supabase db push

# Pull remote schema changes made outside this repo (dashboard SQL editor, etc.)
npx supabase db pull

# Start local Supabase stack for development
npx supabase start

# Generate TypeScript types from the current schema
npx supabase gen types typescript --linked > types/database.types.ts
```

---

## Generated types

`types/database.types.ts` is generated from the live schema, not hand-written.
Regenerate it after every migration that changes table shape:

```bash
npx supabase gen types typescript --linked > types/database.types.ts
```

Consuming repos (`mently-app`, `mently-web`) copy this file in as needed —
there's no automated sync yet. For `mently-web`, given it only touches the
small `marketing.waitlist` table, a hand-written interface may be simpler
than wiring up a copy step; use judgment per repo rather than forcing full
type generation everywhere.

Custom types that aren't derivable from the schema (e.g. app-level enums,
computed shapes) don't belong here — keep those in the consuming repo's own
`lib/types.ts`, same as `mently-app` already does.

---

## Adding a schema change

1. `npx supabase migration new <name>` in this repo.
2. Write the SQL: `create table`/`alter table`, `enable row level security`,
   the RLS policy, and the explicit `grant` statements — all in one file.
3. `npx supabase db push`.
4. `npx supabase migration list` — confirm the new version shows as applied
   on both Local and Remote.
5. If you added a new schema, add it to `supabase/config.toml`'s
   `[api] schemas` list, then check the dashboard's Exposed schemas setting
   to confirm it actually shows enabled — don't trust the push output alone.
6. Regenerate types if the change affects a consuming repo's queries.
7. If the change affects `mently-app` or `mently-web`'s runtime behavior,
   open a matching PR there once this migration is merged — the two repos
   should never get ahead of the schema they depend on.

---

## What doesn't belong here

- No frontend code, no UI, no app framework (React Native, Next.js, etc.).
- No secrets beyond what's needed to link the CLI locally (use `.env`,
  gitignored, never committed).
- No product/business logic — Postgres functions/triggers are fine if
  they're genuinely database-level concerns (e.g. `updated_at` timestamps),
  but anything resembling application logic belongs in the consuming repo.

**Exception — CLI-managed project infrastructure does belong here.** This
repo also owns anything deployed via the Supabase CLI against this specific
project, since it's tied to the same link as migrations, not to either
consuming app's codebase:

- `supabase/functions/` — Edge Functions (e.g. `delete-account`), deployed
  with `supabase functions deploy` and `supabase config push`.
- `supabase/templates/` — auth email templates (e.g. `otp.html`).

These aren't "application code" in the sense the rules above exclude — they
run inside Supabase's infrastructure, versioned and deployed the same way
migrations are, and neither `mently-app` nor `mently-web` invokes them
directly. If in doubt: if it's deployed with `supabase <command>` against
this project's link, it belongs here.