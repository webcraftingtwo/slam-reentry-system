# SLAM Re-Entry System

Underground safety re-entry app for Unki Mine (Valterra Platinum).
Built against Valterra procedure UNK-MIN-MIN-PRO-0002 v6.0.
Currently in a two-section pilot phase.

## Stack
- Vanilla HTML / CSS / JS. NO build process, NO framework, NO npm.
- Supabase backend (Postgres + RLS + auth).
- This is deliberate: the app runs underground with unreliable
  connectivity, so it must stay as static single files.

## Files
- index.html — field app used by underground crews.
- dashboard.html — supervisor / SHE monitoring view.

## Hard rules — do not break these
- NEVER add external dependencies, a bundler, or a build step.
- NEVER weaken or bypass Row Level Security policies. Ask before
  touching any RLS.
- The gas-safety trigger is SERVER-SIDE on purpose so records can't
  be forged from the client. Do not move this logic client-side.
- Preserve the offline sync queue on ALL write paths: handover,
  near-miss, SOS, and the bord cycle tracker. Writes must queue when
  offline and flush when back online — never silently drop.
- Gas records must never be silently dropped (past IRT bug — stay
  alert to this).
- Always escape user input to prevent XSS.

## Features
- Handover, near-miss reporting, SOS.
- Bord Cycle Tracker: Drilling → Blasting → Lashing → Support →
  Complete → Repeat.
- Timers use wall-clock time (previously buggy — keep correct).

## Secrets
- Never put Supabase service-role keys, passwords, or any secret in
  this repo or in this file. Client uses the anon key only.

## When making changes
- This is safety-critical software. Explain what you're changing and
  why before editing anything that touches gas records, RLS, or the
  sync queue. I review all diffs before they ship.
