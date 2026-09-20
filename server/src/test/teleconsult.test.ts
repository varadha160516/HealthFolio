import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import type { Server } from 'node:http';
import { v4 as uuid } from 'uuid';
import { buildApp } from '../app.js';
import { createSession } from '../auth/session.js';
import { db, now } from '../db/db.js';
import { ensureDictionary, makeMember } from './testUtils.js';
import { toWaNumber } from '../whatsapp.js';

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

const DAY = '2026-09-22';
const at = (time: string, day = DAY) => `${day}T${time}:00.000`;

function makeClinic(name: string) {
  const id = uuid();
  db.prepare('INSERT INTO clinics (id, name) VALUES (?, ?)').run(id, name);
  return id;
}
function makeStaff(type: 'doctor' | 'clinic_admin', name: string, clinicId: string | null, offersVideo = false) {
  const id = uuid();
  db.prepare('INSERT INTO providers (id, type, name, specialty, clinic_id, offers_video) VALUES (?, ?, ?, NULL, ?, ?)').run(id, type, name, clinicId, offersVideo ? 1 : 0);
  return id;
}
type Role = 'provider_doctor' | 'provider_clinic_admin' | 'member_primary';
function session(role: Role, providerId: string | null, memberId: string | null = null, familyId: string | null = null) {
  return createSession({ userId: `u-${Math.random()}`, role, displayName: 'T', memberId, familyId, providerId }).token;
}
function familyOf(memberId: string) {
  return (db.prepare('SELECT family_id FROM members WHERE id = ?').get(memberId) as any).family_id as string;
}
function memberSession(memberId: string) {
  return session('member_primary', null, memberId, familyOf(memberId));
}
function insertAppt(memberId: string, providerId: string, datetime: string, opts: { status?: string; mode?: 'in_person' | 'video'; reason?: string | null } = {}) {
  const id = uuid();
  db.prepare(
    `INSERT INTO appointments (id, member_id, provider_id, datetime, status, sharing_preference, reason_for_visit, consent_grant_id, consultation_mode, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 'full_history', ?, NULL, ?, ?, ?)`
  ).run(id, memberId, providerId, datetime, opts.status ?? 'scheduled', opts.reason ?? null, opts.mode ?? 'in_person', now(), now());
  return id;
}
function setPhone(memberId: string, phone: string | null, optIn: boolean) {
  db.prepare('UPDATE members SET phone = ?, whatsapp_opt_in = ? WHERE id = ?').run(phone, optIn ? 1 : 0, memberId);
}
const statusOf = (id: string) => (db.prepare('SELECT status FROM appointments WHERE id = ?').get(id) as any).status as string;
const notifCount = (providerId: string) => (db.prepare(`SELECT COUNT(*) AS c FROM provider_notifications WHERE provider_id = ? AND type = 'patient_checked_in'`).get(providerId) as any).c as number;

describe('video consultations: booking', () => {
  it('only lets a member book video with a doctor who offers it', async () => {
    const yes = makeStaff('doctor', 'Dr. Video', null, true);
    const no = makeStaff('doctor', 'Dr. Inperson', null, false);
    const m = makeMember('Booker');
    const tok = memberSession(m);

    const denied = await call('POST', '/appointments', tok, { member_id: m, provider_id: no, datetime: at('10:00'), consultation_mode: 'video' });
    assert.equal(denied.status, 409);
    const ok = await call('POST', '/appointments', tok, { member_id: m, provider_id: yes, datetime: at('10:00'), consultation_mode: 'video' });
    assert.equal(ok.status, 201);
    assert.equal((db.prepare('SELECT consultation_mode FROM appointments WHERE id = ?').get(ok.body.id) as any).consultation_mode, 'video');
    // Unspecified stays in person, and garbage is refused rather than silently defaulted.
    const plain = await call('POST', '/appointments', tok, { member_id: m, provider_id: no, datetime: at('11:00') });
    assert.equal((db.prepare('SELECT consultation_mode FROM appointments WHERE id = ?').get(plain.body.id) as any).consultation_mode, 'in_person');
    assert.equal((await call('POST', '/appointments', tok, { member_id: m, provider_id: yes, datetime: at('12:00'), consultation_mode: 'telepathy' })).status, 400);
  });

  it('will not switch a visit to video, or move it to a doctor who lacks video, behind their back', async () => {
    const yes = makeStaff('doctor', 'Dr. Yes', null, true);
    const no = makeStaff('doctor', 'Dr. No', null, false);
    const m = makeMember('Editor');
    const tok = memberSession(m);
    const video = insertAppt(m, yes, at('10:00'), { mode: 'video' });
    // Moving a video visit to a doctor without video is refused…
    assert.equal((await call('PATCH', `/appointments/${video}`, tok, { provider_id: no })).status, 409);
    // …and so is turning an in-person visit with such a doctor into a video one.
    const inPerson = insertAppt(m, no, at('11:00'));
    assert.equal((await call('PATCH', `/appointments/${inPerson}`, tok, { consultation_mode: 'video' })).status, 409);
    // A video-capable doctor can flip it.
    const flip = insertAppt(m, yes, at('12:00'));
    assert.equal((await call('PATCH', `/appointments/${flip}`, tok, { consultation_mode: 'video' })).status, 200);
  });

  it('lets a doctor switch video on and off in their profile, and rejects a non-boolean', async () => {
    const d = makeStaff('doctor', 'Dr. Toggle', null, false);
    const tok = session('provider_doctor', d);
    assert.equal((await call('PATCH', '/providers/me/profile', tok, { offers_video: 'yes' })).status, 400);
    assert.equal((await call('PATCH', '/providers/me/profile', tok, { offers_video: true })).status, 200);
    assert.equal((await call('GET', '/providers/me/profile', tok)).body.offers_video, 1);
    assert.equal((await call('PATCH', '/providers/me/profile', tok, { offers_video: false })).status, 200);
    assert.equal((await call('GET', '/providers/me/profile', tok)).body.offers_video, 0);
  });
});

describe('video consultations: the room', () => {
  it('gives the patient and the doctor the same room, and never shows the room name in any listing', async () => {
    const d = makeStaff('doctor', 'Dr. Room', null, true);
    const m = makeMember('Patient');
    const id = insertAppt(m, d, at('10:00'), { mode: 'video' });
    const mTok = memberSession(m);
    const dTok = session('provider_doctor', d);

    const p = await call('POST', `/appointments/${id}/video/join`, mTok);
    const doc = await call('POST', `/appointments/${id}/video/join`, dTok);
    assert.equal(p.status, 200);
    assert.equal(doc.status, 200);
    const room = (db.prepare('SELECT video_room FROM appointments WHERE id = ?').get(id) as any).video_room as string;
    assert.match(room, /^careloop-[0-9a-f]{32}$/);
    assert.ok(p.body.url.includes(room) && doc.body.url.includes(room));
    assert.ok(p.body.url.startsWith('https://'));
    // Rejoining doesn't mint a new room.
    assert.ok((await call('POST', `/appointments/${id}/video/join`, mTok)).body.url.includes(room));

    for (const [path, tok] of [['/appointments', mTok], [`/appointments/${id}`, mTok], ['/appointments', dTok], [`/appointments/${id}`, dTok]] as const) {
      const r = await call('GET', path, tok);
      assert.ok(!JSON.stringify(r.body).includes(room), `${path} leaked the room`);
      assert.ok(!JSON.stringify(r.body).includes('video_room'), `${path} exposes the video_room field`);
    }
    // The audit trail records that a join happened, but not the room.
    const audit = db.prepare(`SELECT * FROM audit_log WHERE action = 'video_joined'`).all();
    assert.ok(audit.length >= 2);
    assert.ok(!JSON.stringify(audit).includes(room));
  });

  it("checks the patient in with no token, and tells the doctor once — not on every rejoin", async () => {
    const d = makeStaff('doctor', 'Dr. Notify', null, true);
    const inPersonFirst = makeMember('In Person');
    const person = insertAppt(inPersonFirst, d, at('09:00'), { status: 'scheduled' });
    const m = makeMember('Remote');
    const id = insertAppt(m, d, at('10:00'), { mode: 'video' });
    const tok = memberSession(m);
    const before = notifCount(d);

    await call('POST', `/appointments/${id}/video/join`, tok);
    assert.equal(statusOf(id), 'checked_in');
    assert.equal((db.prepare('SELECT token_number FROM appointments WHERE id = ?').get(id) as any).token_number, null);
    assert.equal(notifCount(d), before + 1);
    await call('POST', `/appointments/${id}/video/join`, tok);
    await call('POST', `/appointments/${id}/video/join`, tok);
    assert.equal(notifCount(d), before + 1);

    // The video visit didn't take a place in the physical line: the next counter patient is token 1.
    const dTok = session('provider_doctor', d);
    const r = await call('POST', `/appointments/${person}/check-in`, dTok);
    assert.equal(r.body.token, 1);
  });

  it('does not let the doctor joining first check anyone in', async () => {
    const d = makeStaff('doctor', 'Dr. Early', null, true);
    const m = makeMember('Late');
    const id = insertAppt(m, d, at('10:00'), { mode: 'video' });
    await call('POST', `/appointments/${id}/video/join`, session('provider_doctor', d));
    assert.equal(statusOf(id), 'scheduled');
    assert.notEqual((db.prepare('SELECT video_doctor_joined_at FROM appointments WHERE id = ?').get(id) as any).video_doctor_joined_at, null);
  });

  it('refuses everyone who is not on the visit: another family, another doctor, front desk, and in-person visits', async () => {
    const clinic = makeClinic('Sunrise');
    const d = makeStaff('doctor', 'Dr. Mine', clinic, true);
    const otherDoc = makeStaff('doctor', 'Dr. Other', clinic, true);
    const desk = makeStaff('clinic_admin', 'Desk', clinic);
    const m = makeMember('Mine');
    const stranger = makeMember('Stranger');
    const id = insertAppt(m, d, at('10:00'), { mode: 'video' });

    assert.equal((await call('POST', `/appointments/${id}/video/join`, memberSession(stranger))).status, 403);
    assert.equal((await call('POST', `/appointments/${id}/video/join`, session('provider_doctor', otherDoc))).status, 403);
    assert.equal((await call('POST', `/appointments/${id}/video/join`, session('provider_clinic_admin', desk))).status, 403);
    assert.equal((await call('POST', `/appointments/${id}/video/join`, 'nope')).status, 401);
    assert.equal(db.prepare('SELECT video_room FROM appointments WHERE id = ?').get(id) && (db.prepare('SELECT video_room FROM appointments WHERE id = ?').get(id) as any).video_room, null);

    const inPerson = insertAppt(m, d, at('11:00'));
    assert.equal((await call('POST', `/appointments/${inPerson}/video/join`, memberSession(m))).status, 409);
  });

  it('closes the room once the visit is cancelled or completed', async () => {
    const d = makeStaff('doctor', 'Dr. Done', null, true);
    const m = makeMember('Finisher');
    const cancelled = insertAppt(m, d, at('10:00'), { mode: 'video', status: 'cancelled' });
    const completed = insertAppt(m, d, at('11:00'), { mode: 'video', status: 'completed' });
    assert.equal((await call('POST', `/appointments/${cancelled}/video/join`, memberSession(m))).status, 409);
    assert.equal((await call('POST', `/appointments/${completed}/video/join`, session('provider_doctor', d))).status, 409);
  });
});

describe('video consultations: consent is unchanged', () => {
  it('keeps the record locked in the room, and refuses the in-room OTP fallback for a remote patient', async () => {
    const d = makeStaff('doctor', 'Dr. Consent', null, true);
    const m = makeMember('Guarded');
    const id = insertAppt(m, d, at('10:00'), { mode: 'video' });
    const mTok = memberSession(m);
    const dTok = session('provider_doctor', d);

    await call('POST', `/appointments/${id}/video/join`, mTok);
    assert.equal((await call('GET', `/appointments/${id}`, dTok)).body.unlockedData, undefined);

    assert.equal((await call('POST', `/appointments/${id}/request-consent`, dTok, { method: 'otp' })).status, 400);
    assert.equal(statusOf(id), 'checked_in');
    const ok = await call('POST', `/appointments/${id}/request-consent`, dTok, { method: 'in_app' });
    assert.equal(ok.status, 200);
    assert.equal(ok.body.otp, null);
    // Still locked until the patient answers.
    assert.equal((await call('GET', `/appointments/${id}`, dTok)).body.unlockedData, undefined);
    assert.equal((await call('POST', `/appointments/${id}/respond-consent`, mTok, { approve: true })).status, 200);
    assert.notEqual((await call('GET', `/appointments/${id}`, dTok)).body.unlockedData, undefined);
  });

  it('a front desk cannot check a video patient in at the counter, and sees the visit flagged as video', async () => {
    const clinic = makeClinic('Sunrise 2');
    const d = makeStaff('doctor', 'Dr. Desk', clinic, true);
    const desk = makeStaff('clinic_admin', 'Desk 2', clinic);
    const m = makeMember('Remote 2');
    const id = insertAppt(m, d, at('10:00'), { mode: 'video' });
    const deskTok = session('provider_clinic_admin', desk);
    assert.equal((await call('POST', `/frontdesk/appointments/${id}/check-in`, deskTok)).status, 409);
    const q = await call('GET', `/frontdesk/queue?date=${DAY}`, deskTok);
    const row = q.body.doctors.find((x: any) => x.id === d).appointments.find((a: any) => a.id === id);
    assert.equal(row.consultation_mode, 'video');
  });
});

describe('WhatsApp nudges', () => {
  it('normalises phone numbers the way wa.me needs them', () => {
    assert.equal(toWaNumber('98765 43210'), '919876543210');
    assert.equal(toWaNumber('09876543210'), '919876543210');
    assert.equal(toWaNumber('+91 98765-43210'), '919876543210');
    assert.equal(toWaNumber('+1 (415) 555-0132'), '14155550132');
    assert.equal(toWaNumber('12345'), null);
    assert.equal(toWaNumber(null), null);
  });

  it('issues no link unless the patient opted in and has a usable number', async () => {
    const d = makeStaff('doctor', 'Dr. Wa', null);
    const m = makeMember('Optless');
    const id = insertAppt(m, d, at('10:00'));
    const dTok = session('provider_doctor', d);

    setPhone(m, '9876543210', false);
    assert.equal((await call('POST', `/appointments/${id}/whatsapp-link`, dTok, { kind: 'reminder' })).status, 409);
    setPhone(m, null, true);
    assert.equal((await call('POST', `/appointments/${id}/whatsapp-link`, dTok, { kind: 'reminder' })).status, 409);
    setPhone(m, '9876543210', true);
    const ok = await call('POST', `/appointments/${id}/whatsapp-link`, dTok, { kind: 'reminder' });
    assert.equal(ok.status, 200);
    assert.ok(ok.body.url.startsWith('https://wa.me/919876543210?text='));
  });

  it('keeps clinical content out of every message, and the phone number out of every payload', async () => {
    const d = makeStaff('doctor', 'Dr. Quiet', null);
    const m = makeMember('Private Person');
    setPhone(m, '9123456780', true);
    const id = insertAppt(m, d, at('10:00'), { reason: 'suspected diabetes follow-up' });
    const dTok = session('provider_doctor', d);

    const r = await call('POST', `/appointments/${id}/whatsapp-link`, dTok, { kind: 'reminder' });
    const text = decodeURIComponent(r.body.url.split('?text=')[1]);
    assert.ok(text.includes('Private') && text.includes('Dr. Quiet'));
    assert.ok(!/diabet/i.test(text) && !r.body.url.toLowerCase().includes('diabet'));

    const list = await call('GET', '/appointments', dTok);
    assert.equal(list.body[0].whatsapp_available, true);
    assert.ok(!JSON.stringify(list.body).includes('9123456780'));
    const one = await call('GET', `/appointments/${id}`, dTok);
    assert.ok(!JSON.stringify(one.body).includes('9123456780'));
  });

  it('only offers the message that makes sense for where the visit is', async () => {
    const d = makeStaff('doctor', 'Dr. Kinds', null, true);
    const m = makeMember('Kinds');
    setPhone(m, '9000000001', true);
    const dTok = session('provider_doctor', d);
    const link = (id: string, kind: string) => call('POST', `/appointments/${id}/whatsapp-link`, dTok, { kind });

    const scheduled = insertAppt(m, d, at('10:00'));
    assert.equal((await link(scheduled, 'reminder')).status, 200);
    assert.equal((await link(scheduled, 'token')).status, 409); // not waiting yet
    assert.equal((await link(scheduled, 'video_ready')).status, 409); // not a video visit
    assert.equal((await link(scheduled, 'summary_ready')).status, 409); // nothing to point to
    assert.equal((await link(scheduled, 'bogus')).status, 400);

    await call('POST', `/appointments/${scheduled}/check-in`, dTok);
    assert.equal((await link(scheduled, 'reminder')).status, 409); // too late for a reminder
    const token = await link(scheduled, 'token');
    assert.equal(token.status, 200);
    assert.ok(decodeURIComponent(token.body.url).includes('token'));

    const video = insertAppt(m, d, at('11:00'), { mode: 'video' });
    assert.equal((await link(video, 'video_ready')).status, 200);
    assert.ok(decodeURIComponent((await link(video, 'reminder')).body.url).includes('video consultation'));
    // The message points at the app — it never carries the room.
    assert.ok(!decodeURIComponent((await link(video, 'video_ready')).body.url).includes('jit.si'));

    db.prepare(`INSERT INTO visit_summaries (appointment_id, member_id, provider_id, english_text, language, translated_text, status, sent_at, updated_at) VALUES (?, ?, ?, 'x', 'English', NULL, 'sent', ?, ?)`).run(scheduled, m, d, now(), now());
    assert.equal((await link(scheduled, 'summary_ready')).status, 200);

    const cancelled = insertAppt(m, d, at('12:00'), { status: 'cancelled' });
    assert.equal((await link(cancelled, 'reminder')).status, 409);
  });

  it("is scoped: a doctor can only message for their own visits, and a front desk only for their clinic's", async () => {
    const clinicA = makeClinic('Wa A');
    const clinicB = makeClinic('Wa B');
    const dA = makeStaff('doctor', 'Dr. A', clinicA);
    const dB = makeStaff('doctor', 'Dr. B', clinicB);
    const deskA = makeStaff('clinic_admin', 'Desk A', clinicA);
    const m = makeMember('Scoped');
    setPhone(m, '9000000002', true);
    const mine = insertAppt(m, dA, at('10:00'));
    const theirs = insertAppt(m, dB, at('11:00'));
    const dTok = session('provider_doctor', dA);
    const deskTok = session('provider_clinic_admin', deskA);

    assert.equal((await call('POST', `/appointments/${theirs}/whatsapp-link`, dTok, { kind: 'reminder' })).status, 403);
    assert.equal((await call('POST', `/frontdesk/appointments/${mine}/whatsapp-link`, deskTok, { kind: 'reminder' })).status, 200);
    assert.equal((await call('POST', `/frontdesk/appointments/${theirs}/whatsapp-link`, deskTok, { kind: 'reminder' })).status, 404);
    // A patient can't ask for a clinic's link to their own number (or anyone's).
    assert.equal((await call('POST', `/appointments/${mine}/whatsapp-link`, memberSession(m), { kind: 'reminder' })).status, 403);
  });

  it("lets the patient opt in from their profile — but not without a number — and out again", async () => {
    const m = makeMember('Profile');
    const tok = memberSession(m);
    assert.equal((await call('PATCH', `/members/${m}/profile`, tok, { whatsapp_opt_in: true })).status, 400);
    assert.equal((await call('PATCH', `/members/${m}/profile`, tok, { whatsapp_opt_in: 'yes' })).status, 400);
    assert.equal((await call('PATCH', `/members/${m}/profile`, tok, { phone: '9000000003', whatsapp_opt_in: true })).status, 200);
    assert.equal((db.prepare('SELECT whatsapp_opt_in FROM members WHERE id = ?').get(m) as any).whatsapp_opt_in, 1);
    assert.equal((await call('PATCH', `/members/${m}/profile`, tok, { whatsapp_opt_in: false })).status, 200);
    assert.equal((db.prepare('SELECT whatsapp_opt_in FROM members WHERE id = ?').get(m) as any).whatsapp_opt_in, 0);
  });

  it('a patient registered at the counter is only opted in if the desk ticked the box', async () => {
    const clinic = makeClinic('Walk Wa');
    const d = makeStaff('doctor', 'Dr. Walk', clinic);
    const desk = makeStaff('clinic_admin', 'Desk W', clinic);
    const deskTok = session('provider_clinic_admin', desk);
    const walk = (name: string, phone: string, optIn?: boolean) =>
      call('POST', '/frontdesk/walk-ins', deskTok, { provider_id: d, datetime: at('10:00', '2026-10-01'), new_patient: { name, phone, ...(optIn === undefined ? {} : { whatsapp_opt_in: optIn }) } });

    const a = await walk('Walk Yes', '9500000001', true);
    const b = await walk('Walk No', '9500000002');
    assert.equal((db.prepare('SELECT whatsapp_opt_in FROM members WHERE id = ?').get(a.body.member_id) as any).whatsapp_opt_in, 1);
    assert.equal((db.prepare('SELECT whatsapp_opt_in FROM members WHERE id = ?').get(b.body.member_id) as any).whatsapp_opt_in, 0);
  });
});
