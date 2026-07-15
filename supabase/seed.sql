-- Stage 0 synthetic fixtures only. This disposable namespace is not the production schema.
create schema if not exists stage0;

create table if not exists stage0.synthetic_workspaces (
  id uuid primary key,
  slug text not null unique,
  display_name text not null,
  fixture_only boolean not null default true
);

insert into stage0.synthetic_workspaces (id, slug, display_name)
values
  ('10000000-0000-4000-8000-000000000001', 'northstar-motors-test', 'Northstar Motors Test'),
  ('20000000-0000-4000-8000-000000000002', 'harbour-auto-lab', 'Harbour Auto Lab')
on conflict (id) do update
set slug = excluded.slug, display_name = excluded.display_name;
