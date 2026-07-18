alter table marketing.waitlist
  add column field text,
  add column field_is_custom boolean not null default false;

alter table marketing.waitlist
  alter column field set not null;

alter table marketing.waitlist
  alter column country set not null;