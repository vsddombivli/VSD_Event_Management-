-- ============================================================
-- MIGRATION 5 — run this on your live Supabase project.
-- Purely additive: two new nullable columns on the event table.
-- ============================================================

alter table vsd.event add column if not exists notes text;
alter table vsd.event add column if not exists drive_link text;
