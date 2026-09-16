import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { currentDictionaryVersion } from '../dictionary/loader.js';
import { draftCandidateResolution, scanForDrift } from '../pipeline/dictionaryCuration.js';
import { logAudit } from '../audit.js';

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

// --- Provider onboarding review queue ---

const APPLICATION_DOC_MIME: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.pdf': 'application/pdf',
};

// password_hash never leaves the server past this point — the admin UI has no use for it, and
// there's no reason to put even a hash on the wire when the endpoint doesn't need to.
const APPLICATION_LIST_COLUMNS =
  'id, reference_code, email, full_name, phone, role_requested, specialty, registration_number, qualifications, years_of_experience, gst_number, default_fee, clinic_mode, clinic_id, new_clinic_name, new_clinic_address, new_clinic_city, status, rejection_reason, reviewed_by_user_id, reviewed_at, created_provider_id, created_at, updated_at';

// A registration number is the one field this whole review exists to check — treat "12345" and
// " 12345 " as the same, but nothing fancier, since we have no idea what real formatting variance
// looks like across 29+ state councils and don't want to guess past exact-match-ignoring-case.
function normalizeRegistrationNumber(value: string | null | undefined): string | null {
  const trimmed = value?.trim().toUpperCase();
  return trimmed && trimmed.length > 0 ? trimmed : null;
}

/** Cross-checks a registration number against every OTHER approved provider and every other
 * application (any status) that isn't this one — the only dedup the submit flow itself does is on
 * email, so this is the sole place a duplicate/reused registration number is ever surfaced. */
function findDuplicateRegistration(registrationNumber: string | null | undefined, excludeApplicationId: string) {
  const normalized = normalizeRegistrationNumber(registrationNumber);
  if (!normalized) return { providers: [] as any[], applications: [] as any[] };

  const providers = (db.prepare(`SELECT id, name, registration_number FROM providers WHERE registration_number IS NOT NULL`).all() as any[]).filter(
    (p) => normalizeRegistrationNumber(p.registration_number) === normalized
  );
  const applications = (
    db
      .prepare(`SELECT id, full_name, status, registration_number FROM provider_applications WHERE registration_number IS NOT NULL AND id != ?`)
      .all(excludeApplicationId) as any[]
  ).filter((a) => normalizeRegistrationNumber(a.registration_number) === normalized);

  return { providers, applications };
}

adminRouter.get('/admin/provider-applications', (req, res) => {
  const status = req.query.status as string | undefined;
  const search = (req.query.search as string | undefined)?.trim();
  const sort = req.query.sort === 'oldest' ? 'ASC' : 'DESC';

  const where: string[] = [];
  const params: any[] = [];
  if (status) {
    where.push('status = ?');
    params.push(status);
  }
  if (search) {
    where.push('(full_name LIKE ? OR email LIKE ? OR registration_number LIKE ?)');
    const like = `%${search}%`;
    params.push(like, like, like);
  }
  const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';

  const rows = db
    .prepare(
      `SELECT ${APPLICATION_LIST_COLUMNS}, (SELECT COUNT(*) FROM provider_application_documents d WHERE d.application_id = provider_applications.id) AS document_count
       FROM provider_applications ${whereClause} ORDER BY created_at ${sort}`
    )
    .all(...params);
  res.json(rows);
});

adminRouter.get('/admin/provider-applications/:id', (req, res) => {
  const app = db.prepare(`SELECT ${APPLICATION_LIST_COLUMNS}, ocr_extraction_json FROM provider_applications WHERE id = ?`).get(req.params.id) as any;
  if (!app) return res.status(404).json({ error: 'Not found' });
  const clinic = app.clinic_id ? db.prepare('SELECT * FROM clinics WHERE id = ?').get(app.clinic_id) : null;
  const documents = db.prepare('SELECT id, document_type, filename, created_at FROM provider_application_documents WHERE application_id = ? ORDER BY created_at').all(app.id);

  let ocrExtraction = null;
  if (app.ocr_extraction_json) {
    try {
      ocrExtraction = JSON.parse(app.ocr_extraction_json);
    } catch {
      // leave null — a malformed stored value shouldn't break the whole detail view
    }
  }
  delete app.ocr_extraction_json;

  const duplicates = findDuplicateRegistration(app.registration_number, app.id);
  res.json({ application: app, clinic, documents, ocrExtraction, duplicates });
});

adminRouter.get('/admin/provider-applications/:id/documents/:docId/file', (req, res) => {
  const doc = db.prepare('SELECT * FROM provider_application_documents WHERE id = ? AND application_id = ?').get(req.params.docId, req.params.id) as
    | { storage_path: string; filename: string }
    | undefined;
  if (!doc) return res.status(404).json({ error: 'Not found' });
  const filePath = path.join(doc.storage_path, doc.filename);
  if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'File not found' });
  res.setHeader('Content-Type', APPLICATION_DOC_MIME[path.extname(doc.filename).toLowerCase()] ?? 'application/octet-stream');
  fs.createReadStream(filePath).pipe(res);
});

class ApproveConflict extends Error {
  constructor(public payload: any) {
    super('approve_conflict');
  }
}

// Everything from the pending-status check through the final status flip runs inside one
// transaction — a plain read-then-write here would let a double-tap or two admins acting within
// milliseconds of each other create two provider/user rows for the same application before the
// status change lands. Throwing ApproveConflict rolls the whole thing back cleanly.
const runApproval = db.transaction((req: any) => {
  const app = db.prepare('SELECT * FROM provider_applications WHERE id = ?').get(req.params.id) as any;
  if (!app) throw new ApproveConflict({ status: 404, body: { error: 'Not found' } });
  if (app.status !== 'pending') throw new ApproveConflict({ status: 409, body: { error: `Application is already ${app.status}` } });
  if (db.prepare('SELECT id FROM users WHERE email = ?').get(app.email)) {
    throw new ApproveConflict({ status: 409, body: { error: 'An account with this email was created since the application was submitted' } });
  }

  if (req.body?.override_duplicate !== true) {
    const duplicates = findDuplicateRegistration(app.registration_number, app.id);
    if (duplicates.providers.length > 0 || duplicates.applications.length > 0) {
      throw new ApproveConflict({ status: 409, body: { error: 'duplicate_registration_number', duplicates } });
    }
  }

  const timestamp = now();
  let clinicId = app.clinic_id as string | null;
  if (app.clinic_mode === 'new') {
    clinicId = uuid();
    db.prepare('INSERT INTO clinics (id, name, address, city) VALUES (?, ?, ?, ?)').run(clinicId, app.new_clinic_name, app.new_clinic_address, app.new_clinic_city);
  }

  const providerId = uuid();
  db.prepare(
    `INSERT INTO providers (id, type, name, specialty, clinic_id, default_fee, registration_number, qualifications, years_of_experience, gst_number)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(providerId, app.role_requested, app.full_name, app.specialty, clinicId, app.default_fee, app.registration_number, app.qualifications, app.years_of_experience, app.gst_number);

  const role = app.role_requested === 'doctor' ? 'provider_doctor' : 'provider_clinic_admin';
  db.prepare('INSERT INTO users (id, email, password_hash, role, display_name, provider_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)').run(
    uuid(),
    app.email,
    app.password_hash,
    role,
    app.full_name,
    providerId,
    timestamp
  );

  db.prepare(
    `UPDATE provider_applications SET status = 'approved', created_provider_id = ?, reviewed_by_user_id = ?, reviewed_at = ?, updated_at = ? WHERE id = ?`
  ).run(providerId, req.session!.userId, timestamp, timestamp, app.id);

  return { app, providerId, clinicId };
});

adminRouter.post('/admin/provider-applications/:id/approve', (req, res) => {
  let result;
  try {
    result = runApproval(req);
  } catch (e) {
    if (e instanceof ApproveConflict) return res.status(e.payload.status).json(e.payload.body);
    throw e;
  }
  const { app, providerId, clinicId } = result;
  logAudit(req.session!.userId, req.session!.role, 'provider_application_approved', null, {
    applicationId: app.id,
    providerId,
    email: app.email,
    overrodeDuplicateWarning: req.body?.override_duplicate === true,
  });
  res.json({ ok: true, providerId, clinicId });
});

adminRouter.post('/admin/provider-applications/:id/reject', (req, res) => {
  const app = db.prepare('SELECT * FROM provider_applications WHERE id = ?').get(req.params.id) as any;
  if (!app) return res.status(404).json({ error: 'Not found' });
  if (app.status !== 'pending') return res.status(409).json({ error: `Application is already ${app.status}` });
  const reason = (req.body?.reason as string | undefined)?.trim();
  if (!reason) return res.status(400).json({ error: 'A rejection reason is required' });

  const timestamp = now();
  db.prepare(`UPDATE provider_applications SET status = 'rejected', rejection_reason = ?, reviewed_by_user_id = ?, reviewed_at = ?, updated_at = ? WHERE id = ?`).run(
    reason,
    req.session!.userId,
    timestamp,
    timestamp,
    app.id
  );
  logAudit(req.session!.userId, req.session!.role, 'provider_application_rejected', null, { applicationId: app.id, email: app.email, reason });
  res.json({ ok: true });
});
