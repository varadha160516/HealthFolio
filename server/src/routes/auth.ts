import { Router } from 'express';
import { db } from '../db/db.js';
import { verifyPassword } from '../auth/hash.js';
import { createSession } from '../auth/session.js';
import { requireAuth } from '../middleware/auth.js';

export const authRouter = Router();

interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  role: string;
  display_name: string;
  member_id: string | null;
  provider_id: string | null;
}

authRouter.post('/login', (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) return res.status(400).json({ error: 'email and password are required' });

  const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email) as UserRow | undefined;
  if (!user || !verifyPassword(password, user.password_hash)) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  let familyId: string | null = null;
  if (user.member_id) {
    const member = db.prepare('SELECT family_id FROM members WHERE id = ?').get(user.member_id) as { family_id: string } | undefined;
    familyId = member?.family_id ?? null;
  }

  const session = createSession({
    userId: user.id,
    role: user.role as any,
    displayName: user.display_name,
    memberId: user.member_id,
    familyId,
    providerId: user.provider_id,
  });

  res.json({ token: session.token, role: session.role, displayName: session.displayName, memberId: session.memberId, familyId: session.familyId, providerId: session.providerId });
});

authRouter.get('/me', requireAuth, (req, res) => {
  res.json(req.session);
});
