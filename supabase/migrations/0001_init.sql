-- Create a dedicated schema for all application tables.
-- Avoids the open-by-default permissions of the public schema.
create schema if not exists app;

-- Grant usage to the roles Supabase uses for client and auth operations.
grant usage on schema app to anon, authenticated, service_role;

-- Automatically grant access to future tables created in this schema.
alter default privileges in schema app
  grant all on tables to anon, authenticated, service_role;

-- Profiles table: one row per user, created by the auth trigger below
-- the moment their auth.users row exists.
-- Fields mirror the onboarding screens 1:1 (see app/onboarding/{mentee,mentor}).
create table if not exists app.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('mentee', 'mentor')),

  -- Step 1: profile.tsx
  full_name text not null,
  current_position text not null,
  field_of_study text not null,

  -- Step 2: credentials.tsx
  institution text not null,
  education text not null,

  -- Step 3: interests.tsx
  interests text[] not null default '{}',

  -- Step 4: drives.tsx (mentee) / offer.tsx (mentor)
  career_goals text,
  ideal_mentor text,
  current_challenge text,
  offer_areas text[],
  offer_reflection text,

  -- Step 5: availability.tsx
  meeting_frequency text,
  meeting_mode text,
  meeting_duration text,

  -- Shared prefs.tsx
  mentorship_type text,

  -- Tracks which onboarding step the user is currently on
  onboarding_step text not null default 'profile',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Row Level Security: a user can only ever see and edit their own profile.
alter table app.profiles enable row level security;

-- create policy has no IF NOT EXISTS / OR REPLACE in Postgres — drop first.
drop policy if exists "Users can view their own profile" on app.profiles;
create policy "Users can view their own profile"
  on app.profiles for select
  using (auth.uid() = id);

drop policy if exists "Users can update their own profile" on app.profiles;
create policy "Users can update their own profile"
  on app.profiles for update
  using (auth.uid() = id);

-- No insert policy: rows are created only by handle_new_user() below,
-- which runs as security definer and bypasses RLS. Client never inserts directly.

-- Keep updated_at accurate on every edit.
create or replace function app.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists profiles_set_updated_at on app.profiles;
create trigger profiles_set_updated_at
  before update on app.profiles
  for each row
  execute function app.set_updated_at();

-- Auto-create a profile the moment a new auth user exists, so client-side
-- code never has to race email confirmation to insert a row.
create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = app
as $$
begin
  insert into app.profiles (id, role, full_name, current_position, field_of_study, institution, education)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'mentee'),
    '', '', '', '', ''
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();