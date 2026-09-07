import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { computeSummaryCard } from '../summary.js';
import { getCareReminders } from '../pipeline/careCoordinator.js';
import { computeGrowthPercentiles } from '../pipeline/growthPercentile.js';

export const familyRouter = Router();

/** Confirms the requesting session is allowed to act for this member — the primary member
 * can manage every dependent by default (Section 3.1); a self-managed dependent can only act
 * for themselves. */
function assertFamilyAccess(req: any, res: any, memberId: string): boolean {
  const session = req.session;
  const member = db.prepare('SELECT family_id FROM members WHERE id = ?').get(memberId) as { family_id: string } | undefined;
  if (!member) {
    res.status(404).json({ error: 'Member not found' });
    return false;
  }
  if (member.family_id !== session.familyId) {
    res.status(403).json({ error: 'Not a member of your family' });
    return false;
  }
  return true;
}

// Archived members are hidden here by default (never deleted — see /members/:id/archive) so
// nothing else in the app (booking, dashboards, care reminders) has to know about archiving
// separately; pass include_archived=1 for the one screen that needs to show/restore them.
familyRouter.get('/family', requireAuth, (req, res) => {
  const session = req.session!;
  if (!session.familyId) return res.status(403).json({ error: 'No family context for this role' });
  const includeArchived = req.query.include_archived === '1';
  const members = db
    .prepare(`SELECT * FROM members WHERE family_id = ? ${includeArchived ? '' : 'AND archived_at IS NULL'} ORDER BY relationship_to_primary`)
    .all(session.familyId);
  res.json({ familyId: session.familyId, members });
});

// Archive/restore (Section 3.1: only the coordinator manages dependents) — soft-delete only.
// Health records are never a click away from permanent loss in this app; archiving hides a
// member from listings while keeping every document, result, and consultation intact and
// reachable again the moment they're restored.
familyRouter.post('/members/:id/archive', requireAuth, (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary') return res.status(403).json({ error: 'Only the family coordinator can archive a member' });
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const member = db.prepare('SELECT relationship_to_primary FROM members WHERE id = ?').get(req.params.id) as { relationship_to_primary: string };
  if (member.relationship_to_primary === 'self') return res.status(400).json({ error: 'The family coordinator cannot be archived' });
  db.prepare('UPDATE members SET archived_at = ? WHERE id = ?').run(now(), req.params.id);
  res.json({ ok: true });
});

familyRouter.post('/members/:id/restore', requireAuth, (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary') return res.status(403).json({ error: 'Only the family coordinator can restore a member' });
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  db.prepare('UPDATE members SET archived_at = NULL WHERE id = ?').run(req.params.id);
  res.json({ ok: true });
});

// Family care-coordinator agent (Roadmap Section 2.3) — overdue checkups, medications about to
// run out, vaccination checks coming due, across the whole family in one call.
familyRouter.get('/family/care-reminders', requireAuth, (req, res) => {
  const session = req.session!;
  if (!session.familyId) return res.status(403).json({ error: 'No family context for this role' });
  res.json({ reminders: getCareReminders(session.familyId) });
});

familyRouter.post('/family/members', requireAuth, (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary') return res.status(403).json({ error: 'Only the family coordinator can add dependents' });
  const { name, dob, sex, blood_group, relationship_to_primary } = req.body ?? {};
  if (!name || !relationship_to_primary) return res.status(400).json({ error: 'name and relationship_to_primary are required' });

  const id = uuid();
  db.prepare(
    `INSERT INTO members (id, family_id, name, dob, sex, blood_group, relationship_to_primary, login_credentials_ref, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)`
  ).run(id, session.familyId, name, dob ?? null, sex ?? null, blood_group ?? null, relationship_to_primary, now());

  res.status(201).json({ id });
});

familyRouter.get('/members/:id/summary', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  res.json(computeSummaryCard(req.params.id));
});

const PROFILE_FIELDS = [
  'dob',
  'sex',
  'blood_group',
  'phone',
  'address',
  'emergency_contact_name',
  'emergency_contact_phone',
  'emergency_contact_relationship',
  'organ_donor_status',
  'primary_physician_name',
  'primary_physician_phone',
] as const;

const RELATIONSHIP_VALUES = ['spouse', 'child', 'parent', 'other'] as const; // never 'self' here —
// see the dedicated guard below, exactly one member per family holds that value.

familyRouter.patch('/members/:id/profile', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const body = req.body ?? {};

  const setParts: string[] = [];
  const params: Record<string, any> = { id: req.params.id };

  // name/relationship are NOT NULL columns with real invariants, so they're validated separately
  // rather than joining the generic "blank string becomes null" loop below.
  if ('name' in body) {
    const name = (body.name as string | undefined)?.trim();
    if (!name) return res.status(400).json({ error: 'name cannot be empty' });
    setParts.push('name = @name');
    params.name = name;
  }
  if ('relationship_to_primary' in body) {
    const current = db.prepare('SELECT relationship_to_primary FROM members WHERE id = ?').get(req.params.id) as { relationship_to_primary: string } | undefined;
    if (!current) return res.status(404).json({ error: 'Member not found' });
    const next = body.relationship_to_primary as string;
    if (current.relationship_to_primary === 'self') return res.status(400).json({ error: "The family coordinator's own relationship can't be changed" });
    if (!RELATIONSHIP_VALUES.includes(next as any)) return res.status(400).json({ error: `relationship_to_primary must be one of: ${RELATIONSHIP_VALUES.join(', ')}` });
    setParts.push('relationship_to_primary = @relationship_to_primary');
    params.relationship_to_primary = next;
  }

  const updates = PROFILE_FIELDS.filter((f) => f in body);
  for (const f of updates) {
    setParts.push(`${f} = @${f}`);
    params[f] = body[f] === '' ? null : body[f];
  }

  if (setParts.length === 0) return res.status(400).json({ error: 'No recognized profile fields in request body' });
  db.prepare(`UPDATE members SET ${setParts.join(', ')} WHERE id = @id`).run(params);
  res.json({ ok: true });
});

familyRouter.get('/members/:id/insurance', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const policies = db.prepare('SELECT * FROM insurance_policies WHERE member_id = ? ORDER BY period_start DESC').all(req.params.id);
  res.json(policies);
});

familyRouter.post('/members/:id/insurance', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const { payer_name, policy_number, sum_insured, period_start, period_end } = req.body ?? {};
  if (!payer_name || !policy_number) return res.status(400).json({ error: 'payer_name and policy_number are required' });
  const id = uuid();
  db.prepare(
    `INSERT INTO insurance_policies (id, member_id, payer_name, policy_number, sum_insured, period_start, period_end, document_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, NULL)`
  ).run(id, req.params.id, payer_name, policy_number, sum_insured ?? null, period_start ?? null, period_end ?? null);
  res.status(201).json({ id });
});

familyRouter.delete('/insurance/:id', requireAuth, (req, res) => {
  const policy = db.prepare('SELECT member_id FROM insurance_policies WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!policy) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, policy.member_id)) return;
  db.prepare('DELETE FROM insurance_policies WHERE id = ?').run(req.params.id);
  res.status(204).end();
});

familyRouter.post('/members/:id/allergies', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const { value } = req.body ?? {};
  if (!value) return res.status(400).json({ error: 'value is required' });
  const id = uuid();
  db.prepare('INSERT INTO allergies (id, member_id, value, source_document_id, created_at) VALUES (?, ?, ?, NULL, ?)').run(
    id,
    req.params.id,
    value,
    now()
  );
  res.status(201).json({ id });
});

familyRouter.post('/members/:id/chronic-conditions', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const { value } = req.body ?? {};
  if (!value) return res.status(400).json({ error: 'value is required' });
  const id = uuid();
  db.prepare('INSERT INTO chronic_conditions (id, member_id, value, source_document_id, created_at) VALUES (?, ?, ?, NULL, ?)').run(
    id,
    req.params.id,
    value,
    now()
  );
  res.status(201).json({ id });
});

// Manual Vitals entry — see schema.sql's member_vitals_entries for why this is a separate table
// from the document-OCR extracted_parameters pipeline.
const VITALS_FIELDS = ['heart_rate', 'systolic_bp', 'diastolic_bp', 'respiratory_rate', 'spo2', 'temperature_f', 'weight_kg', 'height_cm', 'head_circumference_cm'] as const;

function ageMonthsAt(dob: string | null, atIso: string): number | null {
  if (!dob) return null;
  const d = new Date(dob);
  const at = new Date(atIso);
  if (Number.isNaN(d.getTime()) || Number.isNaN(at.getTime())) return null;
  const months = (at.getFullYear() - d.getFullYear()) * 12 + (at.getMonth() - d.getMonth()) + (at.getDate() - d.getDate()) / 30.4375;
  return Math.max(0, months);
}

familyRouter.get('/members/:id/vitals-entries', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const entries = db.prepare('SELECT * FROM member_vitals_entries WHERE member_id = ? ORDER BY recorded_at DESC').all(req.params.id) as any[];
  const member = db.prepare('SELECT dob, sex FROM members WHERE id = ?').get(req.params.id) as { dob: string | null; sex: string | null } | undefined;

  let growth = null;
  const latest = entries[0];
  if (latest && member) {
    const ageMonths = ageMonthsAt(member.dob, latest.recorded_at);
    if (ageMonths != null && (member.sex === 'male' || member.sex === 'female')) {
      growth = computeGrowthPercentiles({ sex: member.sex, ageMonths, weightKg: latest.weight_kg, heightCm: latest.height_cm });
    } else {
      growth = {
        ageMonths: ageMonths ?? null,
        bmi: null,
        weightForAgePercentile: null,
        heightForAgePercentile: null,
        bmiForAgePercentile: null,
        note: !member.dob
          ? 'Add a date of birth in Profile to enable growth percentiles.'
          : 'Add a sex (male/female) in Profile to enable growth percentiles — the CDC reference charts are sex-specific.',
      };
    }
  }

  res.json({ entries, growth });
});

familyRouter.post('/members/:id/vitals-entries', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const body = req.body ?? {};
  if (VITALS_FIELDS.every((f) => body[f] === undefined || body[f] === null || body[f] === '')) {
    return res.status(400).json({ error: 'At least one vital field is required' });
  }
  const id = uuid();
  const nowTs = now();
  const recordedAt = body.recorded_at || nowTs;
  const values: Record<string, any> = { id, member_id: req.params.id, recorded_at: recordedAt, logged_by_user_id: req.session!.userId, created_at: nowTs };
  for (const f of VITALS_FIELDS) {
    const v = body[f];
    values[f] = v === undefined || v === null || v === '' ? null : Number(v);
  }
  db.prepare(
    `INSERT INTO member_vitals_entries (id, member_id, recorded_at, heart_rate, systolic_bp, diastolic_bp, respiratory_rate, spo2, temperature_f, weight_kg, height_cm, head_circumference_cm, logged_by_user_id, created_at)
     VALUES (@id, @member_id, @recorded_at, @heart_rate, @systolic_bp, @diastolic_bp, @respiratory_rate, @spo2, @temperature_f, @weight_kg, @height_cm, @head_circumference_cm, @logged_by_user_id, @created_at)`
  ).run(values);
  res.status(201).json({ id });
});

export { assertFamilyAccess };
