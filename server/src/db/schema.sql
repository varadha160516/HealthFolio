-- CareLoop schema — implements the entities in PRD Section 10.
-- SQLite. All ids are UUID text. Timestamps are ISO8601 strings.

CREATE TABLE IF NOT EXISTS families (
  id TEXT PRIMARY KEY,
  primary_member_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS members (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES families(id),
  name TEXT NOT NULL,
  dob TEXT,
  sex TEXT CHECK (sex IN ('male','female','other') OR sex IS NULL),
  blood_group TEXT,
  relationship_to_primary TEXT NOT NULL, -- 'self' for the primary member
  login_credentials_ref TEXT, -- nullable: null = coordinator-managed, set = self-managed (user id)
  archived_at TEXT, -- set when the coordinator archives a dependent — hides them from listings without deleting any history
  -- Profile tab fields — stable facts about the person, not derived from uploads (vitals/BP/etc.
  -- are shown on the Profile tab too, but read live from extracted_parameters, not stored here).
  phone TEXT,
  address TEXT,
  emergency_contact_name TEXT,
  emergency_contact_phone TEXT,
  emergency_contact_relationship TEXT,
  organ_donor_status TEXT, -- 'yes' | 'no' | 'unknown' | null
  primary_physician_name TEXT,
  primary_physician_phone TEXT,
  created_at TEXT NOT NULL
);

-- A login resolves to exactly one role context (Section 2).
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('member_primary','member_dependent','provider_doctor','provider_clinic_admin','platform_admin')),
  display_name TEXT NOT NULL,
  member_id TEXT REFERENCES members(id), -- set when role is member_primary/member_dependent
  provider_id TEXT REFERENCES providers(id), -- set when role is provider_*
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS allergies (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  value TEXT NOT NULL,
  source_document_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chronic_conditions (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  value TEXT NOT NULL,
  source_document_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS documents (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  uploaded_by_user_id TEXT NOT NULL REFERENCES users(id),
  document_type TEXT NOT NULL CHECK (document_type IN ('prescription','lab_report','radiology_scan','discharge_summary','vaccination_record','insurance_policy','other')),
  presentation_style TEXT CHECK (presentation_style IN ('tabular','chart_infographic','narrative_handwritten') OR presentation_style IS NULL),
  storage_path TEXT NOT NULL,
  checksum TEXT NOT NULL,
  lab_visit_id TEXT, -- groups multi-page uploads (Section 3.3)
  page_count INTEGER NOT NULL DEFAULT 1,
  upload_date TEXT NOT NULL,
  test_date TEXT, -- the date printed on the document, once known
  source_lab_name TEXT,
  status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing','parsed','failed','manual_entry_required')),
  origin TEXT NOT NULL DEFAULT 'member_upload' CHECK (origin IN ('member_upload','provider_issued')),
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS canonical_parameters (
  canonical_parameter_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  category TEXT NOT NULL,
  sub_panel TEXT, -- optional finer grouping within a category, e.g. "RBC Profile" within CBC
  canonical_unit TEXT NOT NULL,
  range_type TEXT NOT NULL CHECK (range_type IN ('fixed_range','open_upper_bound','open_lower_bound','interpretive_rule','qualitative','none')),
  typical_low REAL,
  typical_high REAL,
  aliases_json TEXT NOT NULL, -- JSON array of strings
  plausible_low REAL,
  plausible_high REAL,
  dictionary_version TEXT NOT NULL,
  loinc_code TEXT
);

CREATE TABLE IF NOT EXISTS dictionary_meta (
  version TEXT PRIMARY KEY,
  loaded_at TEXT NOT NULL,
  source TEXT NOT NULL,
  changelog TEXT
);

-- Extracted parameter time series (Section 3.2 #2, Section 10).
CREATE TABLE IF NOT EXISTS extracted_parameters (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES documents(id),
  member_id TEXT NOT NULL REFERENCES members(id),
  canonical_parameter_id TEXT REFERENCES canonical_parameters(canonical_parameter_id),
  raw_label_as_printed TEXT NOT NULL,
  value_raw TEXT NOT NULL,
  unit_raw TEXT,
  canonical_value REAL,
  canonical_unit TEXT,
  printed_reference_range_json TEXT, -- {low, high} or {text} as printed on the source doc, or null
  resolved_reference_range_json TEXT, -- the range actually used for flagging (Section 4.6)
  range_type TEXT,
  test_date TEXT NOT NULL,
  match_tier INTEGER, -- 1, 2, 3, or null (no match)
  match_confidence REAL,
  extraction_confidence REAL,
  confidence_score REAL,
  review_status TEXT NOT NULL DEFAULT 'pending_review' CHECK (review_status IN ('auto_accepted','pending_review','confirmed','corrected','rejected')),
  in_range_flag TEXT CHECK (in_range_flag IN ('in_range','out_of_range','no_flag') OR in_range_flag IS NULL),
  dictionary_version_at_parse_time TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_extracted_params_member_canon_date
  ON extracted_parameters (member_id, canonical_parameter_id, test_date);

-- Genuinely unmatched labels — dictionary-governance queue (Section 5.3, 4.4 tier 4).
CREATE TABLE IF NOT EXISTS new_parameter_candidates (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  document_id TEXT NOT NULL REFERENCES documents(id),
  extracted_parameter_id TEXT REFERENCES extracted_parameters(id),
  label_as_printed TEXT NOT NULL,
  value TEXT,
  unit TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','resolved_as_new_param','resolved_as_alias','resolved_as_interpretive_index')),
  resolved_canonical_parameter_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS clinics (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT,
  city TEXT,
  latitude REAL,
  longitude REAL
);

CREATE TABLE IF NOT EXISTS providers (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL CHECK (type IN ('doctor','clinic_admin')),
  name TEXT NOT NULL,
  specialty TEXT, -- one of the canonical specializations (see server/src/specializations.ts)
  clinic_id TEXT REFERENCES clinics(id),
  availability_note TEXT, -- free-text display only (e.g. "Mon-Fri, 10am-6pm") — superseded for real
  -- scheduling by provider_availability/provider_time_off below, but kept as a human-readable summary
  default_fee REAL, -- prefills (doesn't force) the per-visit fee prompt on Complete Visit
  registration_number TEXT, -- medical council registration/license number, self-declared (not verified against any registry)
  qualifications TEXT, -- free text, e.g. "MBBS, MD (General Medicine)"
  years_of_experience INTEGER,
  gst_number TEXT, -- shown on invoices; self-declared, not validated against any tax authority
  -- Visual signature only (a stamped image), not a legally-binding e-signature -- this app has no
  -- document-generation/PKI/timestamp-authority layer behind it.
  signature_base64 TEXT,
  -- Payout details for the doctor's own records. Stored as plain fields, same security posture as
  -- the rest of this demo app (no encryption-at-rest) -- fine for practice-management bookkeeping,
  -- not for real production banking credentials. Inert until a real payment gateway exists.
  bank_account_name TEXT,
  bank_account_number TEXT,
  bank_ifsc TEXT,
  bank_upi_id TEXT
);

-- Provider onboarding — a self-serve application, reviewed by a platform_admin before any
-- providers/users row is created. Nothing here is login-capable on its own; only approval
-- creates the real account (see POST /admin/provider-applications/:id/approve).
CREATE TABLE IF NOT EXISTS provider_applications (
  id TEXT PRIMARY KEY,
  reference_code TEXT NOT NULL UNIQUE, -- short code the applicant keeps to check status/resubmit, since there's no email service to notify them
  email TEXT NOT NULL,
  password_hash TEXT NOT NULL, -- the applicant's chosen password, hashed at submission time so approval never needs to touch it in plaintext
  full_name TEXT NOT NULL,
  phone TEXT,
  role_requested TEXT NOT NULL CHECK (role_requested IN ('doctor','clinic_admin')),
  specialty TEXT,
  registration_number TEXT,
  qualifications TEXT,
  years_of_experience INTEGER,
  gst_number TEXT,
  default_fee REAL,
  clinic_mode TEXT NOT NULL CHECK (clinic_mode IN ('existing','new')),
  clinic_id TEXT REFERENCES clinics(id), -- set when clinic_mode = 'existing'
  new_clinic_name TEXT,
  new_clinic_address TEXT,
  new_clinic_city TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  rejection_reason TEXT,
  reviewed_by_user_id TEXT REFERENCES users(id),
  reviewed_at TEXT,
  created_provider_id TEXT REFERENCES providers(id), -- set once approved
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_provider_applications_status ON provider_applications (status, created_at DESC);

CREATE TABLE IF NOT EXISTS provider_application_documents (
  id TEXT PRIMARY KEY,
  application_id TEXT NOT NULL REFERENCES provider_applications(id),
  document_type TEXT NOT NULL CHECK (document_type IN ('registration_certificate','government_id','qualification_certificate','clinic_proof','other')),
  storage_path TEXT NOT NULL,
  filename TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- A member's saved/favorite doctors — bookable regardless of distance (unlike the
-- specialization-based nearby search, which is location-filtered).
CREATE TABLE IF NOT EXISTS preferred_providers (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  provider_id TEXT NOT NULL REFERENCES providers(id),
  created_at TEXT NOT NULL,
  UNIQUE(member_id, provider_id)
);

-- Section 7.1 state machine. Section 8.2: the single source of truth for both sides.
CREATE TABLE IF NOT EXISTS appointments (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  provider_id TEXT NOT NULL REFERENCES providers(id),
  datetime TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','checked_in','consent_requested','consent_granted','in_consultation','completed','consent_denied','consent_expired','cancelled')),
  sharing_preference TEXT CHECK (sharing_preference IN ('summary_card','full_history') OR sharing_preference IS NULL),
  reason_for_visit TEXT, -- member-stated, optional (Roadmap Section 2.6 — lets the pre-visit prep agent prioritize)
  consent_grant_id TEXT,
  -- Set when this row was created by a doctor's "schedule follow-up" action rather than a member
  -- booking — lets the Doctor App notifications feed find "follow-up due today" without guessing
  -- from reason_for_visit text.
  is_follow_up INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS consent_grants (
  id TEXT PRIMARY KEY,
  appointment_id TEXT NOT NULL REFERENCES appointments(id),
  member_id TEXT NOT NULL REFERENCES members(id),
  provider_id TEXT NOT NULL REFERENCES providers(id),
  method TEXT CHECK (method IN ('in_app','otp') OR method IS NULL),
  scope TEXT,
  requested_at TEXT,
  expires_at TEXT,
  granted_at TEXT,
  denied_at TEXT,
  revoked_at TEXT,
  otp_code TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS prescriptions (
  id TEXT PRIMARY KEY,
  -- Nullable: set for provider-issued e-prescriptions (Section 8.1), null for member-uploaded
  -- prescription photos (Section 3.4), which have document_id set instead.
  appointment_id TEXT REFERENCES appointments(id),
  provider_id TEXT REFERENCES providers(id),
  member_id TEXT NOT NULL REFERENCES members(id),
  document_id TEXT REFERENCES documents(id),
  diagnosis_text TEXT,
  -- Optional — the brief's own framing: "keep the ICD code secondary, the doctor shouldn't have
  -- to think about coding while clinically documenting." Free text, not validated against a real
  -- ICD-10 table.
  icd_code TEXT,
  notes TEXT,
  issued_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS prescription_line_items (
  id TEXT PRIMARY KEY,
  prescription_id TEXT NOT NULL REFERENCES prescriptions(id),
  medicine_name TEXT NOT NULL,
  strength TEXT,
  dosage TEXT,
  frequency TEXT,
  duration TEXT,
  instructions TEXT
);

-- Lab Tests: a small fixed catalog (no real lab-partner integration exists) and bookings against
-- it. member_id is nullable — a booking can be for a real family member OR a "just book a test"
-- guest, identified by the guest_* columns instead. This is the one place in the schema where a
-- health record is deliberately allowed to exist without a real members.id row.
CREATE TABLE IF NOT EXISTS lab_test_catalog (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT,
  price REAL NOT NULL,
  turnaround_label TEXT
);

CREATE TABLE IF NOT EXISTS lab_test_bookings (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES families(id),
  member_id TEXT REFERENCES members(id),
  guest_name TEXT,
  guest_age INTEGER,
  guest_mobile TEXT,
  test_names TEXT NOT NULL, -- JSON array of test names, as booked
  lab_name TEXT NOT NULL,
  -- 'pending_schedule' is a doctor-ordered test the member hasn't picked a collection date/slot
  -- for yet — a self-service booking skips straight to 'collection_scheduled' since the member
  -- already chose a date/time as part of booking it.
  status TEXT NOT NULL DEFAULT 'collection_scheduled' CHECK (status IN ('pending_schedule','collection_scheduled','processing','report_ready','cancelled')),
  booked_date TEXT, -- null while 'pending_schedule'
  time_slot TEXT, -- e.g. "07:00-09:00" — the member's chosen collection window
  -- Set once a report is attached — the report itself is a normal documents row (document_type =
  -- 'lab_report'), created via the existing upload+extraction pipeline, just linked back here.
  document_id TEXT REFERENCES documents(id),
  -- Set only for tests a doctor orders mid-consultation (Doctor App) — null for a member's own
  -- self-service booking, which is how most rows here still get created.
  ordered_by_provider_id TEXT REFERENCES providers(id),
  appointment_id TEXT REFERENCES appointments(id),
  clinical_indication TEXT,
  created_at TEXT NOT NULL
);

-- Medication Manager: a schedule the member (or an import review) has turned a prescription line
-- item — or a manual entry — into something actually tracked (dosage times, a duration, adherence
-- logging), as opposed to prescription_line_items above which is just the as-printed record of
-- what a prescription said.
CREATE TABLE IF NOT EXISTS medication_schedules (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  prescription_line_item_id TEXT REFERENCES prescription_line_items(id),
  medicine_name TEXT NOT NULL,
  strength TEXT,
  dose_amount TEXT,
  frequency TEXT NOT NULL CHECK (frequency IN ('daily','weekly','as_needed')),
  times TEXT NOT NULL DEFAULT '[]', -- JSON array of "HH:MM", empty for as_needed
  day_of_week INTEGER, -- 0=Sun..6=Sat, only meaningful for weekly
  start_date TEXT NOT NULL,
  end_date TEXT,
  prescribed_by TEXT,
  purpose TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','stopped')),
  created_at TEXT NOT NULL
);

-- Logged dose events only (taken/skipped) — "due"/"upcoming" for today's view is computed by
-- expanding a schedule's own times and checking whether a log exists yet, not stored per-slot.
CREATE TABLE IF NOT EXISTS medication_dose_logs (
  id TEXT PRIMARY KEY,
  schedule_id TEXT NOT NULL REFERENCES medication_schedules(id),
  member_id TEXT NOT NULL REFERENCES members(id),
  dose_date TEXT NOT NULL, -- YYYY-MM-DD
  dose_time TEXT, -- HH:MM; null for an as_needed log
  status TEXT NOT NULL CHECK (status IN ('taken','skipped')),
  logged_at TEXT NOT NULL
);

-- Cross-provider safety net (see server/src/pipeline/safetyNet.ts): structured-fact checks run
-- across a member's FULL active record — every prescriber, every lab order, self-booked or
-- doctor-ordered — something no single doctor can see given the app's per-visit consent model.
-- Deliberately the same conservative philosophy as medicationReconciliation.ts: name-matching
-- against recorded facts only, never a model guessing at pharmacology. Surfaced to the member/
-- family only, since they're the one party who legitimately sees the whole picture.
CREATE TABLE IF NOT EXISTS safety_flags (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  kind TEXT NOT NULL CHECK (kind IN ('cross_provider_duplicate_medication','allergy_conflict','duplicate_lab_test')),
  severity TEXT NOT NULL DEFAULT 'info' CHECK (severity IN ('info','warning')), -- no 'critical' tier — a nudge to discuss, never an emergency claim
  title TEXT NOT NULL,
  detail TEXT NOT NULL,
  related_json TEXT NOT NULL DEFAULT '{}', -- structured refs (schedule/booking ids, provider names, dates) so the UI can show its work
  dedupe_key TEXT NOT NULL, -- stable per (kind + the specific facts involved) so re-running the check never spams duplicate rows
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','dismissed','discussed')),
  created_at TEXT NOT NULL,
  resolved_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_safety_flags_member ON safety_flags (member_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS insurance_policies (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  payer_name TEXT NOT NULL,
  policy_number TEXT NOT NULL,
  sum_insured REAL,
  period_start TEXT,
  period_end TEXT,
  document_id TEXT REFERENCES documents(id)
);

-- AI health-chat conversation log, per member. A user (coordinator or self-managed dependent)
-- can ask about their own or a dependent's recent reports/consultations; history is kept so the
-- assistant has continuity across turns and so the conversation survives an app restart.
CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  asked_by_user_id TEXT NOT NULL REFERENCES users(id),
  role TEXT NOT NULL CHECK (role IN ('user','assistant')),
  content TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_member ON chat_messages (member_id, created_at);

-- Health insights agent (PRD Section 13.1) — a cached, display-only plain-language trend
-- summary for the Overview tab. Recomputed only when the member's underlying data actually
-- changes (data_signature), not on every screen view, since this calls a model.
CREATE TABLE IF NOT EXISTS health_insights (
  member_id TEXT PRIMARY KEY REFERENCES members(id),
  summary TEXT NOT NULL,
  data_signature TEXT NOT NULL,
  generated_at TEXT NOT NULL
);

-- Consent explainer agent (PRD Section 13.1 companion) — a cached, display-only plain-language
-- explanation of one consent request, shown to the member before they tap Approve/Deny. Keyed on
-- the grant, not the member, since a fresh grant means a fresh (re-request/resend) explanation.
CREATE TABLE IF NOT EXISTS consent_explanations (
  consent_grant_id TEXT PRIMARY KEY REFERENCES consent_grants(id),
  explanation TEXT NOT NULL,
  generated_at TEXT NOT NULL
);

-- Pre-visit prep agent (Roadmap Section 2.6) — a cached, display-only brief drafted the moment
-- access unlocks for this visit. Never served once the appointment leaves consent_granted/
-- in_consultation (see grantsDataAccess) — the route itself enforces that, this table just avoids
-- re-generating it on every poll while the visit is in progress.
CREATE TABLE IF NOT EXISTS previsit_briefs (
  appointment_id TEXT PRIMARY KEY REFERENCES appointments(id),
  brief TEXT NOT NULL,
  generated_at TEXT NOT NULL
);

-- Symptom intake agent (Roadmap Section 2.4) — structures a member's own free-text description
-- of how they're feeling into a dated entry (onset/severity/duration/associated factors) through
-- a short clarifying Q&A. The single most self-harm/health-anxiety adjacent agent in the roadmap:
-- it never diagnoses or estimates likelihood, only structures what the member said (see
-- server/src/pipeline/symptomIntake.ts for the guardrail implementation).
CREATE TABLE IF NOT EXISTS symptom_entries (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  logged_by_user_id TEXT NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress','completed')),
  raw_description TEXT NOT NULL, -- the member's own opening words, unedited
  onset TEXT,
  severity TEXT,
  duration TEXT,
  associated_factors TEXT,
  urgent_flag INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS symptom_intake_messages (
  id TEXT PRIMARY KEY,
  entry_id TEXT NOT NULL REFERENCES symptom_entries(id),
  role TEXT NOT NULL CHECK (role IN ('user','assistant')),
  content TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_symptom_intake_messages_entry ON symptom_intake_messages (entry_id, created_at);

-- Symmetric audit trail (Section 7.4 / 8.3).
CREATE TABLE IF NOT EXISTS audit_log (
  id TEXT PRIMARY KEY,
  actor_id TEXT,
  actor_role TEXT NOT NULL,
  action TEXT NOT NULL,
  target_member_id TEXT,
  metadata_json TEXT,
  timestamp TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_target_member ON audit_log (target_member_id, timestamp);

-- Dictionary curation agent (Roadmap Section 2.9) — half (a), reference-range drift flags. Each
-- row is a proposal only ("this canonical parameter's stored range might be worth re-checking"),
-- never an applied change — an admin reviews and edits canonical_parameters directly, same as
-- resolving a new_parameter_candidates row. note_basis is always 'model_knowledge': there's no
-- live reference-range research connector wired into this app yet (Roadmap Section 3), so this
-- is the model's own trained medical knowledge, not a cited external source — surfaced as such in
-- the admin UI rather than implied to be a live lookup.
CREATE TABLE IF NOT EXISTS dictionary_drift_flags (
  id TEXT PRIMARY KEY,
  canonical_parameter_id TEXT NOT NULL REFERENCES canonical_parameters(canonical_parameter_id),
  note TEXT NOT NULL,
  note_basis TEXT NOT NULL DEFAULT 'model_knowledge',
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','dismissed')),
  checked_at TEXT NOT NULL,
  resolved_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_drift_flags_status ON dictionary_drift_flags (status, checked_at);

-- Manual Vitals entry — member/coordinator self-reported readings (heart rate, blood pressure,
-- respiratory rate, SpO2, temperature, weight, height, head circumference), distinct from the
-- document-OCR-derived extracted_parameters pipeline. Growth percentiles (weight/height/BMI-for-
-- age) are computed on read from these values against real CDC reference data — see
-- server/src/pipeline/growthPercentile.ts — never stored, so they always reflect the member's
-- current age at read time rather than going stale.
CREATE TABLE IF NOT EXISTS member_vitals_entries (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  recorded_at TEXT NOT NULL,
  heart_rate REAL,
  systolic_bp REAL,
  diastolic_bp REAL,
  respiratory_rate REAL,
  spo2 REAL,
  temperature_f REAL,
  weight_kg REAL,
  height_cm REAL,
  head_circumference_cm REAL,
  logged_by_user_id TEXT NOT NULL REFERENCES users(id),
  -- Set only when a Doctor App consultation logged this entry, so a visit summary can show
  -- exactly the vitals taken at that visit rather than guessing from timestamps.
  appointment_id TEXT REFERENCES appointments(id),
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_vitals_entries_member ON member_vitals_entries (member_id, recorded_at DESC);

-- Doctor App: one row per appointment, holding everything about a consultation that isn't
-- already its own table (vitals -> member_vitals_entries, diagnosis/medications -> prescriptions,
-- tests -> lab_test_bookings). Upserted as the doctor works through the Consultation screen, so
-- appointment_id is the primary key rather than a generated id.
CREATE TABLE IF NOT EXISTS consultation_notes (
  appointment_id TEXT PRIMARY KEY REFERENCES appointments(id),
  provider_id TEXT NOT NULL REFERENCES providers(id),
  member_id TEXT NOT NULL REFERENCES members(id),
  chief_complaint TEXT,
  symptom_duration TEXT,
  symptoms TEXT, -- JSON array of strings
  examination TEXT, -- JSON object: {general:{condition,consciousness,hydration}, system:{respiratory:[...],cardiovascular:[...],abdomen:[...],cns:[...]}}
  assessment_notes TEXT,
  advice TEXT, -- JSON array of strings
  follow_up_after TEXT, -- '3_days' | '1_week' | '1_month' | 'as_needed'
  follow_up_reason TEXT,
  follow_up_appointment_id TEXT REFERENCES appointments(id),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Doctor App notifications — a small real feed (not push, polled), populated by real server-side
-- events (a member cancelling, a doctor-ordered lab report arriving), not simulated content.
-- "Follow-up due today" is intentionally NOT stored here — it's derived live from today's
-- appointments in the notifications route, so it can never go stale or be double-inserted.
CREATE TABLE IF NOT EXISTS provider_notifications (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL REFERENCES providers(id),
  type TEXT NOT NULL CHECK (type IN ('lab_report_ready','appointment_cancelled')),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  related_appointment_id TEXT REFERENCES appointments(id),
  created_at TEXT NOT NULL,
  read_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_provider_notifications_provider ON provider_notifications (provider_id, created_at DESC);

-- Created automatically when a doctor completes a visit with a fee entered -- one invoice per
-- appointment. Payment is a demo/simulated flow (no real payment gateway): a member picks a
-- payment method and it's marked paid immediately, no actual card/UPI/netbanking processing.
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
);

-- Medicine ordering from a prescription's line items. Delivery tracking is a simple demo timeline
-- (placed -> delivered), not a real logistics integration -- estimated_delivery_date is computed
-- at order time and status is advanced by the member themselves (a real courier isn't wired up).
CREATE TABLE IF NOT EXISTS pharmacy_orders (
  id TEXT PRIMARY KEY,
  member_id TEXT NOT NULL REFERENCES members(id),
  prescription_id TEXT REFERENCES prescriptions(id),
  line_items TEXT NOT NULL DEFAULT '[]', -- JSON array of {medicine_name, strength, quantity}
  delivery_address TEXT,
  status TEXT NOT NULL DEFAULT 'placed' CHECK (status IN ('placed','delivered','cancelled')),
  estimated_delivery_date TEXT,
  created_at TEXT NOT NULL
);

-- Weekly working hours -- multiple windows per day are allowed (e.g. a morning and an evening
-- clinic). A provider with NO rows here has no restriction applied at booking time (keeps
-- existing/legacy providers working exactly as before until they actually set hours).
CREATE TABLE IF NOT EXISTS provider_availability (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL REFERENCES providers(id),
  day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Sun..6=Sat
  start_time TEXT NOT NULL, -- "HH:MM"
  end_time TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- Whole-day leave/holiday blocks -- a booking on one of these dates is rejected regardless of the
-- weekly windows above.
CREATE TABLE IF NOT EXISTS provider_time_off (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL REFERENCES providers(id),
  date TEXT NOT NULL, -- "YYYY-MM-DD"
  reason TEXT,
  created_at TEXT NOT NULL
);

-- Reusable prescriptions a doctor issues often -- loaded from the consultation screen's own
-- "Add Medicine" flow (bulk-appends line_items) rather than being a separate, disconnected list.
CREATE TABLE IF NOT EXISTS prescription_templates (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL REFERENCES providers(id),
  name TEXT NOT NULL,
  diagnosis_text TEXT,
  icd_code TEXT,
  line_items TEXT NOT NULL DEFAULT '[]', -- JSON array of {medicine_name, strength, dosage, frequency, duration, instructions}
  created_at TEXT NOT NULL
);

-- Reusable lab-test bundles, same idea -- loaded from the "select lab tests" sheet.
CREATE TABLE IF NOT EXISTS lab_test_panels (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL REFERENCES providers(id),
  name TEXT NOT NULL,
  test_names TEXT NOT NULL DEFAULT '[]', -- JSON array of test names
  created_at TEXT NOT NULL
);
