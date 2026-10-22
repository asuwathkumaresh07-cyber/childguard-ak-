create table if not exists public.child_locations (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_meters double precision,
  recorded_at timestamptz not null default now()
);

create index if not exists idx_child_locations_child_time
  on public.child_locations (child_id, recorded_at desc);

create or replace function public.prune_child_location_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.child_locations
  where child_id = new.child_id
    and recorded_at < now() - interval '30 days';
  return new;
end;
$$;

drop trigger if exists child_location_retention on public.child_locations;
create trigger child_location_retention
  after insert on public.child_locations
  for each row execute function public.prune_child_location_history();

create table if not exists public.family_zones (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  name text not null,
  zone_type text not null check (zone_type in ('home', 'school', 'tuition', 'custom')),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  radius_meters integer not null default 200 check (radius_meters between 50 and 5000),
  created_at timestamptz not null default now(),
  unique (family_id, name)
);

create table if not exists public.zone_app_rules (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  zone_id uuid not null references public.family_zones (id) on delete cascade,
  package_name text not null,
  app_label text not null default '',
  created_at timestamptz not null default now(),
  unique (zone_id, package_name)
);

create table if not exists public.zone_events (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  zone_id uuid not null references public.family_zones (id) on delete cascade,
  event_type text not null check (event_type in ('entered', 'exited', 'off_task_app')),
  package_name text,
  occurred_at timestamptz not null default now()
);

create index if not exists idx_zone_events_family_time
  on public.zone_events (family_id, occurred_at desc);

create table if not exists public.child_app_categories (
  family_id uuid not null references public.families (id) on delete cascade,
  package_name text not null,
  category text not null check (
    category in ('productivity', 'education', 'communication', 'entertainment', 'other')
  ),
  updated_at timestamptz not null default now(),
  primary key (family_id, package_name)
);

create table if not exists public.child_tasks (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text not null default '',
  due_at timestamptz,
  points integer not null default 10 check (points between 0 and 1000),
  status text not null default 'assigned' check (
    status in ('assigned', 'submitted', 'approved', 'rejected')
  ),
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles (id) on delete set null
);

create table if not exists public.task_submissions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.child_tasks (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  photo_path text not null,
  note text not null default '',
  submitted_at timestamptz not null default now(),
  unique (task_id)
);

create table if not exists public.child_mood_checkins (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  mood text not null check (mood in ('great', 'okay', 'low', 'stressed')),
  note text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.child_weekly_insights (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  week_start date not null,
  summary text not null,
  trust_score integer not null default 50 check (trust_score between 0 and 100),
  created_at timestamptz not null default now(),
  unique (child_id, week_start)
);

create table if not exists public.child_streaks (
  child_id uuid primary key references public.profiles (id) on delete cascade,
  family_id uuid not null references public.families (id) on delete cascade,
  current_streak integer not null default 0 check (current_streak >= 0),
  best_streak integer not null default 0 check (best_streak >= 0),
  total_points integer not null default 0 check (total_points >= 0),
  last_completed_on date
);

create table if not exists public.child_reward_ledger (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.profiles (id) on delete cascade,
  family_id uuid not null references public.families (id) on delete cascade,
  task_id uuid not null unique references public.child_tasks (id) on delete cascade,
  points_awarded integer not null check (points_awarded >= 0),
  streak_at_award integer not null check (streak_at_award >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.child_autonomy_settings (
  child_id uuid primary key references public.profiles (id) on delete cascade,
  family_id uuid not null references public.families (id) on delete cascade,
  enabled boolean not null default false,
  min_trust_score integer not null default 80
    check (min_trust_score between 0 and 100),
  daily_extra_minutes_cap integer not null default 15
    check (daily_extra_minutes_cap between 1 and 120),
  updated_at timestamptz not null default now()
);

alter table public.child_autonomy_settings enable row level security;
drop policy if exists child_autonomy_settings_parent_select
  on public.child_autonomy_settings;
create policy child_autonomy_settings_parent_select
  on public.child_autonomy_settings
  for select using (public.is_family_owner(family_id));
drop policy if exists child_autonomy_settings_parent_insert
  on public.child_autonomy_settings;
create policy child_autonomy_settings_parent_insert
  on public.child_autonomy_settings
  for insert with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_autonomy_settings.family_id
        and fm.profile_id = child_autonomy_settings.child_id
    )
  );
drop policy if exists child_autonomy_settings_parent_update
  on public.child_autonomy_settings;
create policy child_autonomy_settings_parent_update
  on public.child_autonomy_settings
  for update using (public.is_family_owner(family_id))
  with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_autonomy_settings.family_id
        and fm.profile_id = child_autonomy_settings.child_id
    )
  );

grant select, insert, update on public.child_autonomy_settings to authenticated;

create or replace function public.create_child_extra_time_request(
  p_family_id uuid,
  p_package_name text,
  p_app_label text,
  p_requested_minutes integer
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_enabled boolean := false;
  v_min_score integer := 80;
  v_daily_cap integer := 15;
  v_score integer := 0;
  v_used_today integer := 0;
  v_granted integer := 0;
  v_request_count integer;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles
    where id = v_uid and role = 'child'
  ) then
    raise exception 'Only a signed-in child can request extra time.';
  end if;
  if p_requested_minutes < 1 or p_requested_minutes > 120 then
    raise exception 'Request between 1 and 120 minutes.';
  end if;
  if nullif(trim(p_package_name), '') is null then
    raise exception 'An app package name is required.';
  end if;
  if not exists (
    select 1 from public.family_members
    where family_id = p_family_id and profile_id = v_uid
  ) then
    raise exception 'The child is not linked to this family.';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_uid::text)::bigint);
  select count(*) into v_request_count
  from public.extra_time_requests
  where child_id = v_uid
    and requested_at >= date_trunc('day', now());
  if v_request_count >= 10 then
    raise exception 'Daily extra-time request limit reached.';
  end if;

  select enabled, min_trust_score, daily_extra_minutes_cap
  into v_enabled, v_min_score, v_daily_cap
  from public.child_autonomy_settings
  where child_id = v_uid and family_id = p_family_id;

  if coalesce(v_enabled, false) then
    select trust_score into v_score
    from public.child_weekly_insights
    where child_id = v_uid and family_id = p_family_id
      and week_start = date_trunc('week', current_date)::date;

    if coalesce(v_score, 0) >= coalesce(v_min_score, 80) then
      select coalesce(sum(granted_minutes), 0)
      into v_used_today
      from public.extra_time_requests
      where child_id = v_uid
        and family_id = p_family_id
        and status = 'approved'
        and resolved_at >= date_trunc('day', now());
      v_granted := least(
        p_requested_minutes,
        greatest(coalesce(v_daily_cap, 15) - v_used_today, 0)
      );
    end if;
  end if;

  insert into public.extra_time_requests (
    family_id, child_id, package_name, app_label, requested_minutes,
    granted_minutes, status, resolved_at
  )
  values (
    p_family_id,
    v_uid,
    trim(p_package_name),
    coalesce(trim(p_app_label), ''),
    p_requested_minutes,
    nullif(v_granted, 0),
    case when v_granted > 0 then 'approved' else 'pending' end,
    case when v_granted > 0 then now() else null end
  );

  return case when v_granted > 0 then 'approved' else 'pending' end;
end;
$$;

revoke all on function public.create_child_extra_time_request(
  uuid, text, text, integer
) from public;
grant execute on function public.create_child_extra_time_request(
  uuid, text, text, integer
) to authenticated;

create or replace function public.award_approved_task_points()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_streak integer;
  v_last_date date;
  v_award integer;
begin
  if new.status <> 'approved' or old.status = 'approved' then
    return new;
  end if;

  select current_streak, last_completed_on
    into v_streak, v_last_date
  from public.child_streaks
  where child_id = new.child_id
  for update;

  if not found then
    v_streak := 1;
  elsif v_last_date = current_date then
    v_streak := greatest(v_streak, 1);
  elsif v_last_date = current_date - 1 then
    v_streak := v_streak + 1;
  else
    v_streak := 1;
  end if;

  v_award := new.points + floor(new.points * least(v_streak / 7, 2) * 0.25);

  insert into public.child_streaks (
    child_id, family_id, current_streak, best_streak, total_points,
    last_completed_on
  )
  values (
    new.child_id, new.family_id, v_streak, v_streak, v_award, current_date
  )
  on conflict (child_id) do update set
    current_streak = v_streak,
    best_streak = greatest(public.child_streaks.best_streak, v_streak),
    total_points = public.child_streaks.total_points + v_award,
    last_completed_on = current_date;

  insert into public.child_reward_ledger (
    child_id, family_id, task_id, points_awarded, streak_at_award
  )
  values (new.child_id, new.family_id, new.id, v_award, v_streak)
  on conflict (task_id) do nothing;

  return new;
end;
$$;

create or replace function public.mark_task_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.child_tasks
  set status = 'submitted'
  where id = new.task_id
    and child_id = new.child_id
    and status = 'assigned';
  if not found then
    raise exception 'This task is no longer available for submission.';
  end if;
  return new;
end;
$$;

drop trigger if exists task_submission_marked on public.task_submissions;
create trigger task_submission_marked
  after insert on public.task_submissions
  for each row execute function public.mark_task_submission();

create or replace function public.set_task_review_metadata()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status in ('approved', 'rejected') and new.status <> old.status then
    if old.status <> 'submitted' then
      raise exception 'Only a submitted task can be reviewed.';
    end if;
    new.reviewed_at := now();
    new.reviewed_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists child_task_review_metadata on public.child_tasks;
create trigger child_task_review_metadata
  before update of status on public.child_tasks
  for each row execute function public.set_task_review_metadata();

create or replace function public.generate_child_weekly_insight(
  p_family_id uuid,
  p_child_id uuid
)
returns public.child_weekly_insights
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_start date := date_trunc('week', current_date)::date;
  v_total_seconds bigint;
  v_focus_seconds bigint;
  v_task_total integer;
  v_task_approved integer;
  v_tamper_count integer;
  v_zone_off_task_count integer;
  v_score integer;
  v_summary text;
  v_result public.child_weekly_insights;
begin
  if auth.uid() is null or not public.is_family_owner(p_family_id) then
    raise exception 'Only this family parent can generate a child insight.';
  end if;
  if not exists (
    select 1 from public.family_members
    where family_id = p_family_id and profile_id = p_child_id
  ) then
    raise exception 'The child is not linked to this family.';
  end if;

  select
    coalesce(sum(greatest(coalesce(u.duration_seconds, 0), 0)), 0),
    coalesce(sum(
      case when c.category in ('productivity', 'education')
        then greatest(coalesce(u.duration_seconds, 0), 0)
        else 0 end
    ), 0)
  into v_total_seconds, v_focus_seconds
  from public.app_usage_logs u
  left join public.child_app_categories c
    on c.family_id = u.family_id and c.package_name = u.package_name
  where u.family_id = p_family_id
    and u.child_id = p_child_id
    and u.started_at >= v_week_start
    and u.started_at < v_week_start + 7;

  select count(*), count(*) filter (where status = 'approved')
  into v_task_total, v_task_approved
  from public.child_tasks
  where family_id = p_family_id
    and child_id = p_child_id
    and created_at >= v_week_start;

  select count(*) into v_tamper_count
  from public.child_tamper_events
  where family_id = p_family_id
    and child_id = p_child_id
    and occurred_at >= v_week_start;

  select count(*) into v_zone_off_task_count
  from public.zone_events
  where family_id = p_family_id
    and child_id = p_child_id
    and event_type = 'off_task_app'
    and occurred_at >= v_week_start;

  v_score := greatest(0, least(100,
    50
    + case when v_total_seconds > 0
        then round(30.0 * v_focus_seconds / v_total_seconds)::integer
        else 0 end
    + case when v_task_total > 0
        then round(20.0 * v_task_approved / v_task_total)::integer
        else 0 end
    - least(v_tamper_count * 10, 40)
    - least(v_zone_off_task_count * 5, 25)
  ));

  v_summary := format(
    'This week: %s of %s screen-time hours were in education or productivity apps; %s of %s assigned tasks were approved; %s off-task app events occurred in focus zones; %s protection changes were reported.',
    round(v_focus_seconds / 3600.0, 1),
    round(v_total_seconds / 3600.0, 1),
    v_task_approved,
    v_task_total,
    v_zone_off_task_count,
    v_tamper_count
  );

  insert into public.child_weekly_insights (
    family_id, child_id, week_start, summary, trust_score
  )
  values (
    p_family_id, p_child_id, v_week_start, v_summary, v_score
  )
  on conflict (child_id, week_start) do update set
    summary = excluded.summary,
    trust_score = excluded.trust_score,
    created_at = now()
  returning * into v_result;
  return v_result;
end;
$$;

revoke all on function public.generate_child_weekly_insight(uuid, uuid)
  from public;
grant execute on function public.generate_child_weekly_insight(uuid, uuid)
  to authenticated;

drop trigger if exists child_task_approved_award on public.child_tasks;
create trigger child_task_approved_award
  after update of status on public.child_tasks
  for each row execute function public.award_approved_task_points();

alter table public.child_locations enable row level security;
alter table public.family_zones enable row level security;
alter table public.zone_app_rules enable row level security;
alter table public.zone_events enable row level security;
alter table public.child_app_categories enable row level security;
alter table public.child_tasks enable row level security;
alter table public.task_submissions enable row level security;
alter table public.child_mood_checkins enable row level security;
alter table public.child_weekly_insights enable row level security;
alter table public.child_streaks enable row level security;
alter table public.child_reward_ledger enable row level security;

drop policy if exists child_locations_select on public.child_locations;
create policy child_locations_select on public.child_locations
  for select using (
    public.is_family_owner(family_id) or child_id = auth.uid()
  );
drop policy if exists child_locations_insert on public.child_locations;
create policy child_locations_insert on public.child_locations
  for insert with check (
    child_id = auth.uid()
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_locations.family_id
        and fm.profile_id = auth.uid()
    )
  );

drop policy if exists family_zones_select on public.family_zones;
create policy family_zones_select on public.family_zones
  for select using (public.is_family_member(family_id));
drop policy if exists family_zones_manage on public.family_zones;
create policy family_zones_manage on public.family_zones
  for all using (public.is_family_owner(family_id))
  with check (public.is_family_owner(family_id));

drop policy if exists zone_app_rules_select on public.zone_app_rules;
create policy zone_app_rules_select on public.zone_app_rules
  for select using (public.is_family_member(family_id));
drop policy if exists zone_app_rules_manage on public.zone_app_rules;
create policy zone_app_rules_manage on public.zone_app_rules
  for all using (public.is_family_owner(family_id))
  with check (public.is_family_owner(family_id));

drop policy if exists zone_events_select on public.zone_events;
create policy zone_events_select on public.zone_events
  for select using (public.is_family_owner(family_id) or child_id = auth.uid());
drop policy if exists zone_events_insert on public.zone_events;
create policy zone_events_insert on public.zone_events
  for insert with check (
    child_id = auth.uid()
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = zone_events.family_id
        and fm.profile_id = auth.uid()
    )
    and exists (
      select 1 from public.family_zones z
      where z.id = zone_events.zone_id
        and z.family_id = zone_events.family_id
    )
  );

drop policy if exists child_app_categories_select on public.child_app_categories;
create policy child_app_categories_select on public.child_app_categories
  for select using (public.is_family_member(family_id));
drop policy if exists child_app_categories_manage on public.child_app_categories;
create policy child_app_categories_manage on public.child_app_categories
  for all using (public.is_family_owner(family_id))
  with check (public.is_family_owner(family_id));

drop policy if exists child_tasks_select on public.child_tasks;
create policy child_tasks_select on public.child_tasks
  for select using (public.is_family_owner(family_id) or child_id = auth.uid());
drop policy if exists child_tasks_parent_insert on public.child_tasks;
create policy child_tasks_parent_insert on public.child_tasks
  for insert with check (
    public.is_family_owner(family_id)
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_tasks.family_id
        and fm.profile_id = child_tasks.child_id
    )
    and created_by = auth.uid()
  );
drop policy if exists child_tasks_parent_update on public.child_tasks;
create policy child_tasks_parent_update on public.child_tasks
  for update using (public.is_family_owner(family_id))
  with check (public.is_family_owner(family_id));

drop policy if exists task_submissions_select on public.task_submissions;
create policy task_submissions_select on public.task_submissions
  for select using (
    child_id = auth.uid()
    or exists (
      select 1 from public.child_tasks t
      where t.id = task_submissions.task_id
        and public.is_family_owner(t.family_id)
    )
  );
drop policy if exists task_submissions_child_insert on public.task_submissions;
create policy task_submissions_child_insert on public.task_submissions
  for insert with check (
    child_id = auth.uid()
    and exists (
      select 1 from public.child_tasks t
      where t.id = task_submissions.task_id
        and t.child_id = auth.uid()
        and t.status = 'assigned'
    )
  );

drop policy if exists child_streaks_select on public.child_streaks;
create policy child_streaks_select on public.child_streaks
  for select using (public.is_family_owner(family_id) or child_id = auth.uid());

drop policy if exists child_reward_ledger_select on public.child_reward_ledger;
create policy child_reward_ledger_select on public.child_reward_ledger
  for select using (public.is_family_owner(family_id) or child_id = auth.uid());

drop policy if exists child_mood_checkins_select on public.child_mood_checkins;
create policy child_mood_checkins_select on public.child_mood_checkins
  for select using (public.is_family_owner(family_id) or child_id = auth.uid());
drop policy if exists child_mood_checkins_insert on public.child_mood_checkins;
create policy child_mood_checkins_insert on public.child_mood_checkins
  for insert with check (
    child_id = auth.uid()
    and exists (
      select 1 from public.family_members fm
      where fm.family_id = child_mood_checkins.family_id
        and fm.profile_id = auth.uid()
    )
  );

drop policy if exists child_weekly_insights_select on public.child_weekly_insights;
create policy child_weekly_insights_select on public.child_weekly_insights
  for select using (public.is_family_owner(family_id) or child_id = auth.uid());

grant select, insert on public.child_locations to authenticated;
grant select, insert on public.zone_events to authenticated;
grant select, insert, update, delete on public.family_zones to authenticated;
grant select, insert, update, delete on public.zone_app_rules to authenticated;
grant select, insert, update, delete on public.child_app_categories to authenticated;
grant select, insert, update on public.child_tasks to authenticated;
grant select, insert on public.task_submissions to authenticated;
grant select, insert on public.child_mood_checkins to authenticated;
grant select on public.child_weekly_insights to authenticated;
grant select on public.child_streaks to authenticated;
grant select on public.child_reward_ledger to authenticated;

insert into storage.buckets (id, name, public)
values ('task-proof', 'task-proof', false)
on conflict (id) do nothing;

drop policy if exists task_proof_select on storage.objects;
create policy task_proof_select on storage.objects
  for select to authenticated using (
    bucket_id = 'task-proof'
    and exists (
      select 1 from public.task_submissions s
      join public.child_tasks t on t.id = s.task_id
      where s.photo_path = name
        and (s.child_id = auth.uid() or public.is_family_owner(t.family_id))
    )
  );
drop policy if exists task_proof_insert on storage.objects;
create policy task_proof_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'task-proof'
    and exists (
      select 1 from public.child_tasks t
      where t.id::text = (storage.foldername(name))[2]
        and t.child_id = auth.uid()
        and t.status = 'assigned'
        and t.child_id::text = (storage.foldername(name))[1]
    )
  );
drop policy if exists task_proof_delete on storage.objects;
create policy task_proof_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'task-proof'
    and exists (
    select 1 from public.child_tasks t
    where t.id::text = (storage.foldername(name))[2]
      and t.child_id = auth.uid()
      and t.status = 'assigned'
      and t.child_id::text = (storage.foldername(name))[1]
    )
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'zone_events'
  ) then
    alter publication supabase_realtime add table public.zone_events;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'child_tasks'
  ) then
    alter publication supabase_realtime add table public.child_tasks;
  end if;
end;
$$;
