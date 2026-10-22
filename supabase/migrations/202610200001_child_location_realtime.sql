do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'child_locations'
  ) then
    alter publication supabase_realtime add table public.child_locations;
  end if;
end;
$$;
