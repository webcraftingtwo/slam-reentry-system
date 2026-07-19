/* ============================================================================
   SLAM Re-Entry — crew names & shift labels (shared by index.html + dashboard)
   ----------------------------------------------------------------------------
   THE one place to edit crew names. Keys are the canonical section values
   stored in the database and enforced by RLS — never change the keys, only
   the display names. Loaded as a plain script (no build step) by both pages
   and precached by sw.js for offline use.
   ========================================================================== */

const CREW_NAMES = {
  '14 South': 'Challengers',
  '16 North': 'Pioneers',
};

// Display name for a section: "Challengers", falling back to the raw value.
function crewName(section){
  return CREW_NAMES[section] || section || '';
}

// "Challengers (14 South)" — used where both identities help.
function crewSectionLabel(section){
  if(!section) return '';
  return CREW_NAMES[section] ? CREW_NAMES[section] + ' (' + section + ')' : section;
}

// Shift display: new records store 'A'/'B'/'C' → "SHIFT A";
// legacy records store 'day'/'night'/'afternoon' → "DAY SHIFT".
function shiftLabel(shift){
  if(!shift) return '';
  return /^[abc]$/i.test(shift)
    ? 'SHIFT ' + shift.toUpperCase()
    : shift.toUpperCase() + ' SHIFT';
}
