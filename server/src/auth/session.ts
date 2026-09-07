import { v4 as uuid } from 'uuid';

export type Role = 'member_primary' | 'member_dependent' | 'provider_doctor' | 'provider_clinic_admin' | 'platform_admin';

export interface Session {
  token: string;
  userId: string;
  role: Role;
  displayName: string;
  memberId: string | null;
  familyId: string | null;
  providerId: string | null;
}

// In-memory session store — adequate for a single-process dev/demo deployment.
// A production build should swap this for signed JWTs or a shared session store.
const sessions = new Map<string, Session>();

export function createSession(data: Omit<Session, 'token'>): Session {
  const token = uuid();
  const session = { token, ...data };
  sessions.set(token, session);
  return session;
}

export function getSession(token: string | undefined): Session | undefined {
  if (!token) return undefined;
  return sessions.get(token);
}

export function destroySession(token: string) {
  sessions.delete(token);
}
