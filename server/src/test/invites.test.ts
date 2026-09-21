import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import type { Server } from 'node:http';
import { v4 as uuid } from 'uuid';
import { buildApp } from '../app.js';
import { createSession } from '../auth/session.js';
import { db, now } from '../db/db.js';
import { ensureDictionary, makeMember } from './testUtils.js';
import { resetRateLimits } from '../rateLimit.js';
import { normalizeInviteCode } from '../invites.js';

const DOWNLOAD = 'https://get.example.test/healthfolio';
process.env.HEALTHFOLIO_DOWNLOAD_URL = DOWNLOAD;

let server: Server;
let baseUrl: string;
before(async () => {
  ensureDictionary();
  await new Promise<void>((resolve) => {
    server = buildApp().listen(0, () => resolve());
  });
  const addr = server.address();
  baseUrl = `http://localhost:${typeof addr === 'object' && addr ? addr.port : 0}/api`;
});
after(() => new Promise<void>((resolve) => server.close(() => resolve())));
beforeEach(() => resetRateLimits());

async function call(method: string, path: string, token: string | null, body?: unknown) {
  const resp = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: resp.status, body: (await resp.json().catch(() => null)) as any };
}

let phoneSeq = 9_300_000_000;
const nextPhone = () => String(phoneSeq++);
let emailSeq = 0;
const nextEmail = () => `patient${++emailSeq}@invites.test`;

function makeClinic(name: string) {
  const id = uuid();
  db.prepare('INSERT INTO clinics (id, name) VALUES (?, ?)').run(id, name);
  return id;
}
function makeStaff(type: 'doctor' | 'clinic_admin', name: string, clinicId: string | null) {
  const id = uuid();
  db.prepare('INSERT INTO providers (id, type, name, specialty, clinic_id) VALUES (?, ?, ?, NULL, ?)').run(id, type, name, clinicId);
  return id;
}
type Role = 'provider_doctor' | 'provider_clinic_admin' | 'member_primary';
function session(role: Role, providerId: string | null, memberId: string | null = null, familyId: string | null = null) {
  return createSession({ userId: `u-${Math.random()}`, role, displayName: 'T', memberId, familyId, providerId }).token;
}
function world() {
  const clinic = makeClinic('Sunrise Clinic');
  const other = makeClinic('Other Clinic');
  const doc = makeStaff('doctor', 'Ananya Rao', clinic);
  const doc2 = makeStaff('doctor', 'Dr. Second', clinic);
  const desk = makeStaff('clinic_admin', 'Desk', clinic);
  const otherDoc = makeStaff('doctor', 'Dr. Elsewhere', other);
  const otherDesk = makeStaff('clinic_admin', 'Other Desk', other);
  return {
    clinic,
    doc,
    doc2,
    desk,
    otherDoc,
    docTok: session('provider_doctor', doc),
    doc2Tok: session('provider_doctor', doc2),
    deskTok: session('provider_clinic_admin', desk),
    otherDeskTok: session('provider_clinic_admin', otherDesk),
    otherDocTok: session('provider_doctor', otherDoc),
  };
}
const codeOf = (displayed: string) => displayed;
const rawCode = (displayed: string) => normalizeInviteCode(displayed);
const inviteRow = (displayed: string) => db.prepare('SELECT * FROM patient_invites WHERE code = ?').get(rawCode(displayed)) as any;
async function invite(tok: string, body: Record<string, unknown> = {}) {
  return call('POST', '/invites', tok, { phone: nextPhone(), patient_agreed: true, ...body });
}
const messageOf = (url: string) => decodeURIComponent(url.split('?text=')[1]);

describe('inviting a patient', () => {
  it('needs the clinic to confirm the patient agreed, and a usable number', async () => {
    const w = world();
    assert.equal((await call('POST', '/invites', w.docTok, { phone: nextPhone() })).status, 400);
    assert.equal((await call('POST', '/invites', w.docTok, { phone: nextPhone(), patient_agreed: 'yes' })).status, 400);
    assert.equal((await call('POST', '/invites', w.docTok, { phone: '12345', patient_agreed: true })).status, 400);
    assert.equal((await call('POST', '/invites', w.docTok, { patient_agreed: true })).status, 400);
    assert.equal((await call('POST', '/invites', w.docTok, { phone: nextPhone(), name: 'x'.repeat(61), patient_agreed: true })).status, 400);
  });

  it('is switched off — not silently broken — until the download link is configured', async () => {
    const w = world();
    delete process.env.HEALTHFOLIO_DOWNLOAD_URL;
    try {
      const r = await invite(w.docTok);
      assert.equal(r.status, 503);
      assert.match(r.body.error, /HEALTHFOLIO_DOWNLOAD_URL/);
      process.env.HEALTHFOLIO_DOWNLOAD_URL = 'not a url';
      assert.equal((await invite(w.docTok)).status, 503);
    } finally {
      process.env.HEALTHFOLIO_DOWNLOAD_URL = DOWNLOAD;
    }
    assert.equal(db.prepare('SELECT COUNT(*) AS c FROM patient_invites WHERE provider_id = ?').get(w.doc) && (db.prepare('SELECT COUNT(*) AS c FROM patient_invites WHERE provider_id = ?').get(w.doc) as any).c, 0);
  });

  it('builds a wa.me link with who is inviting, the install link and the code — and nothing clinical', async () => {
    const w = world();
    const phone = nextPhone();
    const r = await invite(w.docTok, { phone, name: 'Meera Nair' });
    assert.equal(r.status, 201);
    assert.ok(r.body.url.startsWith(`https://wa.me/91${phone}?text=`));
    assert.match(r.body.code, /^[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$/);
    const text = messageOf(r.body.url);
    assert.ok(text.includes('Hello Meera,'));
    assert.ok(text.includes('Dr. Ananya Rao (Sunrise Clinic)'));
    assert.ok(text.includes(DOWNLOAD));
    assert.ok(text.includes(r.body.code));
    assert.ok(!/diagnos|prescri|report shows|condition/i.test(text.replace("lab reports, prescriptions and medicines", '')));
    const days = (new Date(r.body.expires_at).getTime() - Date.now()) / 86400000;
    assert.ok(days > 13 && days <= 14);
  });

  it('introduces the front desk as the clinic, not as a doctor', async () => {
    const w = world();
    const text = messageOf((await invite(w.deskTok)).body.url);
    assert.ok(text.includes('Sunrise Clinic invites you'));
    assert.ok(!text.includes('Dr.'));
  });

  it('rejects patients, other roles and unauthenticated callers', async () => {
    const m = makeMember('Pat');
    const fam = (db.prepare('SELECT family_id FROM members WHERE id = ?').get(m) as any).family_id;
    assert.equal((await invite(session('member_primary', null, m, fam))).status, 403);
    assert.equal((await call('POST', '/invites', null, { phone: nextPhone(), patient_agreed: true })).status, 401);
    assert.equal((await call('GET', '/invites/summary', session('member_primary', null, m, fam))).status, 403);
  });

  it("won't invite a number that already has HealthFolio, but will one the desk registered without an app", async () => {
    const w = world();
    const phone = nextPhone();
    const withApp = makeMember('Has App');
    db.prepare('UPDATE members SET phone = ? WHERE id = ?').run(phone, withApp);
    db.prepare(`INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at) VALUES (?, ?, 'x', 'member_primary', 'Has App', ?, NULL, ?)`).run(uuid(), nextEmail(), withApp, now());
    const dup = await invite(w.docTok, { phone: `+91 ${phone.slice(0, 5)} ${phone.slice(5)}` });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.already_on_healthfolio, true);

    const noApp = makeMember('No App');
    const p2 = nextPhone();
    db.prepare('UPDATE members SET phone = ? WHERE id = ?').run(p2, noApp);
    assert.equal((await invite(w.docTok, { phone: p2 })).status, 201);
  });

  it('caps how many a provider can send in a day, and reports when the same number was invited before', async () => {
    const w = world();
    const phone = nextPhone();
    assert.equal((await invite(w.docTok, { phone })).body.invited_before_at, null);
    const again = await invite(w.docTok, { phone });
    assert.notEqual(again.body.invited_before_at, null);

    const ins = db.prepare(`INSERT INTO patient_invites (id, code, provider_id, invited_by_user_id, phone, wa_number, created_at, expires_at) VALUES (?, ?, ?, 'u', '1', '911', ?, ?)`);
    for (let i = 0; i < 48; i++) ins.run(uuid(), `FILL${String(i).padStart(4, '0')}`, w.doc, now(), now());
    const limited = await invite(w.docTok);
    assert.equal(limited.status, 429);
    // The desk has its own allowance.
    assert.equal((await invite(w.deskTok)).status, 201);
  });

  it('logs the invite without keeping the phone number', async () => {
    const w = world();
    const phone = nextPhone();
    await invite(w.docTok, { phone });
    const rows = db.prepare(`SELECT metadata_json FROM audit_log WHERE action = 'patient_invited'`).all() as any[];
    const text = JSON.stringify(rows);
    assert.ok(text.includes(phone.slice(-4)));
    assert.ok(!text.includes(phone));
  });
});

describe('inviting someone the clinic registered at the counter', () => {
  async function registerWalkIn(w: ReturnType<typeof world>, name = 'Counter Patient') {
    const phone = nextPhone();
    const r = await call('POST', '/frontdesk/walk-ins', w.deskTok, { provider_id: w.doc, datetime: '2026-10-05T10:00:00.000', new_patient: { name, phone } });
    assert.equal(r.status, 201);
    return { memberId: r.body.member_id as string, phone };
  }

  it("lets the clinic's own staff invite them — using the number on file, not one they type", async () => {
    const w = world();
    const { memberId, phone } = await registerWalkIn(w);
    const fromDesk = await call('POST', '/invites', w.deskTok, { member_id: memberId, phone: '9999999999', patient_agreed: true });
    assert.equal(fromDesk.status, 201);
    assert.ok(fromDesk.body.url.includes(`wa.me/91${phone}`));
    assert.ok(!fromDesk.body.url.includes('9999999999'));
    assert.equal(inviteRow(fromDesk.body.code).member_id, memberId);
    assert.equal((await call('POST', '/invites', w.doc2Tok, { member_id: memberId, patient_agreed: true })).status, 201); // a colleague at the same clinic
  });

  it("refuses staff from another clinic, and anyone else's patient", async () => {
    const w = world();
    const { memberId } = await registerWalkIn(w);
    assert.equal((await call('POST', '/invites', w.otherDeskTok, { member_id: memberId, patient_agreed: true })).status, 403);
    assert.equal((await call('POST', '/invites', w.otherDocTok, { member_id: memberId, patient_agreed: true })).status, 403);
    // Not a counter-registered patient at all (a self-registered member has no registrar).
    const stranger = makeMember('Stranger');
    db.prepare('UPDATE members SET phone = ? WHERE id = ?').run(nextPhone(), stranger);
    assert.equal((await call('POST', '/invites', w.deskTok, { member_id: stranger, patient_agreed: true })).status, 403);
    assert.equal((await call('POST', '/invites', w.deskTok, { member_id: uuid(), patient_agreed: true })).status, 404);
  });

  it('turns the invite into their existing record — visit history included — instead of a second empty one', async () => {
    const w = world();
    const { memberId } = await registerWalkIn(w, 'Kiran Das');
    const inv = await call('POST', '/invites', w.deskTok, { member_id: memberId, patient_agreed: true });
    const before = (db.prepare('SELECT COUNT(*) AS c FROM members').get() as any).c;

    const checked = await call('GET', `/signup/invite?code=${inv.body.code}`, null);
    assert.equal(checked.status, 200);
    assert.equal(checked.body.claims_existing_record, true);
    assert.equal(checked.body.name, 'Kiran Das');

    const email = nextEmail();
    const joined = await call('POST', '/signup', null, { invite_code: inv.body.code, email, password: 'a-good-password', accept_terms: true });
    assert.equal(joined.status, 201);
    assert.equal(joined.body.memberId, memberId);
    assert.equal((db.prepare('SELECT COUNT(*) AS c FROM members').get() as any).c, before, 'no new member should have been created');
    const appts = await call('GET', '/appointments', joined.body.token);
    assert.equal(appts.body.length, 1, 'the counter visit is theirs now');
    assert.equal((await call('POST', '/login', null, { email, password: 'a-good-password' })).status, 200);

    // …and once claimed, that person can't be invited again.
    assert.equal((await call('POST', '/invites', w.deskTok, { member_id: memberId, patient_agreed: true })).status, 409);
  });
});

describe('joining with a code', () => {
  it('creates a patient account, signs them in, and puts the inviting doctor in their preferred doctors', async () => {
    const w = world();
    const phone = nextPhone();
    const inv = await invite(w.docTok, { phone, name: 'Meera Nair' });
    const email = nextEmail();
    const r = await call('POST', '/signup', null, { invite_code: inv.body.code.toLowerCase().replace('-', ' '), email: email.toUpperCase(), password: 'correct horse', accept_terms: true });
    assert.equal(r.status, 201);
    assert.equal(r.body.role, 'member_primary');
    assert.equal(r.body.displayName, 'Meera Nair');
    assert.equal((await call('GET', '/me', r.body.token)).status, 200);

    const member = db.prepare('SELECT * FROM members WHERE id = ?').get(r.body.memberId) as any;
    assert.equal(member.phone, phone);
    assert.equal(member.relationship_to_primary, 'self');
    assert.ok(member.login_credentials_ref);
    assert.equal((db.prepare('SELECT primary_member_id FROM families WHERE id = ?').get(member.family_id) as any).primary_member_id, member.id);
    assert.ok(db.prepare('SELECT 1 FROM preferred_providers WHERE member_id = ? AND provider_id = ?').get(member.id, w.doc));
    assert.ok(inviteRow(inv.body.code).used_at);
    assert.equal((await call('POST', '/login', null, { email, password: 'correct horse' })).status, 200);
  });

  it('a front-desk invite creates the account but names no doctor', async () => {
    const w = world();
    const inv = await invite(w.deskTok, { name: 'Desk Invitee' });
    const r = await call('POST', '/signup', null, { invite_code: inv.body.code, email: nextEmail(), password: 'password-ok', accept_terms: true });
    assert.equal(r.status, 201);
    assert.equal((db.prepare('SELECT COUNT(*) AS c FROM preferred_providers WHERE member_id = ?').get(r.body.memberId) as any).c, 0);
  });

  it('is single-use, and an unknown, expired or malformed code all read the same', async () => {
    const w = world();
    const inv = await invite(w.docTok, { name: 'Once Only' });
    const body = (email: string) => ({ invite_code: inv.body.code, email, password: 'password-ok', accept_terms: true });
    assert.equal((await call('POST', '/signup', null, body(nextEmail()))).status, 201);
    const second = await call('POST', '/signup', null, body(nextEmail()));
    assert.equal(second.status, 400);

    const expired = await invite(w.docTok, { name: 'Late' });
    db.prepare('UPDATE patient_invites SET expires_at = ? WHERE code = ?').run(new Date(Date.now() - 1000).toISOString(), rawCode(expired.body.code));
    const late = await call('POST', '/signup', null, { invite_code: expired.body.code, email: nextEmail(), password: 'password-ok', accept_terms: true });
    const unknown = await call('POST', '/signup', null, { invite_code: 'ZZZZ-ZZZZ', email: nextEmail(), password: 'password-ok', accept_terms: true });
    const junk = await call('POST', '/signup', null, { invite_code: 'abc', email: nextEmail(), password: 'password-ok', accept_terms: true });
    assert.equal(late.status, 400);
    assert.equal(unknown.status, 400);
    assert.equal(junk.status, 400);
    assert.equal(second.body.error, late.body.error);
    assert.equal(late.body.error, unknown.body.error);
    assert.equal((await call('GET', `/signup/invite?code=${expired.body.code}`, null)).status, 400);
  });

  it("validates the form without burning the code — including when the email is already taken", async () => {
    const w = world();
    const inv = await invite(w.docTok, { name: 'Careful' });
    const good = { invite_code: inv.body.code, email: nextEmail(), password: 'password-ok', accept_terms: true };
    assert.equal((await call('POST', '/signup', null, { ...good, accept_terms: false })).status, 400);
    assert.equal((await call('POST', '/signup', null, { ...good, email: 'not-an-email' })).status, 400);
    assert.equal((await call('POST', '/signup', null, { ...good, password: 'short' })).status, 400);

    const taken = nextEmail();
    db.prepare(`INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at) VALUES (?, ?, 'x', 'platform_admin', 'Someone', NULL, NULL, ?)`).run(uuid(), taken, now());
    const dup = await call('POST', '/signup', null, { ...good, email: taken });
    assert.equal(dup.status, 409);
    assert.equal(inviteRow(inv.body.code).used_at, null, 'a failed sign-up must not spend the code');
    assert.equal((await call('POST', '/signup', null, good)).status, 201);
  });

  it('needs a name when the invite did not carry one', async () => {
    const w = world();
    const inv = await invite(w.docTok); // no name given
    const base = { invite_code: inv.body.code, email: nextEmail(), password: 'password-ok', accept_terms: true };
    assert.equal((await call('POST', '/signup', null, base)).status, 400);
    assert.equal(inviteRow(inv.body.code).used_at, null);
    assert.equal((await call('POST', '/signup', null, { ...base, name: 'Typed Name' })).body.displayName, 'Typed Name');
  });

  it('stores the password hashed, never as typed', async () => {
    const w = world();
    const inv = await invite(w.docTok, { name: 'Hashed' });
    const email = nextEmail();
    await call('POST', '/signup', null, { invite_code: inv.body.code, email, password: 'plain-text-pw', accept_terms: true });
    const u = db.prepare('SELECT password_hash FROM users WHERE email = ?').get(email) as any;
    assert.ok(!u.password_hash.includes('plain-text-pw'));
    assert.match(u.password_hash, /^[0-9a-f]{32}:[0-9a-f]+$/);
  });

  it('slows down anyone guessing codes', async () => {
    for (let i = 0; i < 30; i++) assert.equal((await call('GET', '/signup/invite?code=AAAA-AAAA', null)).status, 400);
    assert.equal((await call('GET', '/signup/invite?code=AAAA-AAAA', null)).status, 429);
    assert.equal((await call('POST', '/signup', null, { invite_code: 'AAAA-AAAA', email: nextEmail(), password: 'password-ok', accept_terms: true })).status, 429);
  });
});

describe('the invite summary', () => {
  it("counts sent, joined, pending and expired — a doctor's own, the desk's whole clinic, never another clinic's", async () => {
    const w = world();
    const a = await invite(w.docTok, { name: 'Joined One' });
    await invite(w.docTok, { name: 'Pending One' });
    const c = await invite(w.doc2Tok, { name: 'Colleague Invite' });
    const gone = await invite(w.docTok, { name: 'Expired One' });
    db.prepare('UPDATE patient_invites SET expires_at = ? WHERE code = ?').run(new Date(Date.now() - 1000).toISOString(), rawCode(gone.body.code));
    await invite(w.otherDocTok, { name: 'Elsewhere' });
    await call('POST', '/signup', null, { invite_code: a.body.code, email: nextEmail(), password: 'password-ok', accept_terms: true });
    void c;

    const mine = (await call('GET', '/invites/summary', w.docTok)).body;
    assert.deepEqual([mine.sent, mine.joined, mine.pending], [3, 1, 1]);
    const desk = (await call('GET', '/invites/summary', w.deskTok)).body;
    assert.deepEqual([desk.sent, desk.joined, desk.pending], [4, 1, 2]);
    assert.deepEqual(desk.recent.map((r: any) => r.status).sort(), ['expired', 'joined', 'pending', 'pending']);
    const other = (await call('GET', '/invites/summary', w.otherDeskTok)).body;
    assert.equal(other.sent, 1);

    const text = JSON.stringify(desk);
    assert.ok(!/\b91\d{10}\b/.test(text), 'the summary must not carry full phone numbers');
    assert.ok(!text.includes(rawCode(a.body.code)), 'or the codes themselves');
  });
});
