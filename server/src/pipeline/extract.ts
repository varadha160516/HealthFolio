import { ExtractAdapter } from './types.js';
import { mockAdapter } from './extractMock.js';
import { claudeAdapter } from './extractClaude.js';

/**
 * Stage 4 (Section 4.3): a vision-capable model reads the rendered page. Adapter selection is
 * the ONLY thing that changes when a real API key is added — every downstream stage (matching,
 * range resolution, confidence, validation) is identical either way.
 */
export function getExtractAdapter(): ExtractAdapter {
  return process.env.ANTHROPIC_API_KEY ? claudeAdapter : mockAdapter;
}

export function extractionModeLabel(): 'live' | 'mock' {
  return process.env.ANTHROPIC_API_KEY ? 'live' : 'mock';
}
