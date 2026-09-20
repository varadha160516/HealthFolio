import Anthropic from '@anthropic-ai/sdk';

const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

// After-visit summary — a plain-language letter to the patient built from the doctor's OWN record
// of this visit (consultation notes, the issued prescription, lab orders, follow-up plan).
//
// Safety design: only ONE short paragraph — what the doctor found — ever passes through a model.
// Everything a patient will act on (medicines with their dose/frequency/duration, the doctor's
// advice, tests ordered, when to come back) is copied programmatically from the structured
// record, never paraphrased, so a hallucinated dose or dropped instruction is impossible by
// construction. The doctor then edits the English draft; only that approved English is translated.

export interface VisitSummarySource {
  memberName: string;
  providerName: string;
  notes: {
    chief_complaint: string | null;
    symptom_duration: string | null;
    symptoms: string[];
    assessment_notes: string | null;
    advice: string[];
  } | null;
  diagnosisText: string | null;
  lineItems: { medicine_name: string; strength: string | null; dosage: string | null; frequency: string | null; duration: string | null; instructions: string | null }[];
  labTests: string[];
  // Only set when the doctor actually acted on a follow-up: a real scheduled appointment (when =
  // its date/time) or a written reason. ClinDesk's follow-up chip defaults to "3 days" and is saved
  // with every notes save, so consultation_notes.follow_up_after alone does NOT mean a follow-up
  // was decided — treating it as one would tell every patient to come back in 3 days.
  followUp: { when: string | null; reason: string | null } | null;
}

const NARRATIVE_PROMPT = `You write the opening paragraph of a doctor's after-visit letter to a patient.
You are given the doctor's own notes from the visit. Write 2-4 short sentences in simple, warm, plain language, addressed to the patient ("you"), saying why they came and what the doctor found or concluded.
Rules, non-negotiable:
- Use ONLY what is in the notes. Never add a diagnosis, cause, prognosis, reassurance, warning sign, or advice that is not there.
- Do not mention medicines, doses, tests or follow-up — those are added separately.
- If the notes give no assessment, just say what they came in for.
Reply with ONLY the paragraph.`;

function narrativeFallback(src: VisitSummarySource): string {
  const parts: string[] = [];
  const complaint = src.notes?.chief_complaint;
  if (complaint) parts.push(`You came in with ${complaint.toLowerCase()}${src.notes?.symptom_duration ? ` for ${src.notes.symptom_duration}` : ''}.`);
  const assessment = src.notes?.assessment_notes || src.diagnosisText;
  if (assessment) parts.push(`Your doctor's assessment: ${assessment}${/[.!?]$/.test(assessment) ? '' : '.'}`);
  return parts.join(' ') || 'Thank you for visiting today. Here is a summary of your visit.';
}

async function narrative(src: VisitSummarySource): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) return narrativeFallback(src);
  const facts = [
    src.notes?.chief_complaint && `Chief complaint: ${src.notes.chief_complaint}`,
    src.notes?.symptom_duration && `Duration: ${src.notes.symptom_duration}`,
    src.notes?.symptoms.length ? `Symptoms: ${src.notes.symptoms.join(', ')}` : null,
    src.notes?.assessment_notes && `Doctor's assessment: ${src.notes.assessment_notes}`,
    src.diagnosisText && `Diagnosis: ${src.diagnosisText}`,
  ]
    .filter(Boolean)
    .join('\n');
  if (!facts) return narrativeFallback(src);
  const resp = await getClient().messages.create({
    model,
    max_tokens: 300,
    system: NARRATIVE_PROMPT,
    messages: [{ role: 'user', content: facts }],
  });
  const text = resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();
  return text || narrativeFallback(src);
}

export async function draftAfterVisitSummary(src: VisitSummarySource): Promise<string> {
  const lines: string[] = [`Dear ${src.memberName},`, '', await narrative(src)];

  if (src.lineItems.length > 0) {
    lines.push('', 'Your medicines:');
    for (const li of src.lineItems) {
      const name = [li.medicine_name, li.strength].filter(Boolean).join(' ');
      const how = [li.dosage, li.frequency, li.duration && `for ${li.duration}`].filter(Boolean).join(', ');
      lines.push(`- ${name}${how ? `: ${how}` : ''}${li.instructions ? ` (${li.instructions})` : ''}`);
    }
  }

  const advice = src.notes?.advice ?? [];
  if (advice.length > 0) {
    lines.push('', 'What to do:');
    for (const a of advice) lines.push(`- ${a}`);
  }

  if (src.labTests.length > 0) {
    lines.push('', 'Tests to get done:');
    for (const t of src.labTests) lines.push(`- ${t}`);
  }

  if (src.followUp) {
    const { when, reason } = src.followUp;
    if (when) lines.push('', `Follow-up: your next visit is on ${when}${reason ? ` (${reason})` : ''}.`);
    else if (reason) lines.push('', `Follow-up: ${reason}.`);
  }

  lines.push('', 'If you have any concerns, please contact the clinic.', '', src.providerName);
  return lines.join('\n');
}
