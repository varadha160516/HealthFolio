import { db } from '../db/db.js';

// Medication adherence for the doctor, from what the patient logged in HealthFolio
// (medication_dose_logs). Shown inside the consent window only — it's served as part of
// unlockedData, the same fail-closed gate as the rest of the patient's records.
//
// What this number is, and isn't: it is how many scheduled doses the patient LOGGED as taken. A dose
// with no log is reported as "not logged", never as "missed" — a patient who doesn't use the
// reminders looks identical to one who skipped everything, and presenting that as non-adherence
// would be a claim the data can't support. Pure structured-fact counting, no inference.

export interface AdherenceSchedule {
  id: string;
  medicine_name: string;
  strength: string | null;
  frequency: 'daily' | 'weekly' | 'as_needed';
  times: string[];
  day_of_week: number | null;
  start_date: string;
  end_date: string | null;
  prescribed_by_provider_id: string | null;
}

export interface AdherenceLog {
  schedule_id: string;
  dose_date: string;
  status: 'taken' | 'skipped';
}

export interface MedicationAdherence {
  schedule_id: string;
  medicine_name: string;
  strength: string | null;
  prescribed_by_you: boolean;
  frequency: 'daily' | 'weekly' | 'as_needed';
  days_counted: number;
  expected: number;
  taken: number;
  skipped: number;
  not_logged: number;
  taken_pct: number | null;
  /** As-needed medicines have no schedule to measure against — just how often they were used. */
  as_needed_uses: number | null;
}

export interface AdherenceReport {
  window: { from: string; to: string; days: number };
  medications: MedicationAdherence[];
}

const DAY_MS = 86_400_000;
export function addDays(date: string, n: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + n * DAY_MS).toISOString().slice(0, 10);
}
function weekday(date: string): number {
  return new Date(`${date}T00:00:00Z`).getUTCDay();
}

/**
 * The window is the last `windowDays` COMPLETED days (ending yesterday). Today is left out on
 * purpose: its later doses haven't happened yet, and the server's calendar day can differ from the
 * patient's near midnight — judging a half-finished day would make a fine patient look non-adherent.
 * Logs are matched per day rather than per exact time slot, so a schedule whose times were edited
 * after doses were logged doesn't turn those logs into phantom "not logged" doses.
 */
export function computeAdherence(
  schedules: AdherenceSchedule[],
  logs: AdherenceLog[],
  today: string,
  viewerProviderId: string,
  windowDays = 7
): AdherenceReport {
  const to = addDays(today, -1);
  const from = addDays(to, -(windowDays - 1));
  const medications: MedicationAdherence[] = [];

  for (const s of schedules) {
    if (s.end_date && s.end_date < from) continue; // the course finished before this window
    const mine = logs.filter((l) => l.schedule_id === s.id);
    const base = {
      schedule_id: s.id,
      medicine_name: s.medicine_name,
      strength: s.strength,
      prescribed_by_you: s.prescribed_by_provider_id !== null && s.prescribed_by_provider_id === viewerProviderId,
      frequency: s.frequency,
    };

    if (s.frequency === 'as_needed') {
      const uses = mine.filter((l) => l.status === 'taken' && l.dose_date >= from && l.dose_date <= today).length;
      medications.push({ ...base, days_counted: 0, expected: 0, taken: 0, skipped: 0, not_logged: 0, taken_pct: null, as_needed_uses: uses });
      continue;
    }

    const effFrom = s.start_date > from ? s.start_date : from;
    const effTo = s.end_date && s.end_date < to ? s.end_date : to;
    let expected = 0;
    let taken = 0;
    let skipped = 0;
    let daysCounted = 0;
    for (let d = effFrom; d <= effTo; d = addDays(d, 1)) {
      const perDay = s.frequency === 'daily' ? Math.max(s.times.length, 1) : s.day_of_week !== null && weekday(d) === s.day_of_week ? 1 : 0;
      if (perDay === 0) continue;
      daysCounted++;
      const dayLogs = mine.filter((l) => l.dose_date === d);
      const t = Math.min(perDay, dayLogs.filter((l) => l.status === 'taken').length);
      const sk = Math.min(perDay - t, dayLogs.filter((l) => l.status === 'skipped').length);
      expected += perDay;
      taken += t;
      skipped += sk;
    }
    medications.push({
      ...base,
      days_counted: daysCounted,
      expected,
      taken,
      skipped,
      not_logged: expected - taken - skipped,
      taken_pct: expected > 0 ? Math.round((taken / expected) * 100) : null,
      as_needed_uses: null,
    });
  }

  medications.sort((a, b) => Number(b.prescribed_by_you) - Number(a.prescribed_by_you) || a.medicine_name.localeCompare(b.medicine_name));
  return { window: { from, to, days: windowDays }, medications };
}

/** Loads the patient's active schedules + recent dose logs and computes the report for the doctor
 * viewing this visit. Whether a schedule is "prescribed by you" comes from the prescription its
 * line item belongs to — never from the free-text prescribed_by the patient may have typed. */
export function adherenceForVisit(memberId: string, viewerProviderId: string, today = new Date().toISOString().slice(0, 10), windowDays = 7): AdherenceReport {
  const rows = db
    .prepare(
      `SELECT s.id, s.medicine_name, s.strength, s.frequency, s.times, s.day_of_week, s.start_date, s.end_date,
              (SELECT rx.provider_id FROM prescription_line_items li JOIN prescriptions rx ON rx.id = li.prescription_id
                WHERE li.id = s.prescription_line_item_id) AS prescribed_by_provider_id
       FROM medication_schedules s WHERE s.member_id = ? AND s.status = 'active'`
    )
    .all(memberId) as any[];

  const schedules: AdherenceSchedule[] = rows.map((r) => {
    let times: string[] = [];
    try {
      times = JSON.parse(r.times ?? '[]');
    } catch {
      // malformed times are treated as one dose a day rather than failing the whole visit screen
    }
    return { ...r, times };
  });

  const from = addDays(today, -windowDays);
  const logs = db
    .prepare('SELECT schedule_id, dose_date, status FROM medication_dose_logs WHERE member_id = ? AND dose_date >= ?')
    .all(memberId, from) as unknown as AdherenceLog[];

  return computeAdherence(schedules, logs, today, viewerProviderId, windowDays);
}
