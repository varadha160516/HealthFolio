import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { translateToEnglish } from '../pipeline/translate.js';

export const translateRouter = Router();

// Supports Symptoms' voice-in-your-language logging — speech_to_text recognizes in whatever
// locale the member picked, this converts that recognized text to English before it's used to
// start/continue a symptom entry.
translateRouter.post('/translate', requireAuth, async (req, res) => {
  const { text, source_language } = req.body ?? {};
  if (!text || typeof text !== 'string' || !text.trim()) return res.status(400).json({ error: 'text is required' });
  if (!process.env.ANTHROPIC_API_KEY) return res.status(502).json({ error: 'Translation is not available right now.' });
  try {
    const translated = await translateToEnglish(text.trim(), (source_language as string) || 'the spoken');
    res.json({ translated });
  } catch (err) {
    console.error('Translation failed:', err);
    res.status(502).json({ error: 'Translation is not available right now.' });
  }
});
