import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import type { Server } from 'node:http';
import { buildApp } from '../app.js';
import { createSession } from '../auth/session.js';
import { db } from '../db/db.js';
import { ensureDictionary, makeMember, makeProvider, makeAppointment } from './testUtils.js';

let server: Server;
let baseUrl: string;

before(async () => {
  ensureDictionary();
  const app = buildApp();
  await new Promise<void>((resolve) => {
    server = app.listen(0, () => resolve());
  });
  const addr = server.address();
  const port = typeof addr === 'object' && addr ? addr.port : 0;
  baseUrl = `http://localhost:${port}/api`;
});

after(() => new Promise<void>((resolve) => server.close(() => resolve())));

function sessionFor(role: 'member_primary' | 'provider_doctor', memberId: string | null, familyId: string | null, providerId: string | null) {
  return createSession({ userId: `u-${Math.random()}`, role, displayName: 'Test', memberId, familyId, providerId });
}

async function call(method: string, path: string, token: string, body?: unknown) {
  const resp = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const json = await resp.json().catch(() => null);
  return { status: resp.status, body: json as any };
}

function setup() {
  const memberId = makeMember(`Member ${Math.random()}`);
  const family = db.prepare('SELECT family_id FROM members WHERE id = ?').get(memberId) as { family_id: string };
  const providerId = makeProvider();
  const appointmentId = makeAppointment(memberId, providerId);
  const memberSession = sessionFor('member_primary', memberId, family.family_id, null);
  const providerSession = sessionFor('provider_doctor', null, null, providerId);
  return { memberId, providerId, appointmentId, memberToken: memberSession.token, providerToken: providerSession.token };
}

describe('appointment/consent state machine (Section 7.1) — access denied at every state except granted/in_consultation', () => {
  it('blocks every write that is not a valid transition from the current state (fail closed)', async () => {
    const { appointmentId, providerToken } = setup();
    const r1 = await call('POST', `/appointments/${appointmentId}/request-consent`, providerToken, {});
    assert.equal(r1.status, 409);
    const r2 = await call('POST', `/appointments/${appointmentId}/start-consultation`, providerToken, {});
    assert.equal(r2.status, 409);
    const r3 = await call('POST', `/appointments/${appointmentId}/complete`, providerToken, {});
    assert.equal(r3.status, 409);
  });

  it('never exposes member data until status is consent_granted or in_consultation, and revokes it immediately on completion', async () => {
    const { appointmentId, memberToken, providerToken } = setup();

    let r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.unlockedData, undefined);

    await call('POST', `/appointments/${appointmentId}/check-in`, providerToken, {});
    r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.status, 'checked_in');
    assert.equal(r.body.unlockedData, undefined);

    await call('POST', `/appointments/${appointmentId}/request-consent`, providerToken, { method: 'in_app' });
    r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.status, 'consent_requested');
    assert.equal(r.body.unlockedData, undefined); // still waiting — no access yet

    await call('POST', `/appointments/${appointmentId}/respond-consent`, memberToken, { approve: true });
    r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.status, 'consent_granted');
    assert.notEqual(r.body.unlockedData, undefined); // NOW unlocked
    assert.ok(r.body.unlockedData.summary);

    await call('POST', `/appointments/${appointmentId}/start-consultation`, providerToken, {});
    r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.status, 'in_consultation');
    assert.notEqual(r.body.unlockedData, undefined);

    await call('POST', `/appointments/${appointmentId}/complete`, providerToken, {});
    r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.status, 'completed');
    assert.equal(r.body.unlockedData, undefined); // access revoked immediately — Section 7.1
  });

  it('denial is a visibly distinct state from "still waiting", and never unlocks data', async () => {
    const { appointmentId, memberToken, providerToken } = setup();
    await call('POST', `/appointments/${appointmentId}/check-in`, providerToken, {});
    await call('POST', `/appointments/${appointmentId}/request-consent`, providerToken, { method: 'in_app' });
    await call('POST', `/appointments/${appointmentId}/respond-consent`, memberToken, { approve: false });

    const r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.status, 'consent_denied');
    assert.notEqual(r.body.status, 'consent_requested'); // distinct from "still waiting"
    assert.equal(r.body.unlockedData, undefined);
  });

  it('OTP fallback carries the same weight as in-app approval and unlocks access on a correct code', async () => {
    const { appointmentId, providerToken } = setup();
    await call('POST', `/appointments/${appointmentId}/check-in`, providerToken, {});
    const req = await call('POST', `/appointments/${appointmentId}/request-consent`, providerToken, { method: 'otp' });
    assert.match(req.body.otp, /^\d{6}$/);

    const wrong = await call('POST', `/appointments/${appointmentId}/verify-otp`, providerToken, { otp: '000000' });
    assert.equal(wrong.status, 401);

    const right = await call('POST', `/appointments/${appointmentId}/verify-otp`, providerToken, { otp: req.body.otp });
    assert.equal(right.status, 200);
    const r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.status, 'consent_granted');
    assert.notEqual(r.body.unlockedData, undefined);
  });

  it('lazily expires a consent request whose window has passed, and never leaves it looking like "still waiting"', async () => {
    const { appointmentId, providerToken } = setup();
    await call('POST', `/appointments/${appointmentId}/check-in`, providerToken, {});
    await call('POST', `/appointments/${appointmentId}/request-consent`, providerToken, { method: 'in_app' });

    const appt = db.prepare('SELECT consent_grant_id FROM appointments WHERE id = ?').get(appointmentId) as { consent_grant_id: string };
    db.prepare('UPDATE consent_grants SET expires_at = ? WHERE id = ?').run(new Date(Date.now() - 1000).toISOString(), appt.consent_grant_id);

    const r = await call('GET', `/appointments/${appointmentId}`, providerToken);
    assert.equal(r.body.status, 'consent_expired');
    assert.equal(r.body.unlockedData, undefined);
  });
});
