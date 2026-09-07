import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { db, now } from '../db/db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

interface DictParam {
  canonical_parameter_id: string;
  display_name: string;
  category: string;
  canonical_unit: string;
  range_type: string;
  typical_reference_range: { low: number | null; high: number | null } | null;
  aliases: string[];
  plausible_range_for_validation: [number | null, number | null] | null;
}

interface DictFile {
  _meta: { version: string; changelog: string };
  parameters: DictParam[];
}

/**
 * Loads CareLoop_Parameter_Dictionary.json into canonical_parameters, versioned.
 * Idempotent: re-running with the same version is a no-op; a new version is inserted
 * fresh so historical ExtractedParameter rows keep pointing at the version active
 * when they were parsed (Section 5.3 — "version the dictionary").
 */
export function loadDictionary(): string {
  const raw = fs.readFileSync(path.join(__dirname, 'parameter_dictionary.json'), 'utf-8');
  const dict: DictFile = JSON.parse(raw);
  const version = dict._meta.version;

  const alreadyLoaded = db.prepare('SELECT 1 FROM dictionary_meta WHERE version = ?').get(version);
  if (alreadyLoaded) return version;

  const insertMeta = db.prepare(
    `INSERT INTO dictionary_meta (version, loaded_at, source, changelog) VALUES (?, ?, ?, ?)`
  );
  const insertParam = db.prepare(`
    INSERT INTO canonical_parameters
      (canonical_parameter_id, display_name, category, canonical_unit, range_type,
       typical_low, typical_high, aliases_json, plausible_low, plausible_high, dictionary_version, loinc_code)
    VALUES (@id, @display_name, @category, @canonical_unit, @range_type,
            @typical_low, @typical_high, @aliases_json, @plausible_low, @plausible_high, @dictionary_version, NULL)
    ON CONFLICT(canonical_parameter_id) DO UPDATE SET
      display_name=excluded.display_name, category=excluded.category, canonical_unit=excluded.canonical_unit,
      range_type=excluded.range_type, typical_low=excluded.typical_low, typical_high=excluded.typical_high,
      aliases_json=excluded.aliases_json, plausible_low=excluded.plausible_low, plausible_high=excluded.plausible_high,
      dictionary_version=excluded.dictionary_version
  `);

  const tx = db.transaction(() => {
    insertMeta.run(version, now(), 'CareLoop_Parameter_Dictionary.json', dict._meta.changelog ?? null);
    for (const p of dict.parameters) {
      insertParam.run({
        id: p.canonical_parameter_id,
        display_name: p.display_name,
        category: p.category,
        canonical_unit: p.canonical_unit,
        range_type: p.range_type,
        typical_low: p.typical_reference_range?.low ?? null,
        typical_high: p.typical_reference_range?.high ?? null,
        aliases_json: JSON.stringify(p.aliases),
        plausible_low: p.plausible_range_for_validation?.[0] ?? null,
        plausible_high: p.plausible_range_for_validation?.[1] ?? null,
        dictionary_version: version,
      });
    }
  });
  tx();
  return version;
}

export function currentDictionaryVersion(): string {
  const row = db
    .prepare('SELECT version FROM dictionary_meta ORDER BY loaded_at DESC LIMIT 1')
    .get() as { version: string } | undefined;
  if (!row) throw new Error('Dictionary not loaded');
  return row.version;
}

export interface CanonicalParameterRow {
  canonical_parameter_id: string;
  display_name: string;
  category: string;
  canonical_unit: string;
  range_type: string;
  typical_low: number | null;
  typical_high: number | null;
  aliases_json: string;
  plausible_low: number | null;
  plausible_high: number | null;
  dictionary_version: string;
}

export function allCanonicalParameters(): CanonicalParameterRow[] {
  return db.prepare('SELECT * FROM canonical_parameters').all() as unknown as CanonicalParameterRow[];
}
