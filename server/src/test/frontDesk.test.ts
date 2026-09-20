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

// Every test gets its own phone number/name: they share one in-memory database, and a reused number
// would (correctly) trip the duplicate-phone warning in a later test.
let phoneSeq = 9_100_000_000;
const nextPhone = () => String(phoneSeq++);
let nameSeq = 0;
const nextName = (base: string) => `${base} ${++nameSeq}`;

const DAY = '2026-09-22';
const at = (time: string, day = DAY) => `${day}T${time}:00.000`;

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
function session(role: 'provider_doctor' | 'provider_clinic_admin' | 'member_primary', providerId: string | null, memberId: string | null = null, familyId: string | null = null) {
  return createSession({ userId: `u-${Math.random()}`, role, displayName: 'T', memberId, familyId, providerId }).token;
}
function appt(memberId: string, providerId: string, datetime: string, status = 'scheduled', reason: string | null = null) {
  const id = uuid();
  db.prepare(
    `INSERT INTO appointments (id, member_id, provider_id, datetime, status, sharing_preference, reason_for_visit, consent_grant_id, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 'full_history', ?, NULL, ?, ?)`
  ).run(id, memberId, providerId, datetime, status, reason, now(), now());
  return id;
}

/** Two clinics; clinic A has two doctors and a front desk, clinic B has one doctor. */
function world() {
  const clinicA = makeClinic('Sunrise');
  const clinicB = makeClinic('Other Clinic');
  const d1 = makeStaff('doctor', 'Dr. One', clinicA);
  const d2 = makeStaff('doctor', 'Dr. Two', clinicA);
  const dB = makeStaff('doctor', 'Dr. Bee', clinicB);
  const desk = makeStaff('clinic_admin', 'Front Desk', clinicA);
  const deskB = makeStaff('clinic_admin', 'Desk B', clinicB);
  return { clinicA, clinicB, d1, d2, dB, desk, deskToken: session('provider_clinic_admin', desk), deskBToken: session('provider_clinic_admin', deskB), d1Token: session('provider_doctor', d1) };
}

describe('front desk: the whole clinic, and nothing beyond it', () => {
  it("shows every doctor's lane at THEIR clinic and nothing from another clinic", async () => {
    const w = world();
    const p1 = makeMember('Asha');
    const p2 = makeMember('Ravi');
    const other = makeMember('Elsewhere');
    appt(p1, w.d1, at('10:00'));
    appt(p2, w.d2, at('11:00'));
    appt(other, w.dB, at('10:00'));

    const r = await call('GET', `/frontdesk/queue?date=${DAY}`, w.deskToken);
    assert.equal(r.status, 200);
    assert.deepEqual(r.body.doctors.map((d: any) => d.name).sort(), ['Dr. One', 'Dr. Two']);
    const names = r.body.doctors.flatMap((d: any) => d.appointments.map((a: any) => a.patient.name));
    assert.deepEqual(names.sort(), ['Asha', 'Ravi']);
    assert.ok(!names.includes('Elsewhere'));
  });

  it('a doctor with no appointments still gets a lane, and days do not bleed into each other', async () => {
    const w = world();
    appt(makeMember('Today'), w.d1, at('10:00'));
    appt(makeMember('Tomorrow'), w.d1, at('10:00', '2026-09-23'));
    const r = await call('GET', `/frontdesk/queue?date=${DAY}`, w.deskToken);
    const lane1 = r.body.doctors.find((d: any) => d.name === 'Dr. One');
    const lane2 = r.body.doctors.find((d: any) => d.name === 'Dr. Two');
    assert.deepEqual(lane1.appointments.map((a: any) => a.patient.name), ['Today']);
    assert.equal(lane2.appointments.length, 0);
  });

  it("never returns the reason for visit or any clinical field — only who, when and where they are in line", async () => {
    const w = world();
    appt(makeMember('Asha'), w.d1, at('10:00'), 'scheduled', 'chest pain and breathlessness');
    const r = await call('GET', `/frontdesk/queue?date=${DAY}`, w.deskToken);
    assert.ok(!JSON.stringify(r.body).includes('chest pain'));
    const a = r.body.doctors.find((d: any) => d.name === 'Dr. One').appointments[0];
    assert.deepEqual(Object.keys(a).sort(), ['checked_in_at', 'datetime', 'id', 'is_follow_up', 'is_walk_in', 'patient', 'status', 'token_number']);
    assert.deepEqual(Object.keys(a.patient).sort(), ['age', 'id', 'name', 'sex']);
  });

  it('counts each doctor\'s day into scheduled / waiting / in progress / completed / closed', async () => {
    const w = world();
    for (const [s, n] of [['scheduled', 2], ['checked_in', 1], ['consent_requested', 1], ['in_consultation', 1], ['completed', 3], ['cancelled', 1]] as const) {
      for (let i = 0; i < n; i++) appt(makeMember(`${s}${i}`), w.d1, at('10:00'), s);
    }
    const r = await call('GET', `/frontdesk/queue?date=${DAY}`, w.deskToken);
    assert.deepEqual(r.body.doctors.find((d: any) => d.name === 'Dr. One').counts, { scheduled: 2, waiting: 2, in_progress: 1, completed: 3, closed: 1 });
  });

  it('rejects everyone who is not a front desk — doctors, members, and unauthenticated calls', async () => {
    const w = world();
    assert.equal((await call('GET', `/frontdesk/queue?date=${DAY}`, w.d1Token)).status, 403);
    const m = makeMember('M');
    const fam = (db.prepare('SELECT family_id FROM members WHERE id = ?').get(m) as any).family_id;
    assert.equal((await call('GET', `/frontdesk/queue?date=${DAY}`, session('member_primary', null, m, fam))).status, 403);
    assert.equal((await call('GET', `/frontdesk/queue?date=${DAY}`, 'not-a-token')).status, 401);
  });

  it('a front desk account not attached to any clinic gets nothing', async () => {
    const orphan = makeStaff('clinic_admin', 'Orphan', null);
    const r = await call('GET', `/frontdesk/queue?date=${DAY}`, session('provider_clinic_admin', orphan));
    assert.equal(r.status, 403);
  });
});

describe('front desk: scope of what they can act on', () => {
  it("cannot check in, or cancel, another clinic's appointment — and it reads as not found", async () => {
    const w = world();
    const theirs = appt(makeMember('X'), w.dB, at('10:00'));
    assert.equal((await call('POST', `/frontdesk/appointments/${theirs}/check-in`, w.deskToken, {})).status, 404);
    assert.equal((await call('POST', `/frontdesk/appointments/${theirs}/cancel`, w.deskToken, {})).status, 404);
    assert.equal((db.prepare('SELECT status FROM appointments WHERE id = ?').get(theirs) as any).status, 'scheduled');
  });

  it('gets NO clinical access to their own clinic\'s visits — the consent gate is untouched', async () => {
    const w = world();
    const a = appt(makeMember('Asha'), w.d1, at('10:00'), 'in_consultation');
    for (const path of [`/appointments/${a}`, `/appointments/${a}/consultation-notes`, `/appointments/${a}/vitals`, `/appointments/${a}/previsit-brief`, `/appointments/${a}/visit-summary`]) {
      const r = await call('GET', path, w.deskToken);
      assert.equal(r.status, 403, `${path} must stay closed to the front desk`);
    }
    assert.equal((await call('POST', `/appointments/${a}/request-consent`, w.deskToken, {})).status, 403);
  });
});

describe('tokens', () => {
  it('are sequential per doctor per day, in the order patients are checked in', async () => {
    const w = world();
    const a1 = appt(makeMember('First'), w.d1, at('11:00'));
    const a2 = appt(makeMember('Second'), w.d1, at('09:00')); // earlier booking, but checked in later
    const b1 = appt(makeMember('OtherDoctor'), w.d2, at('09:00'));
    const nextDay = appt(makeMember('NextDay'), w.d1, at('09:00', '2026-09-23'));

    assert.equal((await call('POST', `/frontdesk/appointments/${a1}/check-in`, w.deskToken, {})).body.token, 1);
    assert.equal((await call('POST', `/frontdesk/appointments/${a2}/check-in`, w.deskToken, {})).body.token, 2);
    assert.equal((await call('POST', `/frontdesk/appointments/${b1}/check-in`, w.deskToken, {})).body.token, 1); // its own doctor's line
    assert.equal((await call('POST', `/frontdesk/appointments/${nextDay}/check-in`, w.deskToken, {})).body.token, 1); // its own day
  });

  it("are shared with the doctor's own check-in, so the two paths can never number differently", async () => {
    const w = world();
    const a1 = appt(makeMember('ViaDoctor'), w.d1, at('10:00'));
    const a2 = appt(makeMember('ViaDesk'), w.d1, at('10:30'));
    const viaDoctor = await call('POST', `/appointments/${a1}/check-in`, w.d1Token, {});
    assert.equal(viaDoctor.body.token, 1);
    assert.equal((await call('POST', `/frontdesk/appointments/${a2}/check-in`, w.deskToken, {})).body.token, 2);
  });

  it("checking in twice is refused, and a token never changes once given", async () => {
    const w = world();
    const a = appt(makeMember('Once'), w.d1, at('10:00'));
    assert.equal((await call('POST', `/frontdesk/appointments/${a}/check-in`, w.deskToken, {})).body.token, 1);
    assert.equal((await call('POST', `/frontdesk/appointments/${a}/check-in`, w.deskToken, {})).status, 409);
    assert.equal((db.prepare('SELECT token_number FROM appointments WHERE id = ?').get(a) as any).token_number, 1);
  });

  it('tell a waiting patient their token and how many are ahead — counts only, never who', async () => {
    const w = world();
    const first = appt(makeMember('Ahead'), w.d1, at('09:00'));
    const meId = makeMember('Me');
    const mine = appt(meId, w.d1, at('09:30'));
    await call('POST', `/frontdesk/appointments/${first}/check-in`, w.deskToken, {});
    await call('POST', `/frontdesk/appointments/${mine}/check-in`, w.deskToken, {});

    const fam = (db.prepare('SELECT family_id FROM members WHERE id = ?').get(meId) as any).family_id;
    const r = await call('GET', `/appointments/${mine}`, session('member_primary', null, meId, fam));
    assert.deepEqual(r.body.queue, { token: 2, ahead: 1 });
    assert.ok(!JSON.stringify(r.body.queue).includes('Ahead'));

    // Once the person ahead goes in to see the doctor, they're no longer ahead in the WAITING line.
    db.prepare(`UPDATE appointments SET status = 'consent_granted' WHERE id = ?`).run(first);
    const r2 = await call('GET', `/appointments/${mine}`, session('member_primary', null, meId, fam));
    assert.equal(r2.body.queue.ahead, 0);
  });

  it('a visit that is not waiting has no queue info', async () => {
    const w = world();
    const m = makeMember('Idle');
    const a = appt(m, w.d1, at('10:00'));
    const fam = (db.prepare('SELECT family_id FROM members WHERE id = ?').get(m) as any).family_id;
    assert.equal((await call('GET', `/appointments/${a}`, session('member_primary', null, m, fam))).body.queue, null);
  });
});

describe('walk-ins', () => {
  it('registers a brand-new patient, checks them in with a token, and tells the doctor', async () => {
    const w = world();
    const patientName = nextName('Meena Iyer');
    const r = await call('POST', '/frontdesk/walk-ins', w.deskToken, {
      provider_id: w.d1,
      datetime: at('10:15'),
      new_patient: { name: patientName, phone: `+91 ${nextPhone()}`, dob: '1985-04-02', sex: 'female' },
      reason: 'fever',
    });
    assert.equal(r.status, 201);
    assert.equal(r.body.token, 1);
    assert.equal(r.body.registered_new, true);

    const row = db.prepare('SELECT status, is_walk_in, token_number, member_id FROM appointments WHERE id = ?').get(r.body.id) as any;
    assert.equal(row.status, 'checked_in');
    assert.equal(row.is_walk_in, 1);
    const member = db.prepare('SELECT name, phone, registered_by_provider_id FROM members WHERE id = ?').get(row.member_id) as any;
    assert.equal(member.name, patientName);
    assert.equal(member.registered_by_provider_id, w.desk);

    const note = db.prepare(`SELECT type, body FROM provider_notifications WHERE provider_id = ? ORDER BY created_at DESC`).get(w.d1) as any;
    assert.equal(note.type, 'patient_checked_in');
    assert.ok(note.body.includes(patientName) && note.body.includes('token 1'));
  });

  it('does NOT unlock anything — the doctor still has to request consent and get it', async () => {
    const w = world();
    const r = await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, datetime: at('10:15'), new_patient: { name: nextName('Meena Iyer'), phone: nextPhone() } });
    assert.equal(r.status, 201);
    const detail = await call('GET', `/appointments/${r.body.id}`, w.d1Token);
    assert.equal(detail.body.status, 'checked_in');
    assert.equal(detail.body.unlockedData, undefined);
  });

  it('a registered walk-in can be found again by phone, however the number is written', async () => {
    const w = world();
    const phone = nextPhone();
    const name = nextName('Meena Iyer');
    const spaced = `${phone.slice(0, 5)} ${phone.slice(5)}`;
    assert.equal((await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, datetime: at('10:15'), new_patient: { name, phone: spaced } })).status, 201);
    const found = await call('GET', `/frontdesk/patients/lookup?phone=${encodeURIComponent(`+91-${phone}`)}`, w.deskToken);
    assert.equal(found.status, 200);
    assert.ok(found.body.some((m: any) => m.name === name));
  });

  it('an existing member is checked in without re-registering, and shows in their own app', async () => {
    const w = world();
    const existing = makeMember('Existing Patient');
    const r = await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, datetime: at('10:15'), member_id: existing });
    assert.equal(r.status, 201);
    assert.equal(r.body.registered_new, false);
    const fam = (db.prepare('SELECT family_id FROM members WHERE id = ?').get(existing) as any).family_id;
    const list = await call('GET', '/appointments', session('member_primary', null, existing, fam));
    assert.ok(list.body.some((a: any) => a.id === r.body.id && a.is_walk_in === 1));
  });

  it('warns before creating a second person on a number that is already registered (family members share phones)', async () => {
    const w = world();
    const phone = nextPhone();
    db.prepare('UPDATE members SET phone = ? WHERE id = ?').run(phone, makeMember('Parent'));
    const first = await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, datetime: at('10:15'), new_patient: { name: 'Child', phone } });
    assert.equal(first.status, 409);
    assert.ok(first.body.matches.some((m: any) => m.name === 'Parent'));
    const confirmed = await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, datetime: at('10:15'), new_patient: { name: 'Child', phone }, confirm_duplicate: true });
    assert.equal(confirmed.status, 201);
  });

  it('will not double-book: someone already booked with that doctor today is pointed at their existing visit', async () => {
    const w = world();
    const m = makeMember('Booked Already');
    const existing = appt(m, w.d1, at('16:00'));
    const r = await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, datetime: at('10:15'), member_id: m });
    assert.equal(r.status, 409);
    assert.equal(r.body.appointment_id, existing);
    // ...but a different doctor is fine.
    assert.equal((await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d2, datetime: at('10:15'), member_id: m })).status, 201);
  });

  it("only for this clinic's own doctors", async () => {
    const w = world();
    const name = nextName('Wrong Clinic Patient');
    const r = await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.dB, datetime: at('10:15'), new_patient: { name, phone: nextPhone() } });
    assert.equal(r.status, 400);
    assert.equal((db.prepare('SELECT COUNT(*) c FROM members WHERE name = ?').get(name) as any).c, 0); // nothing was registered either
  });

  it('validates the patient details', async () => {
    const w = world();
    const post = (new_patient: unknown) => call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, datetime: at('10:15'), new_patient });
    assert.equal((await post({ name: 'A', phone: '9876543210' })).status, 400); // name too short
    assert.equal((await post({ name: 'Meena', phone: '12345' })).status, 400); // phone too short
    assert.equal((await post({ name: 'Meena', phone: '9876543210', sex: 'robot' })).status, 400);
    assert.equal((await post({ name: 'Meena', phone: '9876543210', dob: 'yesterday' })).status, 400);
    assert.equal((await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, datetime: at('10:15') })).status, 400); // no patient at all
    assert.equal((await call('POST', '/frontdesk/walk-ins', w.deskToken, { provider_id: w.d1, new_patient: { name: 'Meena', phone: '9876543210' } })).status, 400); // no datetime
  });
});

describe('patient lookup cannot be used to browse patients', () => {
  it('needs a full number, matches exactly, and returns only id/name/age/sex', async () => {
    const w = world();
    const m = makeMember('Findable');
    db.prepare('UPDATE members SET phone = ?, address = ? WHERE id = ?').run('+91 90000 11111', '12 Secret Street', m);

    assert.equal((await call('GET', '/frontdesk/patients/lookup?phone=90000', w.deskToken)).status, 400); // partial number refused
    const none = await call('GET', '/frontdesk/patients/lookup?phone=9000011112', w.deskToken); // one digit off
    assert.deepEqual(none.body, []);
    const hit = await call('GET', '/frontdesk/patients/lookup?phone=9000011111', w.deskToken);
    assert.deepEqual(Object.keys(hit.body[0]).sort(), ['age', 'id', 'name', 'sex']);
    assert.ok(!JSON.stringify(hit.body).includes('Secret Street'));
  });

  it('is audited, without ever writing the full number to the log', async () => {
    const w = world();
    await call('GET', '/frontdesk/patients/lookup?phone=9000022222', w.deskToken);
    const row = db.prepare(`SELECT * FROM audit_log WHERE action = 'frontdesk_patient_lookup' ORDER BY rowid DESC LIMIT 1`).get() as any;
    assert.ok(row);
    assert.ok(JSON.stringify(row).includes('2222'));
    assert.ok(!JSON.stringify(row).includes('9000022222'));
  });
});

describe('cancelling from the desk', () => {
  it('cancels a scheduled visit and tells the doctor; refuses once the visit is under way', async () => {
    const w = world();
    const a = appt(makeMember('Called In'), w.d1, at('10:00'));
    assert.equal((await call('POST', `/frontdesk/appointments/${a}/cancel`, w.deskToken, {})).status, 200);
    assert.equal((db.prepare('SELECT status FROM appointments WHERE id = ?').get(a) as any).status, 'cancelled');
    assert.ok((db.prepare(`SELECT COUNT(*) c FROM provider_notifications WHERE provider_id = ? AND type = 'appointment_cancelled'`).get(w.d1) as any).c >= 1);

    const underway = appt(makeMember('Underway'), w.d1, at('10:30'), 'in_consultation');
    assert.equal((await call('POST', `/frontdesk/appointments/${underway}/cancel`, w.deskToken, {})).status, 409);
  });
});
