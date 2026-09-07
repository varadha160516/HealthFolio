import { CanonicalParameterRow } from '../dictionary/loader.js';
import { normalizeLabel, tokenOverlapScore, trigramSimilarity } from './normalize.js';
import { MatchResult } from './types.js';
import Anthropic from '@anthropic-ai/sdk';

const anthropicKey = process.env.ANTHROPIC_API_KEY;

/**
 * Three-tier canonical matching (Section 4.4). Stops at the first tier that produces
 * a confident result. Tier 2 and Tier 3 matches are ALWAYS routed to human review by
 * the caller regardless of the numeric score returned here — that's a deliberate
 * clinical-safety rule, not something this function decides.
 */
export async function matchLabel(rawLabel: string, dictionary: CanonicalParameterRow[]): Promise<MatchResult> {
  const normalized = normalizeLabel(rawLabel);
  if (!normalized) return { canonical_parameter_id: null, match_tier: null, match_confidence: 0 };

  // Tier 1 — exact alias match.
  for (const param of dictionary) {
    const aliases: string[] = JSON.parse(param.aliases_json);
    for (const alias of aliases) {
      if (normalizeLabel(alias) === normalized) {
        return { canonical_parameter_id: param.canonical_parameter_id, match_tier: 1, match_confidence: 0.96 };
      }
    }
  }

  // Tier 2 — substring containment either direction, disambiguated by weighted token overlap
  // so shared boilerplate words ("absolute", "count") don't cause a false match between
  // genuinely different parameters (e.g. Absolute Neutrophil Count vs Absolute Basophil Count).
  const tier2Candidates: { param: CanonicalParameterRow; alias: string; overlap: number }[] = [];
  for (const param of dictionary) {
    const aliases: string[] = JSON.parse(param.aliases_json);
    for (const alias of aliases) {
      const normAlias = normalizeLabel(alias);
      if (normAlias.length < 3) continue;
      if (normalized.includes(normAlias) || normAlias.includes(normalized)) {
        tier2Candidates.push({ param, alias, overlap: tokenOverlapScore(rawLabel, alias) });
      }
    }
  }
  if (tier2Candidates.length > 0) {
    tier2Candidates.sort((a, b) => b.overlap - a.overlap);
    const best = tier2Candidates[0];
    // If the top two candidates are equally weighted, the containment match is ambiguous —
    // still return the best guess (tier 2 always goes to review anyway) but keep confidence modest.
    const confidence = 0.7 + Math.min(best.overlap, 1) * 0.05; // 0.70-0.75 band per spec
    return { canonical_parameter_id: best.param.canonical_parameter_id, match_tier: 2, match_confidence: confidence };
  }

  // Tier 3 — semantic match, no shared substring. Prefer a real LLM judgment when a key is
  // configured; otherwise fall back to a local trigram-similarity heuristic.
  const tier3 = anthropicKey ? await semanticMatchViaClaude(rawLabel, dictionary) : semanticMatchLocal(rawLabel, dictionary);
  if (tier3) return { ...tier3, match_tier: 3 };

  return { canonical_parameter_id: null, match_tier: null, match_confidence: 0 };
}

function semanticMatchLocal(
  rawLabel: string,
  dictionary: CanonicalParameterRow[]
): { canonical_parameter_id: string; match_confidence: number } | null {
  let best: { id: string; score: number; overlap: number } | null = null;
  for (const param of dictionary) {
    const aliases: string[] = JSON.parse(param.aliases_json);
    const candidates = [param.display_name, ...aliases];
    for (const c of candidates) {
      const score = trigramSimilarity(rawLabel, c);
      const overlap = tokenOverlapScore(rawLabel, c);
      if (!best || score > best.score) best = { id: param.canonical_parameter_id, score, overlap };
    }
  }
  // Deliberately conservative: character-trigram overlap alone produces false positives on
  // partial word fragments (e.g. "NLR (Neutrophil-Lymphocyte Ratio)" sharing grams with
  // "Neutrophils" despite being a different, uncatalogued index). Require either strong overall
  // similarity or a real shared distinguishing word, so genuinely novel labels still fall through
  // to the tier-4 new-candidate path instead of being guessed into an unrelated parameter.
  if (!best) return null;
  if (best.score < 0.4 && !(best.score >= 0.25 && best.overlap >= 0.3)) return null;
  return { canonical_parameter_id: best.id, match_confidence: Math.min(0.6, 0.3 + best.score) };
}

let anthropicClient: Anthropic | null = null;
function getClient(): Anthropic {
  if (!anthropicClient) anthropicClient = new Anthropic({ apiKey: anthropicKey });
  return anthropicClient;
}

async function semanticMatchViaClaude(
  rawLabel: string,
  dictionary: CanonicalParameterRow[]
): Promise<{ canonical_parameter_id: string; match_confidence: number } | null> {
  const catalogue = dictionary.map((p) => ({
    id: p.canonical_parameter_id,
    name: p.display_name,
    category: p.category,
  }));
  const model = process.env.CARELOOP_MATCH_MODEL || 'claude-sonnet-5';
  try {
    const resp = await getClient().messages.create({
      model,
      max_tokens: 300,
      system:
        'You are a clinical lab terminology matcher. Given a label extracted from a lab report and a catalogue of ' +
        'canonical parameters, decide if the label refers to the SAME clinical concept as one catalogue entry, even ' +
        'with zero shared characters (e.g. an acronym vs its expansion). Respond with strict JSON only: ' +
        '{"canonical_parameter_id": string|null, "confidence": number between 0 and 1}. If nothing plausibly matches, return null.',
      messages: [
        {
          role: 'user',
          content: `Label: "${rawLabel}"\n\nCatalogue:\n${JSON.stringify(catalogue)}`,
        },
      ],
    });
    const text = resp.content.map((b) => ('text' in b ? b.text : '')).join('');
    // Prefer a fenced code block's contents when present — a bare greedy `{...}` regex over-
    // captures whenever the model adds any explanatory prose containing its own braces after
    // the JSON (observed in practice), producing "valid JSON followed by trailing garbage".
    const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
    const jsonText = fenced ? fenced[1] : text.match(/\{[\s\S]*?\}/)?.[0];
    if (!jsonText) return null;
    const parsed = JSON.parse(jsonText);
    if (!parsed.canonical_parameter_id) return null;
    // Tier 3 is never auto-accepted, so cap confidence conservatively regardless of what the model returns.
    return { canonical_parameter_id: parsed.canonical_parameter_id, match_confidence: Math.min(0.65, parsed.confidence ?? 0.5) };
  } catch (err) {
    console.error('Tier-3 semantic match via Claude failed, falling back to local heuristic:', err);
    return semanticMatchLocal(rawLabel, dictionary);
  }
}
