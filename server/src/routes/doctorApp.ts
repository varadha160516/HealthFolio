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
  // The member schedules collection themselves (see PATCH /lab-test-bookings/:id's 'pending_schedule'
  // -> 'collection_scheduled' transition) — no booked_date/time_slot yet, so none is set here.
  const clinicName = db
    .prepare('SELECT c.name FROM providers p JOIN clinics c ON c.id = p.clinic_id WHERE p.id = ?')
    .get(appt.provider_id) as { name: string } | undefined;

  const id = uuid();
  db.prepare(
    `INSERT INTO lab_test_bookings (id, family_id, member_id, test_names, lab_name, status, booked_date, ordered_by_provider_id, appointment_id, clinical_indication, created_at)
     VALUES (?, ?, ?, ?, ?, 'pending_schedule', NULL, ?, ?, ?, ?)`
  ).run(id, member.family_id, appt.member_id, JSON.stringify(test_names), lab_name ?? clinicName?.name ?? 'Lab test', appt.provider_id, appt.id, clinical_indication ?? null, now());
  res.status(201).json({ id });
});

doctorAppRouter.get('/appointments/:id/lab-orders', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const rows = db.prepare('SELECT * FROM lab_test_bookings WHERE appointment_id = ? ORDER BY created_at DESC').all(appt.id) as any[];
  res.json(rows.map((r) => ({ ...r, test_names: parseJson(r.test_names, []) })));
});

// --- Referrals — structured hand-off to a specialist. The reason/notes recorded here never grant
// the receiving doctor any access on their own; they only surface inside THAT doctor's own
// pre-visit brief once the patient books with them and grants consent for that new visit (see
// previsitPrep.ts). This is what makes it safe to write real clinical context here at all. ---

doctorAppRouter.post('/appointments/:id/referrals', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const { target_specialty, target_provider_id, reason, notes, urgency } = req.body ?? {};
  if (!reason || !String(reason).trim()) return res.status(400).json({ error: 'reason is required' });
  if (!target_specialty && !target_provider_id) return res.status(400).json({ error: 'target_specialty or target_provider_id is required' });
  if (urgency && !['routine', 'urgent'].includes(urgency)) return res.status(400).json({ error: "urgency must be 'routine' or 'urgent'" });

  const id = uuid();
  db.prepare(
    `INSERT INTO referrals (id, member_id, referring_appointment_id, referring_provider_id, target_specialty, target_provider_id, reason, notes, urgency, status, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`
  ).run(id, appt.member_id, appt.id, appt.provider_id, target_specialty ?? null, target_provider_id ?? null, reason.trim(), notes?.trim() || null, urgency ?? 'routine', now(), now());
  res.status(201).json({ id });
});

doctorAppRouter.get('/appointments/:id/referrals', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = loadUnlocked(req, res);
  if (!appt) return;
  const rows = db.prepare('SELECT * FROM referrals WHERE referring_appointment_id = ? ORDER BY created_at DESC').all(appt.id);
  res.json(rows);
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

// --- Practice settings: default fee, weekly working hours, time off ---
// Back-office basics (Roadmap follow-up after invoicing/payment): a doctor's default consultation
// fee (prefills, never forces, the per-visit fee prompt on Complete Visit), plus real weekly
// availability and leave days that new bookings are now checked against (see
// checkProviderAvailable in appointments.ts) instead of the old free-text availability_note,
// which stays as a display-only summary.

const PROVIDER_TEXT_FIELDS = [
  'registration_number',
  'qualifications',
  'gst_number',
  'signature_base64',
  'bank_account_name',
  'bank_account_number',
  'bank_ifsc',
  'bank_upi_id',
] as const;

doctorAppRouter.get('/providers/me/profile', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const provider = db
    .prepare(
      `SELECT id, name, specialty, clinic_id, availability_note, default_fee, years_of_experience, ${PROVIDER_TEXT_FIELDS.join(', ')}
       FROM providers WHERE id = ?`
    )
    .get(req.session!.providerId);
  if (!provider) return res.status(404).json({ error: 'Not found' });
  res.json(provider);
});

doctorAppRouter.patch('/providers/me/profile', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const body = req.body ?? {};
  const { default_fee, years_of_experience } = body;
  if (default_fee !== undefined && default_fee !== null) {
    const fee = Number(default_fee);
    if (!Number.isFinite(fee) || fee < 0) return res.status(400).json({ error: 'default_fee must be a non-negative number' });
    db.prepare('UPDATE providers SET default_fee = ? WHERE id = ?').run(fee, req.session!.providerId);
  }
  if (years_of_experience !== undefined && years_of_experience !== null) {
    const years = Number(years_of_experience);
    if (!Number.isInteger(years) || years < 0) return res.status(400).json({ error: 'years_of_experience must be a non-negative whole number' });
    db.prepare('UPDATE providers SET years_of_experience = ? WHERE id = ?').run(years, req.session!.providerId);
  }
  for (const field of PROVIDER_TEXT_FIELDS) {
    if (body[field] !== undefined) {
      db.prepare(`UPDATE providers SET ${field} = ? WHERE id = ?`).run((body[field] as string)?.trim() || null, req.session!.providerId);
    }
  }
  res.json({ ok: true });
});

doctorAppRouter.get('/providers/me/availability', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const rows = db
    .prepare('SELECT id, day_of_week, start_time, end_time FROM provider_availability WHERE provider_id = ? ORDER BY day_of_week, start_time')
    .all(req.session!.providerId);
  res.json(rows);
});

doctorAppRouter.post('/providers/me/availability', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const { day_of_week, start_time, end_time } = req.body ?? {};
  if (!Number.isInteger(day_of_week) || day_of_week < 0 || day_of_week > 6) return res.status(400).json({ error: 'day_of_week must be 0-6' });
  if (!/^\d{2}:\d{2}$/.test(start_time ?? '') || !/^\d{2}:\d{2}$/.test(end_time ?? '')) return res.status(400).json({ error: 'start_time/end_time must be "HH:MM"' });
  if (start_time >= end_time) return res.status(400).json({ error: 'start_time must be before end_time' });
  const id = uuid();
  db.prepare('INSERT INTO provider_availability (id, provider_id, day_of_week, start_time, end_time, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(
    id,
    req.session!.providerId,
    day_of_week,
    start_time,
    end_time,
    now()
  );
  res.status(201).json({ id });
});

doctorAppRouter.delete('/providers/me/availability/:id', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  db.prepare('DELETE FROM provider_availability WHERE id = ? AND provider_id = ?').run(req.params.id, req.session!.providerId);
  res.status(204).end();
});

doctorAppRouter.get('/providers/me/time-off', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const rows = db.prepare('SELECT id, date, reason FROM provider_time_off WHERE provider_id = ? ORDER BY date').all(req.session!.providerId);
  res.json(rows);
});

doctorAppRouter.post('/providers/me/time-off', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const { date, reason } = req.body ?? {};
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date ?? '')) return res.status(400).json({ error: 'date must be "YYYY-MM-DD"' });
  const id = uuid();
  db.prepare('INSERT INTO provider_time_off (id, provider_id, date, reason, created_at) VALUES (?, ?, ?, ?, ?)').run(id, req.session!.providerId, date, reason ?? null, now());
  res.status(201).json({ id });
});

doctorAppRouter.delete('/providers/me/time-off/:id', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  db.prepare('DELETE FROM provider_time_off WHERE id = ? AND provider_id = ?').run(req.params.id, req.session!.providerId);
  res.status(204).end();
});

// --- Billing: every invoice this doctor has issued, for the practice's own billing/revenue view
// (member-side invoice list stays in invoices.ts — this is the mirror for the provider side).
// Optional ?q= (patient name, case-insensitive substring) and ?from=/?to= (YYYY-MM-DD, inclusive
// on issued_at's date) narrow the list for the Billing screen's search/filter -- CSV export reuses
// this same endpoint client-side rather than needing a separate export route. ---
doctorAppRouter.get('/providers/me/invoices', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const { q, from, to } = req.query as { q?: string; from?: string; to?: string };
  const clauses = ['i.provider_id = ?'];
  const params: any[] = [req.session!.providerId];
  if (q) {
    clauses.push('m.name LIKE ?');
    params.push(`%${q}%`);
  }
  if (from) {
    clauses.push('date(i.issued_at) >= date(?)');
    params.push(from);
  }
  if (to) {
    clauses.push('date(i.issued_at) <= date(?)');
    params.push(to);
  }
  const rows = db
    .prepare(`SELECT i.*, m.name AS member_name FROM invoices i JOIN members m ON m.id = i.member_id WHERE ${clauses.join(' AND ')} ORDER BY i.issued_at DESC`)
    .all(...params);
  res.json(rows);
});

// --- Clinic management (clinic_admin's back office; a plain doctor can still read their own
// clinic's details/roster, just not edit them). ---

doctorAppRouter.get('/clinics/me', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const provider = db.prepare('SELECT clinic_id FROM providers WHERE id = ?').get(req.session!.providerId) as { clinic_id: string | null } | undefined;
  if (!provider?.clinic_id) return res.status(404).json({ error: 'Not associated with a clinic' });
  const clinic = db.prepare('SELECT * FROM clinics WHERE id = ?').get(provider.clinic_id);
  res.json(clinic);
});

doctorAppRouter.patch('/clinics/me', requireAuth, requireRole('provider_clinic_admin'), (req, res) => {
  const provider = db.prepare('SELECT clinic_id FROM providers WHERE id = ?').get(req.session!.providerId) as { clinic_id: string | null } | undefined;
  if (!provider?.clinic_id) return res.status(404).json({ error: 'Not associated with a clinic' });
  const { name, address, city } = req.body ?? {};
  const updates: Record<string, any> = {};
  if (name !== undefined) updates.name = (name as string)?.trim() || null;
  if (address !== undefined) updates.address = (address as string)?.trim() || null;
  if (city !== undefined) updates.city = (city as string)?.trim() || null;
  if (Object.keys(updates).length === 0) return res.status(400).json({ error: 'No editable fields in request body' });
  const setClause = Object.keys(updates).map((f) => `${f} = @${f}`).join(', ');
  db.prepare(`UPDATE clinics SET ${setClause} WHERE id = @id`).run({ ...updates, id: provider.clinic_id });
  res.json({ ok: true });
});

doctorAppRouter.get('/clinics/me/providers', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const provider = db.prepare('SELECT clinic_id FROM providers WHERE id = ?').get(req.session!.providerId) as { clinic_id: string | null } | undefined;
  if (!provider?.clinic_id) return res.status(404).json({ error: 'Not associated with a clinic' });
  const rows = db.prepare('SELECT id, type, name, specialty, availability_note FROM providers WHERE clinic_id = ? ORDER BY name').all(provider.clinic_id);
  res.json(rows);
});

// --- Practice templates: reusable prescriptions and lab-test panels, loaded straight into the
// consultation screen's own Add Medicine / Select Lab Tests flows rather than being a
// disconnected list nobody actually uses. ---

function parseJsonArray(raw: string | null | undefined): any[] {
  try {
    return JSON.parse(raw ?? '[]');
  } catch {
    return [];
  }
}

doctorAppRouter.get('/providers/me/prescription-templates', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const rows = db.prepare('SELECT * FROM prescription_templates WHERE provider_id = ? ORDER BY created_at DESC').all(req.session!.providerId) as any[];
  res.json(rows.map((r) => ({ ...r, line_items: parseJsonArray(r.line_items) })));
});

doctorAppRouter.post('/providers/me/prescription-templates', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const { name, diagnosis_text, icd_code, line_items } = req.body ?? {};
  if (!name?.trim()) return res.status(400).json({ error: 'name is required' });
  if (!Array.isArray(line_items) || line_items.length === 0) return res.status(400).json({ error: 'line_items is required' });
  const id = uuid();
  db.prepare(
    `INSERT INTO prescription_templates (id, provider_id, name, diagnosis_text, icd_code, line_items, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(id, req.session!.providerId, name.trim(), diagnosis_text ?? null, icd_code ?? null, JSON.stringify(line_items), now());
  res.status(201).json({ id });
});

doctorAppRouter.delete('/providers/me/prescription-templates/:id', requireAuth, requireRole('provider_doctor'), (req, res) => {
  db.prepare('DELETE FROM prescription_templates WHERE id = ? AND provider_id = ?').run(req.params.id, req.session!.providerId);
  res.status(204).end();
});

doctorAppRouter.get('/providers/me/lab-test-panels', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const rows = db.prepare('SELECT * FROM lab_test_panels WHERE provider_id = ? ORDER BY created_at DESC').all(req.session!.providerId) as any[];
  res.json(rows.map((r) => ({ ...r, test_names: parseJsonArray(r.test_names) })));
});

doctorAppRouter.post('/providers/me/lab-test-panels', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const { name, test_names } = req.body ?? {};
  if (!name?.trim()) return res.status(400).json({ error: 'name is required' });
  if (!Array.isArray(test_names) || test_names.length === 0) return res.status(400).json({ error: 'test_names is required' });
  const id = uuid();
  db.prepare(`INSERT INTO lab_test_panels (id, provider_id, name, test_names, created_at) VALUES (?, ?, ?, ?, ?)`).run(
    id,
    req.session!.providerId,
    name.trim(),
    JSON.stringify(test_names),
    now()
  );
  res.status(201).json({ id });
});

doctorAppRouter.delete('/providers/me/lab-test-panels/:id', requireAuth, requireRole('provider_doctor'), (req, res) => {
  db.prepare('DELETE FROM lab_test_panels WHERE id = ? AND provider_id = ?').run(req.params.id, req.session!.providerId);
  res.status(204).end();
});

// --- Analytics: computed on read from existing tables, no new storage. Patient volume (last 8
// weeks), no-show/cancellation rate, top diagnoses, and follow-up compliance (of this doctor's
// own scheduled follow-ups, how many actually happened vs are overdue and still unscheduled). ---
doctorAppRouter.get('/providers/me/analytics', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const providerId = req.session!.providerId;

  const weeklyVolume = db
    .prepare(
      `SELECT strftime('%Y-%W', datetime) AS week, COUNT(*) AS count
       FROM appointments WHERE provider_id = ? AND datetime >= date('now', '-56 days')
       GROUP BY week ORDER BY week`
    )
    .all(providerId) as { week: string; count: number }[];

  const totals = db
    .prepare(
      `SELECT
         COUNT(*) AS total,
         SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
         SUM(CASE WHEN status IN ('consent_denied','consent_expired') THEN 1 ELSE 0 END) AS no_show
       FROM appointments WHERE provider_id = ?`
    )
    .get(providerId) as { total: number; cancelled: number; no_show: number };

  const topDiagnoses = db
    .prepare(
      `SELECT diagnosis_text, COUNT(*) AS count FROM prescriptions
       WHERE provider_id = ? AND diagnosis_text IS NOT NULL AND diagnosis_text != ''
       GROUP BY diagnosis_text ORDER BY count DESC LIMIT 8`
    )
    .all(providerId);

  const followUps = db
    .prepare(
      `SELECT
         SUM(CASE WHEN follow_up_appointment_id IS NOT NULL THEN 1 ELSE 0 END) AS scheduled,
         COUNT(*) AS advised
       FROM consultation_notes WHERE provider_id = ? AND follow_up_after IS NOT NULL AND follow_up_after != 'as_needed'`
    )
    .get(providerId) as { scheduled: number; advised: number };

  res.json({
    weeklyVolume,
    totals: {
      total: totals.total ?? 0,
      cancelled: totals.cancelled ?? 0,
      noShow: totals.no_show ?? 0,
    },
    topDiagnoses,
    followUps: { scheduled: followUps.scheduled ?? 0, advised: followUps.advised ?? 0 },
  });
});

// --- Compliance: this doctor's own audit trail (consent requests, data access, visit completion)
// -- the same audit_log table the member's own "Consent & access log" already reads, filtered to
// entries this doctor's account actually performed. ---
doctorAppRouter.get('/providers/me/audit-log', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const rows = db.prepare('SELECT * FROM audit_log WHERE actor_id = ? ORDER BY timestamp DESC LIMIT 200').all(req.session!.userId);
  res.json(rows);
});
