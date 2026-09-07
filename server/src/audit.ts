import { v4 as uuid } from 'uuid';
import { db, now } from './db/db.js';

/** Section 7.4/8.3 — every grant/denial/revocation/access is logged and shown symmetrically to both sides. */
export function logAudit(actorId: string | null, actorRole: string, action: string, targetMemberId: string | null, metadata?: Record<string, unknown>) {
  db.prepare(`INSERT INTO audit_log (id, actor_id, actor_role, action, target_member_id, metadata_json, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)`).run(
    uuid(),
    actorId,
    actorRole,
    action,
    targetMemberId,
    metadata ? JSON.stringify(metadata) : null,
    now()
  );
}

export function getAuditLog(targetMemberId: string) {
  return db
    .prepare('SELECT * FROM audit_log WHERE target_member_id = ? ORDER BY timestamp DESC')
    .all(targetMemberId);
}
