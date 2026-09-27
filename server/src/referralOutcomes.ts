import { db, now } from './db/db.js';
import { runSafetyCheck } from './pipeline/safetyNet.js';
import { memberName, notifyProvider } from './notifications.js';

// Closed-loop referrals. A referral already carries the referring doctor's reason and notes to the
// specialist (previsitPrep.ts) — that's an explicit, one-time sharing act the referring doctor
// performed themselves, not a standing grant. This is the mirror of it: once the specialist
// completes the referred visit, the outcome is copied back onto the SAME referral row and the
// referring doctor is told. It never needs the referring doctor to still have an unlocked visit
// with the patient — a referral outcome is the specialist's own report on their own visit, exactly
// like a referral letter's reply in an ordinary clinic, not a browse of the patient's wider record.
//
// Same "organize what was said, never invent" rule as the after-visit summary and the prescription
// PDF this is built from: every field here is copied programmatically from structured data the
// specialist already entered for their own visit. Nothing is drafted or summarized by a model.

interface OutcomeRow {
  outcome_ready_at: string | null;
  outcome_diagnosis_text: string | null;
  outcome_medicines_json: string | null;
  outcome_advice_json: string | null;
  outcome_follow_up_after: string | null;
  outcome_follow_up_reason: string | null;
  outcome_safety_flags_json: string | null;
}

export interface ReferralOutcome {
  ready_at: string;
  diagnosis_text: string | null;
  medicines: string[];
  advice: string[];
  follow_up_after: string | null;
  follow_up_reason: string | null;
  // Cross-provider medicine/allergy conflicts (safetyNet.ts), snapshotted at the moment the
  // specialist's visit completed — the same check a doctor with an unlocked visit sees live.
  safety_flags: unknown[];
}

/** Called once, right when a referred visit completes (appointments.ts's /complete route). */
export function closeReferralLoop(appointmentId: string, referralId: string): void {
  const referral = db.prepare('SELECT id, member_id, referring_provider_id, referring_appointment_id FROM referrals WHERE id = ?').get(referralId) as
    | { id: string; member_id: string; referring_provider_id: string; referring_appointment_id: string }
    | undefined;
  if (!referral) return;

  // The most recent prescription issued at this specific visit — plural rows are possible in
  // principle (nothing stops a second call), so this takes the latest rather than assuming exactly
  // one.
  const prescription = db.prepare('SELECT id, diagnosis_text FROM prescriptions WHERE appointment_id = ? ORDER BY issued_at DESC LIMIT 1').get(appointmentId) as
    | { id: string; diagnosis_text: string | null }
    | undefined;
  const lineItems = prescription
    ? (db.prepare('SELECT medicine_name, strength, dosage, frequency FROM prescription_line_items WHERE prescription_id = ?').all(prescription.id) as {
        medicine_name: string;
        strength: string | null;
        dosage: string | null;
        frequency: string | null;
      }[])
    : [];
  const medicines = lineItems.map((li) => [li.medicine_name, li.strength, li.dosage, li.frequency].filter((v) => v && String(v).trim()).join(' — '));

  const notes = db.prepare('SELECT advice, follow_up_after, follow_up_reason FROM consultation_notes WHERE appointment_id = ?').get(appointmentId) as
    | { advice: string | null; follow_up_after: string | null; follow_up_reason: string | null }
    | undefined;
  let advice: string[] = [];
  try {
    advice = notes?.advice ? JSON.parse(notes.advice) : [];
  } catch {
    advice = [];
  }

  const safetyFlags = runSafetyCheck(referral.member_id).open;

  db.prepare(
    `UPDATE referrals SET
       outcome_diagnosis_text = ?, outcome_medicines_json = ?, outcome_advice_json = ?,
       outcome_follow_up_after = ?, outcome_follow_up_reason = ?, outcome_safety_flags_json = ?,
       outcome_ready_at = ?, updated_at = ?
     WHERE id = ?`
  ).run(
    prescription?.diagnosis_text ?? null,
    JSON.stringify(medicines),
    JSON.stringify(advice),
    notes?.follow_up_after ?? null,
    notes?.follow_up_reason ?? null,
    JSON.stringify(safetyFlags),
    now(),
    now(),
    referral.id
  );

  // Points at the REFERRING doctor's own appointment (the one that created the referral), not the
  // specialist's — that's the only one of the two this doctor can actually open.
  notifyProvider(
    referral.referring_provider_id,
    'referral_outcome_ready',
    'Referral outcome ready',
    `${memberName(referral.member_id)}'s referral visit is complete — the outcome is ready to view.`,
    referral.referring_appointment_id
  );
}

/** Shapes one `referrals` row (plus the joined patient/target-doctor names a listing needs) for the
 * referring doctor's own referrals screen. Only ever called on referrals that row's own
 * referring_provider_id already scopes to the caller — see GET /providers/me/referrals. */
export function serializeReferral(row: Record<string, unknown> & OutcomeRow) {
  const outcome: ReferralOutcome | null = row.outcome_ready_at
    ? {
        ready_at: row.outcome_ready_at as string,
        diagnosis_text: row.outcome_diagnosis_text as string | null,
        medicines: safeParseArray<string>(row.outcome_medicines_json as string | null),
        advice: safeParseArray<string>(row.outcome_advice_json as string | null),
        follow_up_after: row.outcome_follow_up_after as string | null,
        follow_up_reason: row.outcome_follow_up_reason as string | null,
        safety_flags: safeParseArray(row.outcome_safety_flags_json as string | null),
      }
    : null;
  const {
    outcome_diagnosis_text: _a,
    outcome_medicines_json: _b,
    outcome_advice_json: _c,
    outcome_follow_up_after: _d,
    outcome_follow_up_reason: _e,
    outcome_safety_flags_json: _f,
    outcome_ready_at: _g,
    ...rest
  } = row;
  return { ...rest, outcome };
}

function safeParseArray<T = unknown>(json: string | null): T[] {
  if (!json) return [];
  try {
    const v = JSON.parse(json);
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}
