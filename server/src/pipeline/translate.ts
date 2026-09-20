import Anthropic from '@anthropic-ai/sdk';

// Same client/model setup as chatAssistant.ts's getClient() — deliberately not shared/imported
// from there, since that module's client is scoped to chat and this is a separate concern.
const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

/** Translates a doctor-approved English document into the patient's language. Machine translation
 * of clinical content, so the prompt is strict about the things that must never drift — medicine
 * names, numbers, doses, timings — and never adds or drops content. Callers always keep (and show)
 * the English original alongside it. */
export async function translateFromEnglish(text: string, targetLanguage: string): Promise<string> {
  const resp = await getClient().messages.create({
    model,
    max_tokens: 2048,
    system: `You translate a doctor's after-visit letter to a patient from English into ${targetLanguage}, in simple, warm, everyday language a non-medical reader understands.
Non-negotiable:
- Translate ONLY what is written. Never add, remove, soften, or reorder any medical information, advice, or instruction.
- Keep every medicine name, strength, number, dose, duration, date and time EXACTLY as written (numerals stay as digits; medicine names may be written in ${targetLanguage} script only if that is how they are commonly written, otherwise keep them in Latin letters).
- Keep the same line breaks, headings and bullet structure.
Reply with ONLY the translated letter — no preamble, no notes, no quotation marks.`,
    messages: [{ role: 'user', content: text }],
  });
  return resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();
}

/** Translates spoken/typed text to plain English. No mock fallback (unlike chatAssistant's
 * mockReply) — if there's no API key configured, translation just isn't available; the caller
 * decides what to show for that. */
export async function translateToEnglish(text: string, sourceLanguage: string): Promise<string> {
  const resp = await getClient().messages.create({
    model,
    max_tokens: 400,
    system: `Translate the following ${sourceLanguage} text to natural, plain spoken English, as a member describing a health symptom would say it. Reply with ONLY the translated text — no preamble, no quotation marks, no explanation.`,
    messages: [{ role: 'user', content: text }],
  });
  return resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();
}
