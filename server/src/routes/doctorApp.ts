import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { resolveAppointment, assertAppointmentVisible } from './appointments.js';
import { grantsDataAccess } from '../state-machine/appointment.js';

export const doctorAppRouter = Router();

const VITALS_FIELDS = ['heart_rate', 'systolic_bp', 'diastolic_bp', 'respiratory_rate', 'spo2', 'temperature_f', 'weight_kg', 'height_cm'] as const;

function parseJson<T>(text: string | null | undefined, fallback: T): T {
  if (!text) return fallback;
  try {
    return JSON.parse(text) as T;
  } catch {
    return fallback;
  }
}

/** The extra gate every write in this file needs beyond "is this your appointment" — Section
 * 7.2/12.4's fail-closed rule: a provider may only act on member data while the visit is actually
 * unlocked (consent_granted / in_consultation), never on a merely-scheduled or already-completed one. */
function loadUnlocked(req: any, res: any) {
  const appt = resolveAppointment(req.params.id);
  if (!appt) {
    res.status(404).json({ error: 'Not found' });
    return null;
  }
  if (!assertAppointmentVisible(req, res, appt)) return null;
  if (!grantsDataAccess(appt.status)) {
    res.status(403).json({ error: 'Access not unlocked for this visit' });
    return null;
  }
  return appt;
}

// --- Vitals (reuses the same member_vitals_entries table the member's own Vitals tab reads —
// a doctor's reading shows up there too, not a shadow copy). ---

doctorAppRouter.post('/appointments/:id/vitals', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const body = req.body ?? {};
  if (VITALS_FIELDS.every((f) => body[f] === undefined || body[f] === null || body[f] === '')) {
    return res.status(400).json({ error: 'At least one vital field is required' });
  }
  const id = uuid();
  const values: Record<string, any> = { id, member_id: appt.member_id, appointment_id: appt.id, recorded_at: now(), logged_by_user_id: req.session!.userId, created_at: now() };
  for (const f of VITALS_FIELDS) {
    const v = body[f];
    values[f] = v === undefined || v === null || v === '' ? null : Number(v);
  }
  db.prepare(
    `INSERT INTO member_vitals_entries (id, member_id, appointment_id, recorded_at, heart_rate, systolic_bp, diastolic_bp, respiratory_rate, spo2, temperature_f, weight_kg, height_cm, logged_by_user_id, created_at)
     VALUES (@id, @member_id, @appointment_id, @recorded_at, @heart_rate, @systolic_bp, @diastolic_bp, @respiratory_rate, @spo2, @temperature_f, @weight_kg, @height_cm, @logged_by_user_id, @created_at)`
  ).run(values);
  res.status(201).json({ id });
});

doctorAppRouter.get('/appointments/:id/vitals', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const entries = db.prepare('SELECT * FROM member_vitals_entries WHERE appointment_id = ? ORDER BY recorded_at DESC').all(appt.id);
  res.json({ entries });
});

// --- Consultation notes (chief complaint, symptoms, examination, assessment, advice, follow-up
// preference) — one row per appointment, upserted as the doctor works through the screen. ---

function serializeNotes(row: any) {
  if (!row) return null;
  return { ...row, symptoms: parseJson(row.symptoms, []), examination: parseJson(row.examination, {}), advice: parseJson(row.advice, []) };
}

doctorAppRouter.get('/appointments/:id/consultation-notes', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const row = db.prepare('SELECT * FROM consultation_notes WHERE appointment_id = ?').get(appt.id);
  res.json(serializeNotes(row));
});

doctorAppRouter.put('/appointments/:id/consultation-notes', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const b = req.body ?? {};
  const existing = db.prepare('SELECT appointment_id FROM consultation_notes WHERE appointment_id = ?').get(appt.id);
  const shared = {
    appointment_id: appt.id,
    chief_complaint: b.chief_complaint ?? null,
    symptom_duration: b.symptom_duration ?? null,
    symptoms: JSON.stringify(Array.isArray(b.symptoms) ? b.symptoms : []),
    examination: JSON.stringify(b.examination && typeof b.examination === 'object' ? b.examination : {}),
    assessment_notes: b.assessment_notes ?? null,
    advice: JSON.stringify(Array.isArray(b.advice) ? b.advice : []),
    follow_up_after: b.follow_up_after ?? null,
    follow_up_reason: b.follow_up_reason ?? null,
    updated_at: now(),
  };
  if (existing) {
    db.prepare(
      `UPDATE consultation_notes SET chief_complaint=@chief_complaint, symptom_duration=@symptom_duration, symptoms=@symptoms, examination=@examination,
       assessment_notes=@assessment_notes, advice=@advice, follow_up_after=@follow_up_after, follow_up_reason=@follow_up_reason, updated_at=@updated_at
       WHERE appointment_id=@appointment_id`
    ).run(shared);
  } else {
    db.prepare(
      `INSERT INTO consultation_notes (appointment_id, provider_id, member_id, chief_complaint, symptom_duration, symptoms, examination, assessment_notes, advice, follow_up_after, follow_up_reason, created_at, updated_at)
       VALUES (@appointment_id, @provider_id, @member_id, @chief_complaint, @symptom_duration, @symptoms, @examination, @assessment_notes, @advice, @follow_up_after, @follow_up_reason, @updated_at, @updated_at)`
    ).run({ ...shared, provider_id: appt.provider_id, member_id: appt.member_id });
  }
  const row = db.prepare('SELECT * FROM consultation_notes WHERE appointment_id = ?').get(appt.id);
  res.json(serializeNotes(row));
});

// --- Lab orders — a doctor ordering tests mid-consultation, distinct from a member's own
// self-service booking flow but landing in the exact same lab_test_bookings table/pipeline (so a
// report attached later shows up in the member's Documents tab the same way either kind does). ---

doctorAppRouter.post('/appointments/:id/lab-orders', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const { test_names, lab_name, clinical_indication } = req.body ?? {};
  if (!Array.isArray(test_names) || test_names.length === 0) return res.status(400).json({ error: 'test_names must be a non-empty array' });
  const member = db.prepare('SELECT family_id FROM members WHERE id = ?').get(appt.member_id) as { family_id: string } | undefined;
  if (!member) return res.status(404).json({ error: 'Member not found' });

  const id = uuid();
  db.prepare(
    `INSERT INTO lab_test_bookings (id, family_id, member_id, test_names, lab_name, status, booked_date, ordered_by_provider_id, appointment_id, clinical_indication, created_at)
     VALUES (?, ?, ?, ?, ?, 'collection_scheduled', ?, ?, ?, ?, ?)`
  ).run(id, member.family_id, appt.member_id, JSON.stringify(test_names), lab_name ?? 'Clinic-affiliated lab', new Date().toISOString().slice(0, 10), appt.provider_id, appt.id, clinical_indication ?? null, now());
  res.status(201).json({ id });
});

doctorAppRouter.get('/appointments/:id/lab-orders', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const rows = db.prepare('SELECT * FROM lab_test_bookings WHERE appointment_id = ? ORDER BY created_at DESC').all(appt.id) as any[];
  res.json(rows.map((r) => ({ ...r, test_names: parseJson(r.test_names, []) })));
});

// --- Follow-up scheduling — books the next appointment directly rather than just noting an
// intention, so it actually shows up on the doctor's (and member's) appointment list. ---

function computeFollowUpDatetime(after: string, baseDatetimeIso: string): string | null {
  const time = new Date(baseDatetimeIso);
  const from = new Date();
  let d: Date;
  if (after === '3_days') d = new Date(from.getTime() + 3 * 24 * 60 * 60 * 1000);
  else if (after === '1_week') d = new Date(from.getTime() + 7 * 24 * 60 * 60 * 1000);
  else if (after === '1_month') {
    d = new Date(from);
    d.setMonth(d.getMonth() + 1);
  } else return null; // 'as_needed' — preference only, no appointment
  d.setHours(time.getHours(), time.getMinutes(), 0, 0);
  return d.toISOString();
}

doctorAppRouter.post('/appointments/:id/schedule-follow-up', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const { after, reason } = req.body ?? {};
  if (!['3_days', '1_week', '1_month', 'as_needed'].includes(after)) return res.status(400).json({ error: 'after must be one of 3_days, 1_week, 1_month, as_needed' });

  let followUpAppointmentId: string | null = null;
  const nextDatetime = computeFollowUpDatetime(after, appt.datetime);
  if (nextDatetime) {
    followUpAppointmentId = uuid();
    db.prepare(
      `INSERT INTO appointments (id, member_id, provider_id, datetime, status, sharing_preference, reason_for_visit, consent_grant_id, is_follow_up, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'scheduled', NULL, ?, NULL, 1, ?, ?)`
    ).run(followUpAppointmentId, appt.member_id, appt.provider_id, nextDatetime, reason?.trim() || 'Follow-up', now(), now());
  }

  const existing = db.prepare('SELECT appointment_id FROM consultation_notes WHERE appointment_id = ?').get(appt.id);
  if (existing) {
    db.prepare(
      `UPDATE consultation_notes SET follow_up_after=@follow_up_after, follow_up_reason=@follow_up_reason, follow_up_appointment_id=@follow_up_appointment_id, updated_at=@updated_at WHERE appointment_id=@appointment_id`
    ).run({ appointment_id: appt.id, follow_up_after: after, follow_up_reason: reason ?? null, follow_up_appointment_id: followUpAppointmentId, updated_at: now() });
  } else {
    db.prepare(
      `INSERT INTO consultation_notes (appointment_id, provider_id, member_id, follow_up_after, follow_up_reason, follow_up_appointment_id, created_at, updated_at)
       VALUES (@appointment_id, @provider_id, @member_id, @follow_up_after, @follow_up_reason, @follow_up_appointment_id, @updated_at, @updated_at)`
    ).run({
      appointment_id: appt.id,
      provider_id: appt.provider_id,
      member_id: appt.member_id,
      follow_up_after: after,
      follow_up_reason: reason ?? null,
      follow_up_appointment_id: followUpAppointmentId,
      updated_at: now(),
    });
  }
  res.json({ ok: true, followUpAppointmentId });
});

// --- Visit summary — a doctor can always read back the record of a visit THEY conducted,
// regardless of the appointment's current status: this is reviewing their own authored note, not
// re-browsing the patient's broader history, so it deliberately sits outside the grantsDataAccess
// gate (which stays enforced everywhere above). ---

function buildVisitSummary(appointmentId: string) {
  const prescription = db.prepare('SELECT * FROM prescriptions WHERE appointment_id = ? ORDER BY issued_at DESC LIMIT 1').get(appointmentId) as any;
  const lineItems = prescription ? db.prepare('SELECT * FROM prescription_line_items WHERE prescription_id = ?').all(prescription.id) : [];
  const notes = serializeNotes(db.prepare('SELECT * FROM consultation_notes WHERE appointment_id = ?').get(appointmentId));
  const vitals = db.prepare('SELECT * FROM member_vitals_entries WHERE appointment_id = ? ORDER BY recorded_at DESC').all(appointmentId);
  const labOrdersRaw = db.prepare('SELECT * FROM lab_test_bookings WHERE appointment_id = ? ORDER BY created_at DESC').all(appointmentId) as any[];
  return {
    consultationNotes: notes,
    vitals,
    prescription: prescription ? { ...prescription, lineItems } : null,
    labOrders: labOrdersRaw.map((r) => ({ ...r, test_names: parseJson(r.test_names, []) })),
  };
}

doctorAppRouter.get('/appointments/:id/visit-summary', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  res.json(buildVisitSummary(appt.id));
});

// --- Patient visit history — this doctor's OWN past completed visits with this same patient,
// visible only while the CURRENT appointment is unlocked (Section 7.2 again): it's still reading
// the member's history, just authored-by-this-doctor history, so it stays behind the same gate as
// everything else that isn't the doctor's own single visit-summary. Deliberately scoped to this
// provider only — never another doctor's notes about the same patient. ---

doctorAppRouter.get('/appointments/:id/patient-visit-history', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const past = db
    .prepare(`SELECT id, datetime FROM appointments WHERE member_id = ? AND provider_id = ? AND status = 'completed' AND id != ? ORDER BY datetime DESC`)
    .all(appt.member_id, appt.provider_id, appt.id) as { id: string; datetime: string }[];
  res.json(past.map((p) => ({ appointmentId: p.id, datetime: p.datetime, ...buildVisitSummary(p.id) })));
});

// --- Doctor's patient list — every member this provider has ever had an appointment with, plus
// their own most recent diagnosis (their own authored data — not a standing-access read of the
// patient's broader record, see the per-patient detail route below for that distinction). ---

doctorAppRouter.get('/providers/me/patients', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const providerId = req.session!.providerId;
  const rows = db
    .prepare(
      `SELECT m.id, m.name, m.dob, m.sex, MAX(a.datetime) AS last_visit_at
       FROM appointments a JOIN members m ON m.id = a.member_id
       WHERE a.provider_id = ?
       GROUP BY m.id
       ORDER BY last_visit_at DESC`
    )
    .all(providerId) as any[];
  const lastDiagnosis = db.prepare(
    `SELECT diagnosis_text FROM prescriptions WHERE member_id = ? AND provider_id = ? AND diagnosis_text IS NOT NULL ORDER BY issued_at DESC LIMIT 1`
  );
  res.json(rows.map((r) => ({ ...r, lastDiagnosis: (lastDiagnosis.get(r.id, providerId) as any)?.diagnosis_text ?? null })));
});

// Reachable without an active appointment (per the brief) — but deliberately limited to this
// doctor's OWN authored visit history with the patient (their own appointments/diagnoses), never
// the patient's broader health record (allergies, documents, vitals, other doctors' notes), which
// stays behind a real consent grant exactly like everywhere else in this app.
doctorAppRouter.get('/providers/me/patients/:memberId', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const providerId = req.session!.providerId;
  const member = db.prepare('SELECT id, name, dob, sex FROM members WHERE id = ?').get(req.params.memberId) as any;
  if (!member) return res.status(404).json({ error: 'Not found' });
  const appts = db
    .prepare(`SELECT id, datetime, status FROM appointments WHERE member_id = ? AND provider_id = ? ORDER BY datetime DESC`)
    .all(req.params.memberId, providerId) as { id: string; datetime: string; status: string }[];
  if (appts.length === 0) return res.status(404).json({ error: 'You have no appointments with this patient' });
  const diagnosisFor = db.prepare('SELECT diagnosis_text FROM prescriptions WHERE appointment_id = ?');
  res.json({
    member,
    appointments: appts.map((a) => ({ ...a, diagnosisText: (diagnosisFor.get(a.id) as any)?.diagnosis_text ?? null })),
  });
});

// --- Notifications — a small real feed: stored events (appointment_cancelled, lab_report_ready,
// inserted at the source in appointments.ts / labTests.ts) merged with "follow-up due today",
// which is computed live so it can never go stale or get double-inserted. ---

doctorAppRouter.get('/providers/me/notifications', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const providerId = req.session!.providerId;
  const stored = db.prepare('SELECT * FROM provider_notifications WHERE provider_id = ? ORDER BY created_at DESC LIMIT 50').all(providerId) as any[];
  const dueToday = db
    .prepare(
      `SELECT a.id AS appointment_id, a.datetime, m.name AS member_name
       FROM appointments a JOIN members m ON m.id = a.member_id
       WHERE a.provider_id = ? AND a.is_follow_up = 1 AND a.status = 'scheduled' AND date(a.datetime) = date('now')`
    )
    .all(providerId) as any[];
  const followUps = dueToday.map((r) => ({
    id: `followup-${r.appointment_id}`,
    type: 'follow_up_due',
    title: 'Follow-up due',
    body: `${r.member_name} is due for follow-up today.`,
    related_appointment_id: r.appointment_id,
    created_at: r.datetime,
    read_at: null,
  }));
  const merged = [...stored, ...followUps].sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
  res.json(merged);
});

doctorAppRouter.post('/providers/me/notifications/:id/read', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  if (req.params.id.startsWith('followup-')) return res.json({ ok: true }); // derived, nothing to mark
  const providerId = req.session!.providerId;
  db.prepare('UPDATE provider_notifications SET read_at = ? WHERE id = ? AND provider_id = ?').run(now(), req.params.id, providerId);
  res.json({ ok: true });
});
