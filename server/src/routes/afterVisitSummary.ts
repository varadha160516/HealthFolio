import { Router } from 'express';
import { db, now } from '../db/db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { resolveAppointment, assertAppointmentVisible } from './appointments.js';
import { buildVisitSummary } from './doctorApp.js';
import { draftAfterVisitSummary } from '../pipeline/afterVisitSummary.js';
import { translateFromEnglish } from '../pipeline/translate.js';
import { parseLanguage, SUPPORTED_LANGUAGES } from '../languages.js';
import { formatAppointmentWhen } from '../notifications.js';

export const afterVisitSummaryRouter = Router();

// After-visit summary. Flow: the doctor drafts an English letter from their own visit record,
// edits it, previews a translation, then sends. Nothing is stored until "send" — a patient can
// never see an unreviewed draft. Like GET .../visit-summary, this reads the doctor's OWN authored
// record of this one visit, so it deliberately sits outside the consent-window gate (which access
// to the patient's broader records stays behind everywhere else); it is only offered once the
// visit is completed.

function loadCompletedOwnVisit(req: any, res: any) {
  const appt = resolveAppointment(req.params.id);
  if (!appt) {
    res.status(404).json({ error: 'Not found' });
    return null;
  }
  if (!assertAppointmentVisible(req, res, appt)) return null;
  if (appt.status !== 'completed') {
    res.status(409).json({ error: 'An after-visit summary can only be written once the visit is completed' });
    return null;
  }
  return appt;
}

afterVisitSummaryRouter.get('/appointments/:id/after-visit-summary', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = loadCompletedOwnVisit(req, res);
  if (!appt) return;
  const summary = db.prepare('SELECT * FROM visit_summaries WHERE appointment_id = ?').get(appt.id) ?? null;
  // Language is a fact about the patient, but only THIS doctor's own past letters inform the
  // suggestion — never another provider's records.
  const previous = db
    .prepare('SELECT language FROM visit_summaries WHERE member_id = ? AND provider_id = ? ORDER BY sent_at DESC LIMIT 1')
    .get(appt.member_id, appt.provider_id) as { language: string } | undefined;
  res.json({ summary, suggestedLanguage: previous?.language ?? 'English', languages: SUPPORTED_LANGUAGES });
});

afterVisitSummaryRouter.post('/appointments/:id/after-visit-summary/draft', requireAuth, requireRole('provider_doctor'), async (req, res) => {
  const appt = loadCompletedOwnVisit(req, res);
  if (!appt) return;
  const data = buildVisitSummary(appt.id);
  const notes = data.consultationNotes as any;
  const member = db.prepare('SELECT name FROM members WHERE id = ?').get(appt.member_id) as { name: string } | undefined;
  const provider = db.prepare('SELECT name FROM providers WHERE id = ?').get(appt.provider_id) as { name: string } | undefined;

  let followUp: { when: string | null; reason: string | null } | null = null;
  if (notes?.follow_up_appointment_id) {
    const fa = db.prepare('SELECT datetime FROM appointments WHERE id = ?').get(notes.follow_up_appointment_id) as { datetime: string } | undefined;
    if (fa) followUp = { when: formatAppointmentWhen(fa.datetime), reason: notes.follow_up_reason?.trim() || null };
  } else if (notes?.follow_up_reason?.trim()) {
    followUp = { when: null, reason: notes.follow_up_reason.trim() };
  }

  try {
    const english_text = await draftAfterVisitSummary({
      memberName: member?.name ?? 'Patient',
      providerName: provider?.name ?? 'Your doctor',
      notes: notes
        ? {
            chief_complaint: notes.chief_complaint ?? null,
            symptom_duration: notes.symptom_duration ?? null,
            symptoms: notes.symptoms ?? [],
            assessment_notes: notes.assessment_notes ?? null,
            advice: notes.advice ?? [],
          }
        : null,
      diagnosisText: data.prescription?.diagnosis_text ?? null,
      lineItems: (data.prescription?.lineItems ?? []).map((li: any) => ({
        medicine_name: li.medicine_name,
        strength: li.strength ?? null,
        dosage: li.dosage ?? null,
        frequency: li.frequency ?? null,
        duration: li.duration ?? null,
        instructions: li.instructions ?? null,
      })),
      labTests: data.labOrders.flatMap((o: any) => o.test_names as string[]),
      followUp,
    });
    res.json({ english_text });
  } catch (e) {
    console.error(`After-visit summary draft failed for appointment ${appt.id}:`, e);
    res.status(502).json({ error: 'Could not draft a summary right now.' });
  }
});

afterVisitSummaryRouter.post('/appointments/:id/after-visit-summary/translate', requireAuth, requireRole('provider_doctor'), async (req, res) => {
  const appt = loadCompletedOwnVisit(req, res);
  if (!appt) return;
  const englishText = (req.body?.english_text as string | undefined)?.trim();
  if (!englishText) return res.status(400).json({ error: 'english_text is required' });
  const language = parseLanguage(req.body?.language);
  if (language === 'English') return res.json({ translated_text: null, language });
  if (!process.env.ANTHROPIC_API_KEY) return res.status(502).json({ error: 'Translation is not available right now.' });
  try {
    res.json({ translated_text: await translateFromEnglish(englishText, language), language });
  } catch (e) {
    console.error(`After-visit summary translation failed for appointment ${appt.id}:`, e);
    res.status(502).json({ error: 'Translation is not available right now.' });
  }
});

afterVisitSummaryRouter.put('/appointments/:id/after-visit-summary', requireAuth, requireRole('provider_doctor'), (req, res) => {
  const appt = loadCompletedOwnVisit(req, res);
  if (!appt) return;
  const englishText = (req.body?.english_text as string | undefined)?.trim();
  if (!englishText) return res.status(400).json({ error: 'english_text is required' });
  const language = parseLanguage(req.body?.language);
  const translated = (req.body?.translated_text as string | undefined)?.trim() || null;
  if (language !== 'English' && !translated) return res.status(400).json({ error: `Preview the ${language} translation before sending` });

  const ts = now();
  db.prepare(
    `INSERT INTO visit_summaries (appointment_id, member_id, provider_id, english_text, language, translated_text, status, sent_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 'sent', ?, ?)
     ON CONFLICT(appointment_id) DO UPDATE SET english_text = excluded.english_text, language = excluded.language,
       translated_text = excluded.translated_text, updated_at = excluded.updated_at`
  ).run(appt.id, appt.member_id, appt.provider_id, englishText, language, language === 'English' ? null : translated, ts, ts);
  res.json(db.prepare('SELECT * FROM visit_summaries WHERE appointment_id = ?').get(appt.id));
});

// Member side — only ever a summary the doctor explicitly sent.
afterVisitSummaryRouter.get('/appointments/:id/patient-summary', requireAuth, (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary' && session.role !== 'member_dependent') return res.status(403).json({ error: 'Only members can view this' });
  const appt = resolveAppointment(req.params.id);
  if (!appt) return res.status(404).json({ error: 'Not found' });
  if (!assertAppointmentVisible(req, res, appt)) return;
  const summary = db.prepare('SELECT * FROM visit_summaries WHERE appointment_id = ?').get(appt.id) as any;
  if (!summary) return res.status(404).json({ error: 'No summary has been sent for this visit' });
  const provider = db.prepare('SELECT name FROM providers WHERE id = ?').get(appt.provider_id) as { name: string } | undefined;
  res.json({
    language: summary.language,
    english_text: summary.english_text,
    translated_text: summary.translated_text,
    sent_at: summary.sent_at,
    provider_name: provider?.name ?? null,
    appointment_datetime: appt.datetime,
  });
});
