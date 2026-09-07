import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { loadDictionary } from '../dictionary/loader.js';

let dictionaryLoaded = false;

export function ensureDictionary() {
  if (!dictionaryLoaded) {
    loadDictionary();
    dictionaryLoaded = true;
  }
}

export function makeMember(name = 'Test Member'): string {
  const familyId = uuid();
  const memberId = uuid();
  db.prepare('INSERT INTO families (id, primary_member_id, created_at) VALUES (?, ?, ?)').run(familyId, memberId, now());
  db.prepare(
    `INSERT INTO members (id, family_id, name, dob, sex, blood_group, relationship_to_primary, login_credentials_ref, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'self', NULL, ?)`
  ).run(memberId, familyId, name, '1990-01-01', 'female', 'O+', now());
  return memberId;
}

export function makeUser(memberId: string): string {
  const userId = uuid();
  db.prepare(
    `INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at) VALUES (?, ?, 'x', 'member_primary', 'Test', ?, NULL, ?)`
  ).run(userId, `${userId}@test.local`, memberId, now());
  return userId;
}

export function makeProvider(name = 'Dr. Test'): string {
  const providerId = uuid();
  db.prepare(`INSERT INTO providers (id, type, name, specialty, clinic_id) VALUES (?, 'doctor', ?, NULL, NULL)`).run(providerId, name);
  return providerId;
}

export function makeAppointment(memberId: string, providerId: string, status = 'scheduled'): string {
  const id = uuid();
  db.prepare(
    `INSERT INTO appointments (id, member_id, provider_id, datetime, status, sharing_preference, consent_grant_id, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 'full_history', NULL, ?, ?)`
  ).run(id, memberId, providerId, now(), status, now(), now());
  return id;
}

export function makeDocumentStub(memberId: string, uploadedByUserId: string, documentType = 'lab_report'): string {
  const docId = uuid();
  db.prepare(
    `INSERT INTO documents (id, member_id, uploaded_by_user_id, document_type, presentation_style, storage_path, checksum, lab_visit_id, page_count, upload_date, test_date, source_lab_name, status, origin, created_at)
     VALUES (?, ?, ?, ?, NULL, '/tmp', 'testchecksum', NULL, 1, ?, NULL, NULL, 'processing', 'member_upload', ?)`
  ).run(docId, memberId, uploadedByUserId, documentType, now(), now());
  return docId;
}
