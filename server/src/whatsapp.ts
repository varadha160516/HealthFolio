import { db } from './db/db.js';
import { formatAppointmentWhen } from './notifications.js';
import { queueInfo } from './queue.js';

// WhatsApp here is a nudge channel, not a record channel. The clinic taps a button, the server builds
// a wa.me link with a prefilled message, and WhatsApp opens on the clinic's own phone — nothing is
// sent by CareLoop itself (that needs a Meta Business account and approved templates, which this
// project doesn't have yet), and nothing clinical is ever in the text: no reason for visit, no
// diagnosis, no medicines. It says a visit is coming, where you stand in the line, that the doctor is
// ready on video, or that a summary is waiting in the app.
//
// Two gates before a link exists at all: the patient (or the desk, for someone registered at the
// counter) opted in to WhatsApp updates, and the visit isn't cancelled. The phone number is only ever
// inside the returned link — it is not part of any appointment payload.

export type WhatsAppKind = 'reminder' | 'token' | 'video_ready' | 'summary_ready';
export const WHATSAPP_KINDS: WhatsAppKind[] = ['reminder', 'token', 'video_ready', 'summary_ready'];

/** wa.me wants the number as international digits, no plus. A bare 10-digit number is taken as
 * Indian (this app is India-first); anything else must already carry its country code. */
export function toWaNumber(phone: string | null | undefined): string | null {
  const digits = String(phone ?? '').replace(/\D/g, '');
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `91${digits.slice(1)}`;
  if (digits.length >= 11 && digits.length <= 15) return digits;
  return null;
}

export function withDr(name: string): string {
  return /^dr\.?\s/i.test(name) ? name : `Dr. ${name}`;
}

interface Ctx {
  id: string;
  member_id: string;
  provider_id: string;
  datetime: string;
  status: string;
  token_number?: number | null;
  consultation_mode?: string | null;
}

type Issued = { ok: true; url: string; text: string } | { ok: false; status: number; error: string };

/** Whether a WhatsApp link could be issued for this visit at all — the boolean the clients use to
 * decide whether to show the button. Never says why not, and never carries the number. */
export function whatsappAvailable(memberId: string, status: string): boolean {
  if (status === 'cancelled' || status === 'consent_denied' || status === 'consent_expired') return false;
  const m = db.prepare('SELECT phone, whatsapp_opt_in FROM members WHERE id = ?').get(memberId) as { phone: string | null; whatsapp_opt_in: number } | undefined;
  return !!m && m.whatsapp_opt_in === 1 && toWaNumber(m.phone) !== null;
}

export function buildWhatsAppLink(appt: Ctx, kind: WhatsAppKind): Issued {
  const m = db.prepare('SELECT name, phone, whatsapp_opt_in FROM members WHERE id = ?').get(appt.member_id) as { name: string; phone: string | null; whatsapp_opt_in: number } | undefined;
  if (!m) return { ok: false, status: 404, error: 'Patient not found' };
  if (m.whatsapp_opt_in !== 1) return { ok: false, status: 409, error: "This patient hasn't agreed to WhatsApp updates." };
  const number = toWaNumber(m.phone);
  if (!number) return { ok: false, status: 409, error: "This patient's mobile number can't be used for WhatsApp." };
  if (appt.status === 'cancelled') return { ok: false, status: 409, error: 'This appointment was cancelled.' };

  const provider = db.prepare('SELECT p.name AS name, c.name AS clinic FROM providers p LEFT JOIN clinics c ON c.id = p.clinic_id WHERE p.id = ?').get(appt.provider_id) as
    | { name: string; clinic: string | null }
    | undefined;
  const doctor = withDr(provider?.name ?? 'your doctor');
  const first = m.name.trim().split(/\s+/)[0] || 'there';
  const where = provider?.clinic ? ` at ${provider.clinic}` : '';
  const when = formatAppointmentWhen(appt.datetime);

  let text: string;
  if (kind === 'reminder') {
    if (appt.status !== 'scheduled') return { ok: false, status: 409, error: 'A reminder only makes sense before the visit starts.' };
    text = appt.consultation_mode === 'video'
      ? `Hello ${first}, a reminder of your video consultation with ${doctor} on ${when}. Open the HealthFolio app and tap Join video call when it is time.`
      : `Hello ${first}, a reminder of your appointment with ${doctor}${where} on ${when}.`;
  } else if (kind === 'token') {
    const q = queueInfo({ status: appt.status, provider_id: appt.provider_id, datetime: appt.datetime, token_number: appt.token_number });
    if (!q) return { ok: false, status: 409, error: 'This patient is not waiting in the queue.' };
    text = `Hello ${first}, your token${where ? where : ''} is ${q.token}. ${q.ahead === 0 ? "You're next." : `${q.ahead} ${q.ahead === 1 ? 'patient is' : 'patients are'} ahead of you.`}`;
  } else if (kind === 'video_ready') {
    if (appt.consultation_mode !== 'video') return { ok: false, status: 409, error: 'This is not a video visit.' };
    if (appt.status === 'completed') return { ok: false, status: 409, error: 'This visit is already finished.' };
    text = `Hello ${first}, ${doctor} is ready for your video consultation. Open the HealthFolio app, go to Appointments and tap Join video call.`;
  } else if (kind === 'summary_ready') {
    const has = db.prepare('SELECT 1 FROM visit_summaries WHERE appointment_id = ?').get(appt.id);
    if (!has) return { ok: false, status: 409, error: 'There is no visit summary to point to yet.' };
    text = `Hello ${first}, the summary of your visit with ${doctor} is ready. Open the HealthFolio app and tap Summary on that appointment.`;
  } else {
    return { ok: false, status: 400, error: 'Unknown message type.' };
  }

  return { ok: true, url: `https://wa.me/${number}?text=${encodeURIComponent(text)}`, text };
}
