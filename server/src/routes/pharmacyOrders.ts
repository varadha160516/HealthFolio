import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';

export const pharmacyOrdersRouter = Router();

function parseItems(row: any): any[] {
  try {
    return JSON.parse(row.line_items ?? '[]');
  } catch {
    return [];
  }
}
function serialize(row: any) {
  return { ...row, line_items: parseItems(row) };
}

pharmacyOrdersRouter.get('/members/:id/pharmacy-orders', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const rows = db.prepare('SELECT * FROM pharmacy_orders WHERE member_id = ? ORDER BY created_at DESC').all(req.params.id) as any[];
  res.json(rows.map(serialize));
});

// Ordering straight from whichever active medications the member picks on the Medications tab --
// no separate catalog/inventory, this is a demo delivery flow (estimated_delivery_date computed
// at order time, no real courier). prescription_id is optional context, not required: a member
// may order a mix of medicines that trace back to different prescriptions (or none, for a
// manually-added medication).
pharmacyOrdersRouter.post('/members/:id/pharmacy-orders', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;

  const { line_items, delivery_address, prescription_id } = req.body ?? {};
  if (!Array.isArray(line_items) || line_items.length === 0) return res.status(400).json({ error: 'line_items is required' });

  const id = uuid();
  const eta = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString();
  db.prepare(
    `INSERT INTO pharmacy_orders (id, member_id, prescription_id, line_items, delivery_address, status, estimated_delivery_date, created_at)
     VALUES (?, ?, ?, ?, ?, 'placed', ?, ?)`
  ).run(id, req.params.id, prescription_id ?? null, JSON.stringify(line_items), delivery_address ?? null, eta, now());
  res.status(201).json({ id });
});

pharmacyOrdersRouter.patch('/pharmacy-orders/:id', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM pharmacy_orders WHERE id = ?').get(req.params.id) as any;
  if (!row) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, row.member_id)) return;
  const { status } = req.body ?? {};
  if (!['delivered', 'cancelled'].includes(status)) return res.status(400).json({ error: 'status must be delivered or cancelled' });
  if (row.status !== 'placed') return res.status(409).json({ error: `Cannot change status from ${row.status}` });
  db.prepare('UPDATE pharmacy_orders SET status = ? WHERE id = ?').run(status, row.id);
  res.json({ ok: true });
});
