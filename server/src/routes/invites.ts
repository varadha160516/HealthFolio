import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { logAudit } from '../audit.js';
import { hashPassword } from '../auth/hash.js';
import { createSession } from '../auth/session.js';
import { overLimit } from '../rateLimit.js';
import { toWaNumber, withDr } from '../whatsapp.js';
import {
  displayInviteCode,
  downloadUrl,
  INVITE_TTL_DAYS,
  INVITES_PER_PROVIDER_PER_DAY,
  inviteMessage,
  newInviteCode,
  normalizeInviteCode,
  phoneHasAccount,
} from '../invites.js';

export const invitesRouter = Router();

interface InviteRow {
  id: string;
  code: string;
  provider_id: string;
  invited_by_user_id: string;
  phone: string;
  wa_number: string;
  name: string | null;
  member_id: string | null;
  created_at: string;
  expires_at: string;
  used_at: string | null;
  used_by_member_id: string | null;
}

const daysFromNow = (d: number) => new Date(Date.now() + d * 24 * 60 * 60 * 1000).toISOString();

function providerInfo(providerId: string) {
  return db
    .prepare('SELECT p.id AS id, p.type AS type, p.name AS name, p.clinic_id AS clinic_id, c.name AS clinic FROM providers p LEFT JOIN clinics c ON c.id = p.clinic_id WHERE p.id = ?')
    .get(providerId) as { id: string; type: string; name: string; clinic_id: string | null; clinic: string | null } | undefined;
}

/** How the invite introduces its sender: a doctor by name (and clinic), the front desk as the clinic. */
function senderLabel(p: { type: string; name: string; clinic: string | null }): string {
  if (p.type === 'doctor') return `${withDr(p.name)}${p.clinic ? ` (${p.clinic})` : ''}`;
  return p.clinic ?? 'Your clinic';
}

const staff = [requireAuth, requireRole('provider_doctor', 'provider_clinic_admin')];

// ---------------------------------------------------------------------------------------------
// Sending an invite (doctor or front desk)
// ---------------------------------------------------------------------------------------------

invitesRouter.post('/invites', ...staff, (req, res) => {
  const session = req.session!;
  const sender = providerInfo(session.providerId!);
  if (!sender) return res.status(403).json({ error: 'Your account is not linked to a provider.' });
  if (sender.type !== 'doctor' && !sender.clinic_id) return res.status(403).json({ error: 'Your account is not attached to a clinic.' });

  const { phone, name, member_id, patient_agreed } = req.body ?? {};
  // The clinic asserts, each time, that this person agreed to hear from them. Nothing is sent from here
  // either way, but the attestation is recorded so it isn't just an assumption.
  if (patient_agreed !== true) return res.status(400).json({ error: 'Confirm that the patient agreed to receive this invite.' });

  const url = downloadUrl();
  if (!url) return res.status(503).json({ error: 'Invites are not switched on yet: the app download link has not been set on the server (HEALTHFOLIO_DOWNLOAD_URL).' });

  let invitePhone: string;
  let inviteName: string | null;
  let claimMemberId: string | null = null;

  if (member_id) {
    // Someone the clinic itself registered at the counter: they claim that record when they join.
    const m = db.prepare('SELECT id, name, phone, archived_at, registered_by_provider_id FROM members WHERE id = ?').get(member_id) as
      | { id: string; name: string; phone: string | null; archived_at: string | null; registered_by_provider_id: string | null }
      | undefined;
    if (!m || m.archived_at) return res.status(404).json({ error: 'Patient not found' });
    if (db.prepare('SELECT 1 FROM users WHERE member_id = ?').get(m.id)) return res.status(409).json({ error: 'This patient already uses HealthFolio.', already_on_healthfolio: true });
    const registrar = m.registered_by_provider_id ? providerInfo(m.registered_by_provider_id) : undefined;
    const mine = !!registrar && (registrar.id === sender.id || (!!sender.clinic_id && registrar.clinic_id === sender.clinic_id));
    if (!mine) return res.status(403).json({ error: 'You can only invite patients your own clinic registered.' });
    if (!toWaNumber(m.phone)) return res.status(409).json({ error: "This patient's mobile number can't be used for WhatsApp." });
    invitePhone = m.phone!;
    inviteName = m.name;
    claimMemberId = m.id;
  } else {
    if (typeof phone !== 'string' || !toWaNumber(phone)) return res.status(400).json({ error: 'Enter a valid mobile number.' });
    if (name !== undefined && name !== null && (typeof name !== 'string' || name.trim().length > 60)) return res.status(400).json({ error: 'Name is too long.' });
    invitePhone = phone.trim();
    inviteName = typeof name === 'string' && name.trim() ? name.trim() : null;
  }
  const wa = toWaNumber(invitePhone)!;

  if (!claimMemberId && phoneHasAccount(wa)) return res.status(409).json({ error: 'This number already uses HealthFolio.', already_on_healthfolio: true });

  const today = now().slice(0, 10);
  const sentToday = (db.prepare('SELECT COUNT(*) AS c FROM patient_invites WHERE provider_id = ? AND substr(created_at, 1, 10) = ?').get(sender.id, today) as { c: number }).c;
  if (sentToday >= INVITES_PER_PROVIDER_PER_DAY) return res.status(429).json({ error: `You have reached today's limit of ${INVITES_PER_PROVIDER_PER_DAY} invites.` });

  const scopeIds = scopeProviderIds(sender);
  const before = db
    .prepare(`SELECT MAX(created_at) AS at FROM patient_invites WHERE wa_number = ? AND provider_id IN (${scopeIds.map(() => '?').join(',')})`)
    .get(wa, ...scopeIds) as { at: string | null };

  const id = uuid();
  const code = newInviteCode();
  const expiresAt = daysFromNow(INVITE_TTL_DAYS);
  db.prepare(
    `INSERT INTO patient_invites (id, code, provider_id, invited_by_user_id, phone, wa_number, name, member_id, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(id, code, sender.id, session.userId, invitePhone, wa, inviteName, claimMemberId, now(), expiresAt);

  const text = inviteMessage({ sender: senderLabel(sender), firstName: inviteName ? inviteName.split(/\s+/)[0] : null, code, expiresAt, url });
  // Last four digits only — the audit log shouldn't hold a phone book.
  logAudit(session.userId, session.role, 'patient_invited', claimMemberId, { inviteId: id, phoneLast4: wa.slice(-4), claimsExistingRecord: !!claimMemberId });
  res.status(201).json({ url: `https://wa.me/${wa}?text=${encodeURIComponent(text)}`, code: displayInviteCode(code), expires_at: expiresAt, invited_before_at: before.at });
});

/** A doctor sees their own invites; the front desk sees the whole clinic's. */
function scopeProviderIds(p: { id: string; type: string; clinic_id: string | null }): string[] {
  if (p.type === 'doctor' || !p.clinic_id) return [p.id];
  return (db.prepare('SELECT id FROM providers WHERE clinic_id = ?').all(p.clinic_id) as { id: string }[]).map((r) => r.id);
}

invitesRouter.get('/invites/summary', ...staff, (req, res) => {
  const me = providerInfo(req.session!.providerId!);
  if (!me) return res.status(403).json({ error: 'Your account is not linked to a provider.' });
  const ids = scopeProviderIds(me);
  const rows = db
    .prepare(`SELECT id, name, wa_number, member_id, created_at, expires_at, used_at FROM patient_invites WHERE provider_id IN (${ids.map(() => '?').join(',')}) ORDER BY created_at DESC`)
    .all(...ids) as { id: string; name: string | null; wa_number: string; member_id: string | null; created_at: string; expires_at: string; used_at: string | null }[];
  const nowIso = now();
  const statusOf = (r: { used_at: string | null; expires_at: string }) => (r.used_at ? 'joined' : r.expires_at < nowIso ? 'expired' : 'pending');
  res.json({
    sent: rows.length,
    joined: rows.filter((r) => statusOf(r) === 'joined').length,
    pending: rows.filter((r) => statusOf(r) === 'pending').length,
    recent: rows.slice(0, 15).map((r) => ({ id: r.id, name: r.name, phone_tail: r.wa_number.slice(-4), status: statusOf(r), sent_at: r.created_at, claims_existing_record: !!r.member_id })),
  });
});

// ---------------------------------------------------------------------------------------------
// Joining (no login yet)
// ---------------------------------------------------------------------------------------------

const BAD_CODE = 'This invite code is not valid or has expired.';
const tooMany = (req: any, res: any) => {
  if (overLimit(`signup:${req.ip}`, 30, 60 * 60 * 1000)) {
    res.status(429).json({ error: 'Too many attempts — please try again in a while.' });
    return true;
  }
  return false;
};

function usableInvite(code: unknown): InviteRow | null {
  const normalized = normalizeInviteCode(code);
  if (normalized.length !== 8) return null;
  const row = db.prepare('SELECT * FROM patient_invites WHERE code = ?').get(normalized) as InviteRow | undefined;
  if (!row || row.used_at || row.expires_at < now()) return null;
  return row;
}

// Lets the sign-up screen say who invited you (and pre-fill a name) before you commit to anything.
invitesRouter.get('/signup/invite', (req, res) => {
  if (tooMany(req, res)) return;
  const invite = usableInvite(req.query.code);
  if (!invite) return res.status(400).json({ error: BAD_CODE });
  const from = providerInfo(invite.provider_id);
  res.json({ from: from ? senderLabel(from) : 'Your clinic', name: invite.name, claims_existing_record: !!invite.member_id });
});

class SignupError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const runSignup = db.transaction((args: { inviteId: string; name: string | null; email: string; passwordHash: string }) => {
  // Re-read inside the transaction: two people can't both spend the same code.
  const invite = db.prepare('SELECT * FROM patient_invites WHERE id = ?').get(args.inviteId) as InviteRow | undefined;
  if (!invite || invite.used_at || invite.expires_at < now()) throw new SignupError(400, BAD_CODE);
  if (db.prepare('SELECT 1 FROM users WHERE email = ?').get(args.email)) throw new SignupError(409, 'An account with this email already exists — sign in instead.');

  let memberId: string;
  let familyId: string;
  let displayName: string;
  if (invite.member_id) {
    const m = db.prepare('SELECT id, name, family_id, archived_at FROM members WHERE id = ?').get(invite.member_id) as { id: string; name: string; family_id: string; archived_at: string | null } | undefined;
    if (!m || m.archived_at || db.prepare('SELECT 1 FROM users WHERE member_id = ?').get(m.id)) throw new SignupError(400, BAD_CODE);
    memberId = m.id;
    familyId = m.family_id;
    displayName = m.name;
  } else {
    displayName = args.name ?? invite.name ?? '';
    if (displayName.trim().length < 2 || displayName.length > 100) throw new SignupError(400, 'Enter your name.');
    familyId = uuid();
    memberId = uuid();
    db.prepare('INSERT INTO families (id, primary_member_id, created_at) VALUES (?, NULL, ?)').run(familyId, now());
    db.prepare(
      `INSERT INTO members (id, family_id, name, relationship_to_primary, login_credentials_ref, phone, created_at) VALUES (?, ?, ?, 'self', NULL, ?, ?)`
    ).run(memberId, familyId, displayName.trim(), invite.phone, now());
    db.prepare('UPDATE families SET primary_member_id = ? WHERE id = ?').run(memberId, familyId);
  }

  const userId = uuid();
  db.prepare(`INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at) VALUES (?, ?, ?, 'member_primary', ?, ?, NULL, ?)`).run(
    userId,
    args.email,
    args.passwordHash,
    displayName.trim(),
    memberId,
    now()
  );
  db.prepare('UPDATE members SET login_credentials_ref = ? WHERE id = ?').run(userId, memberId);
  db.prepare('UPDATE patient_invites SET used_at = ?, used_by_member_id = ? WHERE id = ?').run(now(), memberId, invite.id);

  // The doctor who invited them is one tap away when they book. (Front-desk invites name no doctor.)
  const inviter = providerInfo(invite.provider_id);
  if (inviter?.type === 'doctor') {
    db.prepare('INSERT OR IGNORE INTO preferred_providers (id, member_id, provider_id, created_at) VALUES (?, ?, ?, ?)').run(uuid(), memberId, inviter.id, now());
  }
  return { userId, memberId, familyId, displayName: displayName.trim(), claimed: !!invite.member_id, inviteId: invite.id };
});

invitesRouter.post('/signup', (req, res) => {
  if (tooMany(req, res)) return;
  const { invite_code, name, email, password, accept_terms } = req.body ?? {};
  const invite = usableInvite(invite_code);
  if (!invite) return res.status(400).json({ error: BAD_CODE });
  if (accept_terms !== true) return res.status(400).json({ error: 'Please accept the terms to continue.' });
  const cleanEmail = String(email ?? '').trim().toLowerCase();
  if (cleanEmail.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) return res.status(400).json({ error: 'Enter a valid email address.' });
  if (typeof password !== 'string' || password.length < 8 || password.length > 200) return res.status(400).json({ error: 'Choose a password of at least 8 characters.' });
  if (name !== undefined && name !== null && typeof name !== 'string') return res.status(400).json({ error: 'Enter your name.' });

  try {
    const result = runSignup({ inviteId: invite.id, name: typeof name === 'string' && name.trim() ? name.trim() : null, email: cleanEmail, passwordHash: hashPassword(password) });
    logAudit(result.userId, 'member_primary', 'signup_via_invite', result.memberId, { inviteId: result.inviteId, claimedExistingRecord: result.claimed, termsVersion: 'pilot-0' });
    const s = createSession({ userId: result.userId, role: 'member_primary', displayName: result.displayName, memberId: result.memberId, familyId: result.familyId, providerId: null });
    res.status(201).json({ token: s.token, role: s.role, displayName: s.displayName, memberId: s.memberId, familyId: s.familyId, providerId: s.providerId });
  } catch (e) {
    if (e instanceof SignupError) return res.status(e.status).json({ error: e.message });
    throw e;
  }
});
