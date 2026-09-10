import { Router } from 'express';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';

export const invoicesRouter = Router();

function serializeInvoice(row: any) {
  const appt = db.prepare('SELECT id, datetime FROM appointments WHERE id = ?').get(row.appointment_id);
  const provider = db.prepare('SELECT id, name, specialty, gst_number FROM providers WHERE id = ?').get(row.provider_id);
  const member = db.prepare('SELECT id, name, dob, sex FROM members WHERE id = ?').get(row.member_id);
  return { ...row, appointment: appt ?? null, provider, member };
}

// Polled by HealthFolio to detect a new unpaid invoice after a visit completes (same pattern as
// the consent-request poll) -- no push notifications wired up, so this only fires while the app
// is open in the foreground. Family-wide so one poll covers every member's visits, not just
// whichever member happens to be selected on screen.
invoicesRouter.get('/family/invoices', requireAuth, (req, res) => {
  const rows = db
    .prepare('SELECT i.* FROM invoices i JOIN members m ON m.id = i.member_id WHERE m.family_id = ? ORDER BY i.issued_at DESC')
    .all(req.session!.familyId) as any[];
  res.json(rows.map(serializeInvoice));
});

invoicesRouter.get('/members/:id/invoices', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const rows = db.prepare('SELECT * FROM invoices WHERE member_id = ? ORDER BY issued_at DESC').all(req.params.id) as any[];
  res.json(rows.map(serializeInvoice));
});

invoicesRouter.get('/appointments/:id/invoice', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM invoices WHERE appointment_id = ?').get(req.params.id) as any;
  if (!row) return res.status(404).json({ error: 'No invoice for this appointment' });
  if (!assertFamilyAccess(req, res, row.member_id)) return;
  res.json(serializeInvoice(row));
});

// Demo payment only -- no real payment gateway is wired up. Marks the invoice paid immediately;
// payment_method is recorded for what it's worth, but nothing here moves real money.
invoicesRouter.post('/invoices/:id/pay', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM invoices WHERE id = ?').get(req.params.id) as any;
  if (!row) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, row.member_id)) return;
  if (row.status === 'paid') return res.status(409).json({ error: 'Already paid' });
  const { payment_method } = req.body ?? {};
  if (!['card', 'upi', 'netbanking'].includes(payment_method)) return res.status(400).json({ error: 'payment_method must be card, upi, or netbanking' });
  db.prepare(`UPDATE invoices SET status = 'paid', payment_method = ?, paid_at = ? WHERE id = ?`).run(payment_method, now(), row.id);
  res.json({ ok: true });
});
