create table if not exists public.protection_control_codes (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  requested_action text not null
    check (requested_action in ('enable', 'disable')),
  code text not null unique,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid references public.profiles (id) on delete set null
);

create index if not exists idx_protection_control_codes_child_expiry
  on public.protection_control_codes (child_id, expires_at desc)
  where used_at is null;

create table if not exists public.protection_control_code_attempts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles (id) on delete cascade,
  attempted_at timestamptz not null default now()
);

create index if not exists idx_protection_control_code_attempts_child_time
  on public.protection_control_code_attempts (child_id, attempted_at desc);

alter table public.protection_control_codes enable row level security;
alter table public.protection_control_code_attempts enable row level security;
revoke all on table public.protection_control_codes
  from public, anon, authenticated;
revoke all on table public.protection_control_code_attempts
  from public, anon, authenticated;

create or replace function public.create_protection_control_code(
  p_family_id uuid,
  p_child_id uuid,
  p_requested_action text
)
returns table (code text, requested_action text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_expires_at timestamptz := now() + interval '10 minutes';
begin
  if v_uid is null or not exists (
    select 1 from public.profiles
    where id = v_uid and role = 'parent'
  ) then
    raise exception 'Only a signed-in parent can generate protection codes.';
  end if;

  if p_requested_action not in ('enable', 'disable') then
    raise exception 'Invalid protection action.';
  end if;

  if not exists (
    select 1
    from public.families f
    join public.family_members fm on fm.family_id = f.id
    join public.profiles child on child.id = fm.profile_id
    where f.id = p_family_id
      and f.owner_id = v_uid
      and fm.profile_id = p_child_id
      and child.role = 'child'
  ) then
    raise exception 'The child is not linked to this parent family.';
  end if;

  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (
      select 1 from public.protection_control_codes existing
      where existing.code = v_code
    );
  end loop;

  insert into public.protection_control_codes (
    family_id, child_id, requested_action, code, created_by, expires_at
  )
  values (
    p_family_id, p_child_id, p_requested_action, v_code, v_uid, v_expires_at
  );

  return query select v_code, p_requested_action, v_expires_at;
end;
$$;

create or replace function public.redeem_protection_control_code(
  p_code text,
  p_requested_action text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_action text;
  v_attempt_count integer;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles
    where id = v_uid and role = 'child'
  ) then
    raise exception 'Only a signed-in child can redeem a protection code.';
  end if;

  if p_requested_action not in ('enable', 'disable') then
    raise exception 'Invalid protection action.';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_uid::text)::bigint);
  delete from public.protection_control_code_attempts
  where attempted_at < now() - interval '15 minutes';

  select count(*) into v_attempt_count
  from public.protection_control_code_attempts
  where child_id = v_uid
    and attempted_at > now() - interval '15 minutes';

  if v_attempt_count >= 5 then
    return 'rate_limited';
  end if;

  insert into public.protection_control_code_attempts (child_id)
  values (v_uid);

  update public.protection_control_codes code_row
  set used_at = now(), used_by = v_uid
  where code_row.code = upper(trim(p_code))
    and code_row.child_id = v_uid
    and code_row.requested_action = p_requested_action
    and code_row.used_at is null
    and code_row.expires_at > now()
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = code_row.family_id
        and fm.profile_id = v_uid
    )
  returning code_row.requested_action into v_action;

  if v_action is null then
    return 'invalid';
  end if;

  return v_action;
end;
$$;

revoke all on function public.create_protection_control_code(uuid, uuid, text)
  from public;
revoke all on function public.redeem_protection_control_code(text, text)
  from public;
grant execute on function public.create_protection_control_code(uuid, uuid, text)
  to authenticated;
grant execute on function public.redeem_protection_control_code(text, text)
  to authenticated;
