import Anthropic from '@anthropic-ai/sdk';
import { db, now } from '../db/db.js';
import { computeOverviewParameters } from '../summary.js';

/** Same short display text the mobile app renders (mobile/lib/utils/range_format.dart) — kept
 * duplicated rather than shared since this is server-side prose generation, not a UI concern. */
function formatReferenceRange(rangeType: string, range: { low: number | null; high: number | null } | null): string {
  if (!range) return '';
  const { low, high } = range;
  if (rangeType === 'fixed_range') return low != null && high != null ? `${low}–${high}` : '';
  if (rangeType === 'open_upper_bound' || rangeType === 'open_lower_bound') return low != null ? `≥ ${low}` : '';
  return '';
}

// Pre-visit prep agent (Roadmap Section 2.6). Fires only while the visit is actually unlocked
// (Section 7.2) — the route enforces grantsDataAccess before ever calling this, and never serves
// a cached brief once that's no longer true. Reads exactly the same flagged-history data the
// doctor console already shows in its own "unlocked data" panel — no broader access than a human
// doctor has at that moment.

const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

interface Facts {
  memberName: string;
  reasonForVisit: string | null;
  abnormal: { display_name: string; category: string; canonical_value: number | null; canonical_unit: string | null; range_text: string }[];
  allergies: string[];
  chronicConditions: string[];
  currentMedications: string[];
}

function factsToPlainText(f: Facts): string {
  const lines = [
    `Patient: ${f.memberName}.`,
    f.reasonForVisit ? `Stated reason for this visit: "${f.reasonForVisit}".` : `No reason for visit was stated.`,
    `Allergies: ${f.allergies.length ? f.allergies.join(', ') : 'none recorded'}.`,
    `Chronic conditions: ${f.chronicConditions.length ? f.chronicConditions.join(', ') : 'none recorded'}.`,
    `Current medications: ${f.currentMedications.length ? f.currentMedications.join(', ') : 'none recorded'}.`,
    `Currently flagged out-of-range results:`,
    ...(f.abnormal.length
      ? f.abnormal.map((a) => `- ${a.display_name} (${a.category}): ${a.canonical_value ?? '—'} ${a.canonical_unit ?? ''} — reference range ${a.range_text}`)
      : ['- none']),
  ];
  return lines.join('\n');
}

const SYSTEM_PROMPT = `You are the CareLoop Pre-visit Prep agent. A doctor's access to a patient's record has just unlocked for a real, currently in-progress visit. You are given the same structured facts already visible elsewhere in the doctor's console (flagged out-of-range results, allergies, conditions, current medications) plus the patient's own stated reason for this visit, if they gave one. You did not derive any of these facts — they were computed deterministically from real data.

Your only job: write a short brief (3-6 sentences, plain prose, no markdown/headers/bullets) that helps the doctor get oriented in the first few seconds of the visit. If a reason for visit was given, lead with whichever flagged results and conditions are actually relevant to it, then briefly note anything else flagged that's unrelated but still worth knowing. If no reason was given, just summarize what's flagged, in order of how out-of-range or clinically attention-worthy it looks from the numbers alone.

Rules, no exceptions:
- Never diagnose, never suggest a treatment or medication, never speculate about what the reason for visit implies medically beyond organizing what's already flagged.
- Do not invent or infer any fact not in the list given — no new allergies, conditions, values, or history.
- If nothing is flagged and no reason was given, say so plainly in one sentence rather than padding.`;

async function phraseBrief(facts: Facts): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) {
    if (facts.abnormal.length === 0 && !facts.reasonForVisit) {
      return `${facts.memberName} has nothing currently flagged out of range and no stated reason for this visit — check the full history panel below for context.`;
    }
    const parts: string[] = [];
    if (facts.reasonForVisit) parts.push(`Visit reason: "${facts.reasonForVisit}".`);
    if (facts.abnormal.length) {
      const items = facts.abnormal.map((a) => `${a.display_name} (${a.canonical_value ?? '—'} ${a.canonical_unit ?? ''}, ref. ${a.range_text})`).join('; ');
      parts.push(`Currently flagged: ${items}.`);
    } else {
      parts.push('Nothing currently flagged out of range.');
    }
    if (facts.allergies.length) parts.push(`Known allergies: ${facts.allergies.join(', ')}.`);
    if (facts.currentMedications.length) parts.push(`Current medications: ${facts.currentMedications.join(', ')}.`);
    return parts.join(' ');
  }

  const resp = await getClient().messages.create({
    model,
    max_tokens: 300,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: factsToPlainText(facts) }],
  });
  const text = resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();
  return text || factsToPlainText(facts);
}

export async function getPrevisitBrief(appointmentId: string): Promise<{ brief: string; generatedAt: string }> {
  const cached = db.prepare('SELECT brief, generated_at FROM previsit_briefs WHERE appointment_id = ?').get(appointmentId) as
    | { brief: string; generated_at: string }
    | undefined;
  if (cached) return { brief: cached.brief, generatedAt: cached.generated_at };

  const appt = db.prepare('SELECT member_id, reason_for_visit FROM appointments WHERE id = ?').get(appointmentId) as
    | { member_id: string; reason_for_visit: string | null }
    | undefined;
  if (!appt) throw new Error('Appointment not found');

  const member = db.prepare('SELECT name FROM members WHERE id = ?').get(appt.member_id) as { name: string };
  const allergies = (db.prepare('SELECT value FROM allergies WHERE member_id = ?').all(appt.member_id) as { value: string }[]).map((r) => r.value);
  const chronicConditions = (db.prepare('SELECT value FROM chronic_conditions WHERE member_id = ?').all(appt.member_id) as { value: string }[]).map((r) => r.value);

  const latestPrescription = db
    .prepare('SELECT id FROM prescriptions WHERE member_id = ? ORDER BY issued_at DESC LIMIT 1')
    .get(appt.member_id) as { id: string } | undefined;
  const currentMedications = latestPrescription
    ? (db.prepare('SELECT medicine_name FROM prescription_line_items WHERE prescription_id = ?').all(latestPrescription.id) as { medicine_name: string }[]).map(
        (r) => r.medicine_name
      )
    : [];

  const { abnormal } = computeOverviewParameters(appt.member_id);
  const facts: Facts = {
    memberName: member.name,
    reasonForVisit: appt.reason_for_visit,
    abnormal: abnormal.map((a) => ({
      display_name: a.display_name,
      category: a.category,
      canonical_value: a.canonical_value,
      canonical_unit: a.canonical_unit,
      range_text: formatReferenceRange(a.range_type, a.resolved_reference_range) || 'not specified',
    })),
    allergies,
    chronicConditions,
    currentMedications,
  };

  const brief = await phraseBrief(facts);
  const generatedAt = now();
  db.prepare(
    `INSERT INTO previsit_briefs (appointment_id, brief, generated_at) VALUES (?, ?, ?)
     ON CONFLICT(appointment_id) DO UPDATE SET brief = excluded.brief, generated_at = excluded.generated_at`
  ).run(appointmentId, brief, generatedAt);

  return { brief, generatedAt };
}
