import { db } from './db/db.js';

// Deliberately includes pending_review here (unlike the trends/YoY VISIBLE_STATUSES in
// parameters.ts) — the member-facing review-confirmation step is switched off for now per
// product decision, so Overview shows every real reading immediately rather than gating on a
// per-value confirmation nobody was actually going to do. `rejected` and unmatched
// (canonical_parameter_id IS NULL) rows are still excluded — one means "this was wrong", the
// other has no display_name/category to render. The pipeline and review-queue machinery behind
// this is untouched, so re-gating on review_status again later is a one-line change back.
const OVERVIEW_STATUSES = "('auto_accepted','confirmed','corrected','pending_review')";

export interface OverviewParameterRow {
  canonical_parameter_id: string;
  display_name: string;
  category: string;
  canonical_value: number | null;
  canonical_unit: string | null;
  value_raw: string;
  test_date: string;
  in_range_flag: string | null;
  range_type: string;
  resolved_reference_range: { low: number | null; high: number | null; text?: string } | null;
  is_new: boolean;
}

/**
 * The latest value per canonical parameter for this member (across the whole history, not just
 * the most recent upload), bucketed for Overview's abnormal/newly-added/existing sections.
 */
export function computeOverviewParameters(memberId: string): {
  abnormal: OverviewParameterRow[];
  newlyAdded: OverviewParameterRow[];
  existing: OverviewParameterRow[];
} {
  const rows = db
    .prepare(
      `SELECT ep.canonical_parameter_id, cp.display_name, cp.category, ep.canonical_value, ep.canonical_unit,
              ep.value_raw, ep.test_date, ep.in_range_flag, ep.range_type, ep.resolved_reference_range_json,
              (SELECT MIN(ep3.test_date) FROM extracted_parameters ep3
               WHERE ep3.member_id = ep.member_id AND ep3.canonical_parameter_id = ep.canonical_parameter_id
                 AND ep3.review_status IN ${OVERVIEW_STATUSES}) AS first_test_date
       FROM extracted_parameters ep
       JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       WHERE ep.member_id = ? AND ep.review_status IN ${OVERVIEW_STATUSES}
         AND ep.test_date = (
           SELECT MAX(ep2.test_date) FROM extracted_parameters ep2
           WHERE ep2.member_id = ep.member_id AND ep2.canonical_parameter_id = ep.canonical_parameter_id
             AND ep2.review_status IN ${OVERVIEW_STATUSES}
         )
       ORDER BY cp.category, cp.display_name`
    )
    .all(memberId) as any[];

  const abnormal: OverviewParameterRow[] = [];
  const newlyAdded: OverviewParameterRow[] = [];
  const existing: OverviewParameterRow[] = [];
  const seen = new Set<string>(); // guards against a rare duplicate-test-date tie for one parameter

  for (const r of rows) {
    if (seen.has(r.canonical_parameter_id)) continue;
    seen.add(r.canonical_parameter_id);
    const row: OverviewParameterRow = {
      canonical_parameter_id: r.canonical_parameter_id,
      display_name: r.display_name,
      category: r.category,
      canonical_value: r.canonical_value,
      canonical_unit: r.canonical_unit,
      value_raw: r.value_raw,
      test_date: r.test_date,
      in_range_flag: r.in_range_flag,
      range_type: r.range_type,
      resolved_reference_range: r.resolved_reference_range_json ? JSON.parse(r.resolved_reference_range_json) : null,
      is_new: r.test_date === r.first_test_date,
    };
    if (row.in_range_flag === 'out_of_range') abnormal.push(row);
    else if (row.is_new) newlyAdded.push(row);
    else existing.push(row);
  }

  return { abnormal, newlyAdded, existing };
}

/**
 * Section 3.2 #4 — the summary card is computed live from the document library / parameter
 * series / prescription history, never separately maintained as its own record.
 */
export function computeSummaryCard(memberId: string) {
  const allergies = db.prepare('SELECT id, value FROM allergies WHERE member_id = ? ORDER BY created_at DESC').all(memberId);
  const chronicConditions = db
    .prepare('SELECT id, value FROM chronic_conditions WHERE member_id = ? ORDER BY created_at DESC')
    .all(memberId);

  const latestPrescription = db
    .prepare('SELECT id, issued_at, diagnosis_text FROM prescriptions WHERE member_id = ? ORDER BY issued_at DESC LIMIT 1')
    .get(memberId) as { id: string; issued_at: string; diagnosis_text: string | null } | undefined;
  const currentMedications = latestPrescription
    ? db.prepare('SELECT medicine_name, strength, dosage, frequency, duration FROM prescription_line_items WHERE prescription_id = ?').all(latestPrescription.id)
    : [];

  // Most recent confirmed/auto-accepted out-of-range value per canonical parameter.
  const recentFlags = db
    .prepare(
      `SELECT ep.canonical_parameter_id, cp.display_name, ep.canonical_value, ep.canonical_unit, ep.test_date, ep.in_range_flag
       FROM extracted_parameters ep
       JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       WHERE ep.member_id = ? AND ep.in_range_flag = 'out_of_range' AND ep.review_status IN ('auto_accepted','confirmed')
         AND ep.test_date = (
           SELECT MAX(ep2.test_date) FROM extracted_parameters ep2
           WHERE ep2.member_id = ep.member_id AND ep2.canonical_parameter_id = ep.canonical_parameter_id
             AND ep2.review_status IN ('auto_accepted','confirmed')
         )
       ORDER BY ep.test_date DESC
       LIMIT 10`
    )
    .all(memberId);

  return {
    allergies,
    chronicConditions,
    currentMedications,
    recentOutOfRangeFlags: recentFlags, // kept for backward compatibility; superseded by `parameters` below
    parameters: computeOverviewParameters(memberId),
  };
}
