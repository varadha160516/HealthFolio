import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import type { Server } from 'node:http';
import { v4 as uuid } from 'uuid';
import { buildApp } from '../app.js';
import { createSession } from '../auth/session.js';
import { db, now } from '../db/db.js';
import { ensureDictionary, makeMember } from './testUtils.js';

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

async function call(method: string, path: string, token: string, body?: unknown) {
  const resp = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: resp.status, body: (await resp.json().catch(() => null)) as any };
}

function makeProvider(name: string) {
  const id = uuid();
  db.prepare('INSERT INTO providers (id, type, name, specialty, clinic_id) VALUES (?, ?, ?, NULL, NULL)').run(id, 'doctor', name);
  return id;
}
function familyOf(memberId: string) {
  return (db.prepare('SELECT family_id FROM members WHERE id = ?').get(memberId) as any).family_id as string;
}
function memberSession(memberId: string) {
  return createSession({ userId: `u-${Math.random()}`, role: 'member_primary', displayName: 'T', memberId, familyId: familyOf(memberId), providerId: null }).token;
}
function docSession(providerId: string) {
  // Issuing a prescription writes a documents row stamped uploaded_by_user_id, which is a real FK
  // against users(id) — a session with a made-up userId fails that insert, so this needs an actual
  // users row behind it (testUtils.makeUser does the same for the member side).
  const userId = uuid();
  db.prepare(`INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at) VALUES (?, ?, 'x', 'provider_doctor', 'T', NULL, ?, ?)`).run(
    userId,
    `${userId}@referral-test.local`,
    providerId,
    now()
  );
  return createSession({ userId, role: 'provider_doctor', displayName: 'T', memberId: null, familyId: null, providerId }).token;
}
const DAY = '2026-11-10';
let seq = 0;
const at = () => `${DAY}T${String(10 + seq).padStart(2, '0')}:00:00.000`;

/** Books and unlocks a visit via the real routes (booking, check-in, consent request/grant, start
 * consultation) and leaves it unlocked, mid-visit — where writing consultation notes, a referral,
 * or a prescription is actually allowed. Returns the appointment id. */
async function startVisit(memberTok: string, memberId: string, providerId: string, docTok: string, referralId?: string) {
  seq++;
  const booked = await call('POST', '/appointments', memberTok, { member_id: memberId, provider_id: providerId, datetime: at(), referral_id: referralId });
  const id = booked.body.id as string;
  await call('POST', `/appointments/${id}/check-in`, docTok);
  await call('POST', `/appointments/${id}/request-consent`, docTok, { method: 'in_app' });
  await call('POST', `/appointments/${id}/respond-consent`, memberTok, { approve: true });
  await call('POST', `/appointments/${id}/start-consultation`, docTok);
  return id;
}

/** Documents (optionally) and completes an already-unlocked visit — the moment closeReferralLoop
 * actually fires, for whichever referral that visit was booked against. */
async function finishVisit(
  id: string,
  docTok: string,
  opts: { prescribe?: { diagnosis: string; medicine: string }; advice?: string[]; followUp?: { after: string; reason: string } } = {}
) {
  if (opts.advice || opts.followUp) {
    await call('PUT', `/appointments/${id}/consultation-notes`, docTok, {
      advice: opts.advice ?? [],
      follow_up_after: opts.followUp?.after ?? null,
      follow_up_reason: opts.followUp?.reason ?? null,
    });
  }
  if (opts.prescribe) {
    await call('POST', `/appointments/${id}/prescriptions`, docTok, {
      diagnosis_text: opts.prescribe.diagnosis,
      line_items: [{ medicine_name: opts.prescribe.medicine, strength: '500mg', dosage: '1 tablet', frequency: 'Morning' }],
    });
  }
  const completed = await call('POST', `/appointments/${id}/complete`, docTok, {});
  assert.equal(completed.status, 200, `complete failed: ${JSON.stringify(completed.body)}`);
}

/** A visit with nothing else to say about it — books, unlocks, documents (if given), completes. */
async function runFullVisit(
  memberTok: string,
  memberId: string,
  providerId: string,
  docTok: string,
  opts: { referralId?: string; prescribe?: { diagnosis: string; medicine: string }; advice?: string[]; followUp?: { after: string; reason: string } } = {}
) {
  const id = await startVisit(memberTok, memberId, providerId, docTok, opts.referralId);
  await finishVisit(id, docTok, opts);
  return id;
}

/** Creates a referral from a currently-unlocked visit (the only time the API allows it), then
 * completes that referring visit — leaving the referral 'booked' rather than still 'pending' once
 * the specialist's visit below is booked against it. */
async function referAndFinish(gpVisitId: string, docTok: string, targetProviderId: string) {
  const r = await call('POST', `/appointments/${gpVisitId}/referrals`, docTok, { target_provider_id: targetProviderId, reason: 'Suspected thyroid issue', urgency: 'routine' });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  await finishVisit(gpVisitId, docTok);
  return r.body.id as string;
}

describe('closed-loop referrals: the outcome comes back', () => {
  it('fills in diagnosis, medicines, advice and follow-up on the SAME referral row the GP already has', async () => {
    const gp = makeProvider('Dr. GP');
    const specialist = makeProvider('Dr. Specialist');
    const member = makeMember('Loop Patient');
    const memberTok = memberSession(member);
    const gpTok = docSession(gp);
    const specTok = docSession(specialist);

    const gpVisit = await startVisit(memberTok, member, gp, gpTok);
    const referralId = await referAndFinish(gpVisit, gpTok, specialist);

    // Before the specialist visit happens, there's nothing to show yet.
    const before = (await call('GET', '/providers/me/referrals', gpTok)).body;
    assert.equal(before.sent, 1);
    assert.equal(before.outcomes_ready, 0);
    assert.equal(before.referrals[0].outcome, null);

    await runFullVisit(memberTok, member, specialist, specTok, {
      referralId,
      prescribe: { diagnosis: 'Hypothyroidism', medicine: 'Levothyroxine' },
      advice: ['Repeat TSH in 6 weeks'],
      followUp: { after: '1_month', reason: 'Recheck thyroid panel' },
    });

    const after = (await call('GET', '/providers/me/referrals', gpTok)).body;
    assert.equal(after.sent, 1);
    assert.equal(after.outcomes_ready, 1);
    const ref = after.referrals[0];
    assert.equal(ref.id, referralId);
    assert.equal(ref.status, 'completed');
    assert.equal(ref.patient_name, 'Loop Patient');
    assert.equal(ref.target_provider_name, 'Dr. Specialist');
    assert.equal(ref.outcome.diagnosis_text, 'Hypothyroidism');
    assert.deepEqual(ref.outcome.medicines, ['Levothyroxine — 500mg — 1 tablet — Morning']);
    assert.deepEqual(ref.outcome.advice, ['Repeat TSH in 6 weeks']);
    assert.equal(ref.outcome.follow_up_after, '1_month');
    assert.equal(ref.outcome.follow_up_reason, 'Recheck thyroid panel');
    assert.ok(ref.outcome.ready_at);
  });

  it('still closes the loop — with an empty outcome, not silence — when the specialist documented nothing', async () => {
    const gp = makeProvider('Dr. Quiet GP');
    const specialist = makeProvider('Dr. Quiet Specialist');
    const member = makeMember('Undocumented');
    const memberTok = memberSession(member);
    const gpTok = docSession(gp);
    const specTok = docSession(specialist);

    const gpVisit = await startVisit(memberTok, member, gp, gpTok);
    const referralId = await referAndFinish(gpVisit, gpTok, specialist);
    await runFullVisit(memberTok, member, specialist, specTok, { referralId }); // no prescription, no notes

    const r = (await call('GET', '/providers/me/referrals', gpTok)).body.referrals[0];
    assert.equal(r.status, 'completed');
    assert.notEqual(r.outcome, null, 'an outcome should still be recorded, even if empty');
    assert.equal(r.outcome.diagnosis_text, null);
    assert.deepEqual(r.outcome.medicines, []);
    assert.deepEqual(r.outcome.advice, []);
  });

  it('notifies the referring doctor, pointing at THEIR OWN appointment, not the specialist\'s', async () => {
    const gp = makeProvider('Dr. Notify GP');
    const specialist = makeProvider('Dr. Notify Specialist');
    const member = makeMember('Notified');
    const memberTok = memberSession(member);
    const gpTok = docSession(gp);
    const specTok = docSession(specialist);

    const gpVisit = await startVisit(memberTok, member, gp, gpTok);
    const referralId = await referAndFinish(gpVisit, gpTok, specialist);
    const specVisit = await runFullVisit(memberTok, member, specialist, specTok, { referralId, prescribe: { diagnosis: 'x', medicine: 'y' } });

    const notifs = (await call('GET', '/providers/me/notifications', gpTok)).body;
    const n = notifs.find((x: any) => x.type === 'referral_outcome_ready');
    assert.ok(n, 'the GP should have a referral_outcome_ready notification');
    assert.equal(n.related_appointment_id, gpVisit);
    assert.notEqual(n.related_appointment_id, specVisit);
    // And the GP can actually open what it points to.
    assert.equal((await call('GET', `/appointments/${gpVisit}`, gpTok)).status, 200);
    // The specialist's own visit stays theirs — the GP still can't see it (never gained standing access).
    assert.equal((await call('GET', `/appointments/${specVisit}`, gpTok)).status, 403);
  });

  it('scopes strictly to the referring doctor: another doctor, the front desk, and the target specialist see none of it', async () => {
    const gp = makeProvider('Dr. Scope GP');
    const specialist = makeProvider('Dr. Scope Specialist');
    const stranger = makeProvider('Dr. Stranger');
    const member = makeMember('Scoped Patient');
    const memberTok = memberSession(member);
    const gpTok = docSession(gp);
    const specTok = docSession(specialist);
    const strangerTok = docSession(stranger);
    const deskId = uuid();
    db.prepare("INSERT INTO providers (id, type, name, specialty, clinic_id) VALUES (?, 'clinic_admin', 'Desk', NULL, NULL)").run(deskId);
    const deskTok = createSession({ userId: 'u-desk', role: 'provider_clinic_admin', displayName: 'T', memberId: null, familyId: null, providerId: deskId }).token;

    const gpVisit = await startVisit(memberTok, member, gp, gpTok);
    const referralId = await referAndFinish(gpVisit, gpTok, specialist);
    await runFullVisit(memberTok, member, specialist, specTok, { referralId, prescribe: { diagnosis: 'private diagnosis', medicine: 'SecretMed' } });

    assert.deepEqual((await call('GET', '/providers/me/referrals', strangerTok)).body.referrals, []);
    // The specialist has their own visit's full record, but this endpoint is the REFERRING doctor's
    // outbox — the specialist never referred anyone here, so their own list is empty too.
    assert.deepEqual((await call('GET', '/providers/me/referrals', specTok)).body.referrals, []);
    assert.equal((await call('GET', '/providers/me/referrals', deskTok)).status, 403);
    assert.equal((await call('GET', '/providers/me/referrals', 'bad-token')).status, 401);

    const mine = (await call('GET', '/providers/me/referrals', gpTok)).body.referrals;
    assert.equal(mine.length, 1);
    assert.equal(mine[0].id, referralId);
  });

  it('lists a still-pending referral with no outcome, and only counts outcomes once ready', async () => {
    const gp = makeProvider('Dr. Pending GP');
    const specialist = makeProvider('Dr. Pending Specialist');
    const member = makeMember('Two Referrals');
    const memberTok = memberSession(member);
    const gpTok = docSession(gp);
    const specTok = docSession(specialist);

    const gpVisit = await startVisit(memberTok, member, gp, gpTok);
    const r1 = await referAndFinish(gpVisit, gpTok, specialist);
    // A second, separate referring visit — its referral stays pending throughout this test.
    const gpVisit2 = await startVisit(memberTok, member, gp, gpTok);
    const r2 = await referAndFinish(gpVisit2, gpTok, specialist);

    await runFullVisit(memberTok, member, specialist, specTok, { referralId: r1, prescribe: { diagnosis: 'd1', medicine: 'm1' } });

    const summary = (await call('GET', '/providers/me/referrals', gpTok)).body;
    assert.equal(summary.sent, 2);
    assert.equal(summary.outcomes_ready, 1);
    const byId = Object.fromEntries(summary.referrals.map((r: any) => [r.id, r]));
    assert.equal(byId[r1].outcome.diagnosis_text, 'd1');
    assert.equal(byId[r2].status, 'pending');
    assert.equal(byId[r2].outcome, null);
  });

  it('carries forward a real cross-provider safety flag as part of the outcome', async () => {
    const gp = makeProvider('Dr. Safety GP');
    const specialist = makeProvider('Dr. Safety Specialist');
    const member = makeMember('Flagged Patient');
    const memberTok = memberSession(member);
    const gpTok = docSession(gp);
    const specTok = docSession(specialist);

    // The GP's own visit puts an allergy on file, the way a real consultation would.
    await call('POST', `/members/${member}/allergies`, memberTok, { value: 'Penicillin' });
    const gpVisit = await startVisit(memberTok, member, gp, gpTok);
    const referralId = await referAndFinish(gpVisit, gpTok, specialist);
    // The specialist, unaware, prescribes exactly that.
    await runFullVisit(memberTok, member, specialist, specTok, { referralId, prescribe: { diagnosis: 'infection', medicine: 'Penicillin' } });

    const r = (await call('GET', '/providers/me/referrals', gpTok)).body.referrals[0];
    assert.ok(Array.isArray(r.outcome.safety_flags) && r.outcome.safety_flags.length > 0, JSON.stringify(r.outcome.safety_flags));
  });
});
