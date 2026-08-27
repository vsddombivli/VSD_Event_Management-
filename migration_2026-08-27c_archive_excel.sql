-- ============================================================
-- MIGRATION 6 — run this on your live Supabase project.
-- Purely additive: one new nullable column on the event table.
-- ============================================================

alter table vsd.event add column if not exists archive_excel_url text;
