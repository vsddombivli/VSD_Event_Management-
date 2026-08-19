-- ============================================================
-- VSD Event Checklist App — Database Schema (custom schema: vsd)
-- Run this once in Supabase: Dashboard → SQL Editor → New query → Run
-- To rename the schema, find/replace "vsd" below before running.
-- ============================================================

create extension if not exists pgcrypto;

create schema if not exists vsd;

-- Make the schema visible to the auto-generated API (also add "vsd" under
-- Project Settings → API → Exposed schemas in the dashboard — see SETUP.md).
grant usage on schema vsd to anon, authenticated, service_role;
alter default privileges in schema vsd grant all on tables to anon, authenticated, service_role;
alter default privileges in schema vsd grant all on sequences to anon, authenticated, service_role;

-- ---------- ADMINS ----------
create table if not exists vsd.admins (
  email text primary key
);

create or replace function vsd.is_admin() returns boolean as $$
  select exists (select 1 from vsd.admins where email = auth.email());
$$ language sql security definer stable set search_path = vsd, public;

-- ---------- EVENT ----------
create table if not exists vsd.event (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  event_date date not null,
  status text not null default 'Active',
  created_at timestamptz default now()
);

-- ---------- AREA ----------
create table if not exists vsd.area (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references vsd.event(id) on delete cascade,
  area_name text not null,
  temple_list text,
  sort_order int default 0,
  created_at timestamptz default now()
);

-- ---------- AREA ASSIGNMENT ----------
create table if not exists vsd.area_assignment (
  id uuid primary key default gen_random_uuid(),
  area_id uuid references vsd.area(id) on delete cascade,
  incharge_name text not null,
  incharge_email text not null,
  helper_names text,
  created_at timestamptz default now()
);

-- ---------- CHECKLIST ITEM ----------
create table if not exists vsd.checklist_item (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references vsd.event(id) on delete cascade,
  label text not null,
  sort_order int default 0
);

-- ---------- AREA CHECKLIST STATUS ----------
create table if not exists vsd.area_checklist_status (
  id uuid primary key default gen_random_uuid(),
  area_id uuid references vsd.area(id) on delete cascade,
  checklist_item_id uuid references vsd.checklist_item(id) on delete cascade,
  status text not null default 'Pending',
  comment text,
  photo_url text,
  updated_by text,
  updated_at timestamptz default now(),
  unique (area_id, checklist_item_id)
);

-- ---------- NOTIFICATION LOG ----------
-- Audit trail for every email sent by the send-notification Edge Function.
-- Generic across notification types (TEAM_ASSIGNMENT now; DUE_TODAY/OVERDUE later).
create table if not exists vsd.notification_log (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references vsd.event(id) on delete cascade,
  area_id uuid references vsd.area(id) on delete set null,
  notification_type text not null,
  recipient text not null,
  sent_at timestamptz default now(),
  provider_message_id text,
  status text not null default 'sent', -- sent / failed
  error_message text
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table vsd.admins enable row level security;
alter table vsd.event enable row level security;
alter table vsd.area enable row level security;
alter table vsd.area_assignment enable row level security;
alter table vsd.checklist_item enable row level security;
alter table vsd.area_checklist_status enable row level security;
alter table vsd.notification_log enable row level security;

create policy admins_select on vsd.admins for select using (vsd.is_admin());

create policy event_select on vsd.event for select using (auth.role() = 'authenticated');
create policy event_admin_all on vsd.event for all using (vsd.is_admin()) with check (vsd.is_admin());

create policy area_select_admin on vsd.area for select using (vsd.is_admin());
create policy area_select_incharge on vsd.area for select using (
  exists (select 1 from vsd.area_assignment aa where aa.area_id = vsd.area.id and aa.incharge_email = auth.email())
);
create policy area_admin_all on vsd.area for all using (vsd.is_admin()) with check (vsd.is_admin());

create policy assignment_select_admin on vsd.area_assignment for select using (vsd.is_admin());
create policy assignment_select_incharge on vsd.area_assignment for select using (incharge_email = auth.email());
create policy assignment_admin_all on vsd.area_assignment for all using (vsd.is_admin()) with check (vsd.is_admin());

create policy checklist_select on vsd.checklist_item for select using (auth.role() = 'authenticated');
create policy checklist_admin_all on vsd.checklist_item for all using (vsd.is_admin()) with check (vsd.is_admin());

create policy status_select_admin on vsd.area_checklist_status for select using (vsd.is_admin());
create policy status_select_incharge on vsd.area_checklist_status for select using (
  exists (select 1 from vsd.area_assignment aa where aa.area_id = vsd.area_checklist_status.area_id and aa.incharge_email = auth.email())
);
create policy status_insert_incharge on vsd.area_checklist_status for insert with check (
  exists (select 1 from vsd.area_assignment aa where aa.area_id = vsd.area_checklist_status.area_id and aa.incharge_email = auth.email())
);
create policy status_update_incharge on vsd.area_checklist_status for update using (
  exists (select 1 from vsd.area_assignment aa where aa.area_id = vsd.area_checklist_status.area_id and aa.incharge_email = auth.email())
) with check (
  exists (select 1 from vsd.area_assignment aa where aa.area_id = vsd.area_checklist_status.area_id and aa.incharge_email = auth.email())
);
create policy status_admin_all on vsd.area_checklist_status for all using (vsd.is_admin()) with check (vsd.is_admin());

-- notification_log: admin-only (the Edge Function writes here using the
-- service role key, which bypasses RLS entirely — these policies only
-- govern what the admin dashboard itself can read/write directly)
create policy notiflog_select_admin on vsd.notification_log for select using (vsd.is_admin());
create policy notiflog_admin_all on vsd.notification_log for all using (vsd.is_admin()) with check (vsd.is_admin());

-- ============================================================
-- STORAGE (for aangi / activity photos) — storage.objects stays in the
-- storage schema regardless of your custom schema; this part is unchanged.
-- Create a bucket named "event-photos" (Storage → New bucket → Public)
-- before running the two policies below.
-- ============================================================

create policy "Public read event photos" on storage.objects
  for select using (bucket_id = 'event-photos');

create policy "Authenticated upload event photos" on storage.objects
  for insert with check (bucket_id = 'event-photos' and auth.role() = 'authenticated');

-- ============================================================
-- Add yourself as admin (replace with your real email), then run:
-- insert into vsd.admins (email) values ('your-email@example.com');
-- ============================================================
