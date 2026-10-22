-- Honor child-specific app controls in existing reward and activity calculations.
-- Internal scoring is retained for autonomy; this does not restore weekly UI cards.

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
  ) and not exists (
    select 1 from public.child_blocked_apps
    where family_id = p_family_id and child_id = v_uid
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
      case when coalesce(o.category, c.category, 'unproductive') in ('educational', 'creative')
        then greatest(coalesce(u.duration_seconds, 0), 0)
        else 0 end
    ), 0)
  into v_total_seconds, v_focus_seconds
  from public.app_usage_logs u
  left join public.child_app_categories c
    on c.family_id = u.family_id and c.package_name = u.package_name
  left join public.child_app_category_overrides o
    on o.family_id = u.family_id and o.child_id = u.child_id
      and o.package_name = u.package_name
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
    select coalesce(o.category, c.category, 'unproductive') as category, sum(greatest(coalesce(u.duration_seconds, 0), 0)) as seconds
    from public.app_usage_logs u
    left join public.child_app_categories c
      on c.family_id = u.family_id and c.package_name = u.package_name
  left join public.child_app_category_overrides o
    on o.family_id = u.family_id and o.child_id = u.child_id
      and o.package_name = u.package_name
    where u.family_id = p_family_id
      and u.child_id = p_child_id
      and u.started_at >= v_week_start
      and u.started_at < v_week_start + 7
    group by coalesce(o.category, c.category, 'unproductive')
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

