import { v4 as uuid } from 'uuid';
import { db, now } from './db/db.js';

export type ProviderNotificationType =
  | 'lab_report_ready'
  | 'appointment_cancelled'
  | 'consent_granted'
  | 'consent_denied'
  | 'appointment_booked'
  | 'appointment_rescheduled'
  | 'patient_checked_in';

/**
 * The single place a doctor-facing event is recorded. ClinDesk polls the resulting feed today
 * (GET /providers/me/notifications), so this is also the one function a real push transport (FCM)
 * would hook into later — every event source already funnels through here instead of inserting
 * into provider_notifications directly.
 */
export function notifyProvider(providerId: string, type: ProviderNotificationType, title: string, body: string, relatedAppointmentId: string | null): void {
  db.prepare(`INSERT INTO provider_notifications (id, provider_id, type, title, body, related_appointment_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`).run(
    uuid(),
    providerId,
    type,
    title,
    body,
    relatedAppointmentId,
    now()
  );
}

/** "Sep 22, 4:30 PM" — appointment datetimes are stored as the wall-clock string the member picked
 * (see appointments.ts), so formatting in the server's own zone reproduces that same wall-clock. */
export function formatAppointmentWhen(datetime: string): string {
  const d = new Date(datetime);
  if (Number.isNaN(d.getTime())) return datetime;
  return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

export function memberName(memberId: string): string {
  return (db.prepare('SELECT name FROM members WHERE id = ?').get(memberId) as { name: string } | undefined)?.name ?? 'A patient';
}
