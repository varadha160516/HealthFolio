import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { allCanonicalParameters, currentDictionaryVersion } from '../dictionary/loader.js';
import { getExtractAdapter } from './extract.js';
import { matchLabel } from './match.js';
import { resolveRange, isPlausible, parseNumeric } from './range.js';
import { convertUnit } from './units.js';
import { normalizeTestDate } from './dateNormalize.js';
import { ExtractOptions, PageInput } from './types.js';

const AUTO_ACCEPT_THRESHOLD = 0.85;

export interface PipelineRunResult {
  documentId: string;
  extractedCount: number;
  autoAcceptedCount: number;
  pendingReviewCount: number;
  newCandidateCount: number;
}

/**
 * Runs pipeline stages 4-11 (Section 4.2) for a lab_report document whose pages have already
 * been intake-stored (stage 1, done by the upload route). Stage 2 (page grouping) is implicit:
 * all pages of one upload batch are sent to the extractor in a single call, and it returns one
 * shared lab_visit_id/test_date for the logical document.
 */
export async function runLabReportPipeline(
  documentId: string,
  memberId: string,
  pages: PageInput[],
  opts?: ExtractOptions
): Promise<PipelineRunResult> {
  const dictionary = allCanonicalParameters();
  const dictionaryVersion = currentDictionaryVersion();
  const adapter = getExtractAdapter();

  // Stage 4 — extract (vision model reads the rendered pages; noise already filtered per prompt/mock).
  const extraction = await adapter.extractLabReport(pages, opts);

  // Normalize to YYYY-MM-DD before this touches anything else — every trend/overview/YoY query
  // sorts and groups by test_date as a plain string, so an unnormalized date (the model has been
  // observed returning the same report's date as "22 Jul 2026", "2026-07-22", and "22 Jul, 2026"
  // across different reads) silently splits one real test event into several fake "different
  // dates". See dateNormalize.ts.
  const testDate = normalizeTestDate(extraction.test_date, new Date().toISOString().slice(0, 10));

  db.prepare(
    `UPDATE documents SET presentation_style = ?, lab_visit_id = ?, test_date = ?, source_lab_name = ?, status = 'parsed' WHERE id = ?`
  ).run(extraction.presentation_style, extraction.lab_visit_id, testDate, extraction.ordering_lab_name, documentId);

  // Stage 5 — normalize / three-tier match. Done as an async pre-pass (tier 3 may call the API)
  // since better-sqlite3 transactions below must run synchronously.
  const matches = await Promise.all(extraction.tuples.map((t) => matchLabel(t.label_as_printed, dictionary)));

  let autoAccepted = 0;
  let pendingReview = 0;
  let newCandidates = 0;

  const insertParam = db.prepare(`
    INSERT INTO extracted_parameters
      (id, document_id, member_id, canonical_parameter_id, raw_label_as_printed, value_raw, unit_raw,
       canonical_value, canonical_unit, printed_reference_range_json, resolved_reference_range_json, range_type,
       test_date, match_tier, match_confidence, extraction_confidence, confidence_score, review_status,
       in_range_flag, dictionary_version_at_parse_time, created_at, updated_at)
    VALUES (@id, @document_id, @member_id, @canonical_parameter_id, @raw_label_as_printed, @value_raw, @unit_raw,
       @canonical_value, @canonical_unit, @printed_reference_range_json, @resolved_reference_range_json, @range_type,
       @test_date, @match_tier, @match_confidence, @extraction_confidence, @confidence_score, @review_status,
       @in_range_flag, @dictionary_version_at_parse_time, @created_at, @updated_at)
  `);
  const insertCandidate = db.prepare(`
    INSERT INTO new_parameter_candidates (id, member_id, document_id, extracted_parameter_id, label_as_printed, value, unit, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)
  `);

  const tx = db.transaction(() => {
    extraction.tuples.forEach((tuple, i) => {
      const match = matches[i];
      const param = match.canonical_parameter_id ? dictionary.find((p) => p.canonical_parameter_id === match.canonical_parameter_id) : undefined;

      const paramId = uuid();
      const nowTs = now();

      if (!param) {
        // Tier 4 — no match at any tier: dictionary-governance candidate, never silently stored/discarded.
        insertParam.run({
          id: paramId,
          document_id: documentId,
          member_id: memberId,
          canonical_parameter_id: null,
          raw_label_as_printed: tuple.label_as_printed,
          value_raw: tuple.value,
          unit_raw: tuple.unit,
          canonical_value: null,
          canonical_unit: null,
          printed_reference_range_json: tuple.printed_reference_range ? JSON.stringify(tuple.printed_reference_range) : null,
          resolved_reference_range_json: null,
          range_type: null,
          test_date: testDate,
          match_tier: null,
          match_confidence: 0,
          extraction_confidence: tuple.extraction_confidence,
          confidence_score: 0,
          review_status: 'pending_review',
          in_range_flag: null,
          dictionary_version_at_parse_time: dictionaryVersion,
          created_at: nowTs,
          updated_at: nowTs,
        });
        insertCandidate.run(uuid(), memberId, documentId, paramId, tuple.label_as_printed, tuple.value, tuple.unit, nowTs);
        newCandidates++;
        pendingReview++;
        return;
      }

      // Stage 6 — unit convert.
      let numericValue = parseNumeric(tuple.value);
      let unitResult = { value: numericValue ?? 0, unit: tuple.unit ?? param.canonical_unit, converted: false, needsReview: false };
      const isQualitative = param.range_type === 'qualitative' || numericValue === null;
      if (!isQualitative && numericValue !== null) {
        unitResult = convertUnit(numericValue, tuple.unit, param.canonical_unit, param.canonical_parameter_id);
        numericValue = unitResult.value;
      }

      // Stage 7 — range resolution (printed range always wins — Section 4.6).
      const resolved = resolveRange(param, isQualitative ? null : numericValue, tuple.printed_reference_range ?? null);

      // Stage 9 — plausibility validation (independent of match tier).
      const plausible = isQualitative ? true : isPlausible(param, numericValue);

      // Stage 8 — confidence score.
      const combined = 0.65 * match.match_confidence + 0.35 * tuple.extraction_confidence;

      let reviewStatus: 'auto_accepted' | 'pending_review' = 'pending_review';
      if (match.match_tier === 1 && combined >= AUTO_ACCEPT_THRESHOLD && plausible && !unitResult.needsReview) {
        reviewStatus = 'auto_accepted';
        autoAccepted++;
      } else {
        pendingReview++;
      }

      insertParam.run({
        id: paramId,
        document_id: documentId,
        member_id: memberId,
        canonical_parameter_id: param.canonical_parameter_id,
        raw_label_as_printed: tuple.label_as_printed,
        value_raw: tuple.value,
        unit_raw: tuple.unit,
        canonical_value: isQualitative ? null : numericValue,
        canonical_unit: isQualitative ? param.canonical_unit : unitResult.unit,
        printed_reference_range_json: tuple.printed_reference_range ? JSON.stringify(tuple.printed_reference_range) : null,
        resolved_reference_range_json: resolved.resolved ? JSON.stringify(resolved.resolved) : null,
        range_type: param.range_type,
        test_date: testDate,
        match_tier: match.match_tier,
        match_confidence: match.match_confidence,
        extraction_confidence: tuple.extraction_confidence,
        confidence_score: combined,
        review_status: reviewStatus,
        in_range_flag: isQualitative ? 'no_flag' : resolved.flag,
        dictionary_version_at_parse_time: dictionaryVersion,
        created_at: nowTs,
        updated_at: nowTs,
      });

    });
  });
  tx();

  return {
    documentId,
    extractedCount: extraction.tuples.length,
    autoAcceptedCount: autoAccepted,
    pendingReviewCount: pendingReview,
    newCandidateCount: newCandidates,
  };
}

/**
 * Member-uploaded prescription photos still go through OCR (Section 3.4's first bullet) —
 * unlike provider-issued e-prescriptions (Section 8.1 step 6), which are structured input from
 * a verified in-app action and skip this pipeline entirely (see routes/appointments.ts).
 */
export async function runPrescriptionPipeline(documentId: string, memberId: string, pages: PageInput[]): Promise<{ prescriptionId: string }> {
  const adapter = getExtractAdapter();
  const extraction = await adapter.extractPrescription(pages);
  const nowTs = now();

  const prescribedDate = extraction.prescribed_date ? normalizeTestDate(extraction.prescribed_date, now().slice(0, 10)) : null;
  db.prepare(`UPDATE documents SET status = 'parsed', test_date = ? WHERE id = ?`).run(prescribedDate, documentId);

  const prescriptionId = uuid();
  db.prepare(
    `INSERT INTO prescriptions (id, appointment_id, provider_id, member_id, document_id, diagnosis_text, notes, issued_at) VALUES (?, NULL, NULL, ?, ?, ?, NULL, ?)`
  ).run(prescriptionId, memberId, documentId, extraction.diagnosis_text, nowTs);

  const insertLine = db.prepare(
    `INSERT INTO prescription_line_items (id, prescription_id, medicine_name, strength, dosage, frequency, duration, instructions) VALUES (?, ?, ?, NULL, ?, ?, ?, NULL)`
  );
  for (const item of extraction.line_items) {
    insertLine.run(uuid(), prescriptionId, item.medicine_name, item.dosage, item.frequency, item.duration);
  }

  return { prescriptionId };
}
