import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';
import { continueIntake, IntakeTurn } from '../pipeline/symptomIntake.js';

export const symptomsRouter = Router();

interface EntryRow {
  id: string;
  member_id: string;
  status: 'in_progress' | 'completed';
  raw_description: string;
  onset: string | null;
  severity: string | null;
  duration: string | null;
  associated_factors: string | null;
  urgent_flag: number;
  created_at: string;
  updated_at: string;
}

function assertEntryAccess(req: any, res: any, entryId: string): EntryRow | null {
  const entry = db.prepare('SELECT * FROM symptom_entries WHERE id = ?').get(entryId) as EntryRow | undefined;
  if (!entry) {
    res.status(404).json({ error: 'Not found' });
    return null;
  }
  if (!assertFamilyAccess(req, res, entry.member_id)) return null;
  return entry;
}

function insertMessage(entryId: string, role: 'user' | 'assistant', content: string) {
  db.prepare('INSERT INTO symptom_intake_messages (id, entry_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)').run(uuid(), entryId, role, content, now());
}

symptomsRouter.get('/members/:id/symptom-entries', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const rows = db.prepare('SELECT * FROM symptom_entries WHERE member_id = ? ORDER BY created_at DESC').all(req.params.id);
  res.json(rows);
});

// Doctor-entered symptom/chief-complaint history from past consultations — a separate store from
// the member's own symptom_entries (self-logged via the intake agent), surfaced here read-only so
// the Symptoms tab can show one merged, source-tagged history without the two stores merging data.
symptomsRouter.get('/members/:id/consultation-symptom-history', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const rows = db
    .prepare(
      `SELECT cn.appointment_id, cn.chief_complaint, cn.symptom_duration, cn.symptoms, cn.created_at, a.datetime AS visit_datetime, p.name AS provider_name
       FROM consultation_notes cn
       JOIN appointments a ON a.id = cn.appointment_id
       JOIN providers p ON p.id = cn.provider_id
       WHERE cn.member_id = ? AND (cn.chief_complaint IS NOT NULL OR cn.symptoms IS NOT NULL)
       ORDER BY cn.created_at DESC`
    )
    .all(req.params.id) as any[];
  res.json(
    rows
      .map((r) => ({ ...r, symptoms: r.symptoms ? JSON.parse(r.symptoms) : [] }))
      .filter((r) => (r.chief_complaint && r.chief_complaint.trim()) || r.symptoms.length > 0)
  );
});

symptomsRouter.get('/symptom-entries/:id', requireAuth, (req, res) => {
  const entry = assertEntryAccess(req, res, req.params.id);
  if (!entry) return;
  const messages = db.prepare('SELECT id, role, content, created_at FROM symptom_intake_messages WHERE entry_id = ? ORDER BY created_at ASC').all(entry.id);
  res.json({ ...entry, messages });
});

// Starts a new entry with the member's own opening description — the first user turn (Roadmap
// Section 2.4). Urgent detection runs on this first message exactly the same as every later one.
symptomsRouter.post('/members/:id/symptom-entries', requireAuth, async (req, res) => {
  const memberId = req.params.id;
  if (!assertFamilyAccess(req, res, memberId)) return;
  const description = (req.body?.message as string | undefined)?.trim();
  if (!description) return res.status(400).json({ error: 'message is required' });

  const session = req.session!;
  const entryId = uuid();
  const createdAt = now();
  db.prepare(
    `INSERT INTO symptom_entries (id, member_id, logged_by_user_id, status, raw_description, onset, severity, duration, associated_factors, urgent_flag, created_at, updated_at)
     VALUES (?, ?, ?, 'in_progress', ?, NULL, NULL, NULL, NULL, 0, ?, ?)`
  ).run(entryId, memberId, session.userId, description, createdAt, createdAt);
  insertMessage(entryId, 'user', description);

  try {
    const result = await continueIntake([{ role: 'user', content: description }]);
    const entry = applyIntakeResult(entryId, result);
    res.status(201).json(entry);
  } catch (err) {
    console.error(err);
    res.status(502).json({ error: 'The symptom intake assistant is unavailable right now — please try again.' });
  }
});

// Continues an in-progress entry's clarifying Q&A (Roadmap Section 2.4).
symptomsRouter.post('/symptom-entries/:id/messages', requireAuth, async (req, res) => {
  const entry = assertEntryAccess(req, res, req.params.id);
  if (!entry) return;
  if (entry.status === 'completed') return res.status(409).json({ error: 'This entry is already complete' });
  const message = (req.body?.message as string | undefined)?.trim();
  if (!message) return res.status(400).json({ error: 'message is required' });

  insertMessage(entry.id, 'user', message);
  const history = db.prepare('SELECT role, content FROM symptom_intake_messages WHERE entry_id = ? ORDER BY created_at ASC').all(entry.id) as unknown as IntakeTurn[];

  try {
    const result = await continueIntake(history);
    const updated = applyIntakeResult(entry.id, result);
    res.json(updated);
  } catch (err) {
    console.error(err);
    res.status(502).json({ error: 'The symptom intake assistant is unavailable right now — please try again.' });
  }
});

function applyIntakeResult(entryId: string, result: Awaited<ReturnType<typeof continueIntake>>) {
  if (result.kind === 'urgent') {
    insertMessage(entryId, 'assistant', result.message);
    db.prepare(`UPDATE symptom_entries SET status = 'completed', urgent_flag = 1, updated_at = ? WHERE id = ?`).run(now(), entryId);
  } else if (result.kind === 'question') {
    insertMessage(entryId, 'assistant', result.question);
    db.prepare(`UPDATE symptom_entries SET updated_at = ? WHERE id = ?`).run(now(), entryId);
  } else {
    insertMessage(entryId, 'assistant', result.noteToMember);
    db.prepare(
      `UPDATE symptom_entries SET status = 'completed', onset = ?, severity = ?, duration = ?, associated_factors = ?, updated_at = ? WHERE id = ?`
    ).run(result.fields.onset, result.fields.severity, result.fields.duration, result.fields.associated_factors, now(), entryId);
  }
  const entry = db.prepare('SELECT * FROM symptom_entries WHERE id = ?').get(entryId) as unknown as EntryRow;
  const messages = db.prepare('SELECT id, role, content, created_at FROM symptom_intake_messages WHERE entry_id = ? ORDER BY created_at ASC').all(entryId);
  return { ...entry, messages };
}
