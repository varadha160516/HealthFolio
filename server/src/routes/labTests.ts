import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';

export const labTestsRouter = Router();

function parseBooking(row: any) {
  return { ...row, test_names: JSON.parse(row.test_names) };
}

/** Bookings can be for a guest (no member_id) — assertFamilyAccess needs a real memberId, so
 * bookings are otherwise scoped by comparing family_id directly against the session. */
function assertBookingFamilyAccess(req: any, res: any, booking: { family_id: string } | undefined): boolean {
  if (!booking) {
    res.status(404).json({ error: 'Not found' });
    return false;
  }
  if (booking.family_id !== req.session.familyId) {
    res.status(403).json({ error: 'Not a member of your family' });
    return false;
  }
  return true;
}

labTestsRouter.get('/lab-tests/catalog', requireAuth, (_req, res) => {
  res.json(db.prepare('SELECT * FROM lab_test_catalog ORDER BY name').all());
});

// All bookings (member + guest) for the signed-in family — the Lab Tests home tab's own list.
labTestsRouter.get('/family/lab-test-bookings', requireAuth, (req, res) => {
  const rows = db.prepare('SELECT * FROM lab_test_bookings WHERE family_id = ? ORDER BY created_at DESC').all(req.session.familyId) as any[];
  res.json(rows.map(parseBooking));
});

// One member's bookings — the member profile screen's own Lab Tests tab.
labTestsRouter.get('/members/:id/lab-test-bookings', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  const rows = db.prepare('SELECT * FROM lab_test_bookings WHERE member_id = ? ORDER BY created_at DESC').all(req.params.id) as any[];
  res.json(rows.map(parseBooking));
});

labTestsRouter.post('/lab-test-bookings', requireAuth, (req, res) => {
  const { member_id, guest_name, guest_age, guest_mobile, test_names, lab_name, booked_date, time_slot } = req.body ?? {};
  if (!Array.isArray(test_names) || test_names.length === 0) return res.status(400).json({ error: 'test_names must be a non-empty array' });
  if (!member_id && !guest_name) return res.status(400).json({ error: 'Either member_id or guest_name is required' });
  if (member_id && guest_name) return res.status(400).json({ error: 'Provide member_id or guest_name, not both' });
  if (member_id && !assertFamilyAccess(req, res, member_id)) return;

  const id = uuid();
  // Client now picks the date explicitly (Choose date & time step); still fall back to "next
  // available" if it's ever omitted, same as before.
  const bookedDate = booked_date ?? new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  db.prepare(
    `INSERT INTO lab_test_bookings (id, family_id, member_id, guest_name, guest_age, guest_mobile, test_names, lab_name, status, booked_date, time_slot, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'collection_scheduled', ?, ?, ?)`
  ).run(
    id,
    req.session.familyId,
    member_id ?? null,
    guest_name ?? null,
    guest_age ?? null,
    guest_mobile ?? null,
    JSON.stringify(test_names),
    lab_name ?? 'Metropolis Lab',
    bookedDate,
    time_slot ?? null,
    now()
  );
  res.status(201).json({ id });
});

labTestsRouter.patch('/lab-test-bookings/:id', requireAuth, (req, res) => {
  const booking = db.prepare('SELECT * FROM lab_test_bookings WHERE id = ?').get(req.params.id) as any;
  if (!assertBookingFamilyAccess(req, res, booking)) return;

  const { status, document_id, booked_date, time_slot } = req.body ?? {};
  // Reschedule (booked_date/time_slot) and cancel are only meaningful before collection has
  // happened — once a sample's been collected the booking is on its way to a report and calling
  // it off or moving the date no longer makes sense.
  if ((status === 'cancelled' || booked_date !== undefined || time_slot !== undefined) && booking.status !== 'collection_scheduled') {
    return res.status(409).json({ error: `Cannot reschedule or cancel a booking that's ${booking.status.replace(/_/g, ' ')}` });
  }
  const updates: string[] = [];
  const values: any[] = [];
  if (status !== undefined) {
    if (!['collection_scheduled', 'processing', 'report_ready', 'cancelled'].includes(status)) return res.status(400).json({ error: 'Invalid status' });
    updates.push('status = ?');
    values.push(status);
  }
  if (document_id !== undefined) {
    updates.push('document_id = ?');
    values.push(document_id);
  }
  if (booked_date !== undefined) {
    updates.push('booked_date = ?');
    values.push(booked_date);
  }
  if (time_slot !== undefined) {
    updates.push('time_slot = ?');
    values.push(time_slot);
  }
  if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
  values.push(req.params.id);
  db.prepare(`UPDATE lab_test_bookings SET ${updates.join(', ')} WHERE id = ?`).run(...values);

  // Doctor App notification — only for tests a doctor actually ordered mid-consultation; a
  // member's own self-booked test has no provider to notify.
  if (status === 'report_ready' && booking.ordered_by_provider_id) {
    const testNames = JSON.parse(booking.test_names).join(', ');
    const member = booking.member_id ? (db.prepare('SELECT name FROM members WHERE id = ?').get(booking.member_id) as { name: string } | undefined) : undefined;
    db.prepare(
      `INSERT INTO provider_notifications (id, provider_id, type, title, body, related_appointment_id, created_at) VALUES (?, ?, 'lab_report_ready', ?, ?, ?, ?)`
    ).run(uuid(), booking.ordered_by_provider_id, 'Lab report available', `${member?.name ?? booking.guest_name ?? 'The patient'}'s ${testNames} report is available.`, booking.appointment_id ?? null, now());
  }

  res.json({ ok: true });
});
