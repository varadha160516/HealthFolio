import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { currentDictionaryVersion } from '../dictionary/loader.js';
import { draftCandidateResolution, scanForDrift } from '../pipeline/dictionaryCuration.js';

export const adminRouter = Router();
// Scoped to '/admin/*' — without this path prefix, `.use()` would fire for EVERY request
// that reaches this router (all routers share the '/api' mount point in app.ts), rejecting
// non-admin roles on completely unrelated endpoints like /api/appointments/*.
adminRouter.use('/admin', requireAuth, requireRole('platform_admin'));

// Section 5.3 — the dictionary-governance queue. Every unmatched extracted label lands here.
adminRouter.get('/admin/candidates', (req, res) => {
  const status = (req.query.status as string) || 'pending';
  const rows = db.prepare('SELECT * FROM new_parameter_candidates WHERE status = ? ORDER BY created_at DESC').all(status);
  res.json(rows);
});

adminRouter.get('/admin/candidates/:id', (req, res) => {
  const row = db.prepare('SELECT * FROM new_parameter_candidates WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Not found' });
  res.json(row);
});

// Dictionary curation agent (Roadmap Section 2.9b) — a draft the admin can accept or override,
// computed on demand (not eagerly for the whole queue) since it may call the model.
adminRouter.get('/admin/candidates/:id/draft', async (req, res) => {
  const row = db.prepare('SELECT * FROM new_parameter_candidates WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Not found' });
  try {
    const draft = await draftCandidateResolution(req.params.id);
    res.json(draft);
  } catch (err) {
    console.error('Candidate draft failed:', err);
    res.status(500).json({ error: 'Draft failed' });
  }
});

interface CandidateRow {
  id: string;
  member_id: string;
  document_id: string;
  extracted_parameter_id: string | null;
  label_as_printed: string;
  value: string | null;
  unit: string | null;
  status: string;
}

/**
 * Resolves a candidate one of three ways (Section 5.3): a brand-new canonical parameter, a new
 * alias of an existing one (the common case), or a lab-specific derived index that requires
 * clinical sign-off before any automated interpretation is attached (Section 4.6).
 */
adminRouter.post('/admin/candidates/:id/resolve', (req, res) => {
  const candidate = db.prepare('SELECT * FROM new_parameter_candidates WHERE id = ?').get(req.params.id) as CandidateRow | undefined;
  if (!candidate) return res.status(404).json({ error: 'Not found' });
  if (candidate.status !== 'pending') return res.status(409).json({ error: 'Candidate already resolved' });

  const { resolution } = req.body ?? {};
  const dictionaryVersion = currentDictionaryVersion();
  const nowTs = now();

  if (resolution === 'new_param') {
    const { canonical_parameter_id, display_name, category, canonical_unit, range_type, typical_low, typical_high } = req.body;
    if (!canonical_parameter_id || !display_name || !category || !canonical_unit || !range_type) {
      return res.status(400).json({ error: 'canonical_parameter_id, display_name, category, canonical_unit, range_type are required' });
    }
    db.prepare(
      `INSERT INTO canonical_parameters (canonical_parameter_id, display_name, category, canonical_unit, range_type, typical_low, typical_high, aliases_json, plausible_low, plausible_high, dictionary_version, loinc_code)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, NULL)`
    ).run(canonical_parameter_id, display_name, category, canonical_unit, range_type, typical_low ?? null, typical_high ?? null, JSON.stringify([candidate.label_as_printed]), dictionaryVersion);

    applyResolutionToExtractedParameter(candidate, canonical_parameter_id, 1, dictionaryVersion);
    db.prepare(`UPDATE new_parameter_candidates SET status = 'resolved_as_new_param', resolved_canonical_parameter_id = ? WHERE id = ?`).run(canonical_parameter_id, candidate.id);
    return res.json({ ok: true, canonical_parameter_id });
  }

  if (resolution === 'alias') {
    const { canonical_parameter_id } = req.body;
    if (!canonical_parameter_id) return res.status(400).json({ error: 'canonical_parameter_id is required' });
    const param = db.prepare('SELECT aliases_json FROM canonical_parameters WHERE canonical_parameter_id = ?').get(canonical_parameter_id) as
      | { aliases_json: string }
      | undefined;
    if (!param) return res.status(404).json({ error: 'Canonical parameter not found' });
    const aliases: string[] = JSON.parse(param.aliases_json);
    if (!aliases.some((a) => a.toLowerCase() === candidate.label_as_printed.toLowerCase())) {
      aliases.push(candidate.label_as_printed);
      db.prepare('UPDATE canonical_parameters SET aliases_json = ? WHERE canonical_parameter_id = ?').run(JSON.stringify(aliases), canonical_parameter_id);
    }
    applyResolutionToExtractedParameter(candidate, canonical_parameter_id, 1, dictionaryVersion);
    db.prepare(`UPDATE new_parameter_candidates SET status = 'resolved_as_alias', resolved_canonical_parameter_id = ? WHERE id = ?`).run(canonical_parameter_id, candidate.id);
    return res.json({ ok: true, canonical_parameter_id });
  }

  if (resolution === 'interpretive_index') {
    const { canonical_parameter_id, display_name, category } = req.body;
    if (!canonical_parameter_id || !display_name || !category) {
      return res.status(400).json({ error: 'canonical_parameter_id, display_name, category are required' });
    }
    db.prepare(
      `INSERT INTO canonical_parameters (canonical_parameter_id, display_name, category, canonical_unit, range_type, typical_low, typical_high, aliases_json, plausible_low, plausible_high, dictionary_version, loinc_code)
       VALUES (?, ?, ?, 'unitless', 'interpretive_rule', NULL, NULL, ?, NULL, NULL, ?, NULL)`
    ).run(canonical_parameter_id, display_name, category, JSON.stringify([candidate.label_as_printed]), dictionaryVersion);

    applyResolutionToExtractedParameter(candidate, canonical_parameter_id, 1, dictionaryVersion, 'no_flag');
    db.prepare(`UPDATE new_parameter_candidates SET status = 'resolved_as_interpretive_index', resolved_canonical_parameter_id = ? WHERE id = ?`).run(canonical_parameter_id, candidate.id);
    return res.json({ ok: true, canonical_parameter_id });
  }

  return res.status(400).json({ error: 'resolution must be one of new_param | alias | interpretive_index' });
});

function applyResolutionToExtractedParameter(
  candidate: CandidateRow,
  canonicalParameterId: string,
  matchTier: number,
  dictionaryVersion: string,
  forceFlag?: 'no_flag'
) {
  if (!candidate.extracted_parameter_id) return;
  db.prepare(
    `UPDATE extracted_parameters
     SET canonical_parameter_id = ?, match_tier = ?, review_status = 'confirmed',
         in_range_flag = COALESCE(?, in_range_flag), dictionary_version_at_parse_time = ?, updated_at = ?
     WHERE id = ?`
  ).run(canonicalParameterId, matchTier, forceFlag ?? null, dictionaryVersion, now(), candidate.extracted_parameter_id);
}

// Cross-member visibility into everything still pending (any reviewer, not just the uploading member).
adminRouter.get('/admin/review-queue', (req, res) => {
  const rows = db
    .prepare(
      `SELECT ep.*, cp.display_name, m.name AS member_name
       FROM extracted_parameters ep
       LEFT JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       JOIN members m ON m.id = ep.member_id
       WHERE ep.review_status = 'pending_review'
       ORDER BY ep.created_at DESC LIMIT 200`
    )
    .all();
  res.json(rows);
});

// Dictionary curation agent (Roadmap Section 2.9a) — reference-range drift flags. No scheduler
// exists in this app, so "periodically" becomes "whenever an admin triggers it" — the nearest
// practical equivalent given the current infrastructure, same on-demand pattern every other agent
// in this app already uses (health insights, care reminders, pre-visit briefs).
adminRouter.get('/admin/dictionary/drift-flags', (req, res) => {
  const status = (req.query.status as string) || 'open';
  const rows = db
    .prepare(
      `SELECT f.*, cp.display_name, cp.category
       FROM dictionary_drift_flags f
       JOIN canonical_parameters cp ON cp.canonical_parameter_id = f.canonical_parameter_id
       WHERE f.status = ?
       ORDER BY f.checked_at DESC`
    )
    .all(status);
  res.json(rows);
});

adminRouter.post('/admin/dictionary/drift-scan', async (req, res) => {
  const canonicalParameterId = (req.body?.canonical_parameter_id as string | undefined) || undefined;
  try {
    const flags = await scanForDrift(canonicalParameterId);
    res.json({ ok: true, newly_flagged: flags });
  } catch (err) {
    console.error('Drift scan failed:', err);
    res.status(500).json({ error: 'Scan failed' });
  }
});

adminRouter.post('/admin/dictionary/drift-flags/:id/dismiss', (req, res) => {
  const row = db.prepare('SELECT id FROM dictionary_drift_flags WHERE id = ?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'Not found' });
  db.prepare(`UPDATE dictionary_drift_flags SET status = 'dismissed', resolved_at = ? WHERE id = ?`).run(now(), req.params.id);
  res.json({ ok: true });
});
