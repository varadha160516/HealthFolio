import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';
import { AppointmentStatus, canTransition, CONSENT_WINDOW_MINUTES, grantsDataAccess } from '../state-machine/appointment.js';
import { logAudit, getAuditLog } from '../audit.js';
import { computeSummaryCard } from '../summary.js';
import { SPECIALIZATIONS } from '../specializations.js';
import { getConsentExplanation } from '../pipeline/consentExplainer.js';
import { getPrevisitBrief } from '../pipeline/previsitPrep.js';
import { checkPrescriptionDraft } from '../pipeline/medicationReconciliation.js';

export const appointmentsRouter = Router();

// Maps a doctor-authored line item's day-part selection (comma-joined subset of
// Morning/Afternoon/Evening/Night, as sent by the Doctor Console medicine sheet) onto the
// member app's medication_schedules time slots. Doctor Console has no "as needed" option, so
// every doctor-issued line item becomes a 'daily' schedule.
function mapDoctorFrequencyToTimes(frequencyText: string | null | undefined): string[] {
  const f = (frequencyText ?? '').toLowerCase();
  const slots: string[] = [];
  if (f.includes('morning')) slots.push('08:00');
  if (f.includes('afternoon')) slots.push('13:00');
  if (f.includes('evening')) slots.push('18:00');
  if (f.includes('night')) slots.push('21:00');
  if (f.includes('bedtime')) slots.push('23:00');
  return slots.length > 0 ? slots : ['08:00'];
}

// Mirrors the duration parsing already used client-side for OCR'd prescriptions
// (prescription_review_screen.dart's _computeEndDate) so a doctor-issued "7 days" / "1 month"
// duration produces the same kind of end date. "Ongoing" or anything unparseable stays open-ended.
function computeMedicationEndDate(startDate: string, durationText: string | null | undefined): string | null {
  const d = (durationText ?? '').toLowerCase();
  const match = d.match(/(\d+)\s*(day|week|month)/);
  if (!match) return null;
  const n = parseInt(match[1], 10);
  if (!n || n <= 0) return null;
  const start = new Date(startDate);
  if (Number.isNaN(start.getTime())) return null;
  const end = new Date(start);
  if (match[2] === 'week') end.setDate(end.getDate() + n * 7);
  else if (match[2] === 'month') end.setMonth(end.getMonth() + n);
  else end.setDate(end.getDate() + n);
  return end.toISOString().slice(0, 10);
}

export interface AppointmentRow {
  id: string;
  member_id: string;
  provider_id: string;
  datetime: string;
  status: AppointmentStatus;
  sharing_preference: string | null;
  reason_for_visit: string | null;
  consent_grant_id: string | null;
}

/** Lazily resolves consent_requested -> consent_expired once the window has passed, rather than
 * relying on a background job — this is the single source of truth both sides read (Section 8.2). */
export function resolveAppointment(id: string): AppointmentRow | undefined {
  const appt = db.prepare('SELECT * FROM appointments WHERE id = ?').get(id) as AppointmentRow | undefined;
  if (!appt) return undefined;
  if (appt.status === 'consent_requested' && appt.consent_grant_id) {
    const grant = db.prepare('SELECT expires_at FROM consent_grants WHERE id = ?').get(appt.consent_grant_id) as { expires_at: string } | undefined;
    if (grant?.expires_at && new Date(grant.expires_at).getTime() < Date.now()) {
      db.prepare(`UPDATE appointments SET status = 'consent_expired', updated_at = ? WHERE id = ?`).run(now(), id);
      db.prepare(`UPDATE consent_grants SET revoked_at = ? WHERE id = ?`).run(now(), appt.consent_grant_id);
      appt.status = 'consent_expired';
    }
  }
  return appt;
}

export function assertAppointmentVisible(req: any, res: any, appt: AppointmentRow): boolean {
  const session = req.session;
  if (session.role === 'member_primary' || session.role === 'member_dependent') {
    const member = db.prepare('SELECT family_id FROM members WHERE id = ?').get(appt.member_id) as { family_id: string } | undefined;
    if (!member || member.family_id !== session.familyId) {
      res.status(403).json({ error: 'Not your appointment' });
      return false;
    }
    return true;
  }
  if (session.role === 'provider_doctor' || session.role === 'provider_clinic_admin') {
    if (appt.provider_id !== session.providerId) {
      // Front desk can act for any doctor at the same clinic in a real deployment; kept 1:1 here for simplicity.
      res.status(403).json({ error: 'Not your appointment' });
      return false;
    }
    return true;
  }
  res.status(403).json({ error: 'Forbidden for this role' });
  return false;
}

function serializeAppointment(appt: AppointmentRow, includeUnlockedData: boolean) {
  const grant = appt.consent_grant_id ? db.prepare('SELECT * FROM consent_grants WHERE id = ?').get(appt.consent_grant_id) : null;
  const provider = db.prepare('SELECT * FROM providers WHERE id = ?').get(appt.provider_id);
  const member = db.prepare('SELECT id, name, dob, sex, blood_group FROM members WHERE id = ?').get(appt.member_id);
  const base: any = { ...appt, provider, member, consentGrant: grant };
  if (includeUnlockedData && grantsDataAccess(appt.status)) {
    const summary = computeSummaryCard(appt.member_id);
    base.unlockedData = {
      summary,
      documents: db.prepare('SELECT * FROM documents WHERE member_id = ? ORDER BY upload_date DESC').all(appt.member_id),
      // Same abnormal-values list Overview shows the member (range + status included, and the
      // same pending_review inclusion — a doctor seeing a DIFFERENT "flagged" set than what the
      // member's own app shows would be exactly the kind of drift Section 8.2 rules out).
      flaggedHistory: summary.parameters.abnormal,
    };
  }
  return base;
}

appointmentsRouter.get('/appointments', requireAuth, (req, res) => {
  const session = req.session!;
  let rows: AppointmentRow[];
  if (session.role === 'member_primary' || session.role === 'member_dependent') {
    rows = db
      .prepare(`SELECT a.* FROM appointments a JOIN members m ON m.id = a.member_id WHERE m.family_id = ? ORDER BY a.datetime DESC`)
      .all(session.familyId) as unknown as AppointmentRow[];
  } else if (session.role === 'provider_doctor' || session.role === 'provider_clinic_admin') {
    rows = db.prepare('SELECT * FROM appointments WHERE provider_id = ? ORDER BY datetime DESC').all(session.providerId) as unknown as AppointmentRow[];
  } else {
    return res.status(403).json({ error: 'Forbidden for this role' });
  }
  rows.forEach((r) => resolveAppointment(r.id));
  res.json(rows.map((r) => serializeAppointment(resolveAppointment(r.id)!, false)));
});

appointmentsRouter.get('/appointments/:id', requireAuth, (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  res.json(serializeAppointment(appt, true));
});

// Booking (Section 8.1 step 1) — a sharing preference is a hint only, it grants no access.
appointmentsRouter.post('/appointments', requireAuth, (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary' && session.role !== 'member_dependent') return res.status(403).json({ error: 'Only members can book' });
  const { member_id, provider_id, datetime, sharing_preference, reason_for_visit } = req.body ?? {};
  if (!member_id || !provider_id || !datetime) return res.status(400).json({ error: 'member_id, provider_id, datetime are required' });
  if (!assertFamilyAccess(req, res, member_id)) return;
  const id = uuid();
  db.prepare(
    `INSERT INTO appointments (id, member_id, provider_id, datetime, status, sharing_preference, reason_for_visit, consent_grant_id, created_at, updated_at)
     VALUES (?, ?, ?, ?, 'scheduled', ?, ?, NULL, ?, ?)`
  ).run(id, member_id, provider_id, datetime, sharing_preference ?? null, reason_for_visit?.trim() || null, now(), now());
  res.status(201).json({ id });
});

// Edit — member-initiated, only while still 'scheduled' (nothing about the visit has happened
// yet, so a plain field update is safe; once checked in or beyond, changing the visit means
// cancelling and rebooking instead).
appointmentsRouter.patch('/appointments/:id', requireAuth, (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary' && session.role !== 'member_dependent') return res.status(403).json({ error: 'Only members can edit an appointment' });
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (appt.status !== 'scheduled') return res.status(409).json({ error: `Cannot edit an appointment once it's ${appt.status.replace(/_/g, ' ')}` });

  const { datetime, provider_id, sharing_preference, reason_for_visit } = req.body ?? {};
  const updates: Record<string, any> = {};
  if (datetime) updates.datetime = datetime;
  if (provider_id) updates.provider_id = provider_id;
  if (sharing_preference) updates.sharing_preference = sharing_preference;
  if (reason_for_visit !== undefined) updates.reason_for_visit = reason_for_visit?.trim() || null;
  if (Object.keys(updates).length === 0) return res.status(400).json({ error: 'No editable fields in request body' });

  const setClause = Object.keys(updates).map((f) => `${f} = @${f}`).join(', ');
  db.prepare(`UPDATE appointments SET ${setClause}, updated_at = @updated_at WHERE id = @id`).run({ ...updates, updated_at: now(), id: appt.id });
  logAudit(session.userId, session.role, 'appointment_edited', appt.member_id, { appointmentId: appt.id, fields: Object.keys(updates) });
  res.json({ ok: true });
});

// Cancel — member-initiated, only before the visit is actually unlocked (Section 7.2): once
// consent_granted/in_consultation, the visit is underway and can no longer be called off from
// here (see the state machine's transition table).
appointmentsRouter.post('/appointments/:id/cancel', requireAuth, (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary' && session.role !== 'member_dependent') return res.status(403).json({ error: 'Only members can cancel an appointment' });
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!canTransition(appt.status, 'cancelled')) return res.status(409).json({ error: `Cannot cancel an appointment that's ${appt.status.replace(/_/g, ' ')}` });
  db.prepare(`UPDATE appointments SET status = 'cancelled', updated_at = ? WHERE id = ?`).run(now(), appt.id);
  logAudit(session.userId, session.role, 'appointment_cancelled', appt.member_id, { appointmentId: appt.id });

  // Doctor App notification — real-time-enough (polled), not simulated: the provider finds out a
  // patient called off their visit without having to notice it in the appointment list.
  const member = db.prepare('SELECT name FROM members WHERE id = ?').get(appt.member_id) as { name: string } | undefined;
  const time = new Date(appt.datetime).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  db.prepare(
    `INSERT INTO provider_notifications (id, provider_id, type, title, body, related_appointment_id, created_at) VALUES (?, ?, 'appointment_cancelled', ?, ?, ?, ?)`
  ).run(uuid(), appt.provider_id, 'Appointment cancelled', `${member?.name ?? 'A patient'} cancelled the ${time} appointment.`, appt.id, now());

  res.json({ ok: true });
});

// Check-in (Section 7.1) — grants no data access, only makes the consent-request action available.
appointmentsRouter.post('/appointments/:id/check-in', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!canTransition(appt.status, 'checked_in')) return res.status(409).json({ error: `Cannot check in from ${appt.status}` });
  db.prepare(`UPDATE appointments SET status = 'checked_in', updated_at = ? WHERE id = ?`).run(now(), appt.id);
  logAudit(req.session!.userId, req.session!.role, 'checked_in', appt.member_id, { appointmentId: appt.id });
  res.json({ ok: true });
});

function issueConsentRequest(appt: AppointmentRow, method: 'in_app' | 'otp', scope: string) {
  const grantId = uuid();
  const expiresAt = new Date(Date.now() + CONSENT_WINDOW_MINUTES * 60 * 1000).toISOString();
  const otp = method === 'otp' ? String(Math.floor(100000 + Math.random() * 900000)) : null;
  db.prepare(
    `INSERT INTO consent_grants (id, appointment_id, member_id, provider_id, method, scope, requested_at, expires_at, granted_at, denied_at, revoked_at, otp_code, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?, ?)`
  ).run(grantId, appt.id, appt.member_id, appt.provider_id, method, scope, now(), expiresAt, otp, now());
  db.prepare(`UPDATE appointments SET status = 'consent_requested', consent_grant_id = ?, updated_at = ? WHERE id = ?`).run(grantId, now(), appt.id);
  return { grantId, otp, expiresAt };
}

// Consent request (Section 7.1/8.1 step 3) — real-time: the member's side reflects this the
// moment it happens (client polls GET /appointments/:id, or a future push-notification channel).
appointmentsRouter.post('/appointments/:id/request-consent', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!canTransition(appt.status, 'consent_requested')) return res.status(409).json({ error: `Cannot request consent from ${appt.status}` });
  const { method, scope } = req.body ?? {};
  const result = issueConsentRequest(appt, method === 'otp' ? 'otp' : 'in_app', scope || appt.sharing_preference || 'full_history');
  logAudit(req.session!.userId, req.session!.role, 'consent_requested', appt.member_id, { appointmentId: appt.id, method: method || 'in_app' });
  // otp is only ever returned to the requesting provider's own console (read aloud by the patient in person) —
  // never surfaced on the member's side, mirroring how the real SMS-fallback channel would behave.
  res.json({ ok: true, expiresAt: result.expiresAt, otp: result.otp });
});

// Resend — explicit only, per Section 7.1 ("the doctor must explicitly resend, never wait indefinitely").
appointmentsRouter.post('/appointments/:id/resend-consent', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!canTransition(appt.status, 'consent_requested')) return res.status(409).json({ error: `Cannot resend from ${appt.status}` });
  const { method, scope } = req.body ?? {};
  const result = issueConsentRequest(appt, method === 'otp' ? 'otp' : 'in_app', scope || appt.sharing_preference || 'full_history');
  logAudit(req.session!.userId, req.session!.role, 'consent_resent', appt.member_id, { appointmentId: appt.id });
  res.json({ ok: true, expiresAt: result.expiresAt, otp: result.otp });
});

// In-app approve/deny (Section 7.1 default path) — the member's own action.
appointmentsRouter.post('/appointments/:id/respond-consent', requireAuth, (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary' && session.role !== 'member_dependent') return res.status(403).json({ error: 'Only members can respond to consent' });
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (appt.status !== 'consent_requested') return res.status(409).json({ error: `No pending consent request (status: ${appt.status})` });

  const { approve } = req.body ?? {};
  const nextStatus: AppointmentStatus = approve ? 'consent_granted' : 'consent_denied';
  if (!canTransition(appt.status, nextStatus)) return res.status(409).json({ error: 'Invalid transition' });

  db.prepare(`UPDATE appointments SET status = ?, updated_at = ? WHERE id = ?`).run(nextStatus, now(), appt.id);
  if (approve) {
    db.prepare(`UPDATE consent_grants SET granted_at = ? WHERE id = ?`).run(now(), appt.consent_grant_id);
  } else {
    db.prepare(`UPDATE consent_grants SET denied_at = ? WHERE id = ?`).run(now(), appt.consent_grant_id);
  }
  // Written from the same consent-grant event on both sides — never two independent writes that could drift (Section 8.1 step 4).
  logAudit(session.userId, session.role, approve ? 'consent_granted' : 'consent_denied', appt.member_id, { appointmentId: appt.id });
  res.json({ ok: true, status: nextStatus });
});

// Consent explainer agent (Roadmap Section 2.5) — plain-language explanation of the pending
// request, for the member to read before responding. Member-only: this explains a request TO
// them, the provider side already sees its own structured request data.
appointmentsRouter.get('/appointments/:id/consent-explanation', requireAuth, async (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary' && session.role !== 'member_dependent') return res.status(403).json({ error: 'Only members can view this' });
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  try {
    const result = await getConsentExplanation(appt.id);
    if (!result) return res.status(409).json({ error: 'No pending consent request' });
    res.json(result);
  } catch (err) {
    console.error(err);
    res.status(502).json({ error: 'Could not generate an explanation right now.' });
  }
});

// OTP fallback (Section 7.1) — carries the same evidentiary weight as in-app approval, not a lesser path.
appointmentsRouter.post('/appointments/:id/verify-otp', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (appt.status !== 'consent_requested' || !appt.consent_grant_id) return res.status(409).json({ error: 'No pending consent request' });

  const grant = db.prepare('SELECT * FROM consent_grants WHERE id = ?').get(appt.consent_grant_id) as { otp_code: string | null } | undefined;
  const { otp } = req.body ?? {};
  if (!grant?.otp_code || otp !== grant.otp_code) {
    return res.status(401).json({ error: 'Incorrect OTP' });
  }
  db.prepare(`UPDATE appointments SET status = 'consent_granted', updated_at = ? WHERE id = ?`).run(now(), appt.id);
  db.prepare(`UPDATE consent_grants SET granted_at = ? WHERE id = ?`).run(now(), appt.consent_grant_id);
  logAudit(req.session!.userId, req.session!.role, 'consent_granted_otp', appt.member_id, { appointmentId: appt.id });
  res.json({ ok: true, status: 'consent_granted' });
});

appointmentsRouter.post('/appointments/:id/start-consultation', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!canTransition(appt.status, 'in_consultation')) return res.status(409).json({ error: `Cannot start consultation from ${appt.status}` });
  db.prepare(`UPDATE appointments SET status = 'in_consultation', updated_at = ? WHERE id = ?`).run(now(), appt.id);
  res.json({ ok: true });
});

// Pre-visit prep agent (Roadmap Section 2.6) — a drafted brief, only ever served while this visit
// is actually unlocked (Section 7.2). Access parity with the doctor console's own unlockedData:
// no broader read scope than a human doctor has at this exact moment.
appointmentsRouter.get('/appointments/:id/previsit-brief', requireAuth, requireRole('provider_doctor', 'provider_clinic_admin'), async (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!grantsDataAccess(appt.status)) return res.status(403).json({ error: 'Access not unlocked for this visit' });
  try {
    res.json(await getPrevisitBrief(appt.id));
  } catch (err) {
    console.error(err);
    res.status(502).json({ error: 'Could not generate a pre-visit brief right now.' });
  }
});

// Medication reconciliation agent (Roadmap Section 2.7) — checks a draft against allergies and
// current medications already on file. Advisory only: flags for the doctor's attention, never
// blocks /appointments/:id/prescriptions from being called regardless of what this returns.
appointmentsRouter.post('/appointments/:id/reconcile-draft', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!grantsDataAccess(appt.status)) return res.status(403).json({ error: 'Access not unlocked for this visit' });
  const { line_items } = req.body ?? {};
  if (!Array.isArray(line_items)) return res.status(400).json({ error: 'line_items is required' });
  res.json({ flags: checkPrescriptionDraft(appt.member_id, line_items) });
});

// Prescription issuance (Section 8.1 step 6) — structured input from a verified in-app action,
// skips OCR entirely and lands directly in the member's record (Section 3.4).
appointmentsRouter.post('/appointments/:id/prescriptions', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!grantsDataAccess(appt.status)) return res.status(403).json({ error: 'Access not unlocked for this visit' });

  const { diagnosis_text, icd_code, notes, line_items } = req.body ?? {};
  if (!Array.isArray(line_items) || line_items.length === 0) return res.status(400).json({ error: 'line_items is required' });

  const provider = db.prepare('SELECT name FROM providers WHERE id = ?').get(appt.provider_id) as { name: string } | undefined;

  // Also files this prescription into the member's Documents tab (document_type='prescription',
  // origin='provider_issued'), the same category member-uploaded prescription photos land in --
  // just with no actual file (page_count 0, a non-existent storage_path so GET .../pages resolves
  // to [] and DocumentViewerScreen falls back to its "no original file" state and renders the
  // line items table instead, exactly as it already does for a member's own uploaded prescription).
  const documentId = uuid();
  db.prepare(
    `INSERT INTO documents (id, member_id, uploaded_by_user_id, document_type, storage_path, checksum, page_count, upload_date, source_lab_name, status, origin, created_at)
     VALUES (?, ?, ?, 'prescription', 'provider-issued', ?, 0, ?, ?, 'parsed', 'provider_issued', ?)`
  ).run(documentId, appt.member_id, req.session!.userId, documentId, now(), provider?.name ?? null, now());

  const prescriptionId = uuid();
  db.prepare(
    `INSERT INTO prescriptions (id, appointment_id, provider_id, member_id, document_id, diagnosis_text, icd_code, notes, issued_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(prescriptionId, appt.id, appt.provider_id, appt.member_id, documentId, diagnosis_text ?? null, icd_code ?? null, notes ?? null, now());
  const insertLine = db.prepare(
    `INSERT INTO prescription_line_items (id, prescription_id, medicine_name, strength, dosage, frequency, duration, instructions) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const insertSchedule = db.prepare(
    `INSERT INTO medication_schedules
       (id, member_id, prescription_line_item_id, medicine_name, strength, dose_amount, frequency, times, day_of_week, start_date, end_date, prescribed_by, purpose, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'daily', ?, NULL, ?, ?, ?, ?, 'active', ?)`
  );
  const startDate = now().slice(0, 10);
  for (const item of line_items) {
    const lineItemId = uuid();
    insertLine.run(lineItemId, prescriptionId, item.medicine_name, item.strength ?? null, item.dosage ?? null, item.frequency ?? null, item.duration ?? null, item.instructions ?? null);
    // Lands directly in the member's Medications tab, same as a doctor's lab order lands
    // directly in the Lab Tests tab -- no OCR-review gate, since this came from a verified
    // in-app action during a consented visit rather than a scanned document.
    insertSchedule.run(
      uuid(),
      appt.member_id,
      lineItemId,
      item.medicine_name,
      item.strength ?? null,
      item.dosage ?? null,
      JSON.stringify(mapDoctorFrequencyToTimes(item.frequency)),
      startDate,
      computeMedicationEndDate(startDate, item.duration),
      provider?.name ?? null,
      diagnosis_text ?? null,
      now()
    );
  }
  res.status(201).json({ prescriptionId });
});

// Completion (Section 7.1/7.3/8.1 step 7) — revokes access immediately; a later visit needs a
// fresh check-in and a fresh grant. Not standing access.
appointmentsRouter.post('/appointments/:id/complete', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (!canTransition(appt.status, 'completed')) return res.status(409).json({ error: `Cannot complete from ${appt.status}` });

  // fee_amount is optional at the API level (older/other clients calling this same endpoint
  // shouldn't break), but Doctor Console's Complete Visit flow always sends it -- that's what
  // actually produces an invoice for the member to pay.
  const { fee_amount } = req.body ?? {};
  let invoiceId: string | undefined;
  if (fee_amount !== undefined && fee_amount !== null) {
    const fee = Number(fee_amount);
    if (!Number.isFinite(fee) || fee < 0) return res.status(400).json({ error: 'fee_amount must be a non-negative number' });
    invoiceId = uuid();
    db.prepare(
      `INSERT INTO invoices (id, appointment_id, member_id, provider_id, fee_amount, currency, status, issued_at) VALUES (?, ?, ?, ?, ?, 'INR', 'pending', ?)`
    ).run(invoiceId, appt.id, appt.member_id, appt.provider_id, fee, now());
  }

  db.prepare(`UPDATE appointments SET status = 'completed', updated_at = ? WHERE id = ?`).run(now(), appt.id);
  if (appt.consent_grant_id) db.prepare(`UPDATE consent_grants SET revoked_at = ? WHERE id = ?`).run(now(), appt.consent_grant_id);
  logAudit(req.session!.userId, req.session!.role, 'visit_completed_access_revoked', appt.member_id, { appointmentId: appt.id });
  res.json({ ok: true, invoiceId });
});

appointmentsRouter.get('/providers', requireAuth, (_req, res) => {
  res.json(db.prepare('SELECT p.*, c.name AS clinic_name FROM providers p LEFT JOIN clinics c ON c.id = p.clinic_id WHERE p.type = ?').all('doctor'));
});

appointmentsRouter.get('/specializations', requireAuth, (_req, res) => {
  res.json(SPECIALIZATIONS);
});

// Manual name search — the alternative to specialty+location browsing, for a member who already
// knows (or half-remembers) who they want to book. Matches on the doctor's name only; deliberately
// simple substring search, no fuzzy matching, over the same doctor directory /providers uses.
appointmentsRouter.get('/providers/search', requireAuth, (req, res) => {
  const q = (req.query.q as string | undefined)?.trim();
  if (!q || q.length < 2) return res.json([]);
  const rows = db
    .prepare(
      `SELECT p.*, c.name AS clinic_name, c.city FROM providers p LEFT JOIN clinics c ON c.id = p.clinic_id
       WHERE p.type = 'doctor' AND p.name LIKE ? ORDER BY p.name LIMIT 20`
    )
    .all(`%${q}%`);
  res.json(rows);
});

/**
 * Distance-filtered doctor search. Every matching-specialty doctor is returned (not just ones
 * inside radius_km) with a computed distance and `within_radius` flag — the client shows the
 * in-radius ones prominently but can fall back to "closest anyway" if nobody's actually within
 * range, rather than a dead-end empty result (real-world doctor density varies a lot by area).
 */
appointmentsRouter.get('/providers/nearby', requireAuth, (req, res) => {
  const specialty = req.query.specialty as string | undefined;
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  const radiusKm = Number(req.query.radius_km) || 20;
  if (!specialty) return res.status(400).json({ error: 'specialty is required' });
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return res.status(400).json({ error: 'lat and lng are required numbers' });

  const rows = db
    .prepare(
      `SELECT p.*, c.name AS clinic_name, c.address, c.city, c.latitude, c.longitude
       FROM providers p JOIN clinics c ON c.id = p.clinic_id
       WHERE p.type = 'doctor' AND p.specialty = ? AND c.latitude IS NOT NULL AND c.longitude IS NOT NULL`
    )
    .all(specialty) as any[];

  const withDistance = rows
    .map((r) => ({ ...r, distance_km: Math.round(haversineKm(lat, lng, r.latitude, r.longitude) * 10) / 10 }))
    .sort((a, b) => a.distance_km - b.distance_km)
    .map((r) => ({ ...r, within_radius: r.distance_km <= radiusKm }));

  res.json(withDistance);
});

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// --- Preferred (favorite) doctors — bookable regardless of distance, per member per specialty ---

appointmentsRouter.get('/members/:id/preferred-providers', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const rows = db
    .prepare(
      `SELECT pp.id AS preference_id, p.*, c.name AS clinic_name, c.address, c.city, c.latitude, c.longitude
       FROM preferred_providers pp
       JOIN providers p ON p.id = pp.provider_id
       LEFT JOIN clinics c ON c.id = p.clinic_id
       WHERE pp.member_id = ?
       ORDER BY pp.created_at DESC`
    )
    .all(req.params.id);
  res.json(rows);
});

appointmentsRouter.post('/members/:id/preferred-providers', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const { provider_id } = req.body ?? {};
  if (!provider_id) return res.status(400).json({ error: 'provider_id is required' });
  const provider = db.prepare('SELECT id FROM providers WHERE id = ?').get(provider_id);
  if (!provider) return res.status(404).json({ error: 'Provider not found' });
  const id = uuid();
  try {
    db.prepare('INSERT INTO preferred_providers (id, member_id, provider_id, created_at) VALUES (?, ?, ?, ?)').run(id, req.params.id, provider_id, now());
  } catch {
    return res.status(200).json({ ok: true, alreadyExisted: true }); // UNIQUE(member_id, provider_id) — fine, already saved
  }
  res.status(201).json({ id });
});

appointmentsRouter.delete('/members/:id/preferred-providers/:providerId', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  db.prepare('DELETE FROM preferred_providers WHERE member_id = ? AND provider_id = ?').run(req.params.id, req.params.providerId);
  res.status(204).end();
});
