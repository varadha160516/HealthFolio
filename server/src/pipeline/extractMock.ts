import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { allCanonicalParameters } from '../dictionary/loader.js';
import {
  ExtractAdapter,
  ExtractedTuple,
  ExtractOptions,
  LabExtractionResult,
  PageInput,
  PrescriptionExtractionResult,
} from './types.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const goldenA: LabExtractionResult & { _comment: string; patient_name_hint: string } = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'fixtures/goldenReportA.json'), 'utf-8')
);
const goldenB: LabExtractionResult & { _comment: string; patient_name_hint: string } = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'fixtures/goldenReportB.json'), 'utf-8')
);

const LABEL_VARIANTS: Record<string, string[]> = {
  // Occasional alternate phrasing so ad-hoc mock uploads also exercise tier 1/2 variety.
  hemoglobin: ['Hemoglobin', 'Hb', 'Haemoglobin'],
  hematocrit: ['HCT', 'Hematocrit (PCV)', 'PCV'],
  rbc_count: ['RBC', 'Total RBC'],
  wbc_count: ['WBC', 'Total Leucocyte Count'],
  platelet_count: ['Platelets', 'Platelet Count'],
  creatinine: ['Sr. Creatinine', 'Creatinine'],
  sgpt_alt: ['SGPT', 'ALT'],
  sgot_ast: ['SGOT', 'AST'],
};

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}
function randRange(low: number, high: number): number {
  return Math.round((low + Math.random() * (high - low)) * 100) / 100;
}

/**
 * Deterministic mock extraction adapter — used when ANTHROPIC_API_KEY is not configured.
 * Golden fixtures (mockFixture set) replay the two reference reports exactly, for regression
 * testing. Anything else generates a plausible, randomized CBC-style panel so an arbitrary
 * upload still exercises the full pipeline end to end. This is a stand-in for the real
 * vision-LLM adapter (extractClaude.ts) — swap by setting ANTHROPIC_API_KEY, no other change needed.
 */
export const mockAdapter: ExtractAdapter = {
  async extractLabReport(_pages: PageInput[], opts?: ExtractOptions): Promise<LabExtractionResult> {
    if (opts?.mockFixture === 'golden_report_a') return stripComment(goldenA);
    if (opts?.mockFixture === 'golden_report_b') return stripComment(goldenB);
    return synthesizePanel();
  },

  async extractPrescription(_pages: PageInput[]): Promise<PrescriptionExtractionResult> {
    const meds = [
      { medicine_name: 'Metformin', dosage: '500mg', frequency: 'BD', duration: '30 days' },
      { medicine_name: 'Atorvastatin', dosage: '10mg', frequency: 'OD (night)', duration: '30 days' },
    ];
    return { diagnosis_text: 'Routine follow-up', prescribed_date: new Date().toISOString().slice(0, 10), line_items: meds };
  },
};

function stripComment(f: LabExtractionResult & { _comment?: string; patient_name_hint?: string }): LabExtractionResult {
  const { presentation_style, lab_visit_id, test_date, ordering_lab_name, tuples } = f;
  return { presentation_style, lab_visit_id, test_date, ordering_lab_name, tuples };
}

function synthesizePanel(): LabExtractionResult {
  const dictionary = allCanonicalParameters().filter((p) => p.category === 'CBC');
  const sampleSize = Math.min(dictionary.length, 8 + Math.floor(Math.random() * 5));
  const shuffled = [...dictionary].sort(() => Math.random() - 0.5).slice(0, sampleSize);

  const tuples: ExtractedTuple[] = shuffled.map((p) => {
    const variants = LABEL_VARIANTS[p.canonical_parameter_id];
    const label = variants ? pick(variants) : p.display_name;
    const low = p.typical_low ?? 0;
    const high = p.typical_high ?? low + 10;
    // ~20% chance of an out-of-range value, to exercise flagging.
    const outOfRange = Math.random() < 0.2;
    const value = outOfRange
      ? Math.random() < 0.5
        ? randRange(low - (high - low) * 0.3, low)
        : randRange(high, high + (high - low) * 0.3)
      : randRange(low, high);
    const printedRange = p.range_type === 'fixed_range' || p.range_type === 'open_upper_bound' || p.range_type === 'open_lower_bound'
      ? { low: p.typical_low, high: p.typical_high }
      : null;
    return {
      label_as_printed: label,
      value: String(value),
      unit: p.canonical_unit,
      printed_reference_range: printedRange,
      extraction_confidence: 0.85 + Math.random() * 0.13,
    };
  });

  // One genuinely novel label with no dictionary match, to exercise the new-candidate path.
  tuples.push({
    label_as_printed: 'Reticulocyte Production Index',
    value: String(randRange(0.5, 2.5)),
    unit: 'unitless',
    printed_reference_range: null,
    extraction_confidence: 0.78,
  });

  return {
    presentation_style: 'tabular',
    lab_visit_id: `MOCK-${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
    test_date: new Date().toISOString().slice(0, 10),
    ordering_lab_name: '(mock extraction — no ANTHROPIC_API_KEY configured)',
    tuples,
  };
}
