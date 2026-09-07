/** Lowercase, strip punctuation/whitespace variation — the baseline for tier-1/tier-2 comparison (Section 4.4). */
export function normalizeLabel(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9%/. ]+/g, ' ') // drop punctuation but keep chars meaningful to lab units/ratios
    .replace(/\s+/g, ' ')
    .trim();
}

const STOPWORDS = new Set(['count', 'total', 'serum', 'plasma', 'blood', 'test', 'level', 'the', 'of', 'a']);

/** Distinguishing (non-stopword) tokens — used to weight tier-2 overlap so e.g.
 * "Absolute Neutrophil Count" doesn't fuzzy-win against "Absolute Basophil Count"
 * just because "absolute" and "count" are shared. */
export function distinguishingTokens(s: string): Set<string> {
  return new Set(normalizeLabel(s).split(' ').filter((t) => t.length > 1 && !STOPWORDS.has(t)));
}

export function tokenOverlapScore(a: string, b: string): number {
  const ta = distinguishingTokens(a);
  const tb = distinguishingTokens(b);
  if (ta.size === 0 || tb.size === 0) return 0;
  let shared = 0;
  for (const t of ta) if (tb.has(t)) shared++;
  return shared / Math.max(ta.size, tb.size); // penalize partial overlap symmetrically
}

/** Character-trigram Jaccard similarity — a local stand-in for a medical-domain embedding
 * model (Section 4.4 tier 3). Swap `semanticMatch` in match.ts for a real embedding/LLM call
 * when available; tier-3 results are never auto-accepted regardless, so this only affects
 * which suggestion a human reviewer sees first. */
export function trigramSimilarity(a: string, b: string): number {
  const grams = (s: string) => {
    const norm = normalizeLabel(s).replace(/ /g, '');
    const set = new Set<string>();
    for (let i = 0; i < norm.length - 2; i++) set.add(norm.slice(i, i + 3));
    return set;
  };
  const ga = grams(a);
  const gb = grams(b);
  if (ga.size === 0 || gb.size === 0) return 0;
  let shared = 0;
  for (const g of ga) if (gb.has(g)) shared++;
  return shared / (ga.size + gb.size - shared);
}
