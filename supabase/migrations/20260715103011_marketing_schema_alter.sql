alter table marketing.waitlist
  drop column postal_code,
  add column country text,
  add column city text;