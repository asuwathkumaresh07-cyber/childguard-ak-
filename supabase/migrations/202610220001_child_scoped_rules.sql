create table if not exists public.child_blocked_domains (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  domain text not null,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (family_id, child_id, domain)
);

create table if not exists public.child_blocked_apps (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  package_name text not null,
  app_label text not null default '',
  created_at timestamptz not null default now(),
  unique (family_id, child_id, package_name)
);

create table if not exists public.child_blocked_categories (
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  category text not null check (category in ('adult', 'social', 'gambling', 'games', 'streaming', 'violence')),
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (family_id, child_id, category)
);

create table if not exists public.child_app_category_overrides (
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  package_name text not null,
  category text not null check (
    category in ('educational', 'creative', 'social', 'entertainment', 'unproductive')
  ),
  updated_at timestamptz not null default now(),
  primary key (family_id, child_id, package_name)
);

create index if not exists idx_child_blocked_domains_child
  on public.child_blocked_domains (family_id, child_id);
create index if not exists idx_child_blocked_apps_child
  on public.child_blocked_apps (family_id, child_id);

alter table public.child_blocked_domains enable row level security;
alter table public.child_blocked_apps enable row level security;
alter table public.child_blocked_categories enable row level security;
alter table public.child_app_category_overrides enable row level security;

create policy child_blocked_domains_select on public.child_blocked_domains
  for select using (
    public.is_family_owner(family_id) or child_id = auth.uid()
  );
create policy child_blocked_domains_manage on public.child_blocked_domains
  for all using (public.is_family_owner(family_id))
  with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_blocked_domains.family_id
        and fm.profile_id = child_blocked_domains.child_id
    )
  );

create policy child_blocked_apps_select on public.child_blocked_apps
  for select using (
    public.is_family_owner(family_id) or child_id = auth.uid()
  );
create policy child_blocked_apps_manage on public.child_blocked_apps
  for all using (public.is_family_owner(family_id))
  with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_blocked_apps.family_id
        and fm.profile_id = child_blocked_apps.child_id
    )
  );

create policy child_blocked_categories_select on public.child_blocked_categories
  for select using (
    public.is_family_owner(family_id) or child_id = auth.uid()
  );
create policy child_blocked_categories_manage on public.child_blocked_categories
  for all using (public.is_family_owner(family_id))
  with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_blocked_categories.family_id
        and fm.profile_id = child_blocked_categories.child_id
    )
  );

create policy child_app_category_overrides_select
  on public.child_app_category_overrides
  for select using (
    public.is_family_owner(family_id) or child_id = auth.uid()
  );
create policy child_app_category_overrides_manage
  on public.child_app_category_overrides
  for all using (public.is_family_owner(family_id))
  with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_app_category_overrides.family_id
        and fm.profile_id = child_app_category_overrides.child_id
    )
  );

-- Realtime updates must include deleted rule rows so devices can remove blocks.
alter table public.child_blocked_domains replica identity full;
alter table public.child_blocked_apps replica identity full;
alter table public.child_blocked_categories replica identity full;
alter table public.child_app_category_overrides replica identity full;

do $$
declare rule_table text;
begin
  foreach rule_table in array array[
    'child_blocked_domains', 'child_blocked_apps',
    'child_blocked_categories', 'child_app_category_overrides'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = rule_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', rule_table);
    end if;
  end loop;
end;
$$;

-- Replace a child's category selection atomically, under the caller's RLS.
create or replace function public.set_child_blocked_categories(
  target_family_id uuid, target_child_id uuid, category_ids text[]
) returns void language plpgsql security invoker set search_path = public as $$
begin
  if not public.is_family_owner(target_family_id) or not exists (
    select 1 from public.family_members
    where family_id = target_family_id and profile_id = target_child_id
  ) then
    raise exception 'Child does not belong to this parent';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    target_family_id::text || ':' || target_child_id::text, 0
  ));
  delete from public.child_blocked_categories
    where family_id = target_family_id and child_id = target_child_id;
  insert into public.child_blocked_categories (family_id, child_id, category, created_by)
    select target_family_id, target_child_id, category, auth.uid()
    from (select distinct unnest(category_ids) as category) selection;
end;
$$;
revoke all on function public.set_child_blocked_categories(uuid, uuid, text[]) from public;
grant execute on function public.set_child_blocked_categories(uuid, uuid, text[]) to authenticated;
