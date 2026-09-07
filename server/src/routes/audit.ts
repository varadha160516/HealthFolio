import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';
import { getAuditLog } from '../audit.js';

export const auditRouter = Router();

// Section 7.4/8.3 — the member's own Consent & Privacy log, identical in substance to what
// providers see on their side for the same grants.
auditRouter.get('/audit', requireAuth, (req, res) => {
  const memberId = req.query.member_id as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;
  res.json(getAuditLog(memberId));
});
