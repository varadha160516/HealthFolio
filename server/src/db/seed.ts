import { v4 as uuid } from 'uuid';
import { db, now } from './db.js';
import { loadDictionary } from '../dictionary/loader.js';
import { hashPassword } from '../auth/hash.js';

/**
 * Seeds a demo household matching the PRD's reference family (self, spouse,
 * 2 children, 2 senior parents) plus one clinic/doctor and a platform admin,
 * so the app is usable the moment it starts. Idempotent.
 */
export function seed() {
  const dictionaryVersion = loadDictionary();

  const existing = db.prepare('SELECT 1 FROM families LIMIT 1').get();
  if (existing) {
    console.log(`Dictionary at v${dictionaryVersion}. Demo data already present, skipping seed.`);
    return;
  }

  const familyId = uuid();
  db.prepare('INSERT INTO families (id, primary_member_id, created_at) VALUES (?, NULL, ?)').run(familyId, now());

  const insertMember = db.prepare(`
    INSERT INTO members (id, family_id, name, dob, sex, blood_group, relationship_to_primary, login_credentials_ref, created_at)
    VALUES (@id, @family_id, @name, @dob, @sex, @blood_group, @relationship_to_primary, @login_credentials_ref, @created_at)
  `);

  const members = [
    { id: uuid(), name: 'Priya Sharma', dob: '1986-04-12', sex: 'female', blood_group: 'O+', relationship_to_primary: 'self' },
    { id: uuid(), name: 'Rohan Sharma', dob: '1984-09-02', sex: 'male', blood_group: 'B+', relationship_to_primary: 'spouse' },
    { id: uuid(), name: 'Aarav Sharma', dob: '2014-01-20', sex: 'male', blood_group: 'O+', relationship_to_primary: 'child' },
    { id: uuid(), name: 'Diya Sharma', dob: '2017-07-08', sex: 'female', blood_group: 'B+', relationship_to_primary: 'child' },
    { id: uuid(), name: 'Suresh Sharma', dob: '1954-03-15', sex: 'male', blood_group: 'A+', relationship_to_primary: 'parent' },
    { id: uuid(), name: 'Lakshmi Sharma', dob: '1957-11-30', sex: 'female', blood_group: 'A+', relationship_to_primary: 'parent' },
  ];
  for (const m of members) {
    insertMember.run({ ...m, family_id: familyId, login_credentials_ref: null, created_at: now() });
  }
  const primary = members[0];
  db.prepare('UPDATE families SET primary_member_id = ? WHERE id = ?').run(primary.id, familyId);

  const primaryUserId = uuid();
  db.prepare(`
    INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at)
    VALUES (?, ?, ?, 'member_primary', ?, ?, NULL, ?)
  `).run(primaryUserId, 'priya@example.com', hashPassword('password123'), primary.name, primary.id, now());
  db.prepare('UPDATE members SET login_credentials_ref = ? WHERE id = ?').run(primaryUserId, primary.id);

  const clinicId = uuid();
  db.prepare('INSERT INTO clinics (id, name) VALUES (?, ?)').run(clinicId, 'Sunrise Family Clinic');

  const providerId = uuid();
  db.prepare('INSERT INTO providers (id, type, name, specialty, clinic_id) VALUES (?, ?, ?, ?, ?)')
    .run(providerId, 'doctor', 'Dr. Ananya Rao', 'General Medicine', clinicId);
  db.prepare(`
    INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at)
    VALUES (?, ?, ?, 'provider_doctor', ?, NULL, ?, ?)
  `).run(uuid(), 'dr.rao@example.com', hashPassword('password123'), 'Dr. Ananya Rao', providerId, now());

  const frontDeskProviderId = uuid();
  db.prepare('INSERT INTO providers (id, type, name, specialty, clinic_id) VALUES (?, ?, ?, ?, ?)')
    .run(frontDeskProviderId, 'clinic_admin', 'Front Desk', null, clinicId);
  db.prepare(`
    INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at)
    VALUES (?, ?, ?, 'provider_clinic_admin', ?, NULL, ?, ?)
  `).run(uuid(), 'frontdesk@example.com', hashPassword('password123'), 'Front Desk — Sunrise Clinic', frontDeskProviderId, now());

  db.prepare(`
    INSERT INTO users (id, email, password_hash, role, display_name, member_id, provider_id, created_at)
    VALUES (?, ?, ?, 'platform_admin', ?, NULL, NULL, ?)
  `).run(uuid(), 'admin@careloop.app', hashPassword('password123'), 'CareLoop Admin', now());

  // A ready-to-use appointment so the check-in/consent flow can be demoed immediately.
  const apptId = uuid();
  const apptTime = new Date(Date.now() + 30 * 60 * 1000).toISOString();
  db.prepare(`
    INSERT INTO appointments (id, member_id, provider_id, datetime, status, sharing_preference, consent_grant_id, created_at, updated_at)
    VALUES (?, ?, ?, ?, 'scheduled', 'full_history', NULL, ?, ?)
  `).run(apptId, primary.id, providerId, apptTime, now(), now());

  console.log(`Seeded demo family "${familyId}" at dictionary v${dictionaryVersion}.`);
  console.log('Login as: priya@example.com / password123 (member_primary)');
  console.log('          dr.rao@example.com / password123 (provider_doctor)');
  console.log('          frontdesk@example.com / password123 (provider_clinic_admin)');
  console.log('          admin@careloop.app / password123 (platform_admin)');
}
