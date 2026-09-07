import { Router } from 'express';
import { db } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';

export const prescriptionsRouter = Router();

// Section 8.3 — "the new prescription already sitting in their records" with no member action needed.
prescriptionsRouter.get('/prescriptions', requireAuth, (req, res) => {
  const memberId = req.query.member_id as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;
  const prescriptions = db
    .prepare('SELECT * FROM prescriptions WHERE member_id = ? ORDER BY issued_at DESC')
    .all(memberId) as any[];
  const lineItemStmt = db.prepare('SELECT * FROM prescription_line_items WHERE prescription_id = ?');
  for (const p of prescriptions) {
    p.line_items = lineItemStmt.all(p.id);
  }
  res.json(prescriptions);
});
