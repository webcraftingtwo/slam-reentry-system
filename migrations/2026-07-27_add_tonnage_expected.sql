-- ============================================================================
-- Add production_performance.tonnage_expected
-- ============================================================================
-- Purpose
--   The Production Performance dashboard chart needed an "expected/planned"
--   tonnage figure to pair with tonnage_hoisted (actual) for an Actual vs
--   Expected chart — that field didn't exist yet, only the actual figure did.
--
-- Purely additive: nullable, no backfill, no data-loss on existing rows.
-- Safe to run any time relative to the app deploy (old app versions simply
-- never populate it; new versions start writing it once both are live).
-- ============================================================================

alter table public.production_performance add column tonnage_expected integer;
comment on column public.production_performance.tonnage_expected is
  'Planned/target tonnage for the shift, paired with tonnage_hoisted (actual) for the dashboard Actual vs Expected chart.';
