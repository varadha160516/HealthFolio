import { Router } from 'express';
import multer from 'multer';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { v4 as uuid } from 'uuid';
import { db, now } from '../db/db.js';
import { requireAuth } from '../middleware/auth.js';
import { assertFamilyAccess } from './family.js';
import { runLabReportPipeline, runPrescriptionPipeline } from '../pipeline/orchestrator.js';
import { extractionModeLabel } from '../pipeline/extract.js';
import { resolveMimeType } from '../pipeline/mime.js';
import { extractPdfPages } from '../pipeline/pdfPages.js';
import { logAudit } from '../audit.js';

export const documentsRouter = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 25 * 1024 * 1024, files: 20 } });

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// CARELOOP_UPLOADS_DIR mirrors db.ts's CARELOOP_DB_PATH override — lets production point this at
// a mounted persistent-disk path instead of a directory relative to the compiled output.
const uploadsDir = process.env.CARELOOP_UPLOADS_DIR || path.resolve(__dirname, '../../uploads');
if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

const DOCUMENT_TYPES = ['prescription', 'lab_report', 'radiology_scan', 'discharge_summary', 'vaccination_record', 'insurance_policy', 'other'];

// For serving the original file back for viewing — broader than pipeline/mime.ts's Claude-specific
// SUPPORTED_MEDIA_TYPES, since anything the upload accepted should be viewable regardless of
// whether the extraction model could read it.
const VIEW_MIME_BY_EXT: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.pdf': 'application/pdf',
};

documentsRouter.get('/documents', requireAuth, (req, res) => {
  const memberId = req.query.member_id as string;
  if (!memberId || !assertFamilyAccess(req, res, memberId)) return;
  const docs = db.prepare('SELECT * FROM documents WHERE member_id = ? ORDER BY upload_date DESC').all(memberId);
  res.json(docs);
});

documentsRouter.get('/documents/:id', requireAuth, (req, res) => {
  const doc = db.prepare('SELECT * FROM documents WHERE id = ?').get(req.params.id) as { member_id: string } | undefined;
  if (!doc) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, doc.member_id)) return;
  const parameters = (
    db
      .prepare(
        `SELECT ep.*, cp.range_type AS dict_range_type
         FROM extracted_parameters ep
         LEFT JOIN canonical_parameters cp ON cp.canonical_parameter_id = ep.canonical_parameter_id
         WHERE ep.document_id = ? ORDER BY ep.raw_label_as_printed`
      )
      .all(req.params.id) as any[]
  ).map((p) => ({
    ...p,
    printed_reference_range_json: undefined,
    resolved_reference_range_json: undefined,
    printed_reference_range: p.printed_reference_range_json ? JSON.parse(p.printed_reference_range_json) : null,
    resolved_reference_range: p.resolved_reference_range_json ? JSON.parse(p.resolved_reference_range_json) : null,
  }));

  const prescription = db.prepare('SELECT * FROM prescriptions WHERE document_id = ?').get(req.params.id) as { id: string } | undefined;
  const prescriptionLineItems = prescription
    ? db.prepare('SELECT * FROM prescription_line_items WHERE prescription_id = ?').all(prescription.id)
    : [];

  res.json({ document: doc, parameters, prescription, prescriptionLineItems });
});

// The original uploaded pages, for a member to go back and verify anything against the source
// (Section 3.2 #1 — the document library is the source of truth, not just the parsed values).
documentsRouter.get('/documents/:id/pages', requireAuth, (req, res) => {
  const doc = db.prepare('SELECT * FROM documents WHERE id = ?').get(req.params.id) as { member_id: string; storage_path: string } | undefined;
  if (!doc) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, doc.member_id)) return;
  if (!fs.existsSync(doc.storage_path)) return res.json([]);

  const files = fs
    .readdirSync(doc.storage_path)
    .filter((f) => /^page-\d+\.[a-z0-9]+$/i.test(f))
    .sort((a, b) => Number(a.match(/^page-(\d+)\./)![1]) - Number(b.match(/^page-(\d+)\./)![1]));

  res.json(
    files.map((f) => ({
      filename: f,
      page_number: Number(f.match(/^page-(\d+)\./)![1]),
      mime_type: VIEW_MIME_BY_EXT[path.extname(f).toLowerCase()] ?? 'application/octet-stream',
    }))
  );
});

documentsRouter.get('/documents/:id/file/:filename', requireAuth, (req, res) => {
  const doc = db.prepare('SELECT * FROM documents WHERE id = ?').get(req.params.id) as { member_id: string; storage_path: string } | undefined;
  if (!doc) return res.status(404).json({ error: 'Not found' });
  if (!assertFamilyAccess(req, res, doc.member_id)) return;

  // Strict allowlist pattern — this becomes part of a filesystem path, so reject anything that
  // isn't exactly the page-N.ext shape this route itself generates (blocks path traversal).
  const filename = req.params.filename;
  if (!/^page-\d+\.[a-z0-9]+$/i.test(filename)) return res.status(400).json({ error: 'Invalid filename' });

  const filePath = path.join(doc.storage_path, filename);
  if (!fs.existsSync(filePath)) return res.status(404).json({ error: 'File not found' });

  res.setHeader('Content-Type', VIEW_MIME_BY_EXT[path.extname(filename).toLowerCase()] ?? 'application/octet-stream');
  res.setHeader('Cache-Control', 'private, max-age=3600');
  fs.createReadStream(filePath).pipe(res);
});

// Stage 1 (INTAKE) + trigger stages 2-11. All files in one request are treated as pages of a
// single logical document (Section 3.3 — multi-page uploads must not become one document per page).
documentsRouter.post('/documents', requireAuth, upload.array('pages', 20), async (req, res) => {
  const session = req.session!;
  if (session.role !== 'member_primary' && session.role !== 'member_dependent') {
    return res.status(403).json({ error: 'Only member roles can upload documents' });
  }

  const { member_id, document_type, mock_fixture, page_selections } = req.body ?? {};
  if (!member_id || !assertFamilyAccess(req, res, member_id)) return;
  if (!document_type || !DOCUMENT_TYPES.includes(document_type)) {
    return res.status(400).json({ error: `document_type must be one of ${DOCUMENT_TYPES.join(', ')}` });
  }
  const files = req.files as Express.Multer.File[] | undefined;
  if (!files || files.length === 0) return res.status(400).json({ error: 'At least one page (file) is required' });

  // Positional (index into `files`), not filename-keyed — filenames can collide (the same source
  // PDF picked twice, say). Each entry is either an array of 1-indexed page numbers, or null/absent
  // to mean "use the whole file" (Section 3.3 grouping is unaffected — this only trims a single
  // oversized PDF down to the pages that actually matter before it reaches the extraction model).
  let pageSelections: (number[] | null)[] = [];
  if (page_selections) {
    try {
      const parsed = JSON.parse(page_selections);
      if (Array.isArray(parsed)) pageSelections = parsed;
    } catch {
      // Malformed selection payload — ignore and fall back to whole-file extraction for everything.
    }
  }

  const documentId = uuid();
  const docDir = path.join(uploadsDir, documentId);
  fs.mkdirSync(docDir, { recursive: true });

  const checksum = crypto.createHash('sha256');
  const pages = await Promise.all(
    files.map(async (f, i) => {
      checksum.update(f.buffer);
      const ext = path.extname(f.originalname) || '.bin';
      // The FULL original file is always what's stored on disk — it's the source of truth
      // (Section 3.2 #1); page trimming only affects what gets sent to the extraction model.
      const storedPath = path.join(docDir, `page-${i + 1}${ext}`);
      fs.writeFileSync(storedPath, f.buffer);

      const mimeType = resolveMimeType(f.mimetype, f.originalname);
      const selection = pageSelections[i];
      let extractionBuffer = f.buffer;
      if (mimeType === 'application/pdf' && selection && selection.length > 0) {
        try {
          extractionBuffer = await extractPdfPages(f.buffer, selection);
        } catch (err) {
          console.error(`Failed to trim PDF to selected pages ${JSON.stringify(selection)}, using the full file instead:`, err);
        }
      }
      return { buffer: extractionBuffer, mimeType, storedPath };
    })
  );

  db.prepare(
    `INSERT INTO documents (id, member_id, uploaded_by_user_id, document_type, presentation_style, storage_path, checksum, lab_visit_id, page_count, upload_date, test_date, source_lab_name, status, origin, created_at)
     VALUES (?, ?, ?, ?, NULL, ?, ?, NULL, ?, ?, NULL, NULL, 'processing', 'member_upload', ?)`
  ).run(documentId, member_id, session.userId, document_type, docDir, checksum.digest('hex'), pages.length, now(), now());

  logAudit(session.userId, session.role, 'document_uploaded', member_id, { documentId, document_type });

  try {
    if (document_type === 'lab_report') {
      const result = await runLabReportPipeline(
        documentId,
        member_id,
        pages.map((p) => ({ buffer: p.buffer, mimeType: p.mimeType })),
        mock_fixture ? { mockFixture: mock_fixture } : undefined
      );
      return res.status(201).json({ documentId, extractionMode: extractionModeLabel(), pipeline: result });
    }
    if (document_type === 'prescription') {
      const result = await runPrescriptionPipeline(
        documentId,
        member_id,
        pages.map((p) => ({ buffer: p.buffer, mimeType: p.mimeType }))
      );
      return res.status(201).json({ documentId, extractionMode: extractionModeLabel(), prescriptionId: result.prescriptionId });
    }
    // Other document types (radiology_scan, discharge_summary, vaccination_record, insurance_policy,
    // other) are stored as-is per Section 3.2 #1; field-level extraction is only specced for lab
    // reports and prescriptions (Sections 4 and 8) in this build.
    db.prepare(`UPDATE documents SET status = 'parsed' WHERE id = ?`).run(documentId);
    return res.status(201).json({ documentId, extractionMode: extractionModeLabel() });
  } catch (err) {
    console.error('Pipeline failed, falling back to manual entry required (Section 11 — never silently drop an upload):', err);
    db.prepare(`UPDATE documents SET status = 'manual_entry_required' WHERE id = ?`).run(documentId);
    return res.status(201).json({ documentId, status: 'manual_entry_required', error: 'Extraction failed; manual entry required.' });
  }
});
