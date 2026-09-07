import { db } from '../db/db.js';

// Medication reconciliation agent (Roadmap Section 2.7). The roadmap is explicit that a real
// drug-interaction/allergy-class reference is external, out-of-scope work for this build ("not
// something to build from scratch... a good candidate for an external MCP connector"). Rather
// than have a model guess at drug-class relationships with no verified reference behind it —
// which would risk a confident, hallucinated "these interact" claim in a health record app —
// this only checks the two things that ARE structured facts already in the system: an exact
// name match against a known allergy, and a duplicate against the patient's current medications.
// Deliberately conservative in scope; flags for the doctor's attention, never blocks signing.

export interface ReconciliationFlag {
  medicine_name: string;
  kind: 'allergy_conflict' | 'duplicate_medication';
  message: string;
}

function normalize(s: string): string {
  return s.trim().toLowerCase();
}

export function checkPrescriptionDraft(memberId: string, draftLineItems: { medicine_name: string }[]): ReconciliationFlag[] {
  const flags: ReconciliationFlag[] = [];
  const draftNames = draftLineItems.map((li) => li.medicine_name).filter((n) => n && n.trim().length > 0);
  if (draftNames.length === 0) return flags;

  const allergies = (db.prepare('SELECT value FROM allergies WHERE member_id = ?').all(memberId) as { value: string }[]).map((r) => r.value);

  const latestPrescription = db.prepare('SELECT id FROM prescriptions WHERE member_id = ? ORDER BY issued_at DESC LIMIT 1').get(memberId) as
    | { id: string }
    | undefined;
  const currentMedications = latestPrescription
    ? (db.prepare('SELECT medicine_name FROM prescription_line_items WHERE prescription_id = ?').all(latestPrescription.id) as { medicine_name: string }[]).map(
        (r) => r.medicine_name
      )
    : [];

  const seenInDraft = new Set<string>();

  for (const name of draftNames) {
    const normName = normalize(name);

    for (const allergy of allergies) {
      const normAllergy = normalize(allergy);
      if (normAllergy.length >= 3 && (normName.includes(normAllergy) || normAllergy.includes(normName))) {
        flags.push({
          medicine_name: name,
          kind: 'allergy_conflict',
          message: `${name} shares a name with a recorded allergy ("${allergy}") — verify with the patient before signing.`,
        });
      }
    }

    for (const current of currentMedications) {
      if (normalize(current) === normName) {
        flags.push({ medicine_name: name, kind: 'duplicate_medication', message: `${name} is already an active medication on file — check this isn't an unintended duplicate.` });
      }
    }

    if (seenInDraft.has(normName)) {
      flags.push({ medicine_name: name, kind: 'duplicate_medication', message: `${name} appears more than once in this draft prescription.` });
    }
    seenInDraft.add(normName);
  }

  return flags;
}
