/**
 * Languages the doctor-facing voice/summary features accept. Kept identical (by design, not shared
 * import — Dart and TS can't share a source file) to the language pickers in
 * mobile/lib/widgets/voice_language_button.dart and doctor_mobile/lib/widgets/ambient_scribe_card.dart
 * / after_visit_summary_card.dart. Names, not locale codes — they go straight into model prompts.
 */
export const SUPPORTED_LANGUAGES = ['English', 'Hindi', 'Tamil', 'Telugu', 'Bengali', 'Kannada', 'Marathi'] as const;
export type SupportedLanguage = (typeof SUPPORTED_LANGUAGES)[number];

export function parseLanguage(value: unknown): SupportedLanguage {
  return (SUPPORTED_LANGUAGES as readonly string[]).includes(value as string) ? (value as SupportedLanguage) : 'English';
}
