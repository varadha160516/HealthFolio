import Anthropic from '@anthropic-ai/sdk';
import { db } from '../db/db.js';
import { computeSummaryCard } from '../summary.js';

const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

export interface ChatTurn {
  role: 'user' | 'assistant';
  content: string;
}

const SYSTEM_PROMPT = `You are the CareLoop Health Assistant, a feature built into the CareLoop family health-records app. You are chatting with a family member (or the family coordinator, asking on a dependent's behalf) about ONE specific person's health record, which is provided to you below as CURRENT HEALTH RECORD. Ground every answer in that record — it is the member's real, private medical data pulled from their own uploaded lab reports, prescriptions and consultations.

How to answer:
- If the record has the information needed (a lab value, a diagnosis, a medication, a reference range), answer directly and specifically, citing the actual value/date from the record.
- If something isn't in the record, say plainly that you don't see it in their records yet, and suggest they upload the relevant report or ask their doctor — never invent a value.
- When a lab value is flagged out of range, briefly explain in plain language what that parameter measures and what "out of range" means for it, then offer 2-4 practical, general, home-level suggestions: a food/diet adjustment, a simple exercise or activity, and any relevant lifestyle habit (sleep, hydration, sun exposure, stress, etc. as appropriate). Keep suggestions realistic and low-effort (e.g. "a brisk 20-minute walk after meals", "more leafy greens and lentils", "15-20 minutes of midday sun a few times a week"). These are general wellness tips, not a prescription.
- Never suggest a specific medication, dosage, or supplement amount, and never contradict or second-guess what a doctor has already prescribed for them — if they're already on medication for something, say the food/lifestyle tips are a complement to that treatment, not a replacement.
- If a value is severely abnormal, or the question describes symptoms that could be urgent (chest pain, severe breathlessness, fainting, very high fever, suicidal thoughts, etc.), say clearly that they should contact a doctor or emergency services promptly, before anything else.
- Keep a warm, calm, plain-spoken tone — this is a family talking about their health, not a clinician's report.
- Respond in plain conversational sentences and short paragraphs only. Do not use markdown formatting, headers, bullet/asterisk symbols, or numbered lists — your reply may be read aloud by text-to-speech, so it must sound natural when spoken.
- Keep replies reasonably short (roughly 3-6 sentences) unless the question genuinely needs more.
- You are not a doctor and cannot diagnose conditions or replace medical care; say so naturally if the person seems to be asking for a diagnosis or treatment decision, and redirect them to their doctor.`;

function fmtValue(v: { canonical_value: number | null; canonical_unit: string | null; value_raw: string }): string {
  if (v.canonical_value != null && v.canonical_unit) return `${v.canonical_value} ${v.canonical_unit}`;
  return v.value_raw;
}

function fmtRange(r: { low: number | null; high: number | null; text?: string } | null): string {
  if (!r) return 'no reference range on file';
  if (r.text) return r.text;
  if (r.low != null && r.high != null) return `${r.low}-${r.high}`;
  if (r.low != null) return `above ${r.low}`;
  if (r.high != null) return `below ${r.high}`;
  return 'no reference range on file';
}

/** Assembles the member's real record into a compact, model-readable text block. */
function buildContextBlock(memberId: string): string {
  const member = db.prepare('SELECT name, dob, sex, blood_group FROM members WHERE id = ?').get(memberId) as
    | { name: string; dob: string | null; sex: string | null; blood_group: string | null }
    | undefined;
  const summary = computeSummaryCard(memberId);
  const recentDocs = db
    .prepare(
      `SELECT document_type, test_date, source_lab_name, upload_date FROM documents
       WHERE member_id = ? AND status = 'parsed' ORDER BY upload_date DESC LIMIT 8`
    )
    .all(memberId) as { document_type: string; test_date: string | null; source_lab_name: string | null; upload_date: string }[];
  const recentPrescriptions = db
    .prepare(`SELECT issued_at, diagnosis_text, notes FROM prescriptions WHERE member_id = ? ORDER BY issued_at DESC LIMIT 5`)
    .all(memberId) as { issued_at: string; diagnosis_text: string | null; notes: string | null }[];

  const lines: string[] = [];
  lines.push('CURRENT HEALTH RECORD');
  lines.push(`Name: ${member?.name ?? 'Unknown'}${member?.dob ? `, DOB ${member.dob}` : ''}${member?.sex ? `, ${member.sex}` : ''}${member?.blood_group ? `, blood group ${member.blood_group}` : ''}`);

  if (summary.allergies.length) lines.push(`Known allergies: ${(summary.allergies as any[]).map((a) => a.value).join(', ')}`);
  if (summary.chronicConditions.length) lines.push(`Chronic conditions: ${(summary.chronicConditions as any[]).map((c) => c.value).join(', ')}`);

  if (summary.currentMedications.length) {
    lines.push('Current medications (from most recent prescription):');
    for (const m of summary.currentMedications as any[]) {
      lines.push(`- ${m.medicine_name}${m.strength ? ` ${m.strength}` : ''}${m.dosage ? `, ${m.dosage}` : ''}${m.frequency ? `, ${m.frequency}` : ''}${m.duration ? `, for ${m.duration}` : ''}`);
    }
  }

  const { abnormal, newlyAdded, existing } = summary.parameters;
  if (abnormal.length) {
    lines.push('Out-of-range results (latest reading per parameter):');
    for (const p of abnormal) {
      lines.push(`- ${p.display_name} (${p.category}): ${fmtValue(p)} on ${p.test_date}, reference range ${fmtRange(p.resolved_reference_range)}`);
    }
  } else {
    lines.push('No parameters are currently flagged out of range.');
  }
  if (newlyAdded.length) {
    lines.push('Other recently added results (in range):');
    for (const p of newlyAdded.slice(0, 10)) lines.push(`- ${p.display_name}: ${fmtValue(p)} on ${p.test_date}`);
  }
  if (existing.length) {
    lines.push(`Also on file (in range, ${existing.length} parameters): ${existing.slice(0, 15).map((p) => p.display_name).join(', ')}${existing.length > 15 ? ', ...' : ''}`);
  }

  if (recentPrescriptions.length) {
    lines.push('Recent consultations/diagnoses:');
    for (const p of recentPrescriptions) {
      if (p.diagnosis_text || p.notes) lines.push(`- ${p.issued_at}: ${p.diagnosis_text ?? ''}${p.notes ? ` (${p.notes})` : ''}`);
    }
  }

  if (recentDocs.length) {
    lines.push('Recently uploaded documents:');
    for (const d of recentDocs) lines.push(`- ${d.document_type.replace(/_/g, ' ')}${d.source_lab_name ? ` from ${d.source_lab_name}` : ''}${d.test_date ? `, dated ${d.test_date}` : ''}`);
  }

  return lines.join('\n');
}

/** Small keyword-matched tip table so chat still works end-to-end without a live API key. */
const MOCK_TIPS: { match: RegExp; tip: string }[] = [
  { match: /gluc|sugar|hba1c|diabet/i, tip: 'cutting back on refined sugar and white-flour foods, and taking a brisk 15-20 minute walk after meals, which both help blood sugar' },
  { match: /vitamin d/i, tip: 'getting 15-20 minutes of midday sun a few times a week and eating more eggs, fatty fish, or fortified milk' },
  { match: /cholesterol|ldl|triglyceride/i, tip: 'adding more fiber like oats and legumes, cutting down on fried food, and getting regular brisk walks or cycling in' },
  { match: /hemoglobin|iron|ferritin/i, tip: 'more iron-rich foods like spinach, lentils, and jaggery, paired with something vitamin-C rich to help absorption' },
  { match: /pressure|bp\b/i, tip: 'reducing added salt, walking regularly, and prioritizing good sleep, all of which help manage blood pressure' },
  { match: /vitamin b12/i, tip: 'more dairy, eggs, and fortified cereals in your diet' },
  { match: /tsh|thyroid/i, tip: 'keeping up gentle regular activity — thyroid levels usually need medical management alongside lifestyle habits, so do loop in your doctor' },
  { match: /bmi|weight/i, tip: 'small portion adjustments and a daily 30-minute walk, which add up over time' },
];

function mockReply(memberId: string, question: string): string {
  const { abnormal } = computeSummaryCard(memberId).parameters;
  if (!abnormal.length) {
    return "I don't see anything flagged out of range in the records I have right now. If you're asking about something specific, try uploading the report it's from, or ask your doctor directly. (This is a demo response — connect a live AI key to get fully tailored answers.)";
  }
  const top = abnormal[0];
  const tipEntry = MOCK_TIPS.find((t) => t.match.test(top.display_name));
  const tip = tipEntry ? tipEntry.tip : 'keeping up a balanced diet, regular light activity, and good sleep and hydration';
  return `Your most recent ${top.display_name} reading was ${fmtValue(top)} on ${top.test_date}, which is outside the reference range of ${fmtRange(top.resolved_reference_range)}. Some general things that can help are ${tip}. This is general wellness guidance, not a diagnosis or a prescription — please check with your doctor, especially if anything feels urgent. (This is a demo response — connect a live AI key to get fully tailored answers.)`;
}

export async function answerChatQuestion(memberId: string, history: ChatTurn[], question: string): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) return mockReply(memberId, question);

  const context = buildContextBlock(memberId);
  const messages = [...history.slice(-16).map((m) => ({ role: m.role, content: m.content })), { role: 'user' as const, content: question }];

  const resp = await getClient().messages.create({
    model,
    max_tokens: 700,
    system: `${SYSTEM_PROMPT}\n\n${context}`,
    messages,
  });

  const text = resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();
  return text || "I couldn't come up with a response there — could you try asking again?";
}
