create or replace function marketing.remove_waitlist_entry(
  p_email text,
  p_role text
)
returns boolean
language sql
security definer
set search_path = marketing
as $$
  update marketing.waitlist
  set removed_at = now()
  where email = p_email
    and role = p_role
    and removed_at is null
  returning true;
$$;

revoke all on function marketing.remove_waitlist_entry(text, text) from public;
grant execute on function marketing.remove_waitlist_entry(text, text) to anon;