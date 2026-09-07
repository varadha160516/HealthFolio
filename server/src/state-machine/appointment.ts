export type AppointmentStatus =
  | 'scheduled'
  | 'checked_in'
  | 'consent_requested'
  | 'consent_granted'
  | 'in_consultation'
  | 'completed'
  | 'consent_denied'
  | 'consent_expired'
  | 'cancelled';

export const CONSENT_WINDOW_MINUTES = 5; // business default per Section 7.1, to be validated against real clinic timing

/** Section 7.1's state machine, expressed as an allow-list so no code path can short-circuit it.
 * `cancelled` (member-initiated) is reachable from any state before a consultation is actually
 * unlocked — once consent_granted/in_consultation, the visit is already underway, so a member
 * can no longer cancel it. */
const ALLOWED_TRANSITIONS: Record<AppointmentStatus, AppointmentStatus[]> = {
  scheduled: ['checked_in', 'cancelled'],
  checked_in: ['consent_requested', 'cancelled'],
  consent_requested: ['consent_granted', 'consent_denied', 'consent_expired', 'cancelled'],
  consent_granted: ['in_consultation'],
  in_consultation: ['completed'],
  completed: [],
  consent_denied: ['consent_requested', 'cancelled'], // explicit resend only, never automatic
  consent_expired: ['consent_requested', 'cancelled'], // explicit resend only, never automatic
  cancelled: [],
};

export function canTransition(from: AppointmentStatus, to: AppointmentStatus): boolean {
  return ALLOWED_TRANSITIONS[from]?.includes(to) ?? false;
}

/** Section 7.2/12.4 — the ONLY states where a provider may see member data. Fail closed everywhere else. */
export function grantsDataAccess(status: AppointmentStatus): boolean {
  return status === 'consent_granted' || status === 'in_consultation';
}

export function isDistinctFromWaiting(status: AppointmentStatus): boolean {
  // consent_denied / consent_expired must never be visually indistinguishable from "still waiting" (Section 7.1).
  return status === 'consent_denied' || status === 'consent_expired';
}
