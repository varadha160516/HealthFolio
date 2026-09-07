/**
 * Stage 6 — unit conversion. Deliberately small: if the extracted unit differs from the
 * canonical unit and no rule exists here, the pipeline flags for review rather than guessing
 * (Section 4.2 stage 6). Keys are `${fromUnit}->${toUnit}` after light normalization.
 */
const CONVERSIONS: Record<string, (v: number) => number> = {
  'mmol/l->mg/dl_glucose': (v) => v * 18.0182,
  'mg/dl->mmol/l_glucose': (v) => v / 18.0182,
  'mmol/l->mg/dl_cholesterol': (v) => v * 38.67,
  'mg/dl->mmol/l_cholesterol': (v) => v / 38.67,
  'umol/l->mg/dl_creatinine': (v) => v / 88.42,
  'mg/dl->umol/l_creatinine': (v) => v * 88.42,
  'g/l->g/dl': (v) => v / 10,
  'g/dl->g/l': (v) => v * 10,
  'mmol/l->mg/dl_urea': (v) => v * 2.801,
  'mg/dl->mmol/l_urea': (v) => v / 2.801,
};

function normUnit(u: string): string {
  return u.trim().toLowerCase().replace(/\s+/g, '');
}

export interface UnitConvertResult {
  value: number;
  unit: string;
  converted: boolean;
  needsReview: boolean;
}

export function convertUnit(value: number, fromUnit: string | null, canonicalUnit: string, parameterId: string): UnitConvertResult {
  if (!fromUnit) return { value, unit: canonicalUnit, converted: false, needsReview: false };
  const from = normUnit(fromUnit);
  const to = normUnit(canonicalUnit);
  if (from === to || from === '' ) return { value, unit: canonicalUnit, converted: false, needsReview: false };

  const conceptSuffix = ['glucose', 'cholesterol', 'creatinine', 'urea'].find((c) => parameterId.includes(c));
  const key1 = conceptSuffix ? `${from}->${to}_${conceptSuffix}` : `${from}->${to}`;
  const key2 = `${from}->${to}`;
  const fn = CONVERSIONS[key1] ?? CONVERSIONS[key2];
  if (fn) return { value: fn(value), unit: canonicalUnit, converted: true, needsReview: false };

  // Unknown unit mismatch — never guess (Section 4.2 stage 6). Keep the raw value/unit and flag.
  return { value, unit: fromUnit, converted: false, needsReview: true };
}
