import { Router } from 'express';
import { db, now } from '../db/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { logAudit } from '../audit.js';
import { assertAppointmentVisible, resolveAppointment } from './appointments.js';
import { canTransition } from '../state-machine/appointment.js';
import { checkInAppointment } from '../queue.js';
import { memberName, notifyProvider } from '../notifications.js';
import { joinUrl, newRoomName } from '../video.js';
import { buildWhatsAppLink, WHATSAPP_KINDS, type WhatsAppKind } from '../whatsapp.js';

export const teleconsultRouter = Router();

// A video consultation changes HOW the two people talk, not what the doctor may see: the record is
// still locked until the patient approves the doctor's access request in their app, and that request
// can't fall back to the in-room OTP (see request-consent in appointments.ts). All this router adds is
// the way into the call — and the call itself lives on a Jitsi room whose name is the only secret, so
// it is handed to exactly two kinds of caller: the patient's own family, and the doctor on the visit.
// Front desk is deliberately not one of them.

teleconsultRouter.post('/appointments/:id/video/join', requireAuth, requireRole('member_primary', 'member_dependent', 'provider_doctor'), (req, res) => {
  const session = req.session!;
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  if (appt.consultation_mode !== 'video') return res.status(409).json({ error: 'This is not a video consultation.' });
  if (appt.status === 'cancelled') return res.status(409).json({ error: 'This appointment was cancelled.' });
  if (appt.status === 'completed') return res.status(409).json({ error: 'This visit is finished.' });

  let room = appt.video_room;
  if (!room) {
    room = newRoomName();
    db.prepare('UPDATE appointments SET video_room = ?, updated_at = ? WHERE id = ?').run(room, now(), appt.id);
  }

  const isDoctor = session.role === 'provider_doctor';
  const ts = now();
  let displayName: string;
  if (isDoctor) {
    db.prepare('UPDATE appointments SET video_doctor_joined_at = COALESCE(video_doctor_joined_at, ?) WHERE id = ?').run(ts, appt.id);
    displayName = (db.prepare('SELECT name FROM providers WHERE id = ?').get(appt.provider_id) as { name: string } | undefined)?.name ?? 'Doctor';
  } else {
    const firstJoin = appt.video_patient_joined_at === null;
    db.prepare('UPDATE appointments SET video_patient_joined_at = COALESCE(video_patient_joined_at, ?) WHERE id = ?').run(ts, appt.id);
    displayName = memberName(appt.member_id);
    // Being in the video room is the remote equivalent of walking in: the visit moves to "checked in"
    // (no token — there is no counter) so the doctor can request access, and the doctor is told once.
    if (canTransition(appt.status, 'checked_in')) checkInAppointment(appt);
    if (firstJoin) notifyProvider(appt.provider_id, 'patient_checked_in', 'Patient is in the video room', `${displayName} is waiting for your video consultation.`, appt.id);
  }

  // The room name is a credential, so it is never written to the audit log — only that a join happened.
  logAudit(session.userId, session.role, 'video_joined', appt.member_id, { appointmentId: appt.id, as: isDoctor ? 'doctor' : 'patient' });
  res.json({ url: joinUrl(room, displayName) });
});

// A WhatsApp nudge link for one of this doctor's own visits. The front-desk twin lives in
// frontDesk.ts and is scoped to the clinic instead.
teleconsultRouter.post('/appointments/:id/whatsapp-link', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  const kind = req.body?.kind as WhatsAppKind;
  if (!WHATSAPP_KINDS.includes(kind)) return res.status(400).json({ error: 'Unknown message type.' });
  const link = buildWhatsAppLink(appt, kind);
  if (!link.ok) return res.status(link.status).json({ error: link.error });
  logAudit(req.session!.userId, req.session!.role, 'whatsapp_link_issued', appt.member_id, { appointmentId: appt.id, kind });
  res.json({ url: link.url });
});
