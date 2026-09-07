import Anthropic from '@anthropic-ai/sdk';

// Symptom intake agent (Roadmap Section 2.4) — "the single agent in this document with the most
// direct self-harm/health-anxiety adjacent risk if built carelessly." Two structural decisions
// enforce the guardrail rather than relying on prompt discipline alone:
//   1. Urgent-symptom detection is a deterministic keyword check that runs BEFORE any model call
//      and short-circuits straight to a fixed, non-generated safety message — it never depends on
//      the model correctly recognizing urgency on its own.
//   2. The model's only allowed output shape is a small JSON object (a question, or a finished
//      structured note) — there is no free-text channel for it to editorialize, speculate about a
//      cause, or estimate severity beyond structuring what the member already said.

const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

export interface IntakeTurn {
  role: 'user' | 'assistant';
  content: string;
}

export interface StructuredFields {
  onset: string | null;
  severity: string | null;
  duration: string | null;
  associated_factors: string | null;
}

export type IntakeResult =
  | { kind: 'urgent'; message: string }
  | { kind: 'question'; question: string }
  | { kind: 'done'; fields: StructuredFields; noteToMember: string };

// Deliberately biased toward over-flagging: a false positive here just shows the member a "go see
// a doctor" message a little early, which costs nothing; a false negative on real stroke/fainting/
// breathing language is the actual harm this whole guardrail exists to prevent. Found by testing
// "I feel like I might pass out and my face feels numb on one side" during development — the
// first pass of these patterns missed both "might pass out" (present tense, not "passed out") and
// a bare "face ... numb" without the word "sudden" — so phrasing is matched loosely on purpose,
// not just the textbook clinical wording.
const URGENT_PATTERNS: RegExp[] = [
  /chest (pain|pressure|tightness|discomfort)|tightness in (my |the )?chest/i,
  /(can'?t|cannot|difficulty|trouble)\s+breath|short(ness)? of breath|gasping for air/i,
  /severe bleeding|(can'?t|won'?t|cannot) stop.{0,15}bleed|bleeding (a lot|heavily|profusely|and (won'?t|can'?t) stop)/i,
  /suicid|kill myself|want to die|end my life|self[\s-]?harm|hurt myself/i,
  /unconscious|unresponsive|pass(ing)? out|passed out|faint(ed|ing)?|might pass out|about to pass out|going to pass out|feel(ing)? (like i'?m going to|like i might) (pass out|faint)/i,
  /seizure|convuls/i,
  /stroke|face (is |feels )?(drooping|numb|weak)|drooping (face|mouth)|slurred speech|numb(ness)?.{0,20}(one|left|right) side|(one|left|right) side.{0,20}numb(ness)?|weak(ness)?.{0,20}(one|left|right) side|(one|left|right) side.{0,20}weak(ness)?|can'?t (move|feel) (my )?(arm|leg|face)/i,
  /severe allergic reaction|anaphyla(x|c)|throat.{0,20}clos(e|ed|ing)|swelling of (the |my )?(throat|tongue|lips)/i,
  /poison(ed|ing)?|overdose/i,
  /choking|can'?t swallow/i,
  /severe (abdominal|stomach) pain/i,
  /coughing (up )?blood|vomiting blood/i,
];

export function detectUrgentSignal(text: string): boolean {
  return URGENT_PATTERNS.some((p) => p.test(text));
}

export const URGENT_SAFETY_MESSAGE =
  "What you're describing sounds like it could be urgent. Please contact a doctor or emergency services right now rather than continuing here — this isn't the right tool for anything that urgent. In India, you can call 108 for an ambulance, or go straight to your nearest emergency room.";

const SYSTEM_PROMPT = `You are the CareLoop Symptom Intake agent. Your only job is to help a family member turn a casual description of how they're feeling into a clear, structured, dated note — for their own records and to show a doctor later. Nothing more.

Ask ONE short clarifying question at a time, in plain conversational language, to fill in whatever is still missing from: when it started (onset), how severe it feels in their own words (mild/moderate/severe or similar), how long it's lasted or whether it comes and goes (duration/pattern), and anything that makes it better, worse, or seems related (associated factors). Don't ask about anything they've already told you. Usually 1-3 questions is enough — once you have enough to write a clear note, stop asking.

Respond with ONLY a JSON object, no other text, no markdown fences, in exactly one of these two shapes:
- Still gathering info: {"done": false, "question": "..."}
- Enough info now: {"done": true, "onset": "...", "severity": "...", "duration": "...", "associated_factors": "...", "note_to_member": "..."}

For the "done" shape: leave any field the member never actually addressed as an empty string rather than guessing or inferring it. "note_to_member" is one short warm sentence confirming you've logged it, and gently suggesting they mention it to their doctor if it continues or gets worse.

Rules, no exceptions:
- Never suggest what might be causing the symptom. Never name a possible condition, diagnosis, or illness. Never estimate how serious or likely something is.
- Never recommend a medication, supplement, or specific treatment.
- Only structure what the member actually told you — do not add, infer, or embellish any detail.
- Anything that sounds urgent is intercepted before it ever reaches you, so treat every message you see as non-urgent and just keep gathering the four fields above.
- Keep every question and the closing note to one or two short sentences.`;

function mockFields(history: IntakeTurn[]): { fields: StructuredFields; nextField: keyof StructuredFields | null } {
  // Deterministic fallback with no API key: cycles through the four fields in a fixed order,
  // storing each user answer verbatim against whichever field was just asked about.
  const order: (keyof StructuredFields)[] = ['onset', 'severity', 'duration', 'associated_factors'];
  const fields: StructuredFields = { onset: null, severity: null, duration: null, associated_factors: null };
  const userAnswers = history.filter((t) => t.role === 'user').slice(1); // [0] is the opening description, not an answer to a question
  for (let i = 0; i < userAnswers.length && i < order.length; i++) fields[order[i]] = userAnswers[i].content.trim();
  const nextField = order.find((f) => fields[f] === null) ?? null;
  return { fields, nextField };
}

const MOCK_QUESTIONS: Record<keyof StructuredFields, string> = {
  onset: 'When did this start?',
  severity: 'How would you describe it — mild, moderate, or severe?',
  duration: 'Is it constant, or does it come and go?',
  associated_factors: 'Does anything seem to make it better or worse?',
};

export async function continueIntake(history: IntakeTurn[]): Promise<IntakeResult> {
  const lastUserMessage = [...history].reverse().find((t) => t.role === 'user');
  if (lastUserMessage && detectUrgentSignal(lastUserMessage.content)) {
    return { kind: 'urgent', message: URGENT_SAFETY_MESSAGE };
  }

  if (!process.env.ANTHROPIC_API_KEY) {
    const { fields, nextField } = mockFields(history);
    if (nextField) return { kind: 'question', question: MOCK_QUESTIONS[nextField] };
    return { kind: 'done', fields, noteToMember: "Thanks — I've logged this. Worth mentioning to your doctor if it continues or gets worse." };
  }

  const resp = await getClient().messages.create({
    model,
    max_tokens: 300,
    system: SYSTEM_PROMPT,
    messages: history.map((t) => ({ role: t.role, content: t.content })),
  });
  const text = resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();

  try {
    const parsed = JSON.parse(text);
    if (parsed.done === true) {
      return {
        kind: 'done',
        fields: {
          onset: parsed.onset || null,
          severity: parsed.severity || null,
          duration: parsed.duration || null,
          associated_factors: parsed.associated_factors || null,
        },
        noteToMember: parsed.note_to_member || "Thanks — I've logged this. Worth mentioning to your doctor if it continues or gets worse.",
      };
    }
    if (typeof parsed.question === 'string' && parsed.question.trim()) {
      return { kind: 'question', question: parsed.question.trim() };
    }
  } catch {
    // Model didn't return valid JSON — fall through to the generic retry question below rather
    // than surfacing raw, unvalidated model text (which could contain anything, including exactly
    // the kind of speculative language this agent must never produce).
  }
  return { kind: 'question', question: 'Could you tell me a bit more about that?' };
}
