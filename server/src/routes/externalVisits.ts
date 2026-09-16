import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';

export const externalVisitsRouter = Router();

// A member's own record of a visit to a doctor not on CareLoop — see schema.sql's comment on
// external_visits for the full rationale. Purely self-declared; the real payoff is that any
// medications the member logs from this visit (via the normal Add Medication flow, prescribed_by
// prefilled from here) feed straight into safetyNet.ts's existing cross-provider checks.

externalVisitsRouter.get('/members/:id/external-visits', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const rows = db.prepare('SELECT * FROM external_visits WHERE member_id = ? ORDER BY visit_date DESC, created_at DESC').all(req.params.id);
  res.json(rows);
});

externalVisitsRouter.post('/members/:id/external-visits', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const { doctor_name, hospital_name, visit_date, diagnosis, notes } = req.body ?? {};
  if (!doctor_name || !String(doctor_name).trim()) return res.status(400).json({ error: 'doctor_name is required' });
  if (!visit_date) return res.status(400).json({ error: 'visit_date is required' });

  const id = uuid();
  db.prepare(
    `INSERT INTO external_visits (id, member_id, doctor_name, hospital_name, visit_date, diagnosis, notes, logged_by_user_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(id, req.params.id, String(doctor_name).trim(), hospital_name ?? null, visit_date, diagnosis ?? null, notes ?? null, req.session!.userId, now());

  res.status(201).json({ id });
});

externalVisitsRouter.delete('/external-visits/:id', requireAuth, (req, res) => {
  const visit = db.prepare('SELECT member_id FROM external_visits WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!visit) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, visit.member_id)) return;
  db.prepare('DELETE FROM external_visits WHERE id = ?').run(req.params.id);
  res.status(204).end();
});
