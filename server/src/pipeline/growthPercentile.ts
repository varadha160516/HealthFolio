import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Growth percentiles (weight-for-age, height-for-age, BMI-for-age) — manual Vitals entry
// feature. These are computed against the CDC 2000 growth chart LMS reference tables
// (National Center for Health Statistics), downloaded verbatim from
// https://www.cdc.gov/growthcharts/data/zscore/*.csv and bundled unmodified under
// server/src/growth-data/. This is real published reference data, not a model guess — unlike
// the dictionary curation agent's drift check (server/src/pipeline/dictionaryCuration.ts), which
// is explicitly knowledge-based because no live reference-range source is wired in; here, one is.
// The LMS→percentile formula below (Cole's LMS method) is the standard method CDC's own
// growth-chart tools use.

interface LmsRow {
  sex: 1 | 2; // CDC convention: 1 = male, 2 = female
  agemos: number;
  L: number;
  M: number;
  S: number;
}

function loadLmsTable(filename: string): LmsRow[] {
  const raw = fs.readFileSync(path.join(__dirname, '../growth-data', filename), 'utf-8');
  const lines = raw
    .replace(/^﻿/, '')
    .split('\n')
    .map((l) => l.replace(/\r$/, ''))
    .filter((l) => l.length > 0);
  return lines.slice(1).map((line) => {
    const parts = line.split(',');
    return { sex: Number(parts[0]) as 1 | 2, agemos: Number(parts[1]), L: Number(parts[2]), M: Number(parts[3]), S: Number(parts[4]) };
  });
}

const wtage = loadLmsTable('wtage.csv'); // weight-for-age, 2-20y
const wtageinf = loadLmsTable('wtageinf.csv'); // weight-for-age, birth-36mo
const statage = loadLmsTable('statage.csv'); // stature-for-age, 2-20y
const lenageinf = loadLmsTable('lenageinf.csv'); // recumbent length-for-age, birth-36mo
const bmiagerev = loadLmsTable('bmiagerev.csv'); // BMI-for-age, 2-20y — CDC publishes no infant BMI-for-age chart, so there's no infant counterpart to fall back to.

const CDC_MAX_AGE_MONTHS = 240; // CDC 2000 charts cover birth to 20 years — nothing beyond.
const INFANT_CUTOFF_MONTHS = 24; // Below this, use the birth-36mo tables; at/above, the 2-20y tables (the two series' own coverage boundary).

function interpolateLms(table: LmsRow[], sex: 1 | 2, agemos: number): LmsRow | null {
  const rows = table.filter((r) => r.sex === sex).sort((a, b) => a.agemos - b.agemos);
  if (rows.length === 0) return null;
  if (agemos <= rows[0].agemos) return rows[0];
  if (agemos >= rows[rows.length - 1].agemos) return rows[rows.length - 1];
  for (let i = 0; i < rows.length - 1; i++) {
    const a = rows[i];
    const b = rows[i + 1];
    if (agemos >= a.agemos && agemos <= b.agemos) {
      const t = b.agemos === a.agemos ? 0 : (agemos - a.agemos) / (b.agemos - a.agemos);
      return { sex, agemos, L: a.L + t * (b.L - a.L), M: a.M + t * (b.M - a.M), S: a.S + t * (b.S - a.S) };
    }
  }
  return rows[rows.length - 1];
}

/** Abramowitz & Stegun 7.1.26 — a standard, widely used error-function approximation (max error
 * ~1.5e-7), used here only to turn a Z-score into a normal-distribution percentile. */
function erf(x: number): number {
  const sign = x < 0 ? -1 : 1;
  const ax = Math.abs(x);
  const a1 = 0.254829592,
    a2 = -0.284496736,
    a3 = 1.421413741,
    a4 = -1.453152027,
    a5 = 1.061405429,
    p = 0.3275911;
  const t = 1 / (1 + p * ax);
  const y = 1 - (((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t) * Math.exp(-ax * ax);
  return sign * y;
}

function normalCdf(z: number): number {
  return 0.5 * (1 + erf(z / Math.SQRT2));
}

/** Cole's LMS method — the standard CDC/WHO conversion from a measurement to a percentile given
 * the reference population's L (skewness), M (median), S (coefficient of variation) at that
 * age/sex. Returns null only if the table has no usable row (should not happen once age is
 * clamped to the table's own range by interpolateLms). */
function lmsPercentile(table: LmsRow[], sexCode: 1 | 2, agemos: number, x: number): number | null {
  const lms = interpolateLms(table, sexCode, agemos);
  if (!lms || lms.M === 0) return null;
  const z = lms.L !== 0 ? (Math.pow(x / lms.M, lms.L) - 1) / (lms.L * lms.S) : Math.log(x / lms.M) / lms.S;
  return Math.round(normalCdf(z) * 1000) / 10; // one decimal place
}

function computeBmi(weightKg: number, heightCm: number): number {
  const heightM = heightCm / 100;
  return Math.round((weightKg / (heightM * heightM)) * 10) / 10;
}

export interface GrowthPercentileInput {
  sex: 'male' | 'female';
  ageMonths: number;
  weightKg: number | null;
  heightCm: number | null;
}

export interface GrowthPercentileResult {
  ageMonths: number;
  bmi: number | null;
  weightForAgePercentile: number | null;
  heightForAgePercentile: number | null;
  bmiForAgePercentile: number | null;
  note: string | null;
}

/** Computes weight-for-age, height-for-age, and BMI-for-age percentiles from a manual Vitals
 * entry's weight/height and the member's sex/age. Never throws — an out-of-range age or missing
 * sex just comes back with nulls and an explanatory note, since this is a display-only
 * convenience, not something any other part of the app depends on being present. */
export function computeGrowthPercentiles(input: GrowthPercentileInput): GrowthPercentileResult {
  const { sex, ageMonths, weightKg, heightCm } = input;
  const bmi = weightKg != null && heightCm != null && heightCm > 0 ? computeBmi(weightKg, heightCm) : null;

  if (ageMonths < 0 || ageMonths > CDC_MAX_AGE_MONTHS) {
    return {
      ageMonths,
      bmi,
      weightForAgePercentile: null,
      heightForAgePercentile: null,
      bmiForAgePercentile: null,
      note: 'Growth percentiles (CDC 2000 growth charts) cover birth to 20 years only — not shown for this member.',
    };
  }

  const sexCode: 1 | 2 = sex === 'male' ? 1 : 2;
  const useInfantTables = ageMonths < INFANT_CUTOFF_MONTHS;
  const weightTable = useInfantTables ? wtageinf : wtage;
  const heightTable = useInfantTables ? lenageinf : statage;

  const weightForAgePercentile = weightKg != null ? lmsPercentile(weightTable, sexCode, ageMonths, weightKg) : null;
  const heightForAgePercentile = heightCm != null ? lmsPercentile(heightTable, sexCode, ageMonths, heightCm) : null;
  const bmiForAgePercentile = bmi != null && !useInfantTables ? lmsPercentile(bmiagerev, sexCode, ageMonths, bmi) : null;

  return {
    ageMonths,
    bmi,
    weightForAgePercentile,
    heightForAgePercentile,
    bmiForAgePercentile,
    note: useInfantTables && bmi != null ? 'BMI-for-age percentile is only defined from age 2 onward — not shown yet for this member.' : null,
  };
}
