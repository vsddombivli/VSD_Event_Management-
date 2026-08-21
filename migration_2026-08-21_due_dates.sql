-- ============================================================
-- MIGRATION 2 — run this on your live Supabase project.
-- (Run this in addition to migration_2026-08-19.sql if you haven't already.)
-- Dashboard → SQL Editor → New query → paste → Run.
-- ============================================================

alter table vsd.checklist_item
  add column if not exists due_date date;
