-- ============================================================
-- MIGRATION 3 — run this on your live Supabase project.
-- Purely additive: no existing table is renamed or dropped, so your
-- current event/areas/incharges/checklist keep working exactly as-is.
-- Dashboard → SQL Editor → New query → paste → Run.
-- ============================================================

-- 1. Areas can now be typed as 'Area' or 'Team'. Existing rows default to 'Area',
--    so everything you've already set up for Saturday is unaffected.
alter table vsd.area add column if not exists unit_type text not null default 'Area';
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'area_unit_type_check'
  ) then
    alter table vsd.area add constraint area_unit_type_check check (unit_type in ('Area','Team'));
  end if;
end $$;

-- 2. Incharge mobile number (email/name already existed).
alter table vsd.area_assignment add column if not exists incharge_mobile text;

-- 3. Structured team/helper members (name + mobile + optional email each),
--    replacing the old free-text "helper_names" field going forward.
--    (helper_names column is left in place, just no longer used by new UI.)
create table if not exists vsd.unit_member (
  id uuid primary key default gen_random_uuid(),
  area_id uuid references vsd.area(id) on delete cascade,
  member_name text not null,
  mobile text,
  email text,
  sort_order int default 0,
  created_at timestamptz default now()
);
alter table vsd.unit_member enable row level security;

create policy unit_member_select_admin on vsd.unit_member for select using (vsd.is_admin());
create policy unit_member_select_incharge on vsd.unit_member for select using (
  exists (select 1 from vsd.area_assignment aa where aa.area_id = vsd.unit_member.area_id and aa.incharge_email = auth.email())
);
create policy unit_member_admin_all on vsd.unit_member for all using (vsd.is_admin()) with check (vsd.is_admin());

-- 4. People directory — powers the "type a name, auto-fill mobile/email"
--    autocomplete for both incharge and team member entry, reusable across events.
create table if not exists vsd.person (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  mobile text,
  email text,
  created_at timestamptz default now()
);
alter table vsd.person enable row level security;

create policy person_select_admin on vsd.person for select using (vsd.is_admin());
create policy person_admin_all on vsd.person for all using (vsd.is_admin()) with check (vsd.is_admin());

-- 5. Responsible person on each to-do item.
alter table vsd.checklist_item add column if not exists responsible_person_name text;
alter table vsd.checklist_item add column if not exists responsible_person_email text;
