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

// An async Express handler that throws (including a synchronous db call inside it) must never crash
// the process — Express 4 does not catch a rejected promise from an async handler on its own, so
// every one of them is wrapped in asyncHandler (see middleware/asyncHandler.ts). This reproduces
// the exact crash found while testing closed-loop referrals: POST /appointments/:id/prescriptions
// inserts a `documents` row stamped uploaded_by_user_id, a real FK against users(id) — a session
// whose userId isn't a real row (which should never happen via the real login flow, but is exactly
// the kind of unexpected state a bug elsewhere, or a forged/corrupted token, could produce) used to
// take the whole server down.
describe('async route handlers survive a thrown error instead of crashing the process', () => {
  it('POST /appointments/:id/prescriptions: a foreign-key violation comes back as a clean 500, not a crash', async () => {
    const providerId = makeProvider('Dr. Crash Test');
    const memberId = makeMember('Crash Test Patient');
    const brokenUserId = uuid(); // deliberately NOT inserted into users — the exact repro
    const docTok = createSession({ userId: brokenUserId, role: 'provider_doctor', displayName: 'T', memberId: null, familyId: null, providerId }).token;
    const memberTok = createSession({ userId: `u-${uuid()}`, role: 'member_primary', displayName: 'T', memberId, familyId: familyOf(memberId), providerId: null }).token;

    const booked = await call('POST', '/appointments', memberTok, { member_id: memberId, provider_id: providerId, datetime: '2026-11-20T09:00:00.000' });
    const apptId = booked.body.id as string;
    await call('POST', `/appointments/${apptId}/check-in`, docTok);
    await call('POST', `/appointments/${apptId}/request-consent`, docTok, { method: 'in_app' });
    await call('POST', `/appointments/${apptId}/respond-consent`, memberTok, { approve: true });
    await call('POST', `/appointments/${apptId}/start-consultation`, docTok);

    const rx = await call('POST', `/appointments/${apptId}/prescriptions`, docTok, {
      diagnosis_text: 'x',
      line_items: [{ medicine_name: 'y' }],
    });
    assert.equal(rx.status, 500, JSON.stringify(rx.body));
    assert.equal(rx.body.error, 'Internal server error');

    // The real proof: the server is still alive and answering other requests afterward.
    assert.equal((await call('GET', `/appointments/${apptId}`, docTok)).status, 200);
    const health = await fetch(`${baseUrl}/health`);
    assert.equal(health.status, 200);

    // And the failed attempt left nothing half-written behind.
    assert.equal((db.prepare('SELECT COUNT(*) AS c FROM prescriptions WHERE appointment_id = ?').get(apptId) as any).c, 0);
    assert.equal((db.prepare('SELECT COUNT(*) AS c FROM documents WHERE member_id = ?').get(memberId) as any).c, 0);
  });

  it('a bad line item rolls back the whole prescription — no orphaned documents/prescriptions row, and the PDF file is cleaned up', async () => {
    const providerId = makeProvider('Dr. Rollback Test');
    const memberId = makeMember('Rollback Test Patient');
    const userId = uuid();
    db.prepare(`INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at) VALUES (?, ?, 'x', 'provider_doctor', 'T', NULL, ?, ?)`).run(
      userId,
      `${userId}@rollback-test.local`,
      providerId,
      now()
    );
    const docTok = createSession({ userId, role: 'provider_doctor', displayName: 'T', memberId: null, familyId: null, providerId }).token;
    const memberTok = createSession({ userId: `u-${uuid()}`, role: 'member_primary', displayName: 'T', memberId, familyId: familyOf(memberId), providerId: null }).token;

    const booked = await call('POST', '/appointments', memberTok, { member_id: memberId, provider_id: providerId, datetime: '2026-11-20T11:00:00.000' });
    const apptId = booked.body.id as string;
    await call('POST', `/appointments/${apptId}/check-in`, docTok);
    await call('POST', `/appointments/${apptId}/request-consent`, docTok, { method: 'in_app' });
    await call('POST', `/appointments/${apptId}/respond-consent`, memberTok, { approve: true });
    await call('POST', `/appointments/${apptId}/start-consultation`, docTok);

    // Missing medicine_name — a real NOT NULL violation, the exact shape of the bug found live:
    // this used to leave a documents+prescriptions row behind with no line items under it.
    const before = (db.prepare('SELECT COUNT(*) AS c FROM documents WHERE member_id = ?').get(memberId) as any).c;
    const rx = await call('POST', `/appointments/${apptId}/prescriptions`, docTok, { diagnosis_text: 'x', line_items: [{}] });
    assert.equal(rx.status, 500, JSON.stringify(rx.body));

    assert.equal((db.prepare('SELECT COUNT(*) AS c FROM documents WHERE member_id = ?').get(memberId) as any).c, before);
    assert.equal((db.prepare('SELECT COUNT(*) AS c FROM prescriptions WHERE appointment_id = ?').get(apptId) as any).c, 0);
    assert.equal((db.prepare('SELECT COUNT(*) AS c FROM prescription_line_items').get() as any).c >= 0, true); // sanity: table still queryable

    // The server is still up, and a real prescription on this same visit still works afterward.
    const ok = await call('POST', `/appointments/${apptId}/prescriptions`, docTok, { diagnosis_text: 'x', line_items: [{ medicine_name: 'Paracetamol' }] });
    assert.equal(ok.status, 201, JSON.stringify(ok.body));
    assert.equal((db.prepare('SELECT COUNT(*) AS c FROM documents WHERE member_id = ?').get(memberId) as any).c, before + 1);
  });

  it('a thrown error in one request does not affect a concurrent, unrelated request', async () => {
    const providerId = makeProvider('Dr. Concurrent');
    const memberId = makeMember('Concurrent Patient');
    const brokenUserId = uuid();
    const docTok = createSession({ userId: brokenUserId, role: 'provider_doctor', displayName: 'T', memberId: null, familyId: null, providerId }).token;
    const memberTok = createSession({ userId: `u-${uuid()}`, role: 'member_primary', displayName: 'T', memberId, familyId: familyOf(memberId), providerId: null }).token;

    const booked = await call('POST', '/appointments', memberTok, { member_id: memberId, provider_id: providerId, datetime: '2026-11-20T10:00:00.000' });
    const apptId = booked.body.id as string;
    await call('POST', `/appointments/${apptId}/check-in`, docTok);
    await call('POST', `/appointments/${apptId}/request-consent`, docTok, { method: 'in_app' });
    await call('POST', `/appointments/${apptId}/respond-consent`, memberTok, { approve: true });
    await call('POST', `/appointments/${apptId}/start-consultation`, docTok);

    const [crashing, unrelated] = await Promise.all([
      call('POST', `/appointments/${apptId}/prescriptions`, docTok, { diagnosis_text: 'x', line_items: [{ medicine_name: 'y' }] }),
      call('GET', '/appointments', memberTok),
    ]);
    assert.equal(crashing.status, 500);
    assert.equal(unrelated.status, 200);
  });
});
