import { db } from '../db/db.js';

// Family care-coordinator agent (Roadmap Section 2.3). Pure date-math against data already in
// the system — no clinical inference, no model call. The three reminder kinds mirror the
// roadmap's own example: a senior parent overdue for a checkup, a medication about to run out,
// a child's vaccination check coming due.

export interface CareReminder {
  id: string;
  member_id: string;
  member_name: string;
  kind: 'checkup_overdue' | 'medication_refill' | 'vaccination_check';
  urgency: 'overdue' | 'upcoming';
  message: string;
  reference_date: string | null;
}

const CHECKUP_INTERVAL_DAYS = 365;
const VACCINATION_CHECK_INTERVAL_DAYS = 365;
const REFILL_LOOKAHEAD_DAYS = 3; // flag a refill up to this many days before it runs out
const REFILL_LOOKBACK_DAYS = 7; // ...and up to this many days after, so it doesn't nag forever
const CHILD_AGE_CUTOFF = 18;

function daysBetween(from: Date, to: Date): number {
  return Math.floor((to.getTime() - from.getTime()) / 86400000);
}

function ageInYears(dob: string | null, asOf: Date): number | null {
  if (!dob) return null;
  const d = new Date(dob);
  if (isNaN(d.getTime())) return null;
  let age = asOf.getFullYear() - d.getFullYear();
  const monthDiff = asOf.getMonth() - d.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && asOf.getDate() < d.getDate())) age--;
  return age;
}

/** Best-effort parse of a free-text duration ("10 days", "2 weeks", "1 month") into days.
 * Returns null when it doesn't parse — callers skip the reminder rather than guess a date. */
function parseDurationDays(text: string | null): number | null {
  if (!text) return null;
  const m = text.trim().toLowerCase().match(/(\d+)\s*(day|week|month)/);
  if (!m) return null;
  const n = Number(m[1]);
  if (m[2] === 'day') return n;
  if (m[2] === 'week') return n * 7;
  return n * 30; // month
}

const isoDate = (d: Date) => d.toISOString().slice(0, 10);

export function getCareReminders(familyId: string): CareReminder[] {
  const today = new Date();
  const reminders: CareReminder[] = [];

  const members = db.prepare('SELECT id, name, dob, created_at FROM members WHERE family_id = ? AND archived_at IS NULL').all(familyId) as {
    id: string;
    name: string;
    dob: string | null;
    created_at: string;
  }[];
  if (members.length === 0) return reminders;

  const lastCompletedStmt = db.prepare(`SELECT MAX(datetime) as dt FROM appointments WHERE member_id = ? AND status = 'completed'`);
  const lastVaccinationStmt = db.prepare(
    `SELECT COALESCE(MAX(test_date), MAX(upload_date)) as dt FROM documents WHERE member_id = ? AND document_type = 'vaccination_record'`
  );

  for (const member of members) {
    const lastCompleted = lastCompletedStmt.get(member.id) as { dt: string | null };
    const checkupReference = new Date(lastCompleted.dt ?? member.created_at);
    if (!isNaN(checkupReference.getTime()) && daysBetween(checkupReference, today) > CHECKUP_INTERVAL_DAYS) {
      reminders.push({
        id: `checkup:${member.id}`,
        member_id: member.id,
        member_name: member.name,
        kind: 'checkup_overdue',
        urgency: 'overdue',
        message: lastCompleted.dt
          ? `${member.name} hasn't had a checkup in over a year — last one was ${isoDate(checkupReference)}.`
          : `${member.name} doesn't have a completed checkup on record yet.`,
        reference_date: isoDate(checkupReference),
      });
    }

    const age = ageInYears(member.dob, today);
    if (age !== null && age < CHILD_AGE_CUTOFF) {
      const lastVaccination = lastVaccinationStmt.get(member.id) as { dt: string | null };
      const vaxReference = new Date(lastVaccination.dt ?? member.created_at);
      if (!isNaN(vaxReference.getTime()) && daysBetween(vaxReference, today) > VACCINATION_CHECK_INTERVAL_DAYS) {
        reminders.push({
          id: `vaccination:${member.id}`,
          member_id: member.id,
          member_name: member.name,
          kind: 'vaccination_check',
          urgency: 'overdue',
          message: lastVaccination.dt
            ? `It's been over a year since a vaccination record was added for ${member.name} — worth checking with their pediatrician if a dose is due.`
            : `No vaccination records on file for ${member.name} yet — worth checking with their pediatrician if anything is due.`,
          reference_date: isoDate(vaxReference),
        });
      }
    }
  }

  const memberIds = members.map((m) => m.id);
  const placeholders = memberIds.map(() => '?').join(',');
  const lineItemRows = db
    .prepare(
      `SELECT pli.medicine_name, pli.duration, p.issued_at, p.member_id
       FROM prescription_line_items pli
       JOIN prescriptions p ON p.id = pli.prescription_id
       WHERE p.member_id IN (${placeholders})
       ORDER BY p.issued_at ASC`
    )
    .all(...memberIds) as { medicine_name: string; duration: string | null; issued_at: string; member_id: string }[];

  // Keep only the latest prescription per (member, medicine) — a course that's since been
  // superseded by a refill shouldn't surface a reminder for the old one.
  const latestByMedicine = new Map<string, (typeof lineItemRows)[number]>();
  for (const row of lineItemRows) latestByMedicine.set(`${row.member_id}|${row.medicine_name.toLowerCase()}`, row);

  const memberNameById = new Map(members.map((m) => [m.id, m.name]));
  for (const row of latestByMedicine.values()) {
    const durationDays = parseDurationDays(row.duration);
    if (durationDays === null) continue;
    const issued = new Date(row.issued_at);
    if (isNaN(issued.getTime())) continue;
    const endDate = new Date(issued.getTime() + durationDays * 86400000);
    const daysUntilEnd = daysBetween(today, endDate);
    if (daysUntilEnd > REFILL_LOOKAHEAD_DAYS || daysUntilEnd < -REFILL_LOOKBACK_DAYS) continue;

    const overdue = daysUntilEnd < 0;
    const name = memberNameById.get(row.member_id) ?? '';
    reminders.push({
      id: `medication:${row.member_id}:${row.medicine_name}`,
      member_id: row.member_id,
      member_name: name,
      kind: 'medication_refill',
      urgency: overdue ? 'overdue' : 'upcoming',
      message: overdue
        ? `${name}'s ${row.medicine_name} likely ran out ${Math.abs(daysUntilEnd)} day${Math.abs(daysUntilEnd) === 1 ? '' : 's'} ago — check if a refill is needed.`
        : `${name}'s ${row.medicine_name} is due to run out ${daysUntilEnd === 0 ? 'today' : `in ${daysUntilEnd} day${daysUntilEnd === 1 ? '' : 's'}`}.`,
      reference_date: isoDate(endDate),
    });
  }

  reminders.sort((a, b) => {
    if (a.urgency !== b.urgency) return a.urgency === 'overdue' ? -1 : 1;
    return (a.reference_date ?? '').localeCompare(b.reference_date ?? '');
  });

  return reminders;
}
