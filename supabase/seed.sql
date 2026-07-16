-- Stage 0 synthetic fixtures only. This disposable namespace is not the production schema.
-- Keep the disposable DDL and rows in one statement so Supabase's seed batch
-- cannot resolve the insert before the table-creation statement has executed.
do $stage0_seed$
begin
  execute 'create schema if not exists stage0';
  execute $stage0_schema$
    create table if not exists stage0.synthetic_workspaces (
      id uuid primary key,
      slug text not null unique,
      display_name text not null,
      fixture_only boolean not null default true
    )
  $stage0_schema$;
  execute $stage0_rows$
    insert into stage0.synthetic_workspaces (id, slug, display_name)
    values
      ('10000000-0000-4000-8000-000000000001', 'northstar-motors-test', 'Northstar Motors Test'),
      ('20000000-0000-4000-8000-000000000002', 'harbour-auto-lab', 'Harbour Auto Lab')
    on conflict (id) do update
    set slug = excluded.slug, display_name = excluded.display_name
  $stage0_rows$;
end
$stage0_seed$;
