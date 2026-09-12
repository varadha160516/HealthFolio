import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';

// Cross-provider safety net — see schema.sql's comment on safety_flags for the full rationale.
// Same discipline as medicationReconciliation.ts: every check here is a structured-fact match
// (exact/substring name comparison, date-window comparison) against data already in the system —
// never a model asked to judge drug interactions or clinical significance. What makes this
// different from that file is scope: this runs across the member's ENTIRE active record — every
// prescriber, every lab order, self-booked or doctor-ordered — which is exactly the view no single
// doctor has under this app's per-visit consent model, but the member/family always does.

export interface SafetyFlag {
  id: string;
  member_id: string;
  kind: 'cross_provider_duplicate_medication' | 'allergy_conflict' | 'duplicate_lab_test';
  severity: 'info' | 'warning';
  title: string;
  detail: string;
  related_json: string;
  dedupe_key: string;
  status: 'open' | 'dismissed' | 'discussed';
  created_at: string;
  resolved_at: string | null;
}

interface ComputedFlag {
  kind: SafetyFlag['kind'];
  severity: SafetyFlag['severity'];
  title: string;
  detail: string;
  related: Record<string, unknown>;
  dedupeKey: string;
}

function normalize(s: string): string {
  return s.trim().toLowerCase();
}

const DUPLICATE_LAB_WINDOW_DAYS = 45;

function daysBetween(a: string, b: string): number {
  return Math.abs(new Date(a).getTime() - new Date(b).getTime()) / (1000 * 60 * 60 * 24);
}

function checkDuplicateMedications(memberId: string): ComputedFlag[] {
  const activeMeds = db
    .prepare(`SELECT id, medicine_name, prescribed_by, start_date FROM medication_schedules WHERE member_id = ? AND status = 'active'`)
    .all(memberId) as { id: string; medicine_name: string; prescribed_by: string | null; start_date: string }[];

  const byName = new Map<string, typeof activeMeds>();
  for (const m of activeMeds) {
    const key = normalize(m.medicine_name);
    if (!byName.has(key)) byName.set(key, []);
    byName.get(key)!.push(m);
  }

  const flags: ComputedFlag[] = [];
  for (const [normName, group] of byName) {
    if (group.length < 2) continue;
    const sources = [...new Set(group.map((g) => g.prescribed_by || 'you (self-added)'))];
    const crossProvider = sources.length > 1;
    const sortedIds = group.map((g) => g.id).sort();
    flags.push({
      kind: 'cross_provider_duplicate_medication',
      severity: crossProvider ? 'warning' : 'info',
      title: `${group[0].medicine_name} is active from ${group.length} sources`,
      detail: crossProvider
        ? `${group[0].medicine_name} is currently active on your record from more than one source: ${sources.join(' and ')}. Worth mentioning at your next visit in case it's an unintended duplicate rather than an intentional dose adjustment.`
        : `${group[0].medicine_name} appears as more than one active entry from the same source (${sources[0]}) — may just need tidying up in your records.`,
      related: { scheduleIds: group.map((g) => g.id), sources, startDates: group.map((g) => g.start_date) },
      dedupeKey: `cross_provider_duplicate_medication:${normName}:${sortedIds.join(',')}`,
    });
  }
  return flags;
}

function checkAllergyConflicts(memberId: string): ComputedFlag[] {
  const activeMeds = db
    .prepare(`SELECT id, medicine_name, prescribed_by FROM medication_schedules WHERE member_id = ? AND status = 'active'`)
    .all(memberId) as { id: string; medicine_name: string; prescribed_by: string | null }[];
  const allergies = (db.prepare('SELECT value FROM allergies WHERE member_id = ?').all(memberId) as { value: string }[]).map((r) => r.value);
  if (allergies.length === 0 || activeMeds.length === 0) return [];

  const flags: ComputedFlag[] = [];
  for (const med of activeMeds) {
    const normMed = normalize(med.medicine_name);
    for (const allergy of allergies) {
      const normAllergy = normalize(allergy);
      if (normAllergy.length >= 3 && (normMed.includes(normAllergy) || normAllergy.includes(normMed))) {
        flags.push({
          kind: 'allergy_conflict',
          severity: 'warning',
          title: `${med.medicine_name} shares a name with a recorded allergy`,
          detail: `${med.medicine_name} (prescribed by ${med.prescribed_by ?? 'you'}) shares a name with your recorded allergy to "${allergy}". This may be a name coincidence, not a real conflict — flag it to whoever prescribed this, or to your pharmacist, to be sure.`,
          related: { scheduleId: med.id, allergy },
          dedupeKey: `allergy_conflict:${med.id}:${normAllergy}`,
        });
      }
    }
  }
  return flags;
}

function checkDuplicateLabTests(memberId: string): ComputedFlag[] {
  const bookings = db
    .prepare(`SELECT id, test_names, ordered_by_provider_id, booked_date, created_at FROM lab_test_bookings WHERE member_id = ? AND status != 'cancelled'`)
    .all(memberId) as { id: string; test_names: string; ordered_by_provider_id: string | null; booked_date: string | null; created_at: string }[];
  if (bookings.length < 2) return [];

  type Entry = { bookingId: string; testName: string; source: string | null; date: string };
  const entries: Entry[] = [];
  for (const b of bookings) {
    let names: string[] = [];
    try {
      names = JSON.parse(b.test_names);
    } catch {
      continue;
    }
    const date = b.booked_date ?? b.created_at;
    for (const name of names) entries.push({ bookingId: b.id, testName: name, source: b.ordered_by_provider_id, date });
  }

  const byName = new Map<string, Entry[]>();
  for (const e of entries) {
    const key = normalize(e.testName);
    if (!byName.has(key)) byName.set(key, []);
    byName.get(key)!.push(e);
  }

  const flags: ComputedFlag[] = [];
  for (const [, group] of byName) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.date.localeCompare(b.date));
    for (let i = 1; i < group.length; i++) {
      const prev = group[i - 1];
      const curr = group[i];
      if (prev.bookingId === curr.bookingId) continue;
      if (daysBetween(prev.date, curr.date) > DUPLICATE_LAB_WINDOW_DAYS) continue;
      const crossSource = prev.source !== curr.source;
      const sortedIds = [prev.bookingId, curr.bookingId].sort();
      flags.push({
        kind: 'duplicate_lab_test',
        severity: 'info',
        title: `${curr.testName} was ordered twice within ${DUPLICATE_LAB_WINDOW_DAYS} days`,
        detail: crossSource
          ? `${curr.testName} was booked twice within ${DUPLICATE_LAB_WINDOW_DAYS} days from different sources — worth checking whether the first result already covers this before paying for a repeat.`
          : `${curr.testName} was booked twice within ${DUPLICATE_LAB_WINDOW_DAYS} days. If the first one wasn't for monitoring a known condition, you may not need the repeat.`,
        related: { bookingIds: sortedIds, dates: [prev.date, curr.date] },
        dedupeKey: `duplicate_lab_test:${normalize(curr.testName)}:${sortedIds.join(',')}`,
      });
    }
  }
  return flags;
}

/** Recomputes every check and upserts newly-found flags — a flag the member already dismissed or
 * marked discussed is never resurrected, only genuinely new facts (a different dedupe_key) create
 * a new row. No scheduler exists in this app (same as the admin dictionary drift-scan), so this
 * runs on demand whenever the member's safety-check screen is opened rather than periodically. */
export function runSafetyCheck(memberId: string): { open: SafetyFlag[]; history: SafetyFlag[] } {
  const computed = [...checkDuplicateMedications(memberId), ...checkAllergyConflicts(memberId), ...checkDuplicateLabTests(memberId)];

  const insert = db.prepare(
    `INSERT INTO safety_flags (id, member_id, kind, severity, title, detail, related_json, dedupe_key, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'open', ?)`
  );
  const findExisting = db.prepare('SELECT id FROM safety_flags WHERE member_id = ? AND dedupe_key = ?');

  for (const f of computed) {
    const existing = findExisting.get(memberId, f.dedupeKey);
    if (existing) continue; // already tracked (open, dismissed, or discussed) — respect whatever state it's in
    insert.run(uuid(), memberId, f.kind, f.severity, f.title, f.detail, JSON.stringify(f.related), f.dedupeKey, now());
  }

  const open = db.prepare(`SELECT * FROM safety_flags WHERE member_id = ? AND status = 'open' ORDER BY created_at DESC`).all(memberId) as unknown as SafetyFlag[];
  const history = db.prepare(`SELECT * FROM safety_flags WHERE member_id = ? AND status != 'open' ORDER BY resolved_at DESC LIMIT 20`).all(memberId) as unknown as SafetyFlag[];
  return { open, history };
}
