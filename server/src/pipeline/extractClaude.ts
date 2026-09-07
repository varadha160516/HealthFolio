import Anthropic from '@anthropic-ai/sdk';
import { ExtractAdapter, LabExtractionResult, PageInput, PrescriptionExtractionResult } from './types.js';

const model = process.env.CARELOOP_EXTRACTION_MODEL || 'claude-sonnet-5';

let client: Anthropic | null = null;
function getClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

/**
 * Claude's API only understands PDFs as a `document` content block (with native page rendering),
 * not as an `image` block — sending a PDF's bytes with type "image" gets rejected outright.
 * Everything else (jpeg/png/webp/gif) goes as `image`.
 */
function toContentBlocks(pages: PageInput[]) {
  return pages.map((p) =>
    p.mimeType === 'application/pdf'
      ? { type: 'document' as const, source: { type: 'base64' as const, media_type: 'application/pdf' as const, data: p.buffer.toString('base64') } }
      : { type: 'image' as const, source: { type: 'base64' as const, media_type: p.mimeType as any, data: p.buffer.toString('base64') } }
  );
}

/**
 * A very large panel (50-100+ result rows) can still exhaust even a generous max_tokens budget.
 * Rather than discard the whole extraction when that happens, salvage every COMPLETE top-level
 * element of the named array (e.g. "tuples") and drop only the one that was mid-write when the
 * model got cut off. This is a real bracket-depth scan (string/escape aware), not a regex —
 * elements like printed_reference_range nest their own {} and a naive scan would misfire on those.
 */
function salvageTruncatedArray(text: string, arrayKey: string): any | null {
  const keyIdx = text.indexOf(`"${arrayKey}"`);
  if (keyIdx === -1) return null;
  const arrStart = text.indexOf('[', keyIdx);
  if (arrStart === -1) return null;

  let depth = 0;
  let inString = false;
  let escape = false;
  let lastCompleteEnd = -1;

  for (let i = arrStart + 1; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escape) escape = false;
      else if (ch === '\\') escape = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') { inString = true; continue; }
    if (ch === '{') { depth++; continue; }
    if (ch === '}') {
      depth--;
      if (depth === 0) lastCompleteEnd = i + 1; // just closed a top-level array element
      continue;
    }
  }
  if (lastCompleteEnd === -1) return null; // couldn't even recover one complete row

  const repaired = `${text.slice(0, arrStart + 1)}${text.slice(arrStart + 1, lastCompleteEnd)}]}`;
  try {
    return JSON.parse(repaired);
  } catch {
    return null;
  }
}

/**
 * Throws with the raw model text attached (truncated for log readability) whenever parsing
 * fails outright, instead of a bare "did not return JSON" — a truncated response (hit
 * max_tokens) and a genuinely malformed one look identical without this, and both need
 * different fixes. `arrayKey` names the response's main array ("tuples" / "line_items") so a
 * truncated response can be partially salvaged instead of failing the whole upload.
 */
function extractJson(text: string, stopReason: string | null, arrayKey: string): any {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const jsonText = fenced ? fenced[1] : text.match(/\{[\s\S]*\}/)?.[0];
  const preview = text.length > 1500 ? `${text.slice(0, 1500)}…[truncated for log, ${text.length} chars total]` : text;
  if (!jsonText) {
    throw new Error(`Extraction model returned no JSON (stop_reason=${stopReason}). Raw response:\n${preview}`);
  }
  try {
    return JSON.parse(jsonText);
  } catch (parseErr) {
    if (stopReason === 'max_tokens') {
      const salvaged = salvageTruncatedArray(jsonText, arrayKey);
      if (salvaged) {
        console.warn(
          `Extraction response hit max_tokens and was truncated — salvaged ${salvaged[arrayKey]?.length ?? 0} complete "${arrayKey}" rows ` +
            `from before the cutoff; whatever came after was dropped. Consider raising max_tokens further if this recurs often.`
        );
        return salvaged;
      }
    }
    const truncatedHint = stopReason === 'max_tokens' ? ' — response was cut off at the token limit and no complete rows could be salvaged.' : '';
    throw new Error(`Extraction model's JSON failed to parse${truncatedHint} (stop_reason=${stopReason}). Raw response:\n${preview}`);
  }
}

const LAB_SYSTEM_PROMPT = `You are the extraction stage of a medical lab-report parsing pipeline (Section 4 of the CareLoop PRD).
You are shown the actual rendered page(s) of a lab report — read them as a person would, not a raw OCR text dump.

Rules, non-negotiable:
- Page layouts vary wildly between labs (different column orders, different header words for the same concept). Do not assume any fixed template.
- Some reports render values as chart/infographic cards (a range bar, a "Currently X, Increased by Y" delta callout, a sparkline) instead of a table. Read the numeric value and its meaning out of the graphic.
- Pages carry NOISE alongside the real DATA: NABL/QR badges, disclaimer paragraphs, signature blocks, promotional/discount banners, app-download prompts. Extract ONLY clinical result rows. Never turn a phone number, discount code, or badge text into a result tuple.
- Some rows print a reference range like "*Refer Note below" instead of a numeric range — capture that as printed_reference_range.text, with low/high null. Do not invent numeric bounds for these.
- If multiple pages share the same Lab Visit ID / Barcode ID / Order ID printed in the header or footer, they are ONE logical report — extract them together into one tuple list and return that shared id as lab_visit_id.
- test_date MUST be formatted as YYYY-MM-DD, regardless of how the report prints it (e.g. a printed "22 Jul 2026" or "22/07/2026" becomes "2026-07-22"). This is load-bearing: every trend graph and comparison in this system sorts and groups by this exact string, so an inconsistent format silently corrupts a member's history.

Return STRICT JSON only, matching this shape exactly, no prose before or after:
{
  "presentation_style": "tabular" | "chart_infographic" | "narrative_handwritten",
  "lab_visit_id": string | null,
  "test_date": "YYYY-MM-DD string" | null,
  "ordering_lab_name": string | null,
  "tuples": [
    {
      "label_as_printed": string,
      "value": string,
      "unit": string | null,
      "printed_reference_range": { "low": number | null, "high": number | null, "text": string | null } | null,
      "extraction_confidence": number
    }
  ]
}`;

const PRESCRIPTION_SYSTEM_PROMPT = `You are the extraction stage of a medical prescription parsing pipeline. You are shown a photo/PDF of a
handwritten or printed prescription. Extract each medicine line item. Return STRICT JSON only, no prose:
{
  "diagnosis_text": string | null,
  "prescribed_date": "YYYY-MM-DD string" | null,
  "line_items": [ { "medicine_name": string, "dosage": string | null, "frequency": string | null, "duration": string | null } ]
}`;

export const claudeAdapter: ExtractAdapter = {
  async extractLabReport(pages: PageInput[]): Promise<LabExtractionResult> {
    const resp = await getClient().messages.create({
      model,
      // A comprehensive annual/health-checkup panel can run to 60-100+ result rows. Even 8192
      // truncated on a real report (a full lipid+CBC+comprehensive panel) — this leaves real
      // headroom, and salvageTruncatedArray() above is the backstop if a report is bigger still.
      max_tokens: 16384,
      system: LAB_SYSTEM_PROMPT,
      // Cast: the installed @anthropic-ai/sdk (0.32.1) predates typed "document" content blocks
      // in messages.create(), even though the API itself accepts them — this is a types-only gap.
      messages: [{ role: 'user', content: [...toContentBlocks(pages), { type: 'text', text: 'Extract this lab report per the rules above.' }] as any }],
    });
    const text = resp.content.map((b) => ('text' in b ? b.text : '')).join('');
    return extractJson(text, resp.stop_reason, 'tuples') as LabExtractionResult;
  },

  async extractPrescription(pages: PageInput[]): Promise<PrescriptionExtractionResult> {
    const resp = await getClient().messages.create({
      model,
      max_tokens: 2048,
      system: PRESCRIPTION_SYSTEM_PROMPT,
      messages: [{ role: 'user', content: [...toContentBlocks(pages), { type: 'text', text: 'Extract this prescription per the rules above.' }] as any }],
    });
    const text = resp.content.map((b) => ('text' in b ? b.text : '')).join('');
    return extractJson(text, resp.stop_reason, 'line_items') as PrescriptionExtractionResult;
  },
};
