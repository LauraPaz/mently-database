-- 0001_init.sql
-- Marketing waitlist schema — isolated from the app database's `app` schema.
-- Mirrors the shared Supabase project used by mently-app.

create schema if not exists marketing;

create table marketing.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  postal_code text not null,
  role text not null check (role in ('mentor', 'mentee')),
  referred_by text,
  created_at timestamptz not null default now(),
  removed_at timestamptz
);

alter table marketing.waitlist enable row level security;

-- Anon key can insert only. No select/update/delete policy exists for
-- anon, so those operations are blocked by default.
create policy "Allow anonymous insert"
  on marketing.waitlist
  for insert
  to anon
  with check (true);