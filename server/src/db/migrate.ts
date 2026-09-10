import type { Db } from './db.js';

/**
 * `CREATE TABLE IF NOT EXISTS` in schema.sql only defines the shape for a brand-new database —
 * it's a no-op against a table that already exists, so evolving the schema on a live database
 * (this one already has real uploaded documents/extracted values) needs actual ALTER TABLE
 * migrations. Each one is idempotent (checks PRAGMA table_info first) so this is safe to run on
 * every startup regardless of which migrations have already applied.
 */
export function runMigrations(db: Db) {
  migratePrescriptionsForMemberUploads(db);
  migrateAppointmentsAllowCancelled(db);
  migrateLabTestBookingsAllowCancelled(db);

  // Profile tab fields — kept on `members` rather than duplicated anywhere else, since these are
  // stable facts about the person, not derived from uploads.
  ensureColumn(db, 'members', 'phone', 'TEXT');
  ensureColumn(db, 'members', 'address', 'TEXT');
  ensureColumn(db, 'members', 'emergency_contact_name', 'TEXT');
  ensureColumn(db, 'members', 'emergency_contact_phone', 'TEXT');
  ensureColumn(db, 'members', 'emergency_contact_relationship', 'TEXT');
  ensureColumn(db, 'members', 'organ_donor_status', 'TEXT'); // 'yes' | 'no' | 'unknown' | null
  ensureColumn(db, 'members', 'primary_physician_name', 'TEXT');
  ensureColumn(db, 'members', 'primary_physician_phone', 'TEXT');

  // Nearby-doctor search + preferred-doctor booking.
  ensureColumn(db, 'clinics', 'address', 'TEXT');
  ensureColumn(db, 'clinics', 'city', 'TEXT');
  ensureColumn(db, 'clinics', 'latitude', 'REAL');
  ensureColumn(db, 'clinics', 'longitude', 'REAL');
  ensureColumn(db, 'providers', 'availability_note', 'TEXT');
  db.exec(`
    CREATE TABLE IF NOT EXISTS preferred_providers (
      id TEXT PRIMARY KEY,
      member_id TEXT NOT NULL REFERENCES members(id),
      provider_id TEXT NOT NULL REFERENCES providers(id),
      created_at TEXT NOT NULL,
      UNIQUE(member_id, provider_id)
    )
  `);

  // AI health-chat conversation log.
  db.exec(`
    CREATE TABLE IF NOT EXISTS chat_messages (
      id TEXT PRIMARY KEY,
      member_id TEXT NOT NULL REFERENCES members(id),
      asked_by_user_id TEXT NOT NULL REFERENCES users(id),
      role TEXT NOT NULL CHECK (role IN ('user','assistant')),
      content TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  `);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_chat_messages_member ON chat_messages (member_id, created_at)`);

  // Health insights agent (PRD Section 13.1) — cached trend-summary text.
  db.exec(`
    CREATE TABLE IF NOT EXISTS health_insights (
      member_id TEXT PRIMARY KEY REFERENCES members(id),
      summary TEXT NOT NULL,
      data_signature TEXT NOT NULL,
      generated_at TEXT NOT NULL
    )
  `);

  // Consent explainer agent — cached plain-language explanation of one consent request.
  db.exec(`
    CREATE TABLE IF NOT EXISTS consent_explanations (
      consent_grant_id TEXT PRIMARY KEY REFERENCES consent_grants(id),
      explanation TEXT NOT NULL,
      generated_at TEXT NOT NULL
    )
  `);

  // Pre-visit prep agent (Roadmap Section 2.6).
  ensureColumn(db, 'appointments', 'reason_for_visit', 'TEXT');
  db.exec(`
    CREATE TABLE IF NOT EXISTS previsit_briefs (
      appointment_id TEXT PRIMARY KEY REFERENCES appointments(id),
      brief TEXT NOT NULL,
      generated_at TEXT NOT NULL
    )
  `);

  // Symptom intake agent (Roadmap Section 2.4) + its Symptoms & Observations tab.
  db.exec(`
    CREATE TABLE IF NOT EXISTS symptom_entries (
      id TEXT PRIMARY KEY,
      member_id TEXT NOT NULL REFERENCES members(id),
      logged_by_user_id TEXT NOT NULL REFERENCES users(id),
      status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress','completed')),
      raw_description TEXT NOT NULL,
      onset TEXT,
      severity TEXT,
      duration TEXT,
      associated_factors TEXT,
      urgent_flag INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  db.exec(`
    CREATE TABLE IF NOT EXISTS symptom_intake_messages (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES symptom_entries(id),
      role TEXT NOT NULL CHECK (role IN ('user','assistant')),
      content TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  `);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_symptom_intake_messages_entry ON symptom_intake_messages (entry_id, created_at)`);

  // Archive a family member (hide from listings, keep all their history) rather than deleting.
  ensureColumn(db, 'members', 'archived_at', 'TEXT');

  // Medication Manager — tracked schedules (manual or from a reviewed prescription import) plus
  // their logged dose events.
  db.exec(`
    CREATE TABLE IF NOT EXISTS medication_schedules (
      id TEXT PRIMARY KEY,
      member_id TEXT NOT NULL REFERENCES members(id),
      prescription_line_item_id TEXT REFERENCES prescription_line_items(id),
      medicine_name TEXT NOT NULL,
      strength TEXT,
      dose_amount TEXT,
      frequency TEXT NOT NULL CHECK (frequency IN ('daily','weekly','as_needed')),
      times TEXT NOT NULL DEFAULT '[]',
      day_of_week INTEGER,
      start_date TEXT NOT NULL,
      end_date TEXT,
      prescribed_by TEXT,
      purpose TEXT,
      status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','stopped')),
      created_at TEXT NOT NULL
    )
  `);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_medication_schedules_member ON medication_schedules (member_id, status)`);
  db.exec(`
    CREATE TABLE IF NOT EXISTS medication_dose_logs (
      id TEXT PRIMARY KEY,
      schedule_id TEXT NOT NULL REFERENCES medication_schedules(id),
      member_id TEXT NOT NULL REFERENCES members(id),
      dose_date TEXT NOT NULL,
      dose_time TEXT,
      status TEXT NOT NULL CHECK (status IN ('taken','skipped')),
      logged_at TEXT NOT NULL
    )
  `);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_medication_dose_logs_schedule ON medication_dose_logs (schedule_id, dose_date)`);

  // Lab Tests — small fixed catalog + bookings (member or guest).
  db.exec(`
    CREATE TABLE IF NOT EXISTS lab_test_catalog (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT,
      price REAL NOT NULL,
      turnaround_label TEXT
    )
  `);
  db.exec(`
    CREATE TABLE IF NOT EXISTS lab_test_bookings (
      id TEXT PRIMARY KEY,
      family_id TEXT NOT NULL REFERENCES families(id),
      member_id TEXT REFERENCES members(id),
      guest_name TEXT,
      guest_age INTEGER,
      guest_mobile TEXT,
      test_names TEXT NOT NULL,
      lab_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'collection_scheduled' CHECK (status IN ('collection_scheduled','processing','report_ready','cancelled')),
      booked_date TEXT NOT NULL,
      document_id TEXT REFERENCES documents(id),
      created_at TEXT NOT NULL
    )
  `);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_lab_test_bookings_member ON lab_test_bookings (member_id)`);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_lab_test_bookings_family ON lab_test_bookings (family_id)`);
  // Collection time window (e.g. "07:00-09:00") — the flow now lets a member pick this explicitly
  // instead of the booking date being silently computed server-side.
  ensureColumn(db, 'lab_test_bookings', 'time_slot', 'TEXT');
  seedLabTestCatalog(db);

  // Health Analysis redesign — sub-groups within a category (e.g. "RBC Profile"/"WBC Profile"
  // within CBC) for the panel-grouped comparison view. No such grouping existed before; every CBC
  // parameter dictionary entry was flat under category='CBC'.
  ensureColumn(db, 'canonical_parameters', 'sub_panel', 'TEXT');
  backfillSubPanels(db);

  // Doctor App — structured diagnosis code, provider-ordered lab tests, per-visit clinical notes,
  // and a small real notification feed. See schema.sql for the full column/table comments.
  ensureColumn(db, 'prescriptions', 'icd_code', 'TEXT');
  ensureColumn(db, 'member_vitals_entries', 'appointment_id', 'TEXT REFERENCES appointments(id)');
  ensureColumn(db, 'appointments', 'is_follow_up', 'INTEGER NOT NULL DEFAULT 0');
  ensureColumn(db, 'lab_test_bookings', 'ordered_by_provider_id', 'TEXT REFERENCES providers(id)');
  ensureColumn(db, 'lab_test_bookings', 'appointment_id', 'TEXT REFERENCES appointments(id)');
  ensureColumn(db, 'lab_test_bookings', 'clinical_indication', 'TEXT');
  db.exec(`
    CREATE TABLE IF NOT EXISTS consultation_notes (
      appointment_id TEXT PRIMARY KEY REFERENCES appointments(id),
      provider_id TEXT NOT NULL REFERENCES providers(id),
      member_id TEXT NOT NULL REFERENCES members(id),
      chief_complaint TEXT,
      symptom_duration TEXT,
      symptoms TEXT,
      examination TEXT,
      assessment_notes TEXT,
      advice TEXT,
      follow_up_after TEXT,
      follow_up_reason TEXT,
      follow_up_appointment_id TEXT REFERENCES appointments(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  `);
  db.exec(`
    CREATE TABLE IF NOT EXISTS provider_notifications (
      id TEXT PRIMARY KEY,
      provider_id TEXT NOT NULL REFERENCES providers(id),
      type TEXT NOT NULL CHECK (type IN ('lab_report_ready','appointment_cancelled')),
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      related_appointment_id TEXT REFERENCES appointments(id),
      created_at TEXT NOT NULL,
      read_at TEXT
    )
  `);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_provider_notifications_provider ON provider_notifications (provider_id, created_at DESC)`);
  db.exec(`
    CREATE TABLE IF NOT EXISTS invoices (
      id TEXT PRIMARY KEY,
      appointment_id TEXT NOT NULL REFERENCES appointments(id),
      member_id TEXT NOT NULL REFERENCES members(id),
      provider_id TEXT NOT NULL REFERENCES providers(id),
      fee_amount REAL NOT NULL,
      currency TEXT NOT NULL DEFAULT 'INR',
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','cancelled')),
      payment_method TEXT CHECK (payment_method IN ('card','upi','netbanking') OR payment_method IS NULL),
      paid_at TEXT,
      issued_at TEXT NOT NULL
    )
  `);
  db.exec(`
    CREATE TABLE IF NOT EXISTS pharmacy_orders (
      id TEXT PRIMARY KEY,
      member_id TEXT NOT NULL REFERENCES members(id),
      prescription_id TEXT REFERENCES prescriptions(id),
      line_items TEXT NOT NULL DEFAULT '[]',
      delivery_address TEXT,
      status TEXT NOT NULL DEFAULT 'placed' CHECK (status IN ('placed','delivered','cancelled')),
      estimated_delivery_date TEXT,
      created_at TEXT NOT NULL
    )
  `);

  // Doctor App's "select lab tests" sheet reads the full catalog — the original 5-row "popular"
  // seed was fine for the member app's own quick-book flow, but too thin for a doctor ordering
  // from a real category list. Adds the rest idempotently (INSERT OR IGNORE by id) rather than
  // re-running seedLabTestCatalog, which no-ops once the table is non-empty.
  expandLabTestCatalog(db);
}

/** Best-effort backfill by display_name pattern, not a hand-curated per-row mapping — the
 * parameter dictionary has no existing sub-panel concept to draw from. Only touches CBC today
 * (the panel the redesign actually needs); safe to extend to other categories later the same way.
 * Re-runs harmlessly on every startup (idempotent UPDATEs, not gated on a "already migrated" check
 * since re-applying the same pattern match is a no-op). */
function backfillSubPanels(db: Db) {
  const rbc = ['%hemoglobin%', '%rbc%', '%hematocrit%', '%mcv%', '%mch%', '%rdw%', '%red cell%', '%nucleated red%'];
  const wbc = ['%wbc%', '%leucocyte%', '%leukocyte%', '%neutrophil%', '%lymphocyte%', '%monocyte%', '%eosinophil%', '%basophil%', '%granulocyte%'];
  const platelet = ['%platelet%', '%mpv%', '%pdw%', '%plateletcrit%', '%pct%'];

  const apply = (patterns: string[], label: string) => {
    for (const p of patterns) {
      db.prepare(`UPDATE canonical_parameters SET sub_panel = ? WHERE category = 'CBC' AND sub_panel IS NULL AND lower(display_name) LIKE ?`).run(label, p);
    }
  };
  apply(rbc, 'RBC Profile');
  apply(wbc, 'WBC Profile');
  apply(platelet, 'Platelet Profile');
}

/** One-time seed for the fixed lab-test catalog — there's no real lab-partner catalog/pricing
 * integration, so this is a small fixed list good enough to book against. Only inserts if the
 * table is empty, so it's safe to call on every startup. */
function seedLabTestCatalog(db: Db) {
  const { count } = db.prepare('SELECT COUNT(*) as count FROM lab_test_catalog').get() as { count: number };
  if (count > 0) return;
  const tests: [string, string, string, number, string][] = [
    ['lt-cbc', 'Complete Blood Count', 'popular', 399, 'Reports in 6 hrs'],
    ['lt-thyroid', 'Thyroid Profile', 'popular', 549, 'Reports in 24 hrs'],
    ['lt-hba1c', 'HbA1c', 'popular', 449, 'Reports in 6 hrs'],
    ['lt-vitd', 'Vitamin D', 'popular', 899, 'Reports in 24 hrs'],
    ['lt-lft', 'Liver Function Test', 'popular', 699, 'Reports in 24 hrs'],
  ];
  const insert = db.prepare('INSERT INTO lab_test_catalog (id, name, category, price, turnaround_label) VALUES (?, ?, ?, ?, ?)');
  for (const t of tests) insert.run(...t);
}

/** Adds the rest of a general-practice-clinic-sized catalog alongside the original 5 "popular"
 * entries (left untouched — the member app's own quick-book screen groups by that category).
 * Idempotent per row (INSERT OR IGNORE by id), so safe on every startup regardless of what's
 * already there. */
function expandLabTestCatalog(db: Db) {
  const tests: [string, string, string, number, string][] = [
    ['lt-lipid', 'Lipid Profile', 'blood', 599, 'Reports in 24 hrs'],
    ['lt-kft', 'Kidney Function Test', 'blood', 649, 'Reports in 24 hrs'],
    ['lt-crp', 'CRP', 'blood', 499, 'Reports in 24 hrs'],
    ['lt-dengue', 'Dengue NS1', 'blood', 799, 'Reports in 24 hrs'],
    ['lt-widal', 'Widal Test', 'blood', 349, 'Reports in 24 hrs'],
    ['lt-malaria', 'Malaria Antigen', 'blood', 399, 'Reports in 6 hrs'],
    ['lt-esr', 'ESR', 'blood', 199, 'Reports in 6 hrs'],
    ['lt-urine-routine', 'Routine Urine Examination', 'urine', 249, 'Reports in 6 hrs'],
    ['lt-urine-culture', 'Urine Culture', 'urine', 549, 'Reports in 48 hrs'],
    ['lt-xray-chest', 'X-Ray Chest', 'imaging', 449, 'Same day'],
    ['lt-usg-abdomen', 'Ultrasound Abdomen', 'imaging', 1299, 'Same day'],
    ['lt-ecg', 'ECG', 'imaging', 299, 'Same day'],
  ];
  const insert = db.prepare('INSERT OR IGNORE INTO lab_test_catalog (id, name, category, price, turnaround_label) VALUES (?, ?, ?, ?, ?)');
  for (const t of tests) insert.run(...t);
}

function ensureColumn(db: Db, table: string, column: string, definition: string) {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[];
  if (!cols.some((c) => c.name === column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
    console.log(`migrated: added ${table}.${column}`);
  }
}

/**
 * The original schema required appointment_id/provider_id on every prescription (true for
 * provider-issued e-prescriptions, Section 8.1) but member-uploaded prescription photos (Section
 * 3.4's first bullet) have neither — they were being inserted as NULL against a NOT NULL column,
 * which SQLite would reject the first time anyone actually uploaded one. Also adds document_id
 * so an uploaded prescription document can be linked back to its parsed line items at all (there
 * was no way to do that before). SQLite can't ALTER a column's NOT NULL away or add one mid-table,
 * so this is a full rebuild — the documented safe pattern (FK off, copy, drop, rename, FK on).
 */
function migratePrescriptionsForMemberUploads(db: Db) {
  const cols = db.prepare(`PRAGMA table_info(prescriptions)`).all() as { name: string; notnull: number }[];
  const appointmentCol = cols.find((c) => c.name === 'appointment_id');
  if (!appointmentCol) return; // table doesn't exist yet — schema.sql will create it correctly
  if (appointmentCol.notnull === 0) return; // already migrated

  const hasDocumentId = cols.some((c) => c.name === 'document_id');

  db.exec('PRAGMA foreign_keys = OFF');
  db.exec(`
    CREATE TABLE prescriptions_migrated (
      id TEXT PRIMARY KEY,
      appointment_id TEXT REFERENCES appointments(id),
      provider_id TEXT REFERENCES providers(id),
      member_id TEXT NOT NULL REFERENCES members(id),
      document_id TEXT REFERENCES documents(id),
      diagnosis_text TEXT,
      notes TEXT,
      issued_at TEXT NOT NULL
    );
    INSERT INTO prescriptions_migrated (id, appointment_id, provider_id, member_id, document_id, diagnosis_text, notes, issued_at)
      SELECT id, appointment_id, provider_id, member_id, ${hasDocumentId ? 'document_id' : 'NULL'}, diagnosis_text, notes, issued_at FROM prescriptions;
    DROP TABLE prescriptions;
    ALTER TABLE prescriptions_migrated RENAME TO prescriptions;
  `);
  db.exec('PRAGMA foreign_keys = ON');
  console.log('migrated: prescriptions.appointment_id/provider_id are now nullable (member-uploaded prescriptions have neither), added document_id');
}

/**
 * SQLite CHECK constraints can't be altered in place — adding 'cancelled' as a real status
 * (member-initiated cancel) needs the same full-rebuild pattern as migratePrescriptionsForMemberUploads
 * above. Found the hard way: shipped the state machine and route changes without this migration,
 * and every real cancel attempt against the already-existing dev database failed with a raw SQLite
 * CHECK-constraint error (500) rather than the intended 200 — the column's CHECK clause only knew
 * about the original 8 statuses.
 */
function migrateAppointmentsAllowCancelled(db: Db) {
  const row = db.prepare(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'appointments'`).get() as { sql: string } | undefined;
  if (!row) return; // table doesn't exist yet — schema.sql will create it correctly
  if (row.sql.includes("'cancelled'")) return; // already migrated

  db.exec('PRAGMA foreign_keys = OFF');
  db.exec(`
    CREATE TABLE appointments_migrated (
      id TEXT PRIMARY KEY,
      member_id TEXT NOT NULL REFERENCES members(id),
      provider_id TEXT NOT NULL REFERENCES providers(id),
      datetime TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','checked_in','consent_requested','consent_granted','in_consultation','completed','consent_denied','consent_expired','cancelled')),
      sharing_preference TEXT CHECK (sharing_preference IN ('summary_card','full_history') OR sharing_preference IS NULL),
      reason_for_visit TEXT,
      consent_grant_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    INSERT INTO appointments_migrated (id, member_id, provider_id, datetime, status, sharing_preference, reason_for_visit, consent_grant_id, created_at, updated_at)
      SELECT id, member_id, provider_id, datetime, status, sharing_preference, reason_for_visit, consent_grant_id, created_at, updated_at FROM appointments;
    DROP TABLE appointments;
    ALTER TABLE appointments_migrated RENAME TO appointments;
  `);
  db.exec('PRAGMA foreign_keys = ON');
  console.log("migrated: appointments.status CHECK constraint now allows 'cancelled'");
}

/** Same rebuild pattern as migrateAppointmentsAllowCancelled, for the lab_test_bookings CHECK
 * constraint — member-initiated cancel needs 'cancelled' as a real status here too. */
function migrateLabTestBookingsAllowCancelled(db: Db) {
  const row = db.prepare(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'lab_test_bookings'`).get() as { sql: string } | undefined;
  if (!row) return; // table doesn't exist yet — schema.sql will create it correctly
  if (row.sql.includes("'cancelled'")) return; // already migrated

  db.exec('PRAGMA foreign_keys = OFF');
  db.exec(`
    CREATE TABLE lab_test_bookings_migrated (
      id TEXT PRIMARY KEY,
      family_id TEXT NOT NULL REFERENCES families(id),
      member_id TEXT REFERENCES members(id),
      guest_name TEXT,
      guest_age INTEGER,
      guest_mobile TEXT,
      test_names TEXT NOT NULL,
      lab_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'collection_scheduled' CHECK (status IN ('collection_scheduled','processing','report_ready','cancelled')),
      booked_date TEXT NOT NULL,
      time_slot TEXT,
      document_id TEXT REFERENCES documents(id),
      created_at TEXT NOT NULL
    );
    INSERT INTO lab_test_bookings_migrated (id, family_id, member_id, guest_name, guest_age, guest_mobile, test_names, lab_name, status, booked_date, time_slot, document_id, created_at)
      SELECT id, family_id, member_id, guest_name, guest_age, guest_mobile, test_names, lab_name, status, booked_date, time_slot, document_id, created_at FROM lab_test_bookings;
    DROP TABLE lab_test_bookings;
    ALTER TABLE lab_test_bookings_migrated RENAME TO lab_test_bookings;
    CREATE INDEX IF NOT EXISTS idx_lab_test_bookings_member ON lab_test_bookings (member_id);
    CREATE INDEX IF NOT EXISTS idx_lab_test_bookings_family ON lab_test_bookings (family_id);
  `);
  db.exec('PRAGMA foreign_keys = ON');
  console.log("migrated: lab_test_bookings.status CHECK constraint now allows 'cancelled'");
}
