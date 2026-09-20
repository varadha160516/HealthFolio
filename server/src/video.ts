import crypto from 'node:crypto';

// Video consultations run on a Jitsi Meet room. The base URL is configurable so a clinic (or a
// production deployment) can point at its own self-hosted Jitsi instead of the public one — the
// public server is fine for trying this out, but a real deployment handling patient calls should
// run its own. Rooms are never created by an API call: a Jitsi room exists the moment two people
// open its URL, so the only "credential" is the room name, which is why it is long and random and
// only ever handed to the two people on the appointment (see routes/teleconsult.ts).
export function videoBaseUrl(): string {
  return (process.env.VIDEO_BASE_URL || 'https://meet.jit.si').replace(/\/+$/, '');
}

export function newRoomName(): string {
  return `careloop-${crypto.randomBytes(16).toString('hex')}`;
}

/** The display name rides in the URL fragment, which the browser never sends to any server — Jitsi
 * reads it client-side to label the participant. */
export function joinUrl(room: string, displayName: string): string {
  return `${videoBaseUrl()}/${room}#userInfo.displayName=${encodeURIComponent(JSON.stringify(displayName))}`;
}
