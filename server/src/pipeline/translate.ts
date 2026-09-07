import Anthropic from '@anthropic-ai/sdk';

// Same client/model setup as chatAssistant.ts's getClient() — deliberately not shared/imported
// from there, since that module's client is scoped to chat and this is a separate concern.
const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
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
