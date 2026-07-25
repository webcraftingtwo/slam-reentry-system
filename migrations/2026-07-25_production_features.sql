-- ============================================================================
-- PRODUCTION FEATURES: production performance, machinery log, hourly tonnage
-- ============================================================================
-- Purpose
--   Add 3 new miner-app features requested during the pilot:
--     1. production_performance — per-bord, per-shift drilling/support metres
--        (expected vs actual), hoist/charging status, blast plan notes.
--     2. machinery_log — per-machine startup/breakdown/assignment log.
--     3. hourly_tonnage — per-bord, per-hour tonnage vs target.
--
-- ROLLOUT ORDER (important)
--   Run this migration BEFORE deploying the updated index.html. The new app
--   writes to these 3 tables; until this migration runs, they don't exist and
--   inserts would be rejected (they'd land in the failed-record queue rather
--   than being lost, but don't rely on it) — same rule as every prior
--   migration in this repo.
--
-- WHAT THIS DOES NOT TOUCH
--   - No existing table, policy, or helper function is modified.
--   - No UPDATE/DELETE policies are added for the new tables (matches
--     near_misses/shift_notes/shift_handovers — no review/edit workflow for
--     this pass). Only INSERT (own rows) and section-fenced SELECT.
--   - Crew names are NOT stored anywhere here — section stays the only
--     canonical value ('14 South' / '16 North'); crew display name is still
--     derived client-side via crew-names.js, per CLAUDE.md.
--
-- Reuses private.user_section() / private.user_is_global(), created by
-- migrations/2026-07-18_section_compartmentalization.sql — no new helper
-- functions needed.
--
-- Review before running:  select * from pg_policies where schemaname='public'
--                          and tablename in
--                          ('production_performance','machinery_log','hourly_tonnage');
-- ============================================================================


-- ── 1. production_performance ───────────────────────────────────────────────
create table public.production_performance (
  id                            uuid primary key default gen_random_uuid(),
  created_at                    timestamptz not null default now(),
  user_id                       uuid not null references auth.users(id),
  officer_name                  text,
  officer_id                    text,
  section                       text not null,
  shift_date                    date not null default current_date,
  shift_type                    text not null check (shift_type in ('A','B','C')),
  bord                          text not null,
  drilled_expected_m2           numeric,
  drilled_actual_m2             numeric,
  support_expected_m2           numeric,
  support_actual_m2             numeric,
  hoisted                       boolean not null default false,
  ends_available_for_charging   boolean not null default false,
  blast_plan_notes              text,
  session_id                    text
);

comment on table public.production_performance is
  'Per-bord, per-shift production metrics (drilled/support m^2 expected vs actual, hoist/charging status, blast plan). Miner-entered.';

alter table public.production_performance enable row level security;

create policy production_performance_insert_own on public.production_performance
for insert to authenticated
with check (user_id = auth.uid());

create policy production_performance_section_select on public.production_performance
for select to authenticated
using (
  private.user_is_global()
  or (section is not null and section = private.user_section())
);


-- ── 2. machinery_log ─────────────────────────────────────────────────────────
create table public.machinery_log (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  user_id           uuid not null references auth.users(id),
  officer_name      text,
  officer_id        text,
  section           text not null,
  shift_date        date not null default current_date,
  shift_type        text not null check (shift_type in ('A','B','C')),
  machine_type      text not null,
  machine_number    text,
  status            text not null default 'running' check (status in ('running','breakdown','idle')),
  startup_time      text,
  breakdown_start   text,
  breakdown_end     text,
  assigned_bords    text,
  location          text,
  comments          text
);

comment on table public.machinery_log is
  'Per-machine availability/utilization log: startup time, breakdown window, bord assignment. Miner-entered.';
comment on column public.machinery_log.assigned_bords is
  'Comma-separated bords this machine is assigned to this shift (e.g. "14SB1, 14SB2"), mirrors shift_handovers.bords.';

alter table public.machinery_log enable row level security;

create policy machinery_log_insert_own on public.machinery_log
for insert to authenticated
with check (user_id = auth.uid());

create policy machinery_log_section_select on public.machinery_log
for select to authenticated
using (
  private.user_is_global()
  or (section is not null and section = private.user_section())
);


-- ── 3. hourly_tonnage ────────────────────────────────────────────────────────
create table public.hourly_tonnage (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  user_id           uuid not null references auth.users(id),
  officer_name      text,
  officer_id        text,
  section           text not null,
  shift_date        date not null default current_date,
  shift_type        text not null check (shift_type in ('A','B','C')),
  bord              text not null,
  hour_slot         text not null,
  tonnage_actual    numeric,
  tonnage_target    numeric
);

comment on table public.hourly_tonnage is
  'Per-bord, per-hour tonnage actual vs target. Miner-entered, one row per hour logged.';

alter table public.hourly_tonnage enable row level security;

create policy hourly_tonnage_insert_own on public.hourly_tonnage
for insert to authenticated
with check (user_id = auth.uid());

create policy hourly_tonnage_section_select on public.hourly_tonnage
for select to authenticated
using (
  private.user_is_global()
  or (section is not null and section = private.user_section())
);


-- ── 4. Post-run checks ───────────────────────────────────────────────────────
-- a) Tables + RLS enabled:
--      select tablename, rowsecurity from pg_tables
--      where schemaname='public' and tablename in
--      ('production_performance','machinery_log','hourly_tonnage');
-- b) Policies in place (2 each: insert_own, section_select):
--      select tablename, policyname, cmd from pg_policies
--      where schemaname='public' and tablename in
--      ('production_performance','machinery_log','hourly_tonnage')
--      order by tablename, cmd;
-- c) Sign in as a 16 North shift_boss and confirm 14 South rows in these 3
--    tables are invisible; as she_manager confirm everything is visible —
--    same check prescribed by the 2026-07-18 compartmentalization migration.
