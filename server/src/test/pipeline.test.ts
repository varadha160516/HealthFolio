import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { db } from '../db/db.js';
import { runLabReportPipeline } from '../pipeline/orchestrator.js';
import { matchLabel } from '../pipeline/match.js';
import { allCanonicalParameters } from '../dictionary/loader.js';
import { ensureDictionary, makeMember, makeUser, makeDocumentStub } from './testUtils.js';

interface ExtractedRow {
  raw_label_as_printed: string;
  canonical_parameter_id: string | null;
  match_tier: number | null;
  review_status: string;
  in_range_flag: string | null;
  resolved_reference_range_json: string | null;
  canonical_value: number | null;
  value_raw: string;
}

function rowsFor(documentId: string): ExtractedRow[] {
  return db.prepare('SELECT * FROM extracted_parameters WHERE document_id = ?').all(documentId) as unknown as ExtractedRow[];
}
function byLabel(rows: ExtractedRow[], label: string): ExtractedRow {
  const r = rows.find((r) => r.raw_label_as_printed === label);
  if (!r) throw new Error(`No row for label "${label}"`);
  return r;
}

describe('golden report A (Tata 1mg-style tabular CBC)', () => {
  let rows: ExtractedRow[];

  before(async () => {
    ensureDictionary();
    const memberId = makeMember('Rohan');
    const userId = makeUser(memberId);
    const docId = makeDocumentStub(memberId, userId);
    await runLabReportPipeline(docId, memberId, [{ buffer: Buffer.from('x'), mimeType: 'image/png' }], { mockFixture: 'golden_report_a' });
    rows = rowsFor(docId);
  });

  it('maps layout-varying aliases to the same canonical parameter (Section 4.1)', () => {
    assert.equal(byLabel(rows, 'HCT').canonical_parameter_id, 'hematocrit');
    assert.equal(byLabel(rows, 'Total RBC').canonical_parameter_id, 'rbc_count');
  });

  it('tier-2 fuzzy-matches "Sr. Creatinine" but always routes it to review regardless of score (Section 4.4)', () => {
    const row = byLabel(rows, 'Sr. Creatinine');
    assert.equal(row.canonical_parameter_id, 'creatinine');
    assert.equal(row.match_tier, 2);
    assert.equal(row.review_status, 'pending_review');
  });

  it('never computes an automated flag for interpretive_rule parameters (Section 4.6, clinical-safety boundary)', () => {
    assert.equal(byLabel(rows, 'RDWI').in_range_flag, 'no_flag');
    assert.equal(byLabel(rows, 'Mentzer Index').in_range_flag, 'no_flag');
  });

  it("preserves the printed reference range for this report's PDW (9-17), not the dictionary default", () => {
    const range = JSON.parse(byLabel(rows, 'PDW').resolved_reference_range_json!);
    assert.deepEqual(range, { low: 9, high: 17 });
  });

  it('routes a genuinely unmatched label to the tier-4 new-candidate path, never silently discarded or guessed (Section 4.4 point 4)', () => {
    const row = byLabel(rows, 'NLR (Neutrophil-Lymphocyte Ratio)');
    assert.equal(row.canonical_parameter_id, null);
    assert.equal(row.match_tier, null);
    assert.equal(row.review_status, 'pending_review');
    const candidate = db.prepare(`SELECT * FROM new_parameter_candidates WHERE label_as_printed = ?`).get('NLR (Neutrophil-Lymphocyte Ratio)');
    assert.ok(candidate);
  });

  it('auto-accepts confident tier-1 matches so they are graph-ready immediately', () => {
    assert.equal(byLabel(rows, 'Hemoglobin').review_status, 'auto_accepted');
    assert.equal(byLabel(rows, 'Hemoglobin').in_range_flag, 'in_range');
  });
});

describe('golden report B (PharmEasy/Docon/Thyrocare chart-infographic)', () => {
  let rows: ExtractedRow[];

  before(async () => {
    ensureDictionary();
    const memberId = makeMember('Priya');
    const userId = makeUser(memberId);
    const docId = makeDocumentStub(memberId, userId);
    await runLabReportPipeline(docId, memberId, [{ buffer: Buffer.from('x'), mimeType: 'image/png' }], { mockFixture: 'golden_report_b' });
    rows = rowsFor(docId);
  });

  it("this report's own printed PDW range (9.6-15.2) differs from report A's (9-17) and both are preserved independently", () => {
    const range = JSON.parse(byLabel(rows, 'PDW').resolved_reference_range_json!);
    assert.deepEqual(range, { low: 9.6, high: 15.2 });
  });

  it('stores qualitative results as text with no numeric flag, never coerced to a number (Section 4.6)', () => {
    const hbsag = byLabel(rows, 'HBsAg');
    assert.equal(hbsag.canonical_value, null);
    assert.equal(hbsag.value_raw, 'Non-Reactive');
    assert.equal(hbsag.in_range_flag, 'no_flag');
  });

  it('flags an out-of-range chart-infographic-derived value correctly (Vitamin D card)', () => {
    const vitD = byLabel(rows, 'Vitamin D');
    assert.equal(vitD.in_range_flag, 'out_of_range');
  });
});

describe('three-tier matching disambiguation (Section 4.4)', () => {
  before(() => ensureDictionary());

  it('does not fuzzy-confuse Absolute Neutrophil Count with Absolute Basophil Count despite shared boilerplate words', async () => {
    const dict = allCanonicalParameters();
    const anc = await matchLabel('Absolute Neutrophil Count', dict);
    const abc = await matchLabel('Absolute Basophil Count', dict);
    assert.equal(anc.canonical_parameter_id, 'anc');
    assert.equal(abc.canonical_parameter_id, 'abc');
  });

  it('tier-1 exact alias match reaches the 0.95-0.97 confidence band', async () => {
    const dict = allCanonicalParameters();
    const match = await matchLabel('HbA1c', dict);
    assert.equal(match.match_tier, 1);
    assert.ok(match.match_confidence >= 0.95);
    assert.ok(match.match_confidence <= 0.97);
  });
});
