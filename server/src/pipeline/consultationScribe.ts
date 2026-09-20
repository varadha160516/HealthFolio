import Anthropic from '@anthropic-ai/sdk';

const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

// Ambient scribe — structures a raw speech-to-text transcript of a consultation into the same
// shape consultation_notes already stores (see doctorApp.ts's PUT /appointments/:id/consultation-
// notes). Same discipline as every other extraction pipeline in this app (medicationReconciliation.ts,
// extractClaude.ts): this ORGANIZES what was actually said, never adds a clinical fact, finding, or
// recommendation that wasn't actually spoken. The doctor reviews and edits every field before
// anything is saved — this endpoint never writes to the database itself.

export interface ConsultationNoteExtraction {
  chief_complaint: string | null;
  symptom_duration: string | null;
  symptoms: string[];
  examination: {
    general: { condition: string | null; consciousness: string | null; hydration: string | null };
    system: { respiratory: string[]; cardiovascular: string | null; abdomen: string | null; cns: string | null };
  };
  assessment_notes: string | null;
  advice: string[];
  follow_up_after: '3_days' | '1_week' | '1_month' | 'as_needed' | null;
  follow_up_reason: string | null;
}

const EMPTY_RESULT: ConsultationNoteExtraction = {
  chief_complaint: null,
  symptom_duration: null,
  symptoms: [],
  examination: { general: { condition: null, consciousness: null, hydration: null }, system: { respiratory: [], cardiovascular: null, abdomen: null, cns: null } },
  assessment_notes: null,
  advice: [],
  follow_up_after: null,
  follow_up_reason: null,
};

const SYSTEM_PROMPT = `You are the structuring stage of an ambient consultation scribe. You are given a raw speech-to-text
transcript of a doctor talking through (or dictating notes about) a patient consultation — it may be messy, conversational,
or include the doctor thinking aloud. Your ONLY job is to organize what was ACTUALLY SAID into the fields below. Never add
a clinical fact, symptom, finding, or recommendation that wasn't actually mentioned in the transcript — leave a field
null/empty rather than guessing. This is dictation support, not a diagnostic tool: you are not deciding what's true about
the patient, only transcribing/organizing what the doctor already said.

Rules:
- chief_complaint: the main presenting complaint, in the doctor's own words if possible.
- symptom_duration: how long symptoms have lasted, if stated (e.g. "3 days", "since last week").
- symptoms: short symptom names actually mentioned (e.g. "Headache", "Cough"), not full sentences.
- examination.general.condition/consciousness/hydration: only fill if the doctor stated something about the patient's
  general condition, consciousness/alertness, or hydration status. Leave null otherwise — never default to "normal".
- examination.system.respiratory: short findings mentioned for the chest/lungs (e.g. "Wheezing", "Clear lungs").
- examination.system.cardiovascular/abdomen/cns: a short phrase for what was said about each system, or null if not
  examined or mentioned.
- assessment_notes: the doctor's clinical assessment/impression, if stated as such (distinct from just repeating symptoms).
- advice: short, distinct pieces of advice/instructions actually given to the patient (e.g. "Rest", "Increase fluids").
- follow_up_after: exactly one of "3_days", "1_week", "1_month", "as_needed" if a follow-up timeframe was mentioned,
  matched to the closest of these four — otherwise null. Never invent a follow-up if none was discussed.
- follow_up_reason: a short reason for follow-up, if stated.

Return STRICT JSON only, no prose before or after, matching this shape exactly:
{
  "chief_complaint": string | null,
  "symptom_duration": string | null,
  "symptoms": string[],
  "examination": {
    "general": { "condition": string | null, "consciousness": string | null, "hydration": string | null },
    "system": { "respiratory": string[], "cardiovascular": string | null, "abdomen": string | null, "cns": string | null }
  },
  "assessment_notes": string | null,
  "advice": string[],
  "follow_up_after": "3_days" | "1_week" | "1_month" | "as_needed" | null,
  "follow_up_reason": string | null
}`;

function parseResult(text: string): ConsultationNoteExtraction {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const jsonText = fenced ? fenced[1] : text.match(/\{[\s\S]*\}/)?.[0];
  if (!jsonText) throw new Error(`Scribe model returned no JSON. Raw response:\n${text.slice(0, 1000)}`);
  const parsed = JSON.parse(jsonText);
  return {
    chief_complaint: parsed.chief_complaint ?? null,
    symptom_duration: parsed.symptom_duration ?? null,
    symptoms: Array.isArray(parsed.symptoms) ? parsed.symptoms : [],
    examination: {
      general: {
        condition: parsed.examination?.general?.condition ?? null,
        consciousness: parsed.examination?.general?.consciousness ?? null,
        hydration: parsed.examination?.general?.hydration ?? null,
      },
      system: {
        respiratory: Array.isArray(parsed.examination?.system?.respiratory) ? parsed.examination.system.respiratory : [],
        cardiovascular: parsed.examination?.system?.cardiovascular ?? null,
        abdomen: parsed.examination?.system?.abdomen ?? null,
        cns: parsed.examination?.system?.cns ?? null,
      },
    },
    assessment_notes: parsed.assessment_notes ?? null,
    advice: Array.isArray(parsed.advice) ? parsed.advice : [],
    follow_up_after: ['3_days', '1_week', '1_month', 'as_needed'].includes(parsed.follow_up_after) ? parsed.follow_up_after : null,
    follow_up_reason: parsed.follow_up_reason ?? null,
  };
}

// The transcript can be in any language the on-device recognizer was set to (see
// ambient_scribe_card.dart) — but consultation_notes, the safety net, pre-visit briefs and every
// other consumer of this record are English, so the structured output always is too.
function languageInstruction(language: string): string {
  if (language === 'English') return '';
  return `\n\nThe transcript is in ${language} (it may mix in English medical terms and drug names). Understand it in ${language}, but write EVERY extracted field in English — translate faithfully, keep drug names and numbers exactly as spoken, and do not add anything that wasn't said.`;
}

export async function structureConsultationTranscript(transcript: string, language: string = 'English'): Promise<ConsultationNoteExtraction> {
  if (!transcript.trim()) return EMPTY_RESULT;
  if (!process.env.ANTHROPIC_API_KEY) {
    // Dev/demo fallback with no live API key — hands the raw transcript back as the chief
    // complaint rather than fabricating structured findings that were never actually said.
    return { ...EMPTY_RESULT, chief_complaint: transcript.trim().slice(0, 200) };
  }

  const resp = await getClient().messages.create({
    model,
    max_tokens: 1024,
    system: SYSTEM_PROMPT + languageInstruction(language),
    messages: [{ role: 'user', content: `TRANSCRIPT:\n${transcript}` }],
  });
  const text = resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map((b) => b.text)
    .join('\n');
  return parseResult(text);
}
