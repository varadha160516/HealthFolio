import Anthropic from '@anthropic-ai/sdk';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { allCanonicalParameters, CanonicalParameterRow } from '../dictionary/loader.js';
import { matchLabel } from './match.js';

// Dictionary curation agent (Roadmap Section 2.9). Two jobs, both purely advisory — every
// output here is a draft for a platform_admin to accept or override, never something this
// module applies to canonical_parameters or new_parameter_candidates itself:
//
// (a) checkParameterDrift/scanForDrift — flags a canonical parameter's stored reference range as
//     possibly worth re-checking. There is no live reference-range research connector wired into
//     this app (Roadmap Section 3 lists one as a pending Tier 3 connector), so this is the
//     model's own trained clinical knowledge, not a cited external source — every flag is stored
//     and surfaced with note_basis='model_knowledge' so the admin UI never implies a live lookup.
// (b) draftCandidateResolution — for one new_parameter_candidates row, proposes how to resolve
//     it (new alias vs. genuinely new parameter), the way a human curator would sketch a first
//     guess before the admin makes the real call.

const model = process.env.CARELOOP_CURATION_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

function extractJson(text: string): string | undefined {
  // Same reasoning as match.ts's semanticMatchViaClaude: prefer a fenced block when present,
  // since a bare greedy brace match over-captures when the model adds prose containing its own
  // braces after the JSON.
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  return fenced ? fenced[1] : text.match(/\{[\s\S]*?\}/)?.[0];
}

// --- (a) Reference-range drift ---------------------------------------------------------------

export interface DriftFlag {
  id: string;
  canonical_parameter_id: string;
  display_name: string;
  category: string;
  note: string;
  note_basis: string;
  status: string;
  checked_at: string;
}

const DRIFT_SYSTEM_PROMPT = `You are the CareLoop Dictionary Curation agent, doing a periodic plausibility re-check of the canonical lab-parameter dictionary's stored reference ranges against your own general clinical knowledge. You are not a live source and cannot fetch a current publication — never write as if you're citing one; the admin already knows this check is knowledge-based, not a live lookup.

For the single parameter given, decide: does its stored typical reference range and unit look consistent with commonly-cited adult reference ranges for this parameter, as best you know them? Minor lab-to-lab variation is normal and NOT worth flagging — only flag something that looks materially off (wrong order of magnitude, an inverted low/high, a unit mismatch, or a range that looks meaningfully outdated).

Respond with strict JSON only: {"flag": boolean, "note": string}. If flag is false, note is a brief one-sentence reason it looks fine (still returned, so there's a record this was checked, not skipped). If flag is true, note explains specifically what looks off, in one or two sentences.`;

/** Checks one parameter. Never throws — a failed or unconfigured check just comes back unflagged
 * with an explanatory note, since "couldn't check" must never silently look the same as "checked,
 * looks fine" when read back later. */
export async function checkParameterDrift(param: CanonicalParameterRow): Promise<{ flag: boolean; note: string }> {
  if (param.range_type === 'interpretive_rule' || param.range_type === 'qualitative' || param.range_type === 'none') {
    return { flag: false, note: 'Not a numeric reference range — nothing to drift-check.' };
  }
  if (!process.env.ANTHROPIC_API_KEY) {
    return { flag: false, note: 'Skipped — no ANTHROPIC_API_KEY configured for this check.' };
  }
  try {
    const resp = await getClient().messages.create({
      model,
      max_tokens: 250,
      system: DRIFT_SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: `Parameter: ${param.display_name} (${param.canonical_parameter_id}), category ${param.category}\nStored range: ${param.typical_low ?? '—'} to ${param.typical_high ?? '—'} ${param.canonical_unit}\nRange type: ${param.range_type}`,
        },
      ],
    });
    const text = resp.content
      .filter((b): b is Anthropic.TextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('');
    const jsonText = extractJson(text);
    if (!jsonText) return { flag: false, note: 'Check produced no parseable result.' };
    const parsed = JSON.parse(jsonText);
    return { flag: Boolean(parsed.flag), note: typeof parsed.note === 'string' ? parsed.note : '' };
  } catch (err) {
    console.error(`Drift check for ${param.canonical_parameter_id} failed:`, err);
    return { flag: false, note: 'Check failed — try again later.' };
  }
}

/** Scans one parameter (canonicalParameterId given) or the whole dictionary, persisting a new
 * 'open' row only for parameters that come back flagged. Sequential, not parallel — this can call
 * the model once per parameter, and there's no need to burst that against the API when it's
 * triggered on demand by an admin rather than latency-sensitive. */
export async function scanForDrift(canonicalParameterId?: string): Promise<DriftFlag[]> {
  const dictionary = canonicalParameterId ? allCanonicalParameters().filter((p) => p.canonical_parameter_id === canonicalParameterId) : allCanonicalParameters();

  const insert = db.prepare(`INSERT INTO dictionary_drift_flags (id, canonical_parameter_id, note, note_basis, status, checked_at) VALUES (?, ?, ?, 'model_knowledge', 'open', ?)`);
  const results: DriftFlag[] = [];

  for (const param of dictionary) {
    const { flag, note } = await checkParameterDrift(param);
    if (!flag) continue;
    const id = uuid();
    const checkedAt = now();
    insert.run(id, param.canonical_parameter_id, note, checkedAt);
    results.push({ id, canonical_parameter_id: param.canonical_parameter_id, display_name: param.display_name, category: param.category, note, note_basis: 'model_knowledge', status: 'open', checked_at: checkedAt });
  }
  return results;
}

// --- (b) Candidate resolution drafting --------------------------------------------------------

export interface CandidateDraft {
  resolution_type: 'alias' | 'new_param' | 'uncertain';
  suggested_canonical_parameter_id: string | null;
  suggested_display_name: string | null;
  suggested_category: string | null;
  confidence: number;
  rationale: string;
}

interface CandidateRow {
  id: string;
  label_as_printed: string;
  value: string | null;
  unit: string | null;
  status: string;
}

const CANDIDATE_DRAFT_SYSTEM_PROMPT = `You are the CareLoop Dictionary Curation agent, assisting a platform_admin who governs the canonical lab-parameter dictionary. You are given a label that appeared on a real lab report and found no confident match against the dictionary during live parsing — it is sitting in the admin's review queue.

Your only job: draft a proposed resolution for the admin to accept or override — you never apply anything yourself. Two possible drafts:
- "alias": you believe this label almost certainly refers to an existing catalogue entry (a lab-specific abbreviation, a translated term, a formatting variant) — return that entry's id and a one-sentence rationale, e.g. "likely a new alias of hematocrit."
- "new_param": you believe this is a genuinely new clinical concept not in the catalogue — suggest a plausible display_name and a category chosen from the catalogue's existing categories, with a one-sentence rationale.
If you are honestly unsure either way, say "uncertain" rather than guessing — the admin would rather see an honest "not sure" than a confident-sounding wrong guess.

Respond with strict JSON only: {"resolution_type": "alias"|"new_param"|"uncertain", "suggested_canonical_parameter_id": string|null, "suggested_display_name": string|null, "suggested_category": string|null, "confidence": number between 0 and 1, "rationale": string}`;

function fallbackDraft(rationale: string): CandidateDraft {
  return { resolution_type: 'uncertain', suggested_canonical_parameter_id: null, suggested_display_name: null, suggested_category: null, confidence: 0, rationale };
}

/** Drafts a proposed resolution for one pending new_parameter_candidates row. */
export async function draftCandidateResolution(candidateId: string): Promise<CandidateDraft> {
  const candidate = db.prepare('SELECT * FROM new_parameter_candidates WHERE id = ?').get(candidateId) as CandidateRow | undefined;
  if (!candidate) throw new Error('Candidate not found');

  const dictionary = allCanonicalParameters();

  // The dictionary may have grown since this candidate was created — an admin resolving an
  // earlier, similar candidate as a new canonical parameter or alias — so re-running the exact
  // same strict matcher live parsing uses first catches that case for free, at the same
  // confidence tier 1/2 parsing itself would trust.
  const strict = await matchLabel(candidate.label_as_printed, dictionary);
  if (strict.canonical_parameter_id && strict.match_tier != null && strict.match_tier <= 2) {
    const param = dictionary.find((p) => p.canonical_parameter_id === strict.canonical_parameter_id);
    return {
      resolution_type: 'alias',
      suggested_canonical_parameter_id: strict.canonical_parameter_id,
      suggested_display_name: param?.display_name ?? null,
      suggested_category: param?.category ?? null,
      confidence: strict.match_confidence,
      rationale: `The dictionary now has a Tier ${strict.match_tier} match for this label — likely a new alias of ${param?.display_name ?? strict.canonical_parameter_id}.`,
    };
  }

  if (!process.env.ANTHROPIC_API_KEY) {
    return fallbackDraft('No AI draft available (no ANTHROPIC_API_KEY configured) — resolve manually from the label and value below.');
  }

  const catalogue = dictionary.map((p) => ({ id: p.canonical_parameter_id, name: p.display_name, category: p.category }));
  try {
    const resp = await getClient().messages.create({
      model,
      max_tokens: 300,
      system: CANDIDATE_DRAFT_SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: `Label as printed: "${candidate.label_as_printed}"\nValue: ${candidate.value ?? '—'} ${candidate.unit ?? ''}\n\nCatalogue:\n${JSON.stringify(catalogue)}`,
        },
      ],
    });
    const text = resp.content
      .filter((b): b is Anthropic.TextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('');
    const jsonText = extractJson(text);
    if (!jsonText) return fallbackDraft('The draft call returned no parseable result — resolve manually.');
    const parsed = JSON.parse(jsonText);
    const resolutionType: CandidateDraft['resolution_type'] = parsed.resolution_type === 'alias' || parsed.resolution_type === 'new_param' ? parsed.resolution_type : 'uncertain';
    return {
      resolution_type: resolutionType,
      suggested_canonical_parameter_id: parsed.suggested_canonical_parameter_id ?? null,
      suggested_display_name: parsed.suggested_display_name ?? null,
      suggested_category: parsed.suggested_category ?? null,
      // Capped well below auto-accept territory — this is a draft for a human to click through,
      // never something any code path treats as confident enough to apply on its own.
      confidence: Math.min(0.75, Math.max(0, typeof parsed.confidence === 'number' ? parsed.confidence : 0.4)),
      rationale: typeof parsed.rationale === 'string' ? parsed.rationale : 'No rationale returned.',
    };
  } catch (err) {
    console.error(`Candidate draft for ${candidateId} failed:`, err);
    return fallbackDraft('The draft call failed — resolve manually from the label and value below.');
  }
}
