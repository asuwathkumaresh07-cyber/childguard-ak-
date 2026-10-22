-- Parent-created child accounts use server-controlled auth app metadata.
-- Ordinary public sign-ups always receive the parent role.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, role, display_name)
  values (
    new.id,
    case
      when new.raw_app_meta_data->>'family_guard_role' = 'child'
        and nullif(new.raw_app_meta_data->>'family_guard_created_by', '') is not null
      then 'child'
      else 'parent'
    end,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop policy if exists profiles_update_self on public.profiles;

drop policy if exists families_insert on public.families;
create policy families_insert on public.families
  for insert with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'parent'
    )
  );

drop policy if exists family_members_insert on public.family_members;
create policy family_members_insert on public.family_members
  for insert with check (public.is_family_owner(family_id));
