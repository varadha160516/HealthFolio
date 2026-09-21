import crypto from 'node:crypto';
import { db } from './db/db.js';
import { toWaNumber } from './whatsapp.js';

// Patient invites. A clinic invites someone to HealthFolio with a WhatsApp message (a wa.me link, opened
// on the clinic's own phone — same mechanism as whatsapp.ts, nothing is sent by CareLoop). The message
// carries a one-time code, and that code is what makes sign-up possible at all: HealthFolio has no open
// registration. It keeps a pilot invite-only, and because the code only ever travels to the invited
// person's own WhatsApp number, holding it is also what lets someone the front desk registered at the
// counter claim their existing record instead of starting a second, empty one.

export const INVITE_TTL_DAYS = 14;
export const INVITES_PER_PROVIDER_PER_DAY = 50;

// No 0/O/1/I/L: the code is read off a phone screen and typed by hand.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export function newInviteCode(): string {
  let out = '';
  for (const b of crypto.randomBytes(8)) out += ALPHABET[b % ALPHABET.length];
  return out;
}

/** What a person types back: any case, with or without the dash or spaces. */
export function normalizeInviteCode(input: unknown): string {
  return String(input ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export function displayInviteCode(code: string): string {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

/** Where the app can be installed from. Deliberately not hard-coded: there is no store listing yet, so
 * whoever runs the server points this at wherever the build lives. Without it there is nothing useful to
 * send, so inviting is switched off rather than sending a message that can't be acted on. */
export function downloadUrl(): string | null {
  const url = (process.env.HEALTHFOLIO_DOWNLOAD_URL ?? '').trim();
  return /^https?:\/\/\S+$/.test(url) ? url : null;
}

/** Is there already a HealthFolio login on this number? Compared on the last 10 digits, like the front
 * desk's lookup, so +91 / spaces / a leading 0 don't matter. */
export function phoneHasAccount(waNumber: string): boolean {
  const last10 = waNumber.slice(-10);
  const rows = db.prepare('SELECT m.phone AS phone FROM members m JOIN users u ON u.member_id = m.id WHERE m.phone IS NOT NULL').all() as { phone: string }[];
  return rows.some((r) => (toWaNumber(r.phone) ?? '').slice(-10) === last10);
}

export function inviteMessage(opts: { sender: string; firstName: string | null; code: string; expiresAt: string; url: string }): string {
  const expires = new Date(opts.expiresAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
  return (
    `Hello${opts.firstName ? ` ${opts.firstName}` : ''}, ${opts.sender} invites you to HealthFolio — one app for your family's lab reports, prescriptions and medicines. ` +
    `Your records stay private and are only shared with a doctor when you approve it.\n\n` +
    `1. Install: ${opts.url}\n` +
    `2. Open the app, tap "Join with an invite code" and enter ${displayInviteCode(opts.code)}\n\n` +
    `The code works once and expires on ${expires}.`
  );
}
