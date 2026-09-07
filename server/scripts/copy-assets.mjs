import { cpSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const src = join(root, 'src');
const dist = join(root, 'dist');

const files = [
  ['db/schema.sql', 'db/schema.sql'],
  ['dictionary/parameter_dictionary.json', 'dictionary/parameter_dictionary.json'],
  ['pipeline/fixtures/goldenReportA.json', 'pipeline/fixtures/goldenReportA.json'],
  ['pipeline/fixtures/goldenReportB.json', 'pipeline/fixtures/goldenReportB.json'],
];

for (const [from, to] of files) {
  const fromPath = join(src, from);
  const toPath = join(dist, to);
  if (!existsSync(fromPath)) continue;
  mkdirSync(dirname(toPath), { recursive: true });
  cpSync(fromPath, toPath);
}

const growthSrc = join(src, 'growth-data');
const growthDist = join(dist, 'growth-data');
if (existsSync(growthSrc)) {
  mkdirSync(growthDist, { recursive: true });
  cpSync(growthSrc, growthDist, { recursive: true, filter: (p) => !p.endsWith('.ts') });
}

console.log('copy-assets: schema.sql, parameter_dictionary.json, growth-data/*.csv -> dist/');
