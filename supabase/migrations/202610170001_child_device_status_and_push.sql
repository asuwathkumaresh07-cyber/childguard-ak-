create table if not exists public.child_device_status (
  child_id uuid primary key references public.profiles (id) on delete cascade,
  family_id uuid not null references public.families (id) on delete cascade,
  vpn_enabled boolean not null,
  usage_access_enabled boolean not null,
  accessibility_enabled boolean not null,
  last_seen_at timestamptz not null default now()
);

create table if not exists public.child_tamper_events (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles (id) on delete cascade,
  family_id uuid not null references public.families (id) on delete cascade,
  event_type text not null check (
    event_type in (
      'vpn_disabled',
      'usage_access_revoked',
      'accessibility_disabled'
    )
  ),
  occurred_at timestamptz not null default now()
);

create index if not exists idx_child_tamper_events_family_time
  on public.child_tamper_events (family_id, occurred_at desc);

create table if not exists public.parent_push_tokens (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.profiles (id) on delete cascade,
  token text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.child_protection_modes (
  child_id uuid primary key references public.profiles (id) on delete cascade,
  family_id uuid not null references public.families (id) on delete cascade,
  mode text not null default 'strict' check (mode in ('strict', 'friendly')),
  updated_at timestamptz not null default now()
);

alter table public.child_device_status enable row level security;
alter table public.child_tamper_events enable row level security;
alter table public.parent_push_tokens enable row level security;
alter table public.child_protection_modes enable row level security;

drop policy if exists child_protection_modes_select
  on public.child_protection_modes;
create policy child_protection_modes_select on public.child_protection_modes
  for select using (
    child_id = auth.uid() or public.is_family_owner(family_id)
  );

drop policy if exists child_protection_modes_insert
  on public.child_protection_modes;
create policy child_protection_modes_insert on public.child_protection_modes
  for insert with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      join public.profiles p on p.id = fm.profile_id
      where fm.family_id = child_protection_modes.family_id
        and fm.profile_id = child_protection_modes.child_id
        and p.role = 'child'
    )
  );

drop policy if exists child_protection_modes_update
  on public.child_protection_modes;
create policy child_protection_modes_update on public.child_protection_modes
  for update using (public.is_family_owner(family_id))
  with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      join public.profiles p on p.id = fm.profile_id
      where fm.family_id = child_protection_modes.family_id
        and fm.profile_id = child_protection_modes.child_id
        and p.role = 'child'
    )
  );

drop policy if exists child_device_status_parent_select
  on public.child_device_status;
create policy child_device_status_parent_select
  on public.child_device_status for select
  using (public.is_family_owner(family_id));

drop policy if exists child_tamper_events_parent_select
  on public.child_tamper_events;
create policy child_tamper_events_parent_select
  on public.child_tamper_events for select
  using (public.is_family_owner(family_id));

drop policy if exists parent_push_tokens_select on public.parent_push_tokens;
create policy parent_push_tokens_select on public.parent_push_tokens
  for select using (
    parent_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'parent'
    )
  );

drop policy if exists parent_push_tokens_insert on public.parent_push_tokens;
create policy parent_push_tokens_insert on public.parent_push_tokens
  for insert with check (
    parent_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'parent'
    )
  );

drop policy if exists parent_push_tokens_update on public.parent_push_tokens;
create policy parent_push_tokens_update on public.parent_push_tokens
  for update using (
    parent_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'parent'
    )
  )
  with check (
    parent_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'parent'
    )
  );

drop policy if exists parent_push_tokens_delete on public.parent_push_tokens;
create policy parent_push_tokens_delete on public.parent_push_tokens
  for delete using (
    parent_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'parent'
    )
  );

revoke all on table public.child_device_status
  from public, anon, authenticated;
revoke all on table public.child_tamper_events
  from public, anon, authenticated;
grant select on table public.child_device_status,
  public.child_tamper_events to authenticated;
grant select, insert, update on table public.child_protection_modes
  to authenticated;
grant select, insert, update, delete on table public.parent_push_tokens
  to authenticated;

create or replace function public.report_child_device_status(
  p_vpn_enabled boolean,
  p_usage_access_enabled boolean,
  p_accessibility_enabled boolean
)
returns table (event_id uuid, event_type text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_family_id uuid;
  v_previous public.child_device_status%rowtype;
  v_has_previous boolean := false;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles
    where id = v_uid and role = 'child'
  ) then
    raise exception 'Only a signed-in child can report device status.';
  end if;

  select fm.family_id into v_family_id
  from public.family_members fm
  where fm.profile_id = v_uid
  limit 1;

  if v_family_id is null then
    raise exception 'Link the child device to a parent family first.';
  end if;

  select * into v_previous
  from public.child_device_status
  where child_id = v_uid
  for update;
  v_has_previous := found;

  insert into public.child_device_status (
    child_id,
    family_id,
    vpn_enabled,
    usage_access_enabled,
    accessibility_enabled,
    last_seen_at
  )
  values (
    v_uid,
    v_family_id,
    p_vpn_enabled,
    p_usage_access_enabled,
    p_accessibility_enabled,
    now()
  )
  on conflict (child_id) do update set
    family_id = excluded.family_id,
    vpn_enabled = excluded.vpn_enabled,
    usage_access_enabled = excluded.usage_access_enabled,
    accessibility_enabled = excluded.accessibility_enabled,
    last_seen_at = excluded.last_seen_at;

  if not v_has_previous then
    return;
  end if;

  if v_previous.vpn_enabled and not p_vpn_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (v_uid, v_family_id, 'vpn_disabled')
      returning id, child_tamper_events.event_type;
  end if;

  if v_previous.usage_access_enabled and not p_usage_access_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (v_uid, v_family_id, 'usage_access_revoked')
      returning id, child_tamper_events.event_type;
  end if;

  if v_previous.accessibility_enabled and not p_accessibility_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (v_uid, v_family_id, 'accessibility_disabled')
      returning id, child_tamper_events.event_type;
  end if;
end;
$$;

create or replace function public.register_parent_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1 from public.profiles
    where id = v_uid and role = 'parent'
  ) then
    raise exception 'Only a signed-in parent can register push notifications.';
  end if;
  if p_token is null or length(trim(p_token)) < 20 then
    raise exception 'The push token is invalid.';
  end if;

  insert into public.parent_push_tokens (parent_id, token, updated_at)
  values (v_uid, trim(p_token), now())
  on conflict (token) do update set
    parent_id = excluded.parent_id,
    updated_at = excluded.updated_at;
end;
$$;

create or replace function public.remove_parent_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
    select 1 from public.profiles
    where id = v_uid and role = 'parent'
  ) then
    raise exception 'Only a signed-in parent can remove push notifications.';
  end if;
  delete from public.parent_push_tokens
  where parent_id = v_uid and token = p_token;
end;
$$;

revoke all on function public.report_child_device_status(boolean, boolean, boolean)
  from public;
revoke all on function public.register_parent_push_token(text) from public;
revoke all on function public.remove_parent_push_token(text) from public;
grant execute on function public.report_child_device_status(boolean, boolean, boolean)
  to authenticated;
grant execute on function public.register_parent_push_token(text)
  to authenticated;
grant execute on function public.remove_parent_push_token(text)
  to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.child_device_status;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.child_tamper_events;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.child_protection_modes;
exception when duplicate_object then null;
end $$;
