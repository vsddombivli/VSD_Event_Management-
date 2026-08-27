-- ============================================================
-- MIGRATION 4 — run this on your live Supabase project.
-- Purely additive: new table + new policies + indices. Nothing existing
-- is touched, so this is safe to run any time.
-- ============================================================

-- Read-only "Viewer" role (e.g. for trustees who should see progress
-- across every event but never edit anything).
create table if not exists vsd.viewer (
  email text primary key
);
alter table vsd.viewer enable row level security;

create or replace function vsd.is_viewer() returns boolean as $$
  select exists (select 1 from vsd.viewer where email = auth.email());
$$ language sql security definer stable set search_path = vsd, public;

create policy viewer_select_admin on vsd.viewer for select using (vsd.is_admin());
create policy viewer_admin_all on vsd.viewer for all using (vsd.is_admin()) with check (vsd.is_admin());

-- Give viewers read-only access across all events (event and checklist_item
-- already allow any authenticated read, so only these four need new policies).
create policy area_select_viewer on vsd.area for select using (vsd.is_viewer());
create policy assignment_select_viewer on vsd.area_assignment for select using (vsd.is_viewer());
create policy status_select_viewer on vsd.area_checklist_status for select using (vsd.is_viewer());
create policy unit_member_select_viewer on vsd.unit_member for select using (vsd.is_viewer());

-- To add a viewer, run (replace with their real email):
-- insert into vsd.viewer (email) values ('trustee@example.com');

-- Indices for query performance as event history grows.
create index if not exists idx_area_event on vsd.area(event_id);
create index if not exists idx_checklist_event on vsd.checklist_item(event_id);
create index if not exists idx_checklist_area on vsd.checklist_item(area_id);
create index if not exists idx_status_area on vsd.area_checklist_status(area_id);
create index if not exists idx_assignment_area on vsd.area_assignment(area_id);
create index if not exists idx_assignment_email on vsd.area_assignment(incharge_email);
create index if not exists idx_unit_member_area on vsd.unit_member(area_id);
