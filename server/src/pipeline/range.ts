import { CanonicalParameterRow } from '../dictionary/loader.js';
import { PrintedRange } from './types.js';

export interface ResolvedRange {
  range_type: string;
  resolved: PrintedRange | null; // the range actually used for flagging — printed wins over dictionary default (Section 4.6)
  flag: 'in_range' | 'out_of_range' | 'no_flag';
}

/**
 * Section 4.6 — five range_type behaviours. Whenever the source document printed its own
 * range, that range wins for THIS result; the dictionary's typical_reference_range is only
 * a fallback for when the report omitted one (and a bound for plausibility validation).
 */
export function resolveRange(
  param: CanonicalParameterRow,
  numericValue: number | null,
  printedRange: PrintedRange | null
): ResolvedRange {
  const range_type = param.range_type;

  if (range_type === 'interpretive_rule' || range_type === 'qualitative') {
    // Clinical-safety boundary (Section 4.6): never auto-compute a flag for these.
    return { range_type, resolved: printedRange, flag: 'no_flag' };
  }

  if (numericValue === null) {
    return { range_type, resolved: printedRange, flag: 'no_flag' };
  }

  if (range_type === 'none') {
    return { range_type, resolved: null, flag: 'no_flag' };
  }

  if (range_type === 'open_upper_bound') {
    const low = printedRange?.low ?? param.typical_low;
    if (low === null || low === undefined) return { range_type, resolved: null, flag: 'no_flag' };
    const resolved: PrintedRange = { low, high: null };
    return { range_type, resolved, flag: numericValue < low ? 'out_of_range' : 'in_range' };
  }

  if (range_type === 'open_lower_bound') {
    const low = printedRange?.low ?? param.typical_low;
    if (low === null || low === undefined) return { range_type, resolved: null, flag: 'no_flag' };
    const resolved: PrintedRange = { low, high: null };
    return { range_type, resolved, flag: numericValue < low ? 'out_of_range' : 'in_range' };
  }

  // fixed_range — the normal case.
  const low = printedRange?.low ?? param.typical_low;
  const high = printedRange?.high ?? param.typical_high;
  if (low === null || low === undefined || high === null || high === undefined) {
    return { range_type, resolved: printedRange, flag: 'no_flag' };
  }
  const resolved: PrintedRange = { low, high };
  const inRange = numericValue >= low && numericValue <= high;
  return { range_type, resolved, flag: inRange ? 'in_range' : 'out_of_range' };
}

/** Stage 9 — plausibility validation, independent of match tier (catches OCR digit errors). */
export function isPlausible(param: CanonicalParameterRow, numericValue: number | null): boolean {
  if (numericValue === null) return true; // qualitative values validated separately (not numeric)
  if (param.plausible_low === null && param.plausible_high === null) return true;
  if (param.plausible_low !== null && numericValue < param.plausible_low) return false;
  if (param.plausible_high !== null && numericValue > param.plausible_high) return false;
  return true;
}

export function parseNumeric(value: string): number | null {
  const cleaned = value.trim().replace(/,/g, '');
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : null;
}
