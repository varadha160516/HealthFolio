import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import type { Server } from 'node:http';
import { v4 as uuid } from 'uuid';
import { buildApp } from '../app.js';
import { createSession } from '../auth/session.js';
import { db, now } from '../db/db.js';
import { computeAdherence, type AdherenceLog, type AdherenceSchedule } from '../pipeline/adherence.js';
import { ensureDictionary, makeMember, makeProvider, makeAppointment } from './testUtils.js';

const TODAY = '2026-09-20'; // window = the 7 completed days 09-13 .. 09-19

function sched(over: Partial<AdherenceSchedule> = {}): AdherenceSchedule {
  return { id: 's1', medicine_name: 'Paracetamol', strength: '650 mg', frequency: 'daily', times: ['08:00', '14:00', '20:00'], day_of_week: null, start_date: '2026-09-01', end_date: null, prescribed_by_provider_id: null, ...over };
}
function log(date: string, status: 'taken' | 'skipped' = 'taken', scheduleId = 's1'): AdherenceLog {
  return { schedule_id: scheduleId, dose_date: date, status };
}
function days(from: string, n: number): string[] {
  return Array.from({ length: n }, (_, i) => new Date(Date.parse(`${from}T00:00:00Z`) + i * 86_400_000).toISOString().slice(0, 10));
}
const only = (r: ReturnType<typeof computeAdherence>) => r.medications[0];

describe('adherence maths (what the patient logged, never inferred)', () => {
  it('the window is the last 7 COMPLETED days — today is left out', () => {
    const r = computeAdherence([sched()], [], TODAY, 'doc');
    assert.deepEqual(r.window, { from: '2026-09-13', to: '2026-09-19', days: 7 });
  });

  it('counts a fully-logged week as 21 of 21', () => {
    const logs = days('2026-09-13', 7).flatMap((d) => [log(d), log(d), log(d)]);
    const m = only(computeAdherence([sched()], logs, TODAY, 'doc'));
    assert.equal(m.expected, 21);
    assert.equal(m.taken, 21);
    assert.equal(m.taken_pct, 100);
    assert.equal(m.not_logged, 0);
  });

  it('separates taken, skipped and not-logged — an unlogged dose is never called "missed"', () => {
    // 3 doses/day. Day 1: 2 taken + 1 skipped. Day 2: 1 taken, nothing else logged. Rest: nothing.
    const logs = [log('2026-09-13'), log('2026-09-13'), log('2026-09-13', 'skipped'), log('2026-09-14')];
    const m = only(computeAdherence([sched()], logs, TODAY, 'doc'));
    assert.equal(m.expected, 21);
    assert.equal(m.taken, 3);
    assert.equal(m.skipped, 1);
    assert.equal(m.not_logged, 17);
    assert.equal(m.taken_pct, 14);
  });

  it('nothing logged at all reads as not-logged, with no adherence percentage claim of "missed"', () => {
    const m = only(computeAdherence([sched()], [], TODAY, 'doc'));
    assert.equal(m.taken, 0);
    assert.equal(m.skipped, 0);
    assert.equal(m.not_logged, 21);
  });

  it('never exceeds 100% even if a day has more logs than doses (double-tapped Taken)', () => {
    const logs = days('2026-09-13', 7).flatMap((d) => [log(d), log(d), log(d), log(d), log(d)]);
    const m = only(computeAdherence([sched()], logs, TODAY, 'doc'));
    assert.equal(m.taken, 21);
    assert.equal(m.taken_pct, 100);
  });

  it("matches logs per day, not per exact time — editing a schedule's times doesn't orphan old logs", () => {
    const logs = [log('2026-09-15'), log('2026-09-15')];
    const m = only(computeAdherence([sched({ times: ['09:30'] })], logs, TODAY, 'doc'));
    assert.equal(m.expected, 7); // one dose a day now
    assert.equal(m.taken, 1); // capped at one per day, not two
  });

  it('only counts days since the medicine was started', () => {
    const m = only(computeAdherence([sched({ start_date: '2026-09-18' })], [], TODAY, 'doc'));
    assert.equal(m.days_counted, 2); // 09-18 and 09-19
    assert.equal(m.expected, 6);
  });

  it('a medicine started today has nothing to judge yet — no percentage', () => {
    const m = only(computeAdherence([sched({ start_date: TODAY })], [], TODAY, 'doc'));
    assert.equal(m.days_counted, 0);
    assert.equal(m.expected, 0);
    assert.equal(m.taken_pct, null);
  });

  it("today's own logs and doses never count", () => {
    const m = only(computeAdherence([sched()], [log(TODAY), log(TODAY), log(TODAY)], TODAY, 'doc'));
    assert.equal(m.taken, 0);
    assert.equal(m.expected, 21);
  });

  it('a finished course is excluded; one that ended mid-window counts only until its end date', () => {
    const finished = sched({ id: 'old', end_date: '2026-09-10' });
    const endedMid = sched({ id: 'mid', end_date: '2026-09-15' });
    const r = computeAdherence([finished, endedMid], [], TODAY, 'doc');
    assert.equal(r.medications.length, 1);
    assert.equal(r.medications[0].schedule_id, 'mid');
    assert.equal(r.medications[0].days_counted, 3); // 09-13, 09-14, 09-15
  });

  it('weekly medicines expect exactly one dose in a 7-day window', () => {
    // 2026-09-16 is a Wednesday (day 3).
    const m = only(computeAdherence([sched({ frequency: 'weekly', times: ['20:00'], day_of_week: 3 })], [log('2026-09-16')], TODAY, 'doc'));
    assert.equal(m.expected, 1);
    assert.equal(m.taken, 1);
    assert.equal(m.taken_pct, 100);
  });

  it('as-needed medicines report uses (including today), not a percentage', () => {
    const m = only(computeAdherence([sched({ frequency: 'as_needed', times: [] })], [log('2026-09-14'), log('2026-09-18'), log(TODAY), log('2026-09-02')], TODAY, 'doc'));
    assert.equal(m.as_needed_uses, 3); // the 09-02 use is outside the window
    assert.equal(m.expected, 0);
    assert.equal(m.taken_pct, null);
  });

  it("flags the viewing doctor's own prescriptions and lists them first", () => {
    const r = computeAdherence(
      [sched({ id: 'a', medicine_name: 'Aspirin', prescribed_by_provider_id: 'other' }), sched({ id: 'z', medicine_name: 'Zinc', prescribed_by_provider_id: 'doc' }), sched({ id: 'm', medicine_name: 'Metformin' })],
      [],
      TODAY,
      'doc'
    );
    assert.deepEqual(r.medications.map((m) => [m.medicine_name, m.prescribed_by_you]), [['Zinc', true], ['Aspirin', false], ['Metformin', false]]);
  });
});

// ---- Through the real endpoint: only inside the consent window, and "prescribed by you" comes from
// the prescription, never from free text the patient typed. ----

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

describe('adherence over the wire', () => {
  function scenario() {
    const memberId = makeMember(`Patient ${Math.random()}`);
    const me = makeProvider('Dr. Me');
    const other = makeProvider('Dr. Other');
    const apptId = makeAppointment(memberId, me, 'consent_granted');
    const token = createSession({ userId: 'u', role: 'provider_doctor', displayName: 'Dr', memberId: null, familyId: null, providerId: me }).token;

    const rx = (providerId: string, name: string) => {
      const rxId = uuid();
      const liId = uuid();
      db.prepare('INSERT INTO prescriptions (id, appointment_id, provider_id, member_id, document_id, diagnosis_text, notes, issued_at) VALUES (?, NULL, ?, ?, NULL, NULL, NULL, ?)').run(rxId, providerId, memberId, now());
      db.prepare('INSERT INTO prescription_line_items (id, prescription_id, medicine_name) VALUES (?, ?, ?)').run(liId, rxId, name);
      const sid = uuid();
      db.prepare(
        `INSERT INTO medication_schedules (id, member_id, prescription_line_item_id, medicine_name, frequency, times, start_date, prescribed_by, status, created_at)
         VALUES (?, ?, ?, ?, 'daily', '["08:00"]', '2026-01-01', ?, 'active', ?)`
      ).run(sid, memberId, liId, name, name === 'FromOther' ? 'Dr. Me' : 'whoever', now()); // free-text prescribed_by deliberately misleading
      return sid;
    };
    return { memberId, apptId, token, mine: rx(me, 'FromMe'), theirs: rx(other, 'FromOther') };
  }

  it('is included while unlocked, and "prescribed by you" follows the prescription, not the patient-typed text', async () => {
    const { apptId, token, mine, theirs } = scenario();
    const r = await get(`/appointments/${apptId}`, token);
    const meds = r.body.unlockedData.adherence.medications as any[];
    assert.equal(meds.find((m) => m.schedule_id === mine).prescribed_by_you, true);
    assert.equal(meds.find((m) => m.schedule_id === theirs).prescribed_by_you, false); // even though its free text says "Dr. Me"
  });

  it('is absent while the visit is locked — no back door around the consent gate', async () => {
    const { apptId, token, memberId } = scenario();
    db.prepare(`UPDATE appointments SET status = 'checked_in' WHERE id = ?`).run(apptId);
    const r = await get(`/appointments/${apptId}`, token);
    assert.equal(r.body.unlockedData, undefined);
    assert.ok(!JSON.stringify(r.body).includes('adherence'));
    assert.ok(memberId);
  });
});
