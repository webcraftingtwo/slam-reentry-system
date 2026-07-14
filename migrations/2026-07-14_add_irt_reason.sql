-- Migration: add a dedicated IRT (Immediate Re-Entry) justification column.
--
-- IRT bypasses the mandatory 2-hour blast lapse (UNK-MIN-MIN-PRO-0002). The
-- field app now requires a written reason before IRT can be selected and stores
-- it on the submission. Until this migration is run, that reason is still
-- preserved inside submissions.overall_remarks (prefixed "IRT reason: ..."), so
-- running this migration is safe to do at any time and loses no historical data.
--
-- This migration only ADDS a nullable column. It does NOT touch Row Level
-- Security policies.

alter table public.submissions
  add column if not exists irt_reason text;

-- NOTE ON THE submit_slam_procedure RPC
-- -------------------------------------
-- The field app writes irt_reason inside submission_data. Whether the RPC
-- persists it depends on how the function is written:
--   * If it inserts via jsonb_populate_record(null::public.submissions, submission_data)
--     (or similar), the new column is populated automatically once this
--     migration has run — no function change needed.
--   * If it lists columns explicitly, add irt_reason to that column list and to
--     the VALUES/SELECT so the RPC path stores it too.
-- Regardless, the app also keeps the reason in overall_remarks and its
-- direct-insert fallback strips irt_reason on a missing-column error, so
-- submissions never fail because of this column.
