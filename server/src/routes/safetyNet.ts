import { Router } from 'express';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';
import { runSafetyCheck } from '../pipeline/safetyNet.js';

export const safetyNetRouter = Router();

safetyNetRouter.get('/members/:id/safety-flags', requireAuth, (req, res) => {
  if (!assertFamilyAccess(req, res, req.params.id)) return;
  res.json(runSafetyCheck(req.params.id));
});

function resolveFlag(req: any, res: any) {
  const flag = db.prepare('SELECT * FROM safety_flags WHERE id = ?').get(req.params.id) as { id: string; member_id: string; status: string } | undefined;
  if (!flag) {
    res.status(404).json({ error: 'Not found' });
    return null;
  }
  if (!assertFamilyAccess(req, res, flag.member_id)) return null;
  return flag;
}

safetyNetRouter.post('/safety-flags/:id/dismiss', requireAuth, (req, res) => {
  const flag = resolveFlag(req, res);
  if (!flag) return;
  db.prepare(`UPDATE safety_flags SET status = 'dismissed', resolved_at = ? WHERE id = ?`).run(now(), flag.id);
  res.json({ ok: true });
});

safetyNetRouter.post('/safety-flags/:id/discussed', requireAuth, (req, res) => {
  const flag = resolveFlag(req, res);
  if (!flag) return;
  db.prepare(`UPDATE safety_flags SET status = 'discussed', resolved_at = ? WHERE id = ?`).run(now(), flag.id);
  res.json({ ok: true });
});

// Home Screen's aggregate badge — how many open flags exist across the whole family, without the
// dashboard having to fetch (and recompute) every member's full flag list just to show a count.
safetyNetRouter.get('/family/safety-flags-summary', requireAuth, (req, res) => {
  const members = db.prepare('SELECT id, name FROM members WHERE family_id = ? AND archived_at IS NULL').all(req.session!.familyId) as { id: string; name: string }[];
  const summary = members
    .map((m) => ({ memberId: m.id, memberName: m.name, openCount: runSafetyCheck(m.id).open.length }))
    .filter((s) => s.openCount > 0);
  res.json(summary);
});
