-- 1. Deduplicate existing (email, role) pairs before the constraint can be added.
--    Keeps the oldest row per pair — check `created_at` exists on your table first;
--    if your column is named differently, adjust before running.
delete from marketing.waitlist a
using marketing.waitlist b
where a.email = b.email
  and a.role = b.role
  and a.created_at > b.created_at;

-- 2. One active row per (email, role) — allows separate mentor + mentee signups
alter table marketing.waitlist
  add constraint waitlist_email_role_key unique (email, role);

-- 3. Atomic insert-or-reactivate. Runs with elevated privilege internally;
--    callers (anon) only ever get back true/null, never row data.
--    true  = inserted, or reactivated after cooldown expired
--    null  = rejected (active duplicate, or still within cooldown)
create or replace function marketing.submit_waitlist_entry(
  p_email text,
  p_role text,
  p_country text,
  p_city text,
  p_field text,
  p_field_is_custom boolean
)
returns boolean
language sql
security definer
set search_path = marketing
as $$
  insert into marketing.waitlist (email, role, country, city, field, field_is_custom)
  values (p_email, p_role, p_country, p_city, p_field, p_field_is_custom)
  on conflict (email, role) do update
    set country = excluded.country,
        city = excluded.city,
        field = excluded.field,
        field_is_custom = excluded.field_is_custom,
        removed_at = null
    where marketing.waitlist.removed_at is not null
      and marketing.waitlist.removed_at < now() - interval '48 hours'
  returning true;
$$;

revoke all on function marketing.submit_waitlist_entry(text, text, text, text, text, boolean) from public;
grant execute on function marketing.submit_waitlist_entry(text, text, text, text, text, boolean) to anon;