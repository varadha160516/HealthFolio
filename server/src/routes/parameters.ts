import { Router } from 'express';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';
import { getHealthInsight } from '../pipeline/healthInsights.js';

export const parametersRouter = Router();

// Health insights agent (PRD Section 13.1) — a cached, display-only plain-language summary of
// what changed in this member's recent results, for the Overview tab.
parametersRouter.get('/parameters/health-insights', requireAuth, async (req, res) => {
  const memberId = req.query.member_id as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;
  try {
    const insight = await getHealthInsight(memberId);
    res.json(insight);
  } catch (err) {
    console.error(err);
    res.status(502).json({ error: 'Could not generate health insights right now.' });
  }
});

// Includes pending_review — the member-facing confirmation gate is switched off for now
// (see summary.ts's OVERVIEW_STATUSES), so Trends/Health Analysis must show the exact same set
// of values Overview does. Leaving this excluding pending_review while Overview included it was
// a real bug: the two screens could show different "latest" values for the same parameter,
// and a trend line could jump between dates that don't reflect the member's actual results.
const VISIBLE_STATUSES = "('auto_accepted','confirmed','corrected','pending_review')";

// Section 6.1 — trend graphs, grouped by category, only for parameters with 2+ confirmed points.
parametersRouter.get('/parameters/trends', requireAuth, (req, res) => {
  const memberId = req.query.member_id as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;

  const rows = db
    .prepare(
      `SELECT ep.*, cp.display_name, cp.category, cp.canonical_unit AS dict_unit
       FROM extracted_parameters ep
       JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       WHERE ep.member_id = ? AND ep.review_status IN ${VISIBLE_STATUSES}
       ORDER BY cp.category, cp.display_name, ep.test_date ASC`
    )
    .all(memberId) as any[];

  const byParam = new Map<string, any>();
  for (const r of rows) {
    if (!byParam.has(r.canonical_parameter_id)) {
      byParam.set(r.canonical_parameter_id, {
        canonical_parameter_id: r.canonical_parameter_id,
        display_name: r.display_name,
        category: r.category,
        range_type: r.range_type,
        unit: r.dict_unit,
        points: [],
      });
    }
    byParam.get(r.canonical_parameter_id).points.push({
      test_date: r.test_date,
      value: r.canonical_value,
      raw_value: r.value_raw,
      in_range_flag: r.in_range_flag,
      resolved_reference_range: r.resolved_reference_range_json ? JSON.parse(r.resolved_reference_range_json) : null,
    });
  }

  const numeric: any[] = [];
  const qualitative: any[] = [];
  for (const p of byParam.values()) {
    if (p.range_type === 'qualitative') {
      qualitative.push(p); // status timeline (Section 6.3) — shown regardless of point count
    } else if (p.points.length >= 2) {
      numeric.push(p); // Section 6.1 — only graph with 2+ confirmed points
    }
  }

  const grouped: Record<string, any[]> = {};
  for (const p of numeric) {
    (grouped[p.category] ??= []).push(p);
  }

  res.json({ groupedByCategory: grouped, qualitativeTimelines: qualitative });
});

// Fixed panel list for the Health Analysis filter chips — the real categories that exist in the
// parameter dictionary, not an open-ended set (matches how the chips are drawn: known, finite).
const HEALTH_ANALYSIS_CATEGORIES = ['CBC', 'Thyroid panel', 'Lipid panel', 'Diabetes panel', 'Vitamins'];

parametersRouter.get('/parameters/health-analysis/categories', requireAuth, (_req, res) => {
  res.json(HEALTH_ANALYSIS_CATEGORIES);
});

// Health Analysis redesign — same "best comparable pair" idea as /parameters/yoy, but scoped to
// one category at a time and grouped by sub_panel (RBC Profile / WBC Profile / ...) for the
// panel-style layout, plus an improved/no-change/declined summary.
parametersRouter.get('/parameters/health-analysis', requireAuth, (req, res) => {
  const memberId = req.query.member_id as string;
  const category = req.query.category as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;
  if (!category || !HEALTH_ANALYSIS_CATEGORIES.includes(category)) return res.status(400).json({ error: `category must be one of ${HEALTH_ANALYSIS_CATEGORIES.join(', ')}` });

  const rows = db
    .prepare(
      `SELECT ep.*, cp.display_name, cp.category, cp.sub_panel, cp.canonical_unit AS dict_unit
       FROM extracted_parameters ep
       JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       WHERE ep.member_id = ? AND cp.category = ? AND ep.review_status IN ${VISIBLE_STATUSES} AND ep.range_type != 'qualitative'
       ORDER BY ep.test_date DESC`
    )
    .all(memberId, category) as any[];

  const picked = pickDefaultComparisonPair(rows);
  if (!picked) return res.json({ category, document1: null, document2: null, groups: [], summary: null });
  const { older: date1, newer: date2 } = picked;

  const docFor = (date: string) =>
    db.prepare(`SELECT id, source_lab_name FROM documents WHERE member_id = ? AND test_date = ? AND document_type = 'lab_report' LIMIT 1`).get(memberId, date) as
      | { id: string; source_lab_name: string | null }
      | undefined;

  const byParamOld = new Map<string, any>();
  const byParamNew = new Map<string, any>();
  for (const r of rows) {
    if (r.test_date === date1) byParamOld.set(r.canonical_parameter_id, r);
    if (r.test_date === date2) byParamNew.set(r.canonical_parameter_id, r);
  }

  const byGroup = new Map<string, any[]>();
  let improved = 0;
  let noChange = 0;
  let declined = 0;

  for (const [paramId, newRow] of byParamNew) {
    const oldRow = byParamOld.get(paramId);
    if (!oldRow) continue;
    const resolvedRange = newRow.resolved_reference_range_json ? JSON.parse(newRow.resolved_reference_range_json) : null;
    const priorValue = oldRow.canonical_value;
    const newValue = newRow.canonical_value;

    const trend = priorValue !== null && newValue !== null ? (newValue > priorValue ? 'up' : newValue < priorValue ? 'down' : 'same') : null;

    // Improved/declined is judged by movement relative to the reference range, not raw direction —
    // "higher is better" isn't true for every parameter, but "further into range" reasonably is.
    let verdict: 'improved' | 'no_change' | 'declined' = 'no_change';
    if (priorValue !== null && newValue !== null && resolvedRange && (resolvedRange.low !== null || resolvedRange.high !== null)) {
      const wasOut = oldRow.in_range_flag === 'out_of_range';
      const isOut = newRow.in_range_flag === 'out_of_range';
      if (wasOut && !isOut) verdict = 'improved';
      else if (!wasOut && isOut) verdict = 'declined';
      else if (wasOut && isOut) {
        const dist = (v: number) => (resolvedRange.low !== null && v < resolvedRange.low ? resolvedRange.low - v : resolvedRange.high !== null && v > resolvedRange.high ? v - resolvedRange.high : 0);
        const oldDist = dist(priorValue);
        const newDist = dist(newValue);
        verdict = newDist < oldDist ? 'improved' : newDist > oldDist ? 'declined' : 'no_change';
      }
    }
    if (verdict === 'improved') improved++;
    else if (verdict === 'declined') declined++;
    else noChange++;

    const group = newRow.sub_panel ?? null;
    if (!byGroup.has(group)) byGroup.set(group, []);
    byGroup.get(group)!.push({
      canonical_parameter_id: paramId,
      display_name: newRow.display_name,
      unit: newRow.dict_unit,
      range_type: newRow.range_type,
      resolved_reference_range: resolvedRange,
      prior_value: priorValue,
      new_value: newValue,
      trend,
      in_range_flag: newRow.in_range_flag,
    });
  }

  for (const list of byGroup.values()) list.sort((a, b) => a.display_name.localeCompare(b.display_name));
  const groups = [...byGroup.entries()]
    .sort(([a], [b]) => (a === null ? 1 : b === null ? -1 : a.localeCompare(b))) // ungrouped last
    .map(([sub_panel, groupRows]) => ({ sub_panel, rows: groupRows }));

  const doc1 = docFor(date1);
  const doc2 = docFor(date2);
  res.json({
    category,
    document1: { document_id: doc1?.id ?? null, test_date: date1, source_lab_name: doc1?.source_lab_name ?? null },
    document2: { document_id: doc2?.id ?? null, test_date: date2, source_lab_name: doc2?.source_lab_name ?? null },
    groups,
    summary: { improved, no_change: noChange, declined, total: improved + noChange + declined },
  });
});

/** Prefer the two most recent dates sharing the largest number of common parameters — a genuine
 * repeat annual panel — rather than simply the two most recent dates overall (Section 6.2). */
function pickDefaultComparisonPair(rows: any[]): { older: string; newer: string } | null {
  const paramsByDate = new Map<string, Set<string>>();
  for (const r of rows) {
    if (!paramsByDate.has(r.test_date)) paramsByDate.set(r.test_date, new Set());
    paramsByDate.get(r.test_date)!.add(r.canonical_parameter_id);
  }
  const dates = [...paramsByDate.keys()].sort().reverse().slice(0, 8); // bound the search to the most recent dates
  if (dates.length < 2) return null;

  let best: { older: string; newer: string; overlap: number } | null = null;
  for (let i = 0; i < dates.length; i++) {
    for (let j = i + 1; j < dates.length; j++) {
      const a = paramsByDate.get(dates[i])!;
      const b = paramsByDate.get(dates[j])!;
      let overlap = 0;
      for (const p of a) if (b.has(p)) overlap++;
      if (!best || overlap > best.overlap || (overlap === best.overlap && dates[i] > best.newer)) {
        best = { newer: dates[i], older: dates[j], overlap };
      }
    }
  }
  return best;
}

// Vitals tab — the latest reading per Vitals-category parameter (BP, pulse, temperature, SpO2,
// weight, ...). Reuses the same canonical "Vitals" category the dictionary already defines and
// the same visible-status filter every other results view uses — this is a dedicated, more
// prominent home for data that was previously only shown buried in the Profile tab.
parametersRouter.get('/parameters/vitals', requireAuth, (req, res) => {
  const memberId = req.query.member_id as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;

  const rows = db
    .prepare(
      `SELECT ep.canonical_parameter_id, cp.display_name, ep.canonical_value, ep.canonical_unit, ep.value_raw, ep.test_date, ep.in_range_flag, ep.range_type, ep.resolved_reference_range_json
       FROM extracted_parameters ep
       JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       WHERE ep.member_id = ? AND cp.category = 'Vitals' AND ep.review_status IN ${VISIBLE_STATUSES}
         AND ep.test_date = (
           SELECT MAX(ep2.test_date) FROM extracted_parameters ep2
           WHERE ep2.member_id = ep.member_id AND ep2.canonical_parameter_id = ep.canonical_parameter_id
             AND ep2.review_status IN ${VISIBLE_STATUSES}
         )
       ORDER BY cp.display_name`
    )
    .all(memberId) as any[];

  res.json(
    rows.map((r) => ({
      canonical_parameter_id: r.canonical_parameter_id,
      display_name: r.display_name,
      canonical_value: r.canonical_value,
      canonical_unit: r.canonical_unit,
      value_raw: r.value_raw,
      test_date: r.test_date,
      in_range_flag: r.in_range_flag,
      range_type: r.range_type,
      resolved_reference_range: r.resolved_reference_range_json ? JSON.parse(r.resolved_reference_range_json) : null,
    }))
  );
});

// Health Timeline tab — every test date the member has results for, newest first, with which
// parameters were tested that day and how each one moved versus its own previous reading. Purely
// deterministic date-math + a running "last value per parameter" scan — no model call, same
// reasoning as the care-coordinator agent's date-math-only scope.
parametersRouter.get('/parameters/health-timeline', requireAuth, (req, res) => {
  const memberId = req.query.member_id as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;

  const rows = db
    .prepare(
      `SELECT ep.canonical_parameter_id, cp.display_name, cp.category, ep.canonical_value, ep.canonical_unit, ep.value_raw, ep.test_date, ep.in_range_flag
       FROM extracted_parameters ep
       JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       WHERE ep.member_id = ? AND ep.review_status IN ${VISIBLE_STATUSES}
       ORDER BY ep.canonical_parameter_id, ep.test_date ASC`
    )
    .all(memberId) as any[];

  // One pass in chronological order per parameter, tracking the previous value seen so each row
  // can carry its own delta against ITS last reading — never a diagnosis, just up/down/same/new.
  const lastValueByParam = new Map<string, number>();
  const withDelta = rows.map((r) => {
    const prev = lastValueByParam.get(r.canonical_parameter_id);
    let delta: 'up' | 'down' | 'same' | 'new' = 'new';
    if (r.canonical_value != null) {
      if (prev !== undefined) delta = r.canonical_value > prev ? 'up' : r.canonical_value < prev ? 'down' : 'same';
      lastValueByParam.set(r.canonical_parameter_id, r.canonical_value);
    }
    return { ...r, delta };
  });

  const byDate = new Map<string, any[]>();
  for (const r of withDelta) {
    if (!byDate.has(r.test_date)) byDate.set(r.test_date, []);
    byDate.get(r.test_date)!.push(r);
  }

  const timeline = [...byDate.keys()]
    .sort()
    .reverse()
    .map((test_date) => ({
      test_date,
      parameters: byDate.get(test_date)!.map((r) => ({
        display_name: r.display_name,
        category: r.category,
        value: r.canonical_value != null ? `${r.canonical_value}${r.canonical_unit ? ' ' + r.canonical_unit : ''}` : r.value_raw,
        delta: r.canonical_value != null ? r.delta : null,
        in_range_flag: r.in_range_flag,
      })),
    }));

  res.json({ timeline });
});

// Member review queue (Section 4.5) — pending_review items, editable/confirmable by the member.
parametersRouter.get('/parameters/review-queue', requireAuth, (req, res) => {
  const memberId = req.query.member_id as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;
  const rows = db
    .prepare(
      `SELECT ep.*, cp.display_name, cp.category
       FROM extracted_parameters ep
       LEFT JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       WHERE ep.member_id = ? AND ep.review_status = 'pending_review'
       ORDER BY ep.created_at DESC`
    )
    .all(memberId);
  res.json(rows);
});

parametersRouter.post('/parameters/:id/confirm', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM extracted_parameters WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!row) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, row.member_id)) return;
  db.prepare(`UPDATE extracted_parameters SET review_status = 'confirmed', updated_at = ? WHERE id = ?`).run(now(), req.params.id);
  res.json({ ok: true });
});

parametersRouter.post('/parameters/:id/correct', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM extracted_parameters WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!row) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, row.member_id)) return;
  const { canonical_value, canonical_unit } = req.body ?? {};
  db.prepare(
    `UPDATE extracted_parameters SET review_status = 'corrected', canonical_value = COALESCE(?, canonical_value), canonical_unit = COALESCE(?, canonical_unit), updated_at = ? WHERE id = ?`
  ).run(canonical_value ?? null, canonical_unit ?? null, now(), req.params.id);
  res.json({ ok: true });
});

parametersRouter.post('/parameters/:id/reject', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM extracted_parameters WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!row) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, row.member_id)) return;
  db.prepare(`UPDATE extracted_parameters SET review_status = 'rejected', updated_at = ? WHERE id = ?`).run(now(), req.params.id);
  res.json({ ok: true });
});
