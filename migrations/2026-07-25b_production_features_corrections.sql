-- ============================================================================
-- PRODUCTION FEATURES: pilot-feedback corrections
-- ============================================================================
-- Purpose (feedback from the first day of real use — 2 production_performance
-- rows and 1 machinery_log row already exist from Blessed Mbewe / Matipaishe
-- Hove, see notes below on how those are handled)
--   1. Drilled/support fields are LINEAR metres, not square metres — rename
--      *_m2 columns to *_m.
--   2. Shift selection becomes Day/Night (a single reusable toggle) instead
--      of A/B/C, for these 3 tables only. shift_handovers keeps A/B/C
--      unchanged — that convention is untouched.
--   3. production_performance.hoisted (boolean) becomes tonnage_hoisted
--      (integer) — a real tonnage figure, not a yes/no flag.
--   4. production_performance.ends_available_for_charging (boolean) becomes
--      ends_available_bords (text, comma-separated bord list) — the app now
--      shows this labelled "Ends Available for Charging" on a Day shift and
--      "Ends Available for Blasting" on a Night shift; same column either
--      way, label is day/night-dependent client-side.
--   5. hourly_tonnage.tonnage_target is removed — not wanted for this
--      feature.
--
-- EXISTING DATA (2 production_performance rows, 1 machinery_log row, live
-- pilot data from today — not test data)
--   - *_m2 -> *_m: plain renames, no data loss (values were already just
--     numbers; only the column name was wrong).
--   - hoisted (bool) -> tonnage_hoisted (int): no reasonable numeric value
--     can be inferred from a boolean, so this drops to NULL for the 2
--     existing rows. Both officers can log the real tonnage figure next time
--     they open the feature.
--   - ends_available_for_charging (bool) -> ends_available_bords (text): the
--     2 existing rows lose their true/false flag (not translatable to a bord
--     list); one of the two already wrote the actual bord names into
--     blast_plan_notes by hand ("Bord 4 and 6 for charging") since there was
--     no structured field for it — exactly the gap this migration fixes.
--   - shift_type ('A') -> shift_period: defaults existing rows to 'day'
--     (a placeholder; there was no way to know their actual day/night shift
--     under the old A/B/C scheme).
--
-- WHAT THIS DOES NOT TOUCH
--   - shift_handovers / bord_cycle_updates / any other table's shift_type
--     stays A/B/C, per CLAUDE.md. Only the 3 new tables from this feature
--     switch to day/night.
--   - RLS policies are untouched (insert-own / section-select still apply;
--     they don't reference any of the renamed/changed columns).
-- ============================================================================


-- ── production_performance ───────────────────────────────────────────────
alter table public.production_performance rename column drilled_expected_m2 to drilled_expected_m;
alter table public.production_performance rename column drilled_actual_m2   to drilled_actual_m;
alter table public.production_performance rename column support_expected_m2 to support_expected_m;
alter table public.production_performance rename column support_actual_m2   to support_actual_m;

alter table public.production_performance drop column hoisted;
alter table public.production_performance add column tonnage_hoisted integer;

alter table public.production_performance drop column ends_available_for_charging;
alter table public.production_performance add column ends_available_bords text;
comment on column public.production_performance.ends_available_bords is
  'Comma-separated bords. Labelled "Ends Available for Charging" (day shift) or "Ends Available for Blasting" (night shift) client-side, based on shift_period.';

alter table public.production_performance drop column shift_type;
alter table public.production_performance add column shift_period text not null default 'day' check (shift_period in ('day','night'));
alter table public.production_performance alter column shift_period drop default;


-- ── machinery_log ────────────────────────────────────────────────────────
alter table public.machinery_log drop column shift_type;
alter table public.machinery_log add column shift_period text not null default 'day' check (shift_period in ('day','night'));
alter table public.machinery_log alter column shift_period drop default;


-- ── hourly_tonnage ───────────────────────────────────────────────────────
alter table public.hourly_tonnage drop column shift_type;
alter table public.hourly_tonnage add column shift_period text not null default 'day' check (shift_period in ('day','night'));
alter table public.hourly_tonnage alter column shift_period drop default;

alter table public.hourly_tonnage drop column tonnage_target;


-- ── Post-run checks ──────────────────────────────────────────────────────
--   select column_name, data_type from information_schema.columns
--   where table_schema='public' and table_name in
--   ('production_performance','machinery_log','hourly_tonnage')
--   order by table_name, ordinal_position;
