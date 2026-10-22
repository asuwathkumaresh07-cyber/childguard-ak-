-- Add per-child time limits and parent approval workflows without replacing
-- existing family, filtering, or activity data.

create table if not exists public.app_time_limits (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  package_name text not null,
  app_label text not null default '',
  daily_limit_seconds integer not null check (daily_limit_seconds > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_id, package_name)
);

create index if not exists idx_app_time_limits_child
  on public.app_time_limits (child_id, package_name);

create table if not exists public.extra_time_requests (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  package_name text not null,
  app_label text not null default '',
  requested_minutes integer not null check (requested_minutes > 0),
  granted_minutes integer check (granted_minutes > 0),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'denied')),
  requested_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id) on delete set null
);

create index if not exists idx_extra_time_requests_family_pending
  on public.extra_time_requests (family_id, requested_at desc)
  where status = 'pending';

create table if not exists public.vpn_control_requests (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  requested_action text not null default 'disable'
    check (requested_action = 'disable'),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'denied')),
  requested_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id) on delete set null
);

create index if not exists idx_vpn_control_requests_family_pending
  on public.vpn_control_requests (family_id, requested_at desc)
  where status = 'pending';

alter table public.app_time_limits enable row level security;
alter table public.extra_time_requests enable row level security;
alter table public.vpn_control_requests enable row level security;
alter table public.vpn_control_requests
  add column if not exists applied_at timestamptz;

drop policy if exists app_time_limits_select on public.app_time_limits;
create policy app_time_limits_select on public.app_time_limits
  for select using (public.is_family_member(family_id));

drop policy if exists app_time_limits_insert on public.app_time_limits;
create policy app_time_limits_insert on public.app_time_limits
  for insert with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      join public.profiles p on p.id = fm.profile_id
      where fm.family_id = app_time_limits.family_id
        and fm.profile_id = app_time_limits.child_id
        and p.role = 'child'
    )
  );

drop policy if exists app_time_limits_update on public.app_time_limits;
create policy app_time_limits_update on public.app_time_limits
  for update using (public.is_family_owner(family_id))
  with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      join public.profiles p on p.id = fm.profile_id
      where fm.family_id = app_time_limits.family_id
        and fm.profile_id = app_time_limits.child_id
        and p.role = 'child'
    )
  );

drop policy if exists app_time_limits_delete on public.app_time_limits;
create policy app_time_limits_delete on public.app_time_limits
  for delete using (public.is_family_owner(family_id));

drop policy if exists extra_time_requests_select on public.extra_time_requests;
create policy extra_time_requests_select on public.extra_time_requests
  for select using (
    child_id = auth.uid() or public.is_family_owner(family_id)
  );

drop policy if exists extra_time_requests_insert on public.extra_time_requests;
create policy extra_time_requests_insert on public.extra_time_requests
  for insert with check (
    child_id = auth.uid()
    and public.is_family_member(family_id)
    and status = 'pending'
    and granted_minutes is null
    and resolved_at is null
    and resolved_by is null
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'child'
    )
  );

drop policy if exists extra_time_requests_parent_update
  on public.extra_time_requests;
create policy extra_time_requests_parent_update
  on public.extra_time_requests for update
  using (
    public.is_family_owner(family_id) and status = 'pending'
  )
  with check (
    public.is_family_owner(family_id)
    and status in ('approved', 'denied')
    and resolved_by = auth.uid()
  );

drop policy if exists vpn_control_requests_select on public.vpn_control_requests;
create policy vpn_control_requests_select on public.vpn_control_requests
  for select using (
    child_id = auth.uid() or public.is_family_owner(family_id)
  );

drop policy if exists vpn_control_requests_insert on public.vpn_control_requests;
create policy vpn_control_requests_insert on public.vpn_control_requests
  for insert with check (
    child_id = auth.uid()
    and public.is_family_member(family_id)
    and status = 'pending'
    and resolved_at is null
    and resolved_by is null
    and applied_at is null
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'child'
    )
  );

drop policy if exists vpn_control_requests_parent_update
  on public.vpn_control_requests;
create policy vpn_control_requests_parent_update
  on public.vpn_control_requests for update
  using (
    public.is_family_owner(family_id) and status = 'pending'
  )
  with check (
    public.is_family_owner(family_id)
    and status in ('approved', 'denied')
    and resolved_by = auth.uid()
  );

drop policy if exists vpn_control_requests_child_ack
  on public.vpn_control_requests;

create or replace function public.acknowledge_vpn_control_request(
  p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.vpn_control_requests
  set applied_at = now()
  where id = p_request_id
    and child_id = auth.uid()
    and status = 'approved'
    and applied_at is null;

  if not found then
    raise exception 'The approved protection request could not be acknowledged.';
  end if;
end;
$$;

revoke all on function public.acknowledge_vpn_control_request(uuid) from public;
grant execute on function public.acknowledge_vpn_control_request(uuid)
  to authenticated;

create or replace function public.add_default_adult_category()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.blocked_categories (family_id, category, created_by)
  values (new.id, 'adult', new.owner_id)
  on conflict (family_id, category) do nothing;
  return new;
end;
$$;

drop trigger if exists family_default_adult_category on public.families;
create trigger family_default_adult_category
  after insert on public.families
  for each row execute function public.add_default_adult_category();

insert into public.blocked_categories (family_id, category, created_by)
select f.id, 'adult', f.owner_id
from public.families f
on conflict (family_id, category) do nothing;

do $$
begin
  alter publication supabase_realtime add table public.app_time_limits;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.extra_time_requests;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.vpn_control_requests;
exception when duplicate_object then null;
end $$;
