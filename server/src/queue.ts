import { db, now } from './db/db.js';

// Clinic queue. A token is a patient's place in line for ONE doctor on ONE day: sequential, assigned
// once when they're checked in (by the doctor's own console or the front desk — both go through
// checkInAppointment so the numbering can't diverge), and stable afterwards.

/** The calendar day an appointment falls on, read straight from its datetime string — the same
 * convention as checkProviderAvailable in appointments.ts, because these strings aren't
 * consistently zoned (member bookings are a wall-clock string, doctor follow-ups are UTC). */
export function appointmentDay(datetime: string): string {
  return datetime.slice(0, 10);
}

export function assignToken(providerId: string, datetime: string): number {
  const row = db
    .prepare(`SELECT COALESCE(MAX(token_number), 0) AS m FROM appointments WHERE provider_id = ? AND substr(datetime, 1, 10) = ?`)
    .get(providerId, appointmentDay(datetime)) as { m: number };
  return row.m + 1;
}

/** scheduled -> checked_in. Callers check canTransition first. Keeps an existing token if the row
 * already has one (e.g. a walk-in row that was created checked in), so a token never changes. */
export function checkInAppointment(appt: { id: string; provider_id: string; datetime: string; token_number?: number | null }): number {
  const token = appt.token_number ?? assignToken(appt.provider_id, appt.datetime);
  const ts = now();
  db.prepare(`UPDATE appointments SET status = 'checked_in', token_number = ?, checked_in_at = COALESCE(checked_in_at, ?), updated_at = ? WHERE id = ?`).run(token, ts, ts, appt.id);
  return token;
}

/** What a waiting patient (or their doctor) can be told about the line: their token and how many
 * people are still ahead of them for the same doctor today. Counts only — never who. */
export function queueInfo(appt: { status: string; provider_id: string; datetime: string; token_number?: number | null }): { token: number; ahead: number } | null {
  if (appt.status !== 'checked_in' || appt.token_number == null) return null;
  const row = db
    .prepare(`SELECT COUNT(*) AS c FROM appointments WHERE provider_id = ? AND substr(datetime, 1, 10) = ? AND status = 'checked_in' AND token_number < ?`)
    .get(appt.provider_id, appointmentDay(appt.datetime), appt.token_number) as { c: number };
  return { token: appt.token_number, ahead: row.c };
}
