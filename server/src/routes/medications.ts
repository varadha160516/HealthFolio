import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';

export const medicationsRouter = Router();

function todayParts() {
  const d = new Date();
  return { date: d.toISOString().slice(0, 10), time: d.toTimeString().slice(0, 5), weekday: d.getDay() };
}

function parseTimes(row: any): string[] {
  try {
    return JSON.parse(row.times ?? '[]');
  } catch {
    return [];
  }
}

/** List of every member's schedules, raw — Active/History/Cabinet bucketing happens client-side
 * (same pattern as the Documents tab's category grid), since "active" here just means
 * status = 'active' and the client already needs to group by frequency too. */
medicationsRouter.get('/members/:id/medications', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const rows = db.prepare('SELECT * FROM medication_schedules WHERE member_id = ? ORDER BY created_at DESC').all(req.params.id) as any[];
  res.json(rows.map((r) => ({ ...r, times: parseTimes(r) })));
});

// Section 5 of the request — "Today's medications": scheduled slots expanded from each active
// schedule's own times, plus PRN medicines shown separately with their own last-taken readout
// rather than a fixed time slot.
medicationsRouter.get('/members/:id/medications/today', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const { date, time, weekday } = todayParts();
  const schedules = db
    .prepare("SELECT * FROM medication_schedules WHERE member_id = ? AND status = 'active'")
    .all(req.params.id) as any[];
  const logStmt = db.prepare('SELECT * FROM medication_dose_logs WHERE schedule_id = ? AND dose_date = ? AND (dose_time = ? OR (dose_time IS NULL AND ? IS NULL))');

  const scheduled: any[] = [];
  const prn: any[] = [];

  for (const s of schedules) {
    if (s.frequency === 'as_needed') {
      const lastLog = db
        .prepare("SELECT * FROM medication_dose_logs WHERE schedule_id = ? AND status = 'taken' ORDER BY dose_date DESC, logged_at DESC LIMIT 1")
        .get(s.id) as any;
      prn.push({ schedule_id: s.id, medicine_name: s.medicine_name, strength: s.strength, dose_amount: s.dose_amount, last_taken_at: lastLog?.logged_at ?? null });
      continue;
    }
    if (s.frequency === 'weekly' && s.day_of_week !== weekday) continue;
    for (const t of parseTimes(s)) {
      const log = logStmt.get(s.id, date, t, t) as any;
      const status = log ? log.status : t <= time ? 'due' : 'upcoming';
      scheduled.push({ schedule_id: s.id, medicine_name: s.medicine_name, strength: s.strength, dose_amount: s.dose_amount, time: t, status });
    }
  }

  scheduled.sort((a, b) => a.time.localeCompare(b.time));
  res.json({ date, scheduled, prn });
});

medicationsRouter.get('/medications/:id', requireAuth, (req, res) => {
  const schedule = db.prepare('SELECT * FROM medication_schedules WHERE id = ?').get(req.params.id) as any;
  if (!schedule) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, schedule.member_id)) return;

  let source: any = null;
  if (schedule.prescription_line_item_id) {
    const lineItem = db.prepare('SELECT * FROM prescription_line_items WHERE id = ?').get(schedule.prescription_line_item_id) as any;
    if (lineItem) {
      const prescription = db.prepare('SELECT * FROM prescriptions WHERE id = ?').get(lineItem.prescription_id) as any;
      const document = prescription?.document_id ? db.prepare('SELECT * FROM documents WHERE id = ?').get(prescription.document_id) : null;
      source = document ? { document_id: document.id, document_type: document.document_type, upload_date: document.upload_date } : null;
    }
  }

  const { date, time } = todayParts();
  const logStmt = db.prepare('SELECT * FROM medication_dose_logs WHERE schedule_id = ? AND dose_date = ? AND (dose_time = ? OR (dose_time IS NULL AND ? IS NULL))');
  const today = parseTimes(schedule).map((t) => {
    const log = logStmt.get(schedule.id, date, t, t) as any;
    return { time: t, status: log ? log.status : t <= time ? 'due' : 'upcoming' };
  });

  res.json({ schedule: { ...schedule, times: parseTimes(schedule) }, source, today });
});

medicationsRouter.post('/members/:id/medications', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const { medicine_name, strength, dose_amount, frequency, times, day_of_week, start_date, end_date, prescribed_by, purpose, prescription_line_item_id } = req.body ?? {};
  if (!medicine_name || !frequency || !start_date) return res.status(400).json({ error: 'medicine_name, frequency and start_date are required' });
  if (!['daily', 'weekly', 'as_needed'].includes(frequency)) return res.status(400).json({ error: 'Invalid frequency' });

  const id = uuid();
  db.prepare(
    `INSERT INTO medication_schedules
       (id, member_id, prescription_line_item_id, medicine_name, strength, dose_amount, frequency, times, day_of_week, start_date, end_date, prescribed_by, purpose, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)`
  ).run(
    id,
    req.params.id,
    prescription_line_item_id ?? null,
    medicine_name,
    strength ?? null,
    dose_amount ?? null,
    frequency,
    JSON.stringify(frequency === 'as_needed' ? [] : times ?? []),
    frequency === 'weekly' ? (day_of_week ?? new Date().getDay()) : null,
    start_date,
    end_date ?? null,
    prescribed_by ?? null,
    purpose ?? null,
    now()
  );
  res.status(201).json({ id });
});

medicationsRouter.patch('/medications/:id', requireAuth, (req, res) => {
  const schedule = db.prepare('SELECT member_id FROM medication_schedules WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!schedule) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, schedule.member_id)) return;

  const fields = ['medicine_name', 'strength', 'dose_amount', 'frequency', 'day_of_week', 'start_date', 'end_date', 'prescribed_by', 'purpose', 'status'] as const;
  const updates: string[] = [];
  const values: any[] = [];
  for (const f of fields) {
    if (Object.prototype.hasOwnProperty.call(req.body ?? {}, f)) {
      updates.push(`${f} = ?`);
      values.push(req.body[f]);
    }
  }
  if (Object.prototype.hasOwnProperty.call(req.body ?? {}, 'times')) {
    updates.push('times = ?');
    values.push(JSON.stringify(req.body.times ?? []));
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
  values.push(req.params.id);
  db.prepare(`UPDATE medication_schedules SET ${updates.join(', ')} WHERE id = ?`).run(...values);
  res.json({ ok: true });
});

medicationsRouter.delete('/medications/:id', requireAuth, (req, res) => {
  const schedule = db.prepare('SELECT member_id FROM medication_schedules WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!schedule) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, schedule.member_id)) return;
  db.prepare('DELETE FROM medication_dose_logs WHERE schedule_id = ?').run(req.params.id);
  db.prepare('DELETE FROM medication_schedules WHERE id = ?').run(req.params.id);
  res.status(204).end();
});

// Logs a Taken/Skip action for one slot. Upserted on (schedule_id, dose_date, dose_time) so
// tapping a different action for the same dose replaces the earlier one rather than stacking logs.
medicationsRouter.post('/medications/:id/doses', requireAuth, (req, res) => {
  const schedule = db.prepare('SELECT member_id FROM medication_schedules WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!schedule) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, schedule.member_id)) return;

  const { date, time, status } = req.body ?? {};
  if (!date || !status || !['taken', 'skipped'].includes(status)) return res.status(400).json({ error: 'date and a valid status are required' });

  const existing = db
    .prepare('SELECT id FROM medication_dose_logs WHERE schedule_id = ? AND dose_date = ? AND (dose_time = ? OR (dose_time IS NULL AND ? IS NULL))')
    .get(req.params.id, date, time ?? null, time ?? null) as { id: string } | undefined;

  if (existing) {
    db.prepare('UPDATE medication_dose_logs SET status = ?, logged_at = ? WHERE id = ?').run(status, now(), existing.id);
    return res.json({ id: existing.id });
  }
  const id = uuid();
  db.prepare('INSERT INTO medication_dose_logs (id, schedule_id, member_id, dose_date, dose_time, status, logged_at) VALUES (?, ?, ?, ?, ?, ?, ?)').run(
    id,
    req.params.id,
    schedule.member_id,
    date,
    time ?? null,
    status,
    now()
  );
  res.status(201).json({ id });
});

