alter table public.extra_time_requests
  add column if not exists trade_suggestion text;

create or replace function public.suggest_extra_time_trade()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.trade_suggestion := case
    when new.requested_minutes <= 15 then
      'Suggested trade: use this as one focused session and stop when the timer ends.'
    when new.requested_minutes <= 30 then
      'Suggested trade: complete one 15-minute homework, reading, or creative task before using the extra time.'
    else
      'Suggested trade: split this into two shorter sessions and check in with your parent before the second one.'
  end;
  return new;
end;
$$;

drop trigger if exists extra_time_trade_suggestion
  on public.extra_time_requests;
create trigger extra_time_trade_suggestion
  before insert or update of requested_minutes on public.extra_time_requests
  for each row execute function public.suggest_extra_time_trade();

update public.extra_time_requests
set trade_suggestion = case
  when requested_minutes <= 15 then
    'Suggested trade: use this as one focused session and stop when the timer ends.'
  when requested_minutes <= 30 then
    'Suggested trade: complete one 15-minute homework, reading, or creative task before using the extra time.'
  else
    'Suggested trade: split this into two shorter sessions and check in with your parent before the second one.'
end
where trade_suggestion is null;

alter table public.child_app_categories
  drop constraint if exists child_app_categories_category_check;

update public.child_app_categories
set category = case category
  when 'productivity' then 'educational'
  when 'education' then 'educational'
  when 'communication' then 'social'
  when 'other' then 'unproductive'
  else category
end;

alter table public.child_app_categories
  add constraint child_app_categories_category_check
  check (category in (
    'educational', 'creative', 'social', 'entertainment', 'unproductive'
  ));

alter table public.child_weekly_insights
  add column if not exists mood_alert boolean not null default false,
  add column if not exists mood_alert_reason text;

alter table public.child_tamper_events
  drop constraint if exists child_tamper_events_event_type_check;
alter table public.child_tamper_events
  add constraint child_tamper_events_event_type_check
  check (event_type in (
    'vpn_disabled',
    'vpn_enabled',
    'usage_access_revoked',
    'usage_access_restored',
    'accessibility_disabled',
    'accessibility_restored'
  ));

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
    child_id, family_id, vpn_enabled, usage_access_enabled,
    accessibility_enabled, last_seen_at
  )
  values (
    v_uid, v_family_id, p_vpn_enabled, p_usage_access_enabled,
    p_accessibility_enabled, now()
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

  if v_previous.vpn_enabled is distinct from p_vpn_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (
        v_uid, v_family_id,
        case when p_vpn_enabled then 'vpn_enabled' else 'vpn_disabled' end
      )
      returning id, child_tamper_events.event_type;
  end if;

  if v_previous.usage_access_enabled is distinct from p_usage_access_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (
        v_uid, v_family_id,
        case
          when p_usage_access_enabled then 'usage_access_restored'
          else 'usage_access_revoked'
        end
      )
      returning id, child_tamper_events.event_type;
  end if;

  if v_previous.accessibility_enabled is distinct from p_accessibility_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (
        v_uid, v_family_id,
        case
          when p_accessibility_enabled then 'accessibility_restored'
          else 'accessibility_disabled'
        end
      )
      returning id, child_tamper_events.event_type;
  end if;
end;
$$;

revoke all on function public.report_child_device_status(boolean, boolean, boolean)
  from public;
grant execute on function public.report_child_device_status(boolean, boolean, boolean)
  to authenticated;

create or replace function public.annotate_child_weekly_insight()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_low_mood_count integer;
  v_off_task_count integer;
begin
  select count(*) into v_low_mood_count
  from public.child_mood_checkins
  where child_id = new.child_id
    and family_id = new.family_id
    and created_at >= new.week_start
    and created_at < new.week_start + 7
    and mood in ('low', 'stressed');

  select count(*) into v_off_task_count
  from public.zone_events
  where child_id = new.child_id
    and family_id = new.family_id
    and occurred_at >= new.week_start
    and occurred_at < new.week_start + 7
    and event_type = 'off_task_app';

  new.mood_alert := v_low_mood_count >= 3
    or (v_low_mood_count >= 2 and v_off_task_count >= 2);
  new.mood_alert_reason := case
    when v_low_mood_count >= 3 then
      'Several low or stressed mood check-ins were submitted this week. Consider checking in supportively.'
    when v_low_mood_count >= 2 and v_off_task_count >= 2 then
      'Low or stressed mood check-ins coincided with repeated off-task app events. Consider a supportive check-in.'
    else null
  end;
  return new;
end;
$$;

drop trigger if exists child_weekly_insight_mood_annotation
  on public.child_weekly_insights;
create trigger child_weekly_insight_mood_annotation
  before insert or update on public.child_weekly_insights
  for each row execute function public.annotate_child_weekly_insight();

create or replace function public.refresh_child_weekly_mood_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_start date := date_trunc('week', new.created_at)::date;
  v_low_mood_count integer;
  v_off_task_count integer;
begin
  select count(*) into v_low_mood_count
  from public.child_mood_checkins
  where child_id = new.child_id
    and family_id = new.family_id
    and created_at >= v_week_start
    and created_at < v_week_start + 7
    and mood in ('low', 'stressed');

  select count(*) into v_off_task_count
  from public.zone_events
  where child_id = new.child_id
    and family_id = new.family_id
    and occurred_at >= v_week_start
    and occurred_at < v_week_start + 7
    and event_type = 'off_task_app';

  update public.child_weekly_insights
  set mood_alert = v_low_mood_count >= 3
      or (v_low_mood_count >= 2 and v_off_task_count >= 2),
      mood_alert_reason = case
        when v_low_mood_count >= 3 then
          'Several low or stressed mood check-ins were submitted this week. Consider checking in supportively.'
        when v_low_mood_count >= 2 and v_off_task_count >= 2 then
          'Low or stressed mood check-ins coincided with repeated off-task app events. Consider a supportive check-in.'
        else null
      end
  where child_id = new.child_id
    and family_id = new.family_id
    and week_start = v_week_start;

  return new;
end;
$$;

drop trigger if exists child_mood_checkin_refreshes_weekly_alert
  on public.child_mood_checkins;
create trigger child_mood_checkin_refreshes_weekly_alert
  after insert on public.child_mood_checkins
  for each row execute function public.refresh_child_weekly_mood_alert();

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
  v_category_summary text;
  v_task_total integer;
  v_task_approved integer;
  v_task_streak integer;
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
      case when c.category in ('educational', 'creative')
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

  select coalesce(string_agg(
    format('%s: %s hours', category, round(seconds / 3600.0, 1)),
    ', ' order by category
  ), 'No categorized app activity yet')
  into v_category_summary
  from (
    select c.category, sum(greatest(coalesce(u.duration_seconds, 0), 0)) as seconds
    from public.app_usage_logs u
    join public.child_app_categories c
      on c.family_id = u.family_id and c.package_name = u.package_name
    where u.family_id = p_family_id
      and u.child_id = p_child_id
      and u.started_at >= v_week_start
      and u.started_at < v_week_start + 7
    group by c.category
  ) categorized;

  select count(*), count(*) filter (where status = 'approved')
  into v_task_total, v_task_approved
  from public.child_tasks
  where family_id = p_family_id
    and child_id = p_child_id
    and created_at >= v_week_start;

  select coalesce(current_streak, 0) into v_task_streak
  from public.child_streaks
  where child_id = p_child_id and family_id = p_family_id;
  v_task_streak := coalesce(v_task_streak, 0);

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
    45
    + case when v_total_seconds > 0
        then round(25.0 * v_focus_seconds / v_total_seconds)::integer
        else 0 end
    + case when v_task_total > 0
        then round(20.0 * v_task_approved / v_task_total)::integer
        else 0 end
    + least(v_task_streak, 10)
    - least(v_tamper_count * 10, 40)
    - least(v_zone_off_task_count * 5, 25)
  ));

  v_summary := format(
    'This week: %s of %s screen-time hours were in educational or creative apps. App activity: %s. %s of %s assigned tasks were approved; %s off-task app events occurred in focus zones; %s protection changes were reported.',
    round(v_focus_seconds / 3600.0, 1),
    round(v_total_seconds / 3600.0, 1),
    v_category_summary,
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

alter table public.child_streaks
  add column if not exists bonus_time_minutes integer not null default 0
    check (bonus_time_minutes >= 0),
  add column if not exists app_unlock_credits integer not null default 0
    check (app_unlock_credits >= 0);

alter table public.child_reward_ledger
  add column if not exists bonus_time_minutes integer not null default 0
    check (bonus_time_minutes >= 0),
  add column if not exists app_unlock_credits integer not null default 0
    check (app_unlock_credits >= 0);

create table if not exists public.child_temporary_app_unlocks (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id) on delete cascade,
  child_id uuid not null references public.profiles (id) on delete cascade,
  package_name text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists idx_child_temporary_app_unlocks_active
  on public.child_temporary_app_unlocks (child_id, expires_at desc);

create or replace function public.prune_child_temporary_app_unlock_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.child_temporary_app_unlocks
  where child_id = new.child_id
    and expires_at < now() - interval '30 days';
  return new;
end;
$$;

drop trigger if exists child_temporary_app_unlock_retention
  on public.child_temporary_app_unlocks;
create trigger child_temporary_app_unlock_retention
  after insert on public.child_temporary_app_unlocks
  for each row execute function public.prune_child_temporary_app_unlock_history();

alter table public.child_temporary_app_unlocks enable row level security;
drop policy if exists child_temporary_app_unlocks_select
  on public.child_temporary_app_unlocks;
create policy child_temporary_app_unlocks_select
  on public.child_temporary_app_unlocks
  for select using (
    child_id = auth.uid() or public.is_family_owner(family_id)
  );
revoke all on table public.child_temporary_app_unlocks
  from public, anon, authenticated;
grant select on table public.child_temporary_app_unlocks to authenticated;

create or replace function public.award_approved_task_points()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_streak integer;
  v_time_bonus integer;
  v_unlock_credit integer;
  v_award integer;
begin
  if new.status <> 'approved' or old.status = 'approved' then
    return new;
  end if;

  select current_streak into v_streak
  from public.child_streaks
  where child_id = new.child_id
  for update;

  v_streak := coalesce(v_streak, 0) + 1;
  v_time_bonus := case
    when v_streak % 3 = 0 then least(30, (v_streak / 3) * 5)
    else 0
  end;
  v_unlock_credit := case when v_streak % 7 = 0 then 1 else 0 end;
  v_award := new.points + floor(new.points * least(v_streak / 7, 2) * 0.25);

  insert into public.child_streaks (
    child_id, family_id, current_streak, best_streak, total_points,
    last_completed_on, bonus_time_minutes, app_unlock_credits
  )
  values (
    new.child_id, new.family_id, v_streak, v_streak, v_award,
    current_date, v_time_bonus, v_unlock_credit
  )
  on conflict (child_id) do update set
    current_streak = v_streak,
    best_streak = greatest(public.child_streaks.best_streak, v_streak),
    total_points = public.child_streaks.total_points + v_award,
    last_completed_on = current_date,
    bonus_time_minutes =
      public.child_streaks.bonus_time_minutes + v_time_bonus,
    app_unlock_credits =
      public.child_streaks.app_unlock_credits + v_unlock_credit;

  insert into public.child_reward_ledger (
    child_id, family_id, task_id, points_awarded, streak_at_award,
    bonus_time_minutes, app_unlock_credits
  )
  values (
    new.child_id, new.family_id, new.id, v_award, v_streak,
    v_time_bonus, v_unlock_credit
  )
  on conflict (task_id) do nothing;

  return new;
end;
$$;

create or replace function public.reset_child_task_streak_on_rejection()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'rejected' and old.status <> 'rejected' then
    update public.child_streaks
    set current_streak = 0
    where child_id = new.child_id;
  end if;
  return new;
end;
$$;

drop trigger if exists child_task_rejection_breaks_streak
  on public.child_tasks;
create trigger child_task_rejection_breaks_streak
  after update of status on public.child_tasks
  for each row execute function public.reset_child_task_streak_on_rejection();

create or replace function public.redeem_child_temporary_app_unlock(
  p_family_id uuid,
  p_package_name text
)
returns public.child_temporary_app_unlocks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_credits integer;
  v_result public.child_temporary_app_unlocks;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles where id = v_uid and role = 'child'
  ) then
    raise exception 'Only a signed-in child can redeem an app unlock.';
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
  if not exists (
    select 1 from public.blocked_apps
    where family_id = p_family_id
      and package_name = trim(p_package_name)
  ) then
    raise exception 'Choose an app currently blocked by your parent.';
  end if;

  select app_unlock_credits into v_credits
  from public.child_streaks
  where child_id = v_uid and family_id = p_family_id
  for update;

  if coalesce(v_credits, 0) < 1 then
    raise exception 'Complete more approved tasks to earn an app unlock.';
  end if;

  update public.child_streaks
  set app_unlock_credits = app_unlock_credits - 1
  where child_id = v_uid and family_id = p_family_id;

  insert into public.child_temporary_app_unlocks (
    family_id, child_id, package_name, expires_at
  )
  values (
    p_family_id, v_uid, trim(p_package_name), now() + interval '15 minutes'
  )
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.redeem_child_temporary_app_unlock(uuid, text)
  from public;
grant execute on function public.redeem_child_temporary_app_unlock(uuid, text)
  to authenticated;

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
  v_bonus_balance integer := 0;
  v_bonus_used integer := 0;
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

  select bonus_time_minutes into v_bonus_balance
  from public.child_streaks
  where child_id = v_uid and family_id = p_family_id
  for update;

  v_bonus_used := least(
    greatest(p_requested_minutes - v_granted, 0),
    coalesce(v_bonus_balance, 0)
  );
  v_granted := v_granted + v_bonus_used;

  if v_bonus_used > 0 then
    update public.child_streaks
    set bonus_time_minutes = bonus_time_minutes - v_bonus_used
    where child_id = v_uid and family_id = p_family_id;
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

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'child_weekly_insights'
  ) then
    alter publication supabase_realtime
      add table public.child_weekly_insights;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'child_temporary_app_unlocks'
  ) then
    alter publication supabase_realtime
      add table public.child_temporary_app_unlocks;
  end if;
end;
$$;
