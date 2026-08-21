-- ============================================================
-- MIGRATION — run this if you already ran the original schema.sql
-- on your live Supabase project. Safe to run once; uses IF NOT EXISTS
-- where possible. Dashboard → SQL Editor → New query → paste → Run.
-- ============================================================

-- Allows a checklist item to belong to one specific area instead of
-- the whole event (NULL area_id = shared across all areas, unchanged).
alter table vsd.checklist_item
  add column if not exists area_id uuid references vsd.area(id) on delete cascade;

-- Old rows already have status values of 'Pending' from before the
-- 3-state (Not Done / Partial / Done) update — normalize them.
update vsd.area_checklist_status set status = 'Not Done' where status = 'Pending';

-- New default going forward.
alter table vsd.area_checklist_status alter column status set default 'Not Done';
