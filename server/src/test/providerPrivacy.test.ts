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

async function get(path: string, token: string) {
  const resp = await fetch(`${baseUrl}${path}`, { headers: { Authorization: `Bearer ${token}` } });
  return { status: resp.status, body: (await resp.json().catch(() => null)) as any };
}

const SECRETS = ['1234567890123456', 'HDFC0001234', 'dr.secret@upi', 'Secret Holder', 'SIGNATURE-IMAGE-BYTES'];

// A doctor's payout details and signature image live on the providers row (Practice Settings), and
// used to leak to every logged-in patient through `SELECT p.*`.
describe('doctor payout details stay private', () => {
  function setup() {
    const clinicId = uuid();
    db.prepare('INSERT INTO clinics (id, name, city, latitude, longitude) VALUES (?, ?, ?, 12.9, 77.6)').run(clinicId, 'Privacy Clinic', 'Bengaluru');
    const doctorId = uuid();
    db.prepare(
      `INSERT INTO providers (id, type, name, specialty, clinic_id, registration_number, bank_account_name, bank_account_number, bank_ifsc, bank_upi_id, signature_base64)
       VALUES (?, 'doctor', 'Dr. Privacy', 'General Medicine', ?, 'REG-77', 'Secret Holder', '1234567890123456', 'HDFC0001234', 'dr.secret@upi', 'SIGNATURE-IMAGE-BYTES')`
    ).run(doctorId, clinicId);
    const memberId = makeMember('Nosy Patient');
    const apptId = uuid();
    db.prepare(
      `INSERT INTO appointments (id, member_id, provider_id, datetime, status, sharing_preference, reason_for_visit, consent_grant_id, created_at, updated_at)
       VALUES (?, ?, ?, '2026-09-22T10:00:00.000', 'scheduled', 'full_history', NULL, NULL, ?, ?)`
    ).run(apptId, memberId, doctorId, now(), now());
    db.prepare(`INSERT INTO preferred_providers (id, member_id, provider_id, created_at) VALUES (?, ?, ?, ?)`).run(uuid(), memberId, doctorId, now());
    const family = (db.prepare('SELECT family_id FROM members WHERE id = ?').get(memberId) as any).family_id as string;
    const memberTok = createSession({ userId: 'u-m', role: 'member_primary', displayName: 'T', memberId, familyId: family, providerId: null }).token;
    const doctorTok = createSession({ userId: 'u-d', role: 'provider_doctor', displayName: 'T', memberId: null, familyId: null, providerId: doctorId }).token;
    return { memberId, apptId, memberTok, doctorTok };
  }

  it('never appears in any directory or appointment payload a patient can read', async () => {
    const w = setup();
    const paths = [
      '/providers',
      '/providers/search?q=Privacy',
      '/providers/nearby?specialty=General%20Medicine&lat=12.9&lng=77.6',
      `/members/${w.memberId}/preferred-providers`,
      '/appointments',
      `/appointments/${w.apptId}`,
    ];
    for (const path of paths) {
      const r = await get(path, w.memberTok);
      assert.equal(r.status, 200, path);
      const text = JSON.stringify(r.body);
      assert.ok(text.includes('Dr. Privacy'), `${path} should still list the doctor`);
      for (const secret of SECRETS) assert.ok(!text.includes(secret), `${path} leaked "${secret}"`);
    }
  });

  it("still gives the doctor their own signature for the prescription view — but not their bank details", async () => {
    const w = setup();
    for (const path of ['/appointments', `/appointments/${w.apptId}`]) {
      const r = await get(path, w.doctorTok);
      const text = JSON.stringify(r.body);
      assert.ok(text.includes('SIGNATURE-IMAGE-BYTES'), `${path} lost the doctor's signature`);
      assert.ok(text.includes('REG-77'));
      for (const secret of SECRETS.filter((s) => s !== 'SIGNATURE-IMAGE-BYTES')) assert.ok(!text.includes(secret), `${path} leaked "${secret}"`);
    }
  });
});
