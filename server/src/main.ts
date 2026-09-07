import { seed } from './db/seed.js';
import { seedProviderDirectory, seedSecondDoctorPerSpecialty } from './db/seedProviders.js';
import { buildApp } from './app.js';
import { extractionModeLabel } from './pipeline/extract.js';

seed();
seedProviderDirectory();
seedSecondDoctorPerSpecialty();

const app = buildApp();
const port = Number(process.env.PORT) || 4000;
app.listen(port, () => {
  console.log(`CareLoop API listening on http://localhost:${port} (extraction mode: ${extractionModeLabel()})`);
});
