import { db } from '../db/db.js';

// A composite "Health Index" — inspired by the category of product ByoMap and similar
// longevity-optimization apps ship, but built from OUR OWN methodology, not theirs: the exact
// formula those products use to combine sub-scores into one number is never publicly disclosed,
// so replicating it would mean guessing and calling it "the same logic," which this app doesn't
// do (see medicationReconciliation.ts's comment for the same principle applied elsewhere).
//
// What IS reused here are six well-established, PUBLISHED clinical markers — HOMA-IR, the
// triglyceride/HDL ratio, Non-HDL cholesterol, FIB-4, the ApoB/ApoA1 ratio, and the Omega-3
// Index — standard medical literature, not any one company's proprietary IP. The last two need
// specialized panels most patients never order (added to the dictionary in v1.2.0 specifically
// for this), so they show a plain "what test is missing" message rather than a guessed value
// until a member's actual lab results include them.
//
// This is general wellness information computed from real values already on file — never a
// diagnosis, never a suggestion to act on. Published cutoffs vary slightly by source; the ones
// below are the commonly-cited consensus ranges, not a specific individual's risk threshold.

const OVERVIEW_STATUSES = "('auto_accepted','confirmed','corrected','pending_review')"; // mirrors summary.ts

export type Tier = 'optimal' | 'normal' | 'watch' | 'abnormal';

export interface HealthIndexSubScore {
  id: string;
  label: string;
  value: number | null;
  unit: string;
  tier: Tier | null;
  testDate: string | null;
  sourceParameters: string[];
  explanation: string;
  missing: boolean;
  missingReason?: string;
}

export interface HealthIndexResult {
  compositeScore: number | null;
  compositeTier: Tier | null;
  subScores: HealthIndexSubScore[];
  computedAt: string;
  methodologyNote: string;
}

interface LatestValue {
  value: number;
  testDate: string;
}

function latestValue(memberId: string, canonicalId: string): LatestValue | null {
  const row = db
    .prepare(
      `SELECT canonical_value, test_date FROM extracted_parameters
       WHERE member_id = ? AND canonical_parameter_id = ? AND review_status IN ${OVERVIEW_STATUSES} AND canonical_value IS NOT NULL
       ORDER BY test_date DESC LIMIT 1`
    )
    .get(memberId, canonicalId) as { canonical_value: number; test_date: string } | undefined;
  return row ? { value: row.canonical_value, testDate: row.test_date } : null;
}

function laterOf(a: string, b: string): string {
  return a > b ? a : b;
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Ascending cutoffs: value < optimal -> optimal, < normal -> normal, < watch -> watch, else abnormal. */
function tierFromAscendingCutoffs(value: number, optimal: number, normal: number, watch: number): Tier {
  if (value < optimal) return 'optimal';
  if (value < normal) return 'normal';
  if (value < watch) return 'watch';
  return 'abnormal';
}

/** Descending cutoffs, for markers where HIGHER is better: value >= optimal -> optimal, >= normal
 * -> normal, >= watch -> watch, else abnormal. */
function tierFromDescendingCutoffs(value: number, optimal: number, normal: number, watch: number): Tier {
  if (value >= optimal) return 'optimal';
  if (value >= normal) return 'normal';
  if (value >= watch) return 'watch';
  return 'abnormal';
}

const TIER_POINTS: Record<Tier, number> = { optimal: 100, normal: 75, watch: 50, abnormal: 25 };

export function computeHealthIndex(memberId: string, ageYears: number | null): HealthIndexResult {
  const subScores: HealthIndexSubScore[] = [];

  // 1. HOMA-IR (insulin resistance) = (fasting glucose mg/dL x fasting insulin uIU/mL) / 405
  const glucose = latestValue(memberId, 'fasting_glucose');
  const insulin = latestValue(memberId, 'fasting_insulin');
  if (glucose && insulin) {
    const homaIr = round2((glucose.value * insulin.value) / 405);
    subScores.push({
      id: 'homa_ir',
      label: 'Insulin Resistance (HOMA-IR)',
      value: homaIr,
      unit: '',
      tier: tierFromAscendingCutoffs(homaIr, 1.0, 2.0, 2.9),
      testDate: laterOf(glucose.testDate, insulin.testDate),
      sourceParameters: ['fasting_glucose', 'fasting_insulin'],
      explanation: 'Estimates insulin resistance from fasting glucose and insulin together.',
      missing: false,
    });
  } else {
    subScores.push(missingSubScore('homa_ir', 'Insulin Resistance (HOMA-IR)', ['fasting_glucose', 'fasting_insulin'], 'Needs a fasting glucose and fasting insulin result — order a diabetes panel that includes fasting insulin.'));
  }

  // 2. TG/HDL ratio = triglycerides / HDL (both mg/dL)
  const triglycerides = latestValue(memberId, 'triglycerides');
  const hdl = latestValue(memberId, 'hdl');
  if (triglycerides && hdl && hdl.value > 0) {
    const ratio = round2(triglycerides.value / hdl.value);
    subScores.push({
      id: 'tg_hdl_ratio',
      label: 'Triglyceride / HDL Ratio',
      value: ratio,
      unit: '',
      tier: tierFromAscendingCutoffs(ratio, 1.0, 2.0, 3.5),
      testDate: laterOf(triglycerides.testDate, hdl.testDate),
      sourceParameters: ['triglycerides', 'hdl'],
      explanation: 'A cardiometabolic marker — a higher ratio is associated with insulin resistance and smaller, denser LDL particles.',
      missing: false,
    });
  } else {
    subScores.push(missingSubScore('tg_hdl_ratio', 'Triglyceride / HDL Ratio', ['triglycerides', 'hdl'], 'Needs a lipid panel with triglycerides and HDL.'));
  }

  // 3. Non-HDL cholesterol — read directly if the lab reported it, else derive from total - HDL.
  let nonHdl = latestValue(memberId, 'non_hdl_cholesterol');
  const totalCholesterol = latestValue(memberId, 'total_cholesterol');
  if (!nonHdl && totalCholesterol && hdl) {
    nonHdl = { value: round2(totalCholesterol.value - hdl.value), testDate: laterOf(totalCholesterol.testDate, hdl.testDate) };
  }
  if (nonHdl) {
    subScores.push({
      id: 'non_hdl_cholesterol',
      label: 'Non-HDL Cholesterol',
      value: nonHdl.value,
      unit: 'mg/dL',
      tier: tierFromAscendingCutoffs(nonHdl.value, 130, 160, 190),
      testDate: nonHdl.testDate,
      sourceParameters: ['non_hdl_cholesterol', 'total_cholesterol', 'hdl'],
      explanation: 'All the cholesterol carried in particles linked to plaque buildup — total cholesterol minus HDL.',
      missing: false,
    });
  } else {
    subScores.push(missingSubScore('non_hdl_cholesterol', 'Non-HDL Cholesterol', ['total_cholesterol', 'hdl'], 'Needs a lipid panel with total cholesterol and HDL.'));
  }

  // 4. FIB-4 (liver fibrosis risk) = (age x AST) / (platelets[10^9/L] x sqrt(ALT))
  const ast = latestValue(memberId, 'sgot_ast');
  const alt = latestValue(memberId, 'sgpt_alt');
  const platelets = latestValue(memberId, 'platelet_count');
  if (ast && alt && platelets && ageYears != null && alt.value > 0 && platelets.value > 0) {
    const fib4 = round2((ageYears * ast.value) / (platelets.value * Math.sqrt(alt.value)));
    subScores.push({
      id: 'fib4',
      label: 'Liver Fibrosis Risk (FIB-4)',
      value: fib4,
      unit: '',
      tier: tierFromAscendingCutoffs(fib4, 1.3, 1.9, 2.67),
      testDate: laterOf(laterOf(ast.testDate, alt.testDate), platelets.testDate),
      sourceParameters: ['sgot_ast', 'sgpt_alt', 'platelet_count'],
      explanation: 'A published liver-fibrosis screening score combining age with a liver panel and platelet count.',
      missing: false,
    });
  } else {
    subScores.push(missingSubScore('fib4', 'Liver Fibrosis Risk (FIB-4)', ['sgot_ast', 'sgpt_alt', 'platelet_count'], 'Needs a liver function panel (AST, ALT) and a platelet count, plus the member\'s age.'));
  }

  // 5. ApoB/ApoA1 ratio — a published cardiovascular risk ratio (used in e.g. the INTERHEART
  // study), not a single company's invention. Needs a specialized lipoprotein panel most patients
  // never order, so it's only shown once both values are actually on file.
  const apoB = latestValue(memberId, 'apo_b');
  const apoA1 = latestValue(memberId, 'apo_a1');
  if (apoB && apoA1 && apoA1.value > 0) {
    const ratio = round2(apoB.value / apoA1.value);
    subScores.push({
      id: 'apob_apoa1_ratio',
      label: 'ApoB / ApoA1 Ratio',
      value: ratio,
      unit: '',
      tier: tierFromAscendingCutoffs(ratio, 0.4, 0.6, 0.9),
      testDate: laterOf(apoB.testDate, apoA1.testDate),
      sourceParameters: ['apo_b', 'apo_a1'],
      explanation: 'A cardiovascular risk ratio from a specialized lipoprotein panel — lower generally reflects a more favorable particle balance.',
      missing: false,
    });
  } else {
    subScores.push(missingSubScore('apob_apoa1_ratio', 'ApoB / ApoA1 Ratio', ['apo_b', 'apo_a1'], 'Needs a specialized lipoprotein panel with ApoB and ApoA1 — not part of a routine lipid panel.'));
  }

  // 6. Omega-3 Index — directly measured (% of EPA+DHA in red blood cell membranes), not derived
  // from other values. Published reference zones from HS-Omega-3 Index research (Harris & von
  // Schacky): higher is better, unlike every other sub-score here.
  const omega3 = latestValue(memberId, 'omega3_index');
  if (omega3) {
    subScores.push({
      id: 'omega3_index',
      label: 'Omega-3 Index',
      value: omega3.value,
      unit: '%',
      tier: tierFromDescendingCutoffs(omega3.value, 8, 6, 4),
      testDate: omega3.testDate,
      sourceParameters: ['omega3_index'],
      explanation: 'The share of EPA and DHA in red blood cell membranes — a specialized fatty-acid panel result, not part of routine lab work. Higher is better here.',
      missing: false,
    });
  } else {
    subScores.push(missingSubScore('omega3_index', 'Omega-3 Index', ['omega3_index'], 'Needs a specialized Omega-3 Index fatty-acid panel — not part of a routine lipid panel.'));
  }

  const available = subScores.filter((s) => !s.missing && s.tier != null);
  const compositeScore = available.length > 0 ? Math.round(available.reduce((sum, s) => sum + TIER_POINTS[s.tier!], 0) / available.length) : null;
  const compositeTier: Tier | null =
    compositeScore == null ? null : compositeScore >= 90 ? 'optimal' : compositeScore >= 70 ? 'normal' : compositeScore >= 50 ? 'watch' : 'abnormal';

  return {
    compositeScore,
    compositeTier,
    subScores,
    computedAt: new Date().toISOString(),
    methodologyNote:
      'Computed from published clinical formulas (HOMA-IR, triglyceride/HDL ratio, Non-HDL cholesterol, FIB-4, ApoB/ApoA1 ratio, Omega-3 Index) using your most recent lab values for each. The last two need a specialized panel most routine lab work doesn\'t include. This is general wellness information, not a diagnosis — talk to your doctor about what any of these mean for you.',
  };
}

function missingSubScore(id: string, label: string, sourceParameters: string[], missingReason: string): HealthIndexSubScore {
  return { id, label, value: null, unit: '', tier: null, testDate: null, sourceParameters, explanation: '', missing: true, missingReason };
}
