-- ============================================================================
-- SECTION COMPARTMENTALIZATION
-- ============================================================================
-- Purpose
--   1. Unify section names to '14 South' / '16 North' (old: North Section /
--      South Section / Development Section).
--   2. Add shift_handovers.bords so a handover is targeted at the bords the
--      outgoing crew actually worked (e.g. '16N B7').
--   3. Enforce section fencing in RLS:
--        - miners, shift_boss, supervisor (section manager), safety_officer:
--          can only SELECT rows from their own section
--        - she_manager, admin: see everything
--      The dashboard/app apply the same filters client-side, but THIS is the
--      enforcement — the client is just a mirror.
--
-- ROLLOUT ORDER (important)
--   Run this migration BEFORE deploying the updated index.html/dashboard.html.
--   The new app writes shift_handovers.bords; until this migration runs, that
--   column doesn't exist and handover inserts would be rejected (they'd land
--   in the failed-record queue rather than being lost, but don't rely on it).
--
-- WHAT THIS DOES NOT TOUCH
--   - No INSERT/UPDATE/DELETE policies are changed. All write paths (and the
--     offline sync queue behaviour) are untouched.
--   - gas_readings INSERT is untouched. Gas records must never be blocked.
--   - The server-side gas-safety trigger is untouched.
--
-- Review before running:  select * from pg_policies where schemaname='public';
-- ============================================================================


-- ── 1. Section name unification ─────────────────────────────────────────────
-- Profiles: remap; Development Section has no zones left, so those accounts
-- get NULL and both apps fail closed until an admin assigns 14 South/16 North.
update public.profiles set section = '16 North' where section = 'North Section';
update public.profiles set section = '14 South' where section = 'South Section';
update public.profiles set section = null       where section = 'Development Section';

-- Data tables: remap historical rows so section dashboards stay continuous.
do $$
declare t text;
begin
  foreach t in array array['submissions','shift_handovers','near_misses',
                           'sos_alerts','ground_alerts','shift_notes',
                           'bord_cycle_updates','phase_progress']
  loop
    execute format('update public.%I set section = ''16 North'' where section = ''North Section''', t);
    execute format('update public.%I set section = ''14 South'' where section = ''South Section''', t);
  end loop;
end $$;


-- ── 2. Handover bord targeting ──────────────────────────────────────────────
alter table public.shift_handovers add column if not exists bords text;
comment on column public.shift_handovers.bords is
  'Comma-separated bords worked this shift (e.g. "16N B7, 16N Strike"). Set from the bord cycle tracker selection.';


-- ── 3. Helper functions (SECURITY DEFINER so they can read profiles without
--       tripping RLS recursion) ─────────────────────────────────────────────
create schema if not exists private;

create or replace function private.user_section() returns text
language sql stable security definer set search_path = public as
$$ select section from public.profiles where id = auth.uid() $$;

create or replace function private.user_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;

create or replace function private.user_is_global() returns boolean
language sql stable security definer set search_path = public as
$$ select coalesce((select role from public.profiles where id = auth.uid())
                   in ('she_manager','admin'), false) $$;

revoke all on function private.user_section(), private.user_role(), private.user_is_global() from public;
grant execute on function private.user_section(), private.user_role(), private.user_is_global() to authenticated;


-- ── 4. Section-fenced SELECT policies ───────────────────────────────────────
-- RLS policies are PERMISSIVE (OR'd together), so any pre-existing broad
-- SELECT policy (e.g. USING (true)) would defeat the fence. This block drops
-- every existing SELECT policy on the fenced tables, then creates the fence.
-- service_role bypasses RLS entirely, so server-side jobs are unaffected.
do $$
declare
  t text;
  pol record;
begin
  foreach t in array array['submissions','shift_handovers','near_misses',
                           'sos_alerts','ground_alerts','shift_notes',
                           'bord_cycle_updates','phase_progress']
  loop
    execute format('alter table public.%I enable row level security', t);

    for pol in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = t and cmd = 'SELECT'
    loop
      execute format('drop policy %I on public.%I', pol.policyname, t);
    end loop;

    execute format($f$
      create policy %I on public.%I for select to authenticated
      using (
        private.user_is_global()
        or (section is not null and section = private.user_section())
      )
    $f$, t || '_section_select', t);
  end loop;
end $$;

-- gas_readings has no section column (and we deliberately do not add one to
-- the write path). Fence SELECT via its parent submission / session instead.
do $$
declare pol record;
begin
  alter table public.gas_readings enable row level security;
  for pol in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'gas_readings' and cmd = 'SELECT'
  loop
    execute format('drop policy %I on public.gas_readings', pol.policyname);
  end loop;
end $$;

create policy gas_readings_section_select on public.gas_readings
for select to authenticated
using (
  private.user_is_global()
  or exists (select 1 from public.submissions s
             where s.id = gas_readings.submission_id
               and s.section = private.user_section())
  or exists (select 1 from public.phase_progress pp
             where pp.session_id = gas_readings.session_id
               and pp.section = private.user_section())
);

-- profiles: own row always readable (login depends on it); section-scoped
-- dashboard roles can list their section; global roles list everyone.
do $$
declare pol record;
begin
  alter table public.profiles enable row level security;
  for pol in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'profiles' and cmd = 'SELECT'
  loop
    execute format('drop policy %I on public.profiles', pol.policyname);
  end loop;
end $$;

create policy profiles_section_select on public.profiles
for select to authenticated
using (
  id = auth.uid()
  or private.user_is_global()
  or (private.user_role() in ('shift_boss','supervisor','safety_officer')
      and section = private.user_section())
);


-- ── 5. Post-run checks ──────────────────────────────────────────────────────
-- a) No profiles left on old names:
--      select section, count(*) from public.profiles group by 1;
-- b) Policies in place:
--      select tablename, policyname, cmd from pg_policies
--      where schemaname='public' order by tablename;
-- c) Sign in as a 16 North shift_boss and confirm 14 South records are gone
--    from every dashboard tab; as she_manager confirm everything is visible.
