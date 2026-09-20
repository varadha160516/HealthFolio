import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { logAudit } from '../audit.js';
import { resolveAppointment } from './appointments.js';
import { canTransition } from '../state-machine/appointment.js';
import { assignToken, checkInAppointment } from '../queue.js';
import { formatAppointmentWhen, memberName, notifyProvider } from '../notifications.js';

export const frontDeskRouter = Router();

// Front desk (provider_clinic_admin). Deliberately NOT built by widening assertAppointmentVisible:
// the clinical endpoints (notes, vitals, pre-visit brief, visit summary) accept this role too, so
// letting a receptionist "see" every doctor's appointments there would hand them clinical data.
// Instead they get their own narrow surface: who is here, who is waiting, and the actions that
// move the queue (check in, walk-in, cancel). It never returns reasons for visit or anything
// clinical, and it can never unlock a consultation — consent is still the doctor's request and the
// patient's answer.
frontDeskRouter.use('/frontdesk', requireAuth, requireRole('provider_clinic_admin'));

function clinicOf(req: any, res: any): { id: string; name: string } | null {
  const row = db
    .prepare('SELECT c.id AS id, c.name AS name FROM providers p JOIN clinics c ON c.id = p.clinic_id WHERE p.id = ?')
    .get(req.session.providerId) as { id: string; name: string } | undefined;
  if (!row) {
    res.status(403).json({ error: 'Your account is not attached to a clinic.' });
    return null;
  }
  return row;
}

/** Loads an appointment only if it's one of THIS clinic's doctors'. Anything else reads as not
 * found, so a front desk can't probe for appointments at other clinics. */
function clinicAppointment(req: any, res: any, clinicId: string) {
  const appt = resolveAppointment(req.params.id);
  const owner = appt ? (db.prepare('SELECT clinic_id FROM providers WHERE id = ?').get(appt.provider_id) as { clinic_id: string | null } | undefined) : undefined;
  if (!appt || owner?.clinic_id !== clinicId) {
    res.status(404).json({ error: 'Not found' });
    return null;
  }
  return appt;
}

function ageFromDob(dob: string | null): number | null {
  if (!dob) return null;
  const t = new Date(dob).getTime();
  return Number.isNaN(t) ? null : Math.floor((Date.now() - t) / (365.25 * 24 * 60 * 60 * 1000));
}

function digitsOf(phone: unknown): string {
  return String(phone ?? '').replace(/\D/g, '');
}

/** Two numbers match if their last 10 digits do — tolerant of +91 / spaces / dashes, and of
 * nothing looser (no prefix or partial matching, so this can't be used to browse patients). */
function findMembersByPhone(phone: string): { id: string; name: string; dob: string | null; sex: string | null }[] {
  const d = digitsOf(phone);
  if (d.length < 10) return [];
  const last10 = d.slice(-10);
  const rows = db.prepare('SELECT id, name, dob, sex, phone FROM members WHERE phone IS NOT NULL AND archived_at IS NULL').all() as any[];
  return rows.filter((r) => digitsOf(r.phone).slice(-10) === last10).slice(0, 5);
}

type Bucket = 'scheduled' | 'waiting' | 'in_progress' | 'completed' | 'closed';
function bucketOf(status: string): Bucket {
  if (status === 'scheduled') return 'scheduled';
  if (status === 'checked_in' || status === 'consent_requested') return 'waiting';
  if (status === 'consent_granted' || status === 'in_consultation') return 'in_progress';
  if (status === 'completed') return 'completed';
  return 'closed'; // cancelled / consent denied / consent expired
}

// The clinic's whole day, one lane per doctor.
frontDeskRouter.get('/frontdesk/queue', (req, res) => {
  const clinic = clinicOf(req, res);
  if (!clinic) return;
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(req.query.date ?? '')) ? String(req.query.date) : new Date().toISOString().slice(0, 10);

  const doctors = db.prepare(`SELECT id, name, specialty FROM providers WHERE clinic_id = ? AND type = 'doctor' ORDER BY name`).all(clinic.id) as { id: string; name: string; specialty: string | null }[];
  const rows = db
    .prepare(
      `SELECT a.id, a.provider_id, a.datetime, a.token_number, a.checked_in_at, a.is_walk_in, a.is_follow_up,
              m.id AS member_id, m.name AS member_name, m.dob, m.sex
       FROM appointments a
       JOIN providers p ON p.id = a.provider_id
       JOIN members m ON m.id = a.member_id
       WHERE p.clinic_id = ? AND substr(a.datetime, 1, 10) = ?
       ORDER BY a.datetime`
    )
    .all(clinic.id, date) as any[];

  const lanes = doctors.map((d) => {
    const appointments = rows
      .filter((r) => r.provider_id === d.id)
      .map((r) => ({
        id: r.id,
        datetime: r.datetime,
        // resolveAppointment lazily times out a stale consent request, so the desk never shows a
        // request as "still waiting" after it has actually expired.
        status: resolveAppointment(r.id)!.status,
        token_number: r.token_number,
        checked_in_at: r.checked_in_at,
        is_walk_in: !!r.is_walk_in,
        is_follow_up: !!r.is_follow_up,
        patient: { id: r.member_id, name: r.member_name, age: ageFromDob(r.dob), sex: r.sex },
      }));
    const counts: Record<Bucket, number> = { scheduled: 0, waiting: 0, in_progress: 0, completed: 0, closed: 0 };
    for (const a of appointments) counts[bucketOf(a.status)]++;
    return { id: d.id, name: d.name, specialty: d.specialty, counts, appointments };
  });

  res.json({ date, clinic, doctors: lanes });
});

frontDeskRouter.post('/frontdesk/appointments/:id/check-in', (req, res) => {
  const clinic = clinicOf(req, res);
  if (!clinic) return;
  const appt = clinicAppointment(req, res, clinic.id);
  if (!appt) return;
  if (!canTransition(appt.status, 'checked_in')) return res.status(409).json({ error: `Cannot check in from ${appt.status.replace(/_/g, ' ')}` });

  const token = checkInAppointment(appt);
  logAudit(req.session!.userId, req.session!.role, 'frontdesk_checked_in', appt.member_id, { appointmentId: appt.id, token });
  notifyProvider(appt.provider_id, 'patient_checked_in', 'Patient checked in', `${memberName(appt.member_id)} is waiting — token ${token}.`, appt.id);
  res.json({ ok: true, token });
});

// A patient who called to cancel, or a slot that will clearly go unused.
frontDeskRouter.post('/frontdesk/appointments/:id/cancel', (req, res) => {
  const clinic = clinicOf(req, res);
  if (!clinic) return;
  const appt = clinicAppointment(req, res, clinic.id);
  if (!appt) return;
  if (!canTransition(appt.status, 'cancelled')) return res.status(409).json({ error: `Cannot cancel an appointment that's ${appt.status.replace(/_/g, ' ')}` });

  db.prepare(`UPDATE appointments SET status = 'cancelled', updated_at = ? WHERE id = ?`).run(now(), appt.id);
  logAudit(req.session!.userId, req.session!.role, 'frontdesk_cancelled', appt.member_id, { appointmentId: appt.id });
  notifyProvider(appt.provider_id, 'appointment_cancelled', 'Appointment cancelled', `Front desk cancelled ${memberName(appt.member_id)}'s ${formatAppointmentWhen(appt.datetime)} appointment.`, appt.id);
  res.json({ ok: true });
});

// Exact-number lookup only, minimal fields back, every search audited (last 4 digits, never the
// whole number). The front desk needs to know whether the person in front of them is already on
// CareLoop; it must not become a way to browse everyone who is.
frontDeskRouter.get('/frontdesk/patients/lookup', (req, res) => {
  if (!clinicOf(req, res)) return;
  const phone = String(req.query.phone ?? '');
  if (digitsOf(phone).length < 10) return res.status(400).json({ error: 'Enter the full 10-digit mobile number.' });
  const matches = findMembersByPhone(phone);
  logAudit(req.session!.userId, req.session!.role, 'frontdesk_patient_lookup', null, { phoneLast4: digitsOf(phone).slice(-4), matches: matches.length });
  res.json(matches.map((m) => ({ id: m.id, name: m.name, age: ageFromDob(m.dob), sex: m.sex })));
});

// A patient physically at the counter with no appointment. Creates the visit already checked in,
// with a token, for one of THIS clinic's doctors — bypassing working hours and slot conflicts
// (they're here) but nothing about consent: the doctor still requests access and the patient still
// answers. An existing CareLoop member gets the normal in-app prompt; a patient registered here has
// no app, so the doctor uses the OTP path.
frontDeskRouter.post('/frontdesk/walk-ins', (req, res) => {
  const clinic = clinicOf(req, res);
  if (!clinic) return;
  const { provider_id, member_id, new_patient, datetime, reason, confirm_duplicate } = req.body ?? {};

  const doctor = db.prepare(`SELECT id, name FROM providers WHERE id = ? AND clinic_id = ? AND type = 'doctor'`).get(provider_id, clinic.id) as { id: string; name: string } | undefined;
  if (!doctor) return res.status(400).json({ error: 'Choose a doctor at your clinic.' });
  if (typeof datetime !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(datetime)) return res.status(400).json({ error: 'datetime is required' });

  let memberId: string;
  let patientName: string;
  let registeredNew = false;

  if (member_id) {
    const m = db.prepare('SELECT id, name FROM members WHERE id = ? AND archived_at IS NULL').get(member_id) as { id: string; name: string } | undefined;
    if (!m) return res.status(404).json({ error: 'Patient not found' });
    memberId = m.id;
    patientName = m.name;
  } else if (new_patient && typeof new_patient === 'object') {
    const name = String(new_patient.name ?? '').trim();
    const phone = String(new_patient.phone ?? '').trim();
    if (name.length < 2 || name.length > 100) return res.status(400).json({ error: "Enter the patient's name." });
    if (digitsOf(phone).length < 10) return res.status(400).json({ error: 'A 10-digit mobile number is required.' });
    const sex = new_patient.sex;
    if (sex != null && !['male', 'female', 'other'].includes(sex)) return res.status(400).json({ error: 'Invalid sex' });
    const dob = new_patient.dob ? String(new_patient.dob) : null;
    if (dob && (!/^\d{4}-\d{2}-\d{2}$/.test(dob) || Number.isNaN(new Date(dob).getTime()))) return res.status(400).json({ error: 'Date of birth must be YYYY-MM-DD' });

    // Family members legitimately share a phone, so a match warns rather than blocks.
    const existing = findMembersByPhone(phone);
    if (existing.length > 0 && confirm_duplicate !== true) {
      return res.status(409).json({
        error: 'Someone is already registered with this number — check whether it is the same person.',
        matches: existing.map((m) => ({ id: m.id, name: m.name, age: ageFromDob(m.dob), sex: m.sex })),
      });
    }

    const familyId = uuid();
    memberId = uuid();
    db.prepare('INSERT INTO families (id, primary_member_id, created_at) VALUES (?, ?, ?)').run(familyId, memberId, now());
    db.prepare(
      `INSERT INTO members (id, family_id, name, dob, sex, relationship_to_primary, login_credentials_ref, phone, registered_by_provider_id, created_at)
       VALUES (?, ?, ?, ?, ?, 'self', NULL, ?, ?, ?)`
    ).run(memberId, familyId, name, dob, sex ?? null, phone, req.session!.providerId, now());
    patientName = name;
    registeredNew = true;
    logAudit(req.session!.userId, req.session!.role, 'frontdesk_patient_registered', memberId, { providerId: doctor.id });
  } else {
    return res.status(400).json({ error: 'Choose an existing patient or register a new one.' });
  }

  // They're already booked with this doctor today — check that visit in rather than double-booking.
  const day = datetime.slice(0, 10);
  const existingVisit = db
    .prepare(
      `SELECT id, status FROM appointments WHERE member_id = ? AND provider_id = ? AND substr(datetime, 1, 10) = ?
       AND status NOT IN ('cancelled','completed','consent_denied','consent_expired')`
    )
    .get(memberId, doctor.id, day) as { id: string; status: string } | undefined;
  if (existingVisit) {
    return res.status(409).json({ error: `${patientName} already has an appointment with ${doctor.name} today.`, appointment_id: existingVisit.id, appointment_status: existingVisit.status });
  }

  const id = uuid();
  const token = assignToken(doctor.id, datetime);
  const ts = now();
  db.prepare(
    `INSERT INTO appointments (id, member_id, provider_id, datetime, status, sharing_preference, reason_for_visit, consent_grant_id, token_number, checked_in_at, is_walk_in, created_at, updated_at)
     VALUES (?, ?, ?, ?, 'checked_in', NULL, ?, NULL, ?, ?, 1, ?, ?)`
  ).run(id, memberId, doctor.id, datetime, typeof reason === 'string' && reason.trim() ? reason.trim() : null, token, ts, ts, ts);

  logAudit(req.session!.userId, req.session!.role, 'frontdesk_walk_in_created', memberId, { appointmentId: id, providerId: doctor.id, token, registeredNew });
  notifyProvider(doctor.id, 'patient_checked_in', 'Walk-in patient waiting', `${patientName} is waiting — token ${token}.`, id);
  res.status(201).json({ id, token, registered_new: registeredNew, member_id: memberId });
});
