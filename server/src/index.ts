// Load server/.env (if present) into process.env BEFORE anything else is imported — several
// modules (pipeline/extract.ts, pipeline/match.ts) read process.env.ANTHROPIC_API_KEY at
// module-load time, so this must run first. A dynamic import defers loading main.ts (and its
// transitive imports) until after loadEnvFile() below has already run.
try {
  process.loadEnvFile();
} catch {
  // No server/.env file present — fine, falls back to whatever's already in the shell environment.
}

await import('./main.js');
