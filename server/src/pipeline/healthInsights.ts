import crypto from 'node:crypto';
import Anthropic from '@anthropic-ai/sdk';
import { db, now } from '../db/db.js';

const model = process.env.CARELOOP_CHAT_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

// Same set Trends/YoY use (parameters.ts VISIBLE_STATUSES) — Overview must never draw a
// conclusion from a different slice of the data than what the member actually sees.
const VISIBLE_STATUSES = "('auto_accepted','confirmed','corrected','pending_review')";

// Only range types with real numeric semantics get a trend claim — an interpretive_rule or
// qualitative "value" isn't something a direction/streak claim is safe to make about (same
// boundary Section 4.6 already enforces for automated flagging).
const NUMERIC_RANGE_TYPES = new Set(['fixed_range', 'open_upper_bound', 'open_lower_bound']);

interface Point {
  test_date: string;
  canonical_value: number | null;
  in_range_flag: string | null;
}

interface Fact {
  display_name: string;
  kind: 'newly_out_of_range' | 'back_in_range' | 'trend';
  direction?: 'up' | 'down';
  streak?: number;
  priority: number; // lower = surfaced first
}

const DEFAULT_SUMMARY = "Not enough history yet to spot trends — this will fill in as more results come in over future checkups.";

function buildSignature(rows: { canonical_parameter_id: string; test_date: string; canonical_value: number | null; in_range_flag: string | null }[]): string {
  const normalized = rows
    .map((r) => `${r.canonical_parameter_id}|${r.test_date}|${r.canonical_value}|${r.in_range_flag}`)
    .sort()
    .join('\n');
  return crypto.createHash('sha256').update(normalized).digest('hex');
}

/** Deterministic fact extraction — the model never judges what "changed"; it only phrases facts
 * this code already computed from real data. Keeps the guardrail (describe, don't diagnose)
 * enforced structurally rather than relying on prompt discipline alone. */
function extractFacts(byParam: Map<string, { display_name: string; range_type: string; points: Point[] }>): Fact[] {
  const facts: Fact[] = [];

  for (const { display_name, range_type, points } of byParam.values()) {
    if (!NUMERIC_RANGE_TYPES.has(range_type)) continue;
    const numericPoints = points.filter((p) => p.canonical_value != null);
    if (numericPoints.length < 2) continue;

    const latest = numericPoints[numericPoints.length - 1];
    const previous = numericPoints[numericPoints.length - 2];

    if (latest.in_range_flag === 'out_of_range' && previous.in_range_flag === 'in_range') {
      facts.push({ display_name, kind: 'newly_out_of_range', priority: 0 });
    } else if (latest.in_range_flag === 'in_range' && previous.in_range_flag === 'out_of_range') {
      facts.push({ display_name, kind: 'back_in_range', priority: 1 });
    }

    // A streak of 3+ consecutive points all moving the same direction — found by taking the
    // pairwise differences and counting how many trailing diffs share the sign of the most
    // recent one, stopping at the first sign change or a flat (zero) step.
    const values = numericPoints.map((p) => p.canonical_value!);
    const diffs: number[] = [];
    for (let i = 1; i < values.length; i++) diffs.push(values[i] - values[i - 1]);
    const lastDiff = diffs[diffs.length - 1];
    if (lastDiff !== 0) {
      const risingRun = lastDiff > 0;
      let runLength = 1;
      for (let i = diffs.length - 2; i >= 0; i--) {
        if (diffs[i] === 0 || diffs[i] > 0 !== risingRun) break;
        runLength++;
      }
      const streak = runLength + 1; // number of points spanning that run of diffs
      if (streak >= 3) facts.push({ display_name, kind: 'trend', direction: risingRun ? 'up' : 'down', streak, priority: 2 });
    }
  }

  facts.sort((a, b) => a.priority - b.priority);
  return facts.slice(0, 5); // keep the summary short — top 5 most notable facts only
}

function factToPlainText(f: Fact): string {
  switch (f.kind) {
    case 'newly_out_of_range':
      return `${f.display_name} was in range last time and is now flagged out of range.`;
    case 'back_in_range':
      return `${f.display_name} was flagged out of range before and is now back in range.`;
    case 'trend':
      return `${f.display_name} has been trending ${f.direction === 'up' ? 'up' : 'down'} for the last ${f.streak} checkups in a row.`;
  }
}

const SYSTEM_PROMPT = `You are the CareLoop Health Insights agent. You are given a short list of factual, pre-computed observations about one family member's lab-result history — you did not derive these facts yourself, they were computed deterministically from their real data. Your only job is to phrase them into a short, warm, plain-language summary (2-4 sentences) for the family to read at a glance on the Overview tab.

Rules, no exceptions:
- Describe what changed. Never diagnose, never suggest what caused it, never recommend a treatment, medication, or supplement.
- If any fact describes something newly out of range, end by suggesting the family discuss it with their doctor — do not say what to do about it beyond that.
- If all facts are positive (back in range, or a trend moving in a healthy direction), keep the tone encouraging but factual — don't editorialize beyond what the facts say.
- Do not invent or infer anything beyond the facts given. Do not mention parameters that aren't in the list.
- No markdown, no headers, no bullet points — plain sentences only.`;

async function phraseSummary(facts: Fact[]): Promise<string> {
  const factLines = facts.map(factToPlainText).join('\n');
  if (!process.env.ANTHROPIC_API_KEY) {
    // Mock mode — no LLM call, just join the facts with a plain connective and the same
    // doctor-referral rule the live prompt enforces.
    const hasNegative = facts.some((f) => f.kind === 'newly_out_of_range');
    const sentence = facts.length === 1 ? factToPlainText(facts[0]) : `${factToPlainText(facts[0])} Also, ${facts.slice(1).map((f) => factToPlainText(f).charAt(0).toLowerCase() + factToPlainText(f).slice(1)).join(' ')}`;
    return hasNegative ? `${sentence} Worth mentioning to your doctor at the next visit.` : sentence;
  }

  const resp = await getClient().messages.create({
    model,
    max_tokens: 250,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: `Observations:\n${factLines}` }],
  });
  const text = resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map((b) => b.text)
    .join('\n')
    .trim();
  return text || DEFAULT_SUMMARY;
}

export async function getHealthInsight(memberId: string): Promise<{ summary: string; generatedAt: string; hasNotableChange: boolean }> {
  const rows = db
    .prepare(
      `SELECT ep.canonical_parameter_id, cp.display_name, cp.range_type, ep.canonical_value, ep.test_date, ep.in_range_flag
       FROM extracted_parameters ep
       JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
       WHERE ep.member_id = ? AND ep.review_status IN ${VISIBLE_STATUSES}
       ORDER BY cp.display_name, ep.test_date ASC`
    )
    .all(memberId) as { canonical_parameter_id: string; display_name: string; range_type: string; canonical_value: number | null; test_date: string; in_range_flag: string | null }[];

  const signature = buildSignature(rows);
  const cached = db.prepare('SELECT summary, data_signature, generated_at FROM health_insights WHERE member_id = ?').get(memberId) as
    | { summary: string; data_signature: string; generated_at: string }
    | undefined;
  if (cached && cached.data_signature === signature) {
    return { summary: cached.summary, generatedAt: cached.generated_at, hasNotableChange: cached.summary !== DEFAULT_SUMMARY };
  }

  const byParam = new Map<string, { display_name: string; range_type: string; points: Point[] }>();
  for (const r of rows) {
    if (!byParam.has(r.canonical_parameter_id)) byParam.set(r.canonical_parameter_id, { display_name: r.display_name, range_type: r.range_type, points: [] });
    byParam.get(r.canonical_parameter_id)!.points.push({ test_date: r.test_date, canonical_value: r.canonical_value, in_range_flag: r.in_range_flag });
  }

  const facts = extractFacts(byParam);
  const summary = facts.length === 0 ? DEFAULT_SUMMARY : await phraseSummary(facts);
  const generatedAt = now();

  db.prepare(
    `INSERT INTO health_insights (member_id, summary, data_signature, generated_at) VALUES (?, ?, ?, ?)
     ON CONFLICT(member_id) DO UPDATE SET summary = excluded.summary, data_signature = excluded.data_signature, generated_at = excluded.generated_at`
  ).run(memberId, summary, signature, generatedAt);

  return { summary, generatedAt, hasNotableChange: facts.length > 0 };
}
