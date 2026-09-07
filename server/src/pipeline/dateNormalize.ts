const MONTHS: Record<string, string> = {
  jan: '01', feb: '02', mar: '03', apr: '04', may: '05', jun: '06',
  jul: '07', aug: '08', sep: '09', oct: '10', nov: '11', dec: '12',
};

function pad2(n: string | number): string {
  return String(n).padStart(2, '0');
}

/**
 * Normalizes a lab report's test_date to canonical YYYY-MM-DD. This matters more than it looks:
 * the extraction model was observed returning the SAME report's date as "22 Jul 2026",
 * "2026-07-22", "22 Jul, 2026", and "22 Jul 2026 06:43" across repeated reads of the identical
 * file — and every trend/overview/YoY query in this app sorts, groups, and compares test_date
 * as a plain string. Un-normalized, that silently splits one real test event into several
 * "different dates", which is exactly what broke trend graphs (Section 3.3 requires dates to be
 * a reliable sort/comparison key). Deliberately does NOT use `new Date(string)` — that parses
 * non-ISO formats via the local timezone and can shift the calendar day by one, which is a worse
 * bug than the one this is fixing. Pure string/regex parsing only.
 */
export function normalizeTestDate(raw: string | null | undefined, fallback: string): string {
  if (!raw) return fallback;
  const s = raw.trim();

  // Already ISO (optionally with a trailing time component to strip).
  const iso = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;

  // "22 Jul 2026", "22 Jul, 2026", "22 Jul 2026 06:43"
  const dMonY = s.match(/^(\d{1,2})\s+([A-Za-z]{3,})\.?,?\s+(\d{4})/);
  if (dMonY) {
    const month = MONTHS[dMonY[2].slice(0, 3).toLowerCase()];
    if (month) return `${dMonY[3]}-${month}-${pad2(dMonY[1])}`;
  }

  // "Jul 22, 2026", "Jul 22 2026"
  const monDY = s.match(/^([A-Za-z]{3,})\.?\s+(\d{1,2}),?\s+(\d{4})/);
  if (monDY) {
    const month = MONTHS[monDY[1].slice(0, 3).toLowerCase()];
    if (month) return `${monDY[3]}-${month}-${pad2(monDY[2])}`;
  }

  // "22/07/2026" or "22-07-2026" — assumes day-first (DD/MM/YYYY), the convention on the
  // Indian diagnostic-lab reports this pipeline is built around (Section 1).
  const numeric = s.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/);
  if (numeric) return `${numeric[3]}-${pad2(numeric[2])}-${pad2(numeric[1])}`;

  console.warn(`normalizeTestDate: couldn't parse "${raw}" against any known lab-report date format — falling back to ${fallback}.`);
  return fallback;
}
