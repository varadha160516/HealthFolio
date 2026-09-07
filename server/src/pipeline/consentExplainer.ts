import Anthropic from '@anthropic-ai/sdk';
import { db, now } from '../db/db.js';

const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

const SCOPE_LABELS: Record<string, string> = {
  summary_card: 'a summary card (headline vitals and flags only, not the full record)',
  full_history: 'your full health history (every document and result on file)',
};

interface ConsentFacts {
  memberName: string;
  providerName: string;
  specialty: string | null;
  clinicName: string | null;
  appointmentDate: string;
  scope: string;
  method: string;
}

function factsToPlainText(f: ConsentFacts): string {
  const scopeText = SCOPE_LABELS[f.scope] ?? f.scope;
  const clinicText = f.clinicName ? ` at ${f.clinicName}` : '';
  const specialtyText = f.specialty ? ` (${f.specialty})` : '';
  return `Doctor: Dr. ${f.providerName}${specialtyText}${clinicText}. Visit: today's appointment, ${f.appointmentDate}. Requesting: ${scopeText}. Delivery method: ${f.method}.`;
}

const SYSTEM_PROMPT = `You are the CareLoop Consent Explainer agent. Before a family member decides whether to approve or deny a doctor's real-time request to view their health record, you explain in plain language exactly what is being asked — nothing more.

You are given structured facts about one request — you did not derive these, they come directly from the request record. Write 2-4 short plain sentences covering: which doctor is asking, for which visit, and what scope of access (a summary card, or the full history). If the delivery method is "otp", add one short sentence noting that reading a numeric code out to someone has the same effect as tapping Approve, so it should only be shared with someone they trust in that moment.

Rules, no exceptions:
- Explain, never persuade. Do not use words like "safe", "recommended", "you should approve", or any language that nudges toward Approve.
- Do not mention Deny as a lesser or unusual choice — if you reference it at all, present it with the exact same neutral weight as Approve.
- Do not invent any detail not in the facts given (no clinical guesses, no assumptions about why the doctor wants access).
- No markdown, no headers, no bullet points — plain sentences only.`;

async function phraseExplanation(facts: ConsentFacts): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) {
    const scopeText = SCOPE_LABELS[facts.scope] ?? facts.scope;
    const specialtyText = facts.specialty ? `, ${facts.specialty}` : '';
    const clinicText = facts.clinicName ? ` at ${facts.clinicName}` : '';
    let sentence = `Dr. ${facts.providerName}${specialtyText}${clinicText} is asking to view ${scopeText} for today's appointment (${facts.appointmentDate}).`;
    if (facts.method === 'otp') {
      sentence += ' This request was sent as a one-time code — reading that code out to someone has the same effect as tapping Approve, so only share it with someone you trust in the moment.';
    }
    sentence += ' You can choose Approve or Deny — both are recorded either way.';
    return sentence;
  }

  const resp = await getClient().messages.create({
    model,
    max_tokens: 220,
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

export async function getConsentExplanation(appointmentId: string): Promise<{ explanation: string; generatedAt: string } | null> {
  const appt = db
    .prepare('SELECT id, member_id, provider_id, datetime, status, consent_grant_id FROM appointments WHERE id = ?')
    .get(appointmentId) as { id: string; member_id: string; provider_id: string; datetime: string; status: string; consent_grant_id: string | null } | undefined;
  if (!appt || appt.status !== 'consent_requested' || !appt.consent_grant_id) return null;

  const grant = db.prepare('SELECT method, scope FROM consent_grants WHERE id = ?').get(appt.consent_grant_id) as
    | { method: string | null; scope: string | null }
    | undefined;
  if (!grant) return null;

  const cached = db.prepare('SELECT explanation, generated_at FROM consent_explanations WHERE consent_grant_id = ?').get(appt.consent_grant_id) as
    | { explanation: string; generated_at: string }
    | undefined;
  if (cached) return { explanation: cached.explanation, generatedAt: cached.generated_at };

  const member = db.prepare('SELECT name FROM members WHERE id = ?').get(appt.member_id) as { name: string };
  const provider = db.prepare('SELECT name, specialty, clinic_id FROM providers WHERE id = ?').get(appt.provider_id) as {
    name: string;
    specialty: string | null;
    clinic_id: string | null;
  };
  const clinic = provider.clinic_id ? (db.prepare('SELECT name FROM clinics WHERE id = ?').get(provider.clinic_id) as { name: string } | undefined) : undefined;

  const facts: ConsentFacts = {
    memberName: member.name,
    providerName: provider.name,
    specialty: provider.specialty,
    clinicName: clinic?.name ?? null,
    appointmentDate: new Date(appt.datetime).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' }),
    scope: grant.scope || 'full_history',
    method: grant.method || 'in_app',
  };

  const explanation = await phraseExplanation(facts);
  const generatedAt = now();
  db.prepare(
    `INSERT INTO consent_explanations (consent_grant_id, explanation, generated_at) VALUES (?, ?, ?)
     ON CONFLICT(consent_grant_id) DO UPDATE SET explanation = excluded.explanation, generated_at = excluded.generated_at`
  ).run(appt.consent_grant_id, explanation, generatedAt);

  return { explanation, generatedAt };
}
