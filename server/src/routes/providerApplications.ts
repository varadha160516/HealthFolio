import { Router } from 'express';
import multer from 'multer';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { hashPassword } from '../auth/hash.js';
import { uploadsDir } from './documents.js';
import { SPECIALIZATIONS } from '../specializations.js';

export const providerApplicationsRouter = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 15 * 1024 * 1024, files: 10 } });

const DOCUMENT_TYPES = ['registration_certificate', 'government_id', 'qualification_certificate', 'clinic_proof', 'other'];
const ROLES = ['doctor', 'clinic_admin'];

function generateReferenceCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I — easy to read back over the phone
  let code = 'APP-';
  for (let i = 0; i < 6; i++) code += alphabet[crypto.randomInt(alphabet.length)];
  return code;
}

function saveApplicationFiles(applicationId: string, files: Express.Multer.File[], documentTypes: string[]) {
  const docDir = path.join(uploadsDir, 'applications', applicationId);
  fs.mkdirSync(docDir, { recursive: true });
  const insert = db.prepare(
    `INSERT INTO provider_application_documents (id, application_id, document_type, storage_path, filename, created_at) VALUES (?, ?, ?, ?, ?, ?)`
  );
  files.forEach((f, i) => {
    const docType = DOCUMENT_TYPES.includes(documentTypes[i]) ? documentTypes[i] : 'other';
    const ext = path.extname(f.originalname) || '.bin';
    const filename = `${docType}-${i + 1}${ext}`;
    fs.writeFileSync(path.join(docDir, filename), f.buffer);
    insert.run(uuid(), applicationId, docType, docDir, filename, now());
  });
}

// --- Public, unauthenticated reference data — the application form exists before anyone has a session. ---

providerApplicationsRouter.get('/public/specializations', (_req, res) => res.json(SPECIALIZATIONS));

providerApplicationsRouter.get('/public/clinics', (_req, res) => {
  res.json(db.prepare('SELECT id, name, address, city FROM clinics ORDER BY name').all());
});

// --- Submission ---

providerApplicationsRouter.post('/provider-applications', upload.array('documents', 10), (req, res) => {
  const b = req.body ?? {};
  const { email, password, full_name, phone, role_requested, specialty, registration_number, qualifications, years_of_experience, gst_number, default_fee, clinic_mode, clinic_id, new_clinic_name, new_clinic_address, new_clinic_city } = b;

  if (!email || !password || !full_name) return res.status(400).json({ error: 'email, password, and full_name are required' });
  if (!ROLES.includes(role_requested)) return res.status(400).json({ error: `role_requested must be one of ${ROLES.join(', ')}` });
  if (!['existing', 'new'].includes(clinic_mode)) return res.status(400).json({ error: "clinic_mode must be 'existing' or 'new'" });
  if (clinic_mode === 'existing' && !clinic_id) return res.status(400).json({ error: 'clinic_id is required when clinic_mode is existing' });
  if (clinic_mode === 'new' && !new_clinic_name) return res.status(400).json({ error: 'new_clinic_name is required when clinic_mode is new' });
  if (String(password).length < 8) return res.status(400).json({ error: 'password must be at least 8 characters' });

  const existingUser = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
  if (existingUser) return res.status(409).json({ error: 'An account with this email already exists' });
  const pendingApp = db.prepare(`SELECT id FROM provider_applications WHERE email = ? AND status = 'pending'`).get(email);
  if (pendingApp) return res.status(409).json({ error: 'An application with this email is already pending review' });

  const id = uuid();
  let referenceCode = generateReferenceCode();
  while (db.prepare('SELECT id FROM provider_applications WHERE reference_code = ?').get(referenceCode)) referenceCode = generateReferenceCode();
  const timestamp = now();

  db.prepare(
    `INSERT INTO provider_applications
       (id, reference_code, email, password_hash, full_name, phone, role_requested, specialty, registration_number, qualifications, years_of_experience, gst_number, default_fee, clinic_mode, clinic_id, new_clinic_name, new_clinic_address, new_clinic_city, status, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`
  ).run(
    id,
    referenceCode,
    email,
    hashPassword(password),
    full_name,
    phone ?? null,
    role_requested,
    specialty ?? null,
    registration_number ?? null,
    qualifications ?? null,
    years_of_experience ? Number(years_of_experience) : null,
    gst_number ?? null,
    default_fee ? Number(default_fee) : null,
    clinic_mode,
    clinic_mode === 'existing' ? clinic_id : null,
    clinic_mode === 'new' ? new_clinic_name : null,
    clinic_mode === 'new' ? (new_clinic_address ?? null) : null,
    clinic_mode === 'new' ? (new_clinic_city ?? null) : null,
    timestamp,
    timestamp
  );

  const files = (req.files as Express.Multer.File[] | undefined) ?? [];
  let documentTypes: string[] = [];
  try {
    documentTypes = JSON.parse(b.document_types ?? '[]');
  } catch {
    // malformed -- every file just falls back to 'other' inside saveApplicationFiles
  }
  if (files.length > 0) saveApplicationFiles(id, files, documentTypes);

  res.status(201).json({ applicationId: id, referenceCode });
});

// --- Status check + resubmission, gated by email + reference_code (the only "auth" an applicant has) ---

function loadApplicationByReference(email: string, referenceCode: string) {
  return db.prepare('SELECT * FROM provider_applications WHERE email = ? AND reference_code = ?').get(email, referenceCode) as any;
}

providerApplicationsRouter.get('/provider-applications/status', (req, res) => {
  const email = req.query.email as string | undefined;
  const referenceCode = req.query.reference_code as string | undefined;
  if (!email || !referenceCode) return res.status(400).json({ error: 'email and reference_code are required' });
  const app = loadApplicationByReference(email, referenceCode);
  if (!app) return res.status(404).json({ error: 'No application found for that email and reference code' });
  const { password_hash, ...rest } = app;
  res.json(rest);
});

// Resubmission after rejection reuses the same application row (same reference code) rather than
// creating a new one — one continuous record for an admin to see the history of, and the applicant
// doesn't have to memorize a second code.
providerApplicationsRouter.post('/provider-applications/:id/resubmit', upload.array('documents', 10), (req, res) => {
  const app = db.prepare('SELECT * FROM provider_applications WHERE id = ?').get(req.params.id) as any;
  if (!app) return res.status(404).json({ error: 'Not found' });
  const { email, reference_code } = req.body ?? {};
  if (app.email !== email || app.reference_code !== reference_code) return res.status(403).json({ error: 'email/reference_code do not match this application' });
  if (app.status !== 'rejected') return res.status(409).json({ error: 'Only a rejected application can be resubmitted' });

  const b = req.body ?? {};
  const updates: Record<string, unknown> = { updated_at: now(), status: 'pending', rejection_reason: null, reviewed_at: null, reviewed_by_user_id: null };
  for (const field of ['full_name', 'phone', 'specialty', 'registration_number', 'qualifications', 'gst_number']) {
    if (b[field] !== undefined) updates[field] = b[field];
  }
  if (b.years_of_experience !== undefined) updates.years_of_experience = Number(b.years_of_experience);
  if (b.default_fee !== undefined) updates.default_fee = Number(b.default_fee);

  const setClause = Object.keys(updates)
    .map((k) => `${k} = @${k}`)
    .join(', ');
  db.prepare(`UPDATE provider_applications SET ${setClause} WHERE id = @id`).run({ ...updates, id: app.id });

  const files = (req.files as Express.Multer.File[] | undefined) ?? [];
  let documentTypes: string[] = [];
  try {
    documentTypes = JSON.parse(b.document_types ?? '[]');
  } catch {
    // see submission handler
  }
  if (files.length > 0) saveApplicationFiles(app.id, files, documentTypes);

  res.json({ ok: true });
});
