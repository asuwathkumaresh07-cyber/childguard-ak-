alter table public.child_device_status
  add column if not exists location_sharing_enabled boolean not null default false;

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
    'accessibility_restored',
    'location_sharing_disabled',
    'location_sharing_enabled'
  ));

create or replace function public.report_child_device_status(
  p_vpn_enabled boolean,
  p_usage_access_enabled boolean,
  p_accessibility_enabled boolean,
  p_location_sharing_enabled boolean
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
    location_sharing_enabled,
    last_seen_at
  )
  values (
    v_uid,
    v_family_id,
    p_vpn_enabled,
    p_usage_access_enabled,
    p_accessibility_enabled,
    p_location_sharing_enabled,
    now()
  )
  on conflict (child_id) do update set
    family_id = excluded.family_id,
    vpn_enabled = excluded.vpn_enabled,
    usage_access_enabled = excluded.usage_access_enabled,
    accessibility_enabled = excluded.accessibility_enabled,
    location_sharing_enabled = excluded.location_sharing_enabled,
    last_seen_at = excluded.last_seen_at;

  if not v_has_previous then
    return;
  end if;

  if v_previous.vpn_enabled is distinct from p_vpn_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (
        v_uid,
        v_family_id,
        case when p_vpn_enabled then 'vpn_enabled' else 'vpn_disabled' end
      )
      returning id, child_tamper_events.event_type;
  end if;

  if v_previous.usage_access_enabled is distinct from p_usage_access_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (
        v_uid,
        v_family_id,
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
        v_uid,
        v_family_id,
        case
          when p_accessibility_enabled then 'accessibility_restored'
          else 'accessibility_disabled'
        end
      )
      returning id, child_tamper_events.event_type;
  end if;

  if v_previous.location_sharing_enabled is distinct from p_location_sharing_enabled then
    return query
      insert into public.child_tamper_events (child_id, family_id, event_type)
      values (
        v_uid,
        v_family_id,
        case
          when p_location_sharing_enabled then 'location_sharing_enabled'
          else 'location_sharing_disabled'
        end
      )
      returning id, child_tamper_events.event_type;
  end if;
end;
$$;

revoke all on function public.report_child_device_status(boolean, boolean, boolean, boolean)
  from public;
grant execute on function public.report_child_device_status(boolean, boolean, boolean, boolean)
  to authenticated;
