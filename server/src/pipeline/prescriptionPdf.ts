import { PDFDocument, PDFFont, PDFPage, StandardFonts, rgb } from 'pdf-lib';

export interface PrescriptionPdfLineItem {
  medicine_name: string;
  strength?: string | null;
  duration?: string | null;
  frequency?: string | null;
  instructions?: string | null;
}

export interface PrescriptionPdfData {
  providerName: string;
  specialty?: string | null;
  clinicName?: string | null;
  registrationNumber?: string | null;
  memberName: string;
  age?: number | null;
  sex?: string | null;
  issuedAt: string;
  chiefComplaint?: string | null;
  vitalsLine?: string | null;
  diagnosisText?: string | null;
  icdCode?: string | null;
  lineItems: PrescriptionPdfLineItem[];
  advice?: string[];
  followUpAfter?: string | null;
  followUpReason?: string | null;
  signatureBase64?: string | null;
}

const PAGE_WIDTH = 595.28; // A4 at 72dpi
const PAGE_HEIGHT = 841.89;
const MARGIN = 50;
const INK = rgb(0.17, 0.18, 0.3); // ~#2C2D4D, matches ClinDesk's docTextPrimary
const MUTED = rgb(0.545, 0.545, 0.659); // ~#8B8CA8
const ACCENT = rgb(0.31, 0.32, 0.6); // a printable-safe darker take on docAccentDark
const RULE = rgb(0.855, 0.839, 0.925); // ~#DAD6EC

function followUpLabel(v: string): string {
  return { '3_days': '3 days', '1_week': '1 week', '1_month': '1 month' }[v] ?? 'As needed';
}

/** Builds a printable prescription PDF from exactly the same fields the ClinDesk app's own
 * Prescription screen renders (see prescription_view_screen.dart) — no field here is guessed,
 * every one traces back to GET /appointments/:id + GET /appointments/:id/visit-summary. */
export async function generatePrescriptionPdf(data: PrescriptionPdfData): Promise<Buffer> {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const italic = await doc.embedFont(StandardFonts.HelveticaOblique);

  let page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  let y = PAGE_HEIGHT - MARGIN;

  const ensureSpace = (needed: number) => {
    if (y - needed < MARGIN) {
      page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
      y = PAGE_HEIGHT - MARGIN;
    }
  };

  const draw = (text: string, opts: { size?: number; f?: PDFFont; color?: ReturnType<typeof rgb>; gap?: number; x?: number } = {}) => {
    const { size = 10.5, f = font, color = INK, gap = 14, x = MARGIN } = opts;
    ensureSpace(gap);
    page.drawText(text, { x, y: y - size, size, font: f, color });
    y -= gap;
  };

  const rule = () => {
    ensureSpace(10);
    page.drawLine({ start: { x: MARGIN, y }, end: { x: PAGE_WIDTH - MARGIN, y }, thickness: 0.75, color: RULE });
    y -= 12;
  };

  // Letterhead
  draw(data.providerName, { size: 15, f: bold, gap: 18 });
  const subtitle = [data.specialty, data.clinicName].filter((v): v is string => !!v && v.length > 0).join('  ·  ');
  if (subtitle) draw(subtitle, { size: 9.5, color: MUTED, gap: 12 });
  if (data.registrationNumber) draw(`Reg. No. ${data.registrationNumber}`, { size: 8.5, color: MUTED, gap: 14 });
  const issued = new Date(data.issuedAt);
  draw(`Prescription  ·  ${issued.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' })}`, { size: 9, color: ACCENT, f: bold, gap: 16 });
  rule();

  // Patient
  const patientMeta = [data.age != null ? `${data.age} yrs` : null, data.sex ? data.sex[0].toUpperCase() + data.sex.slice(1) : null].filter(Boolean).join('  ·  ');
  draw(data.memberName, { size: 12.5, f: bold, gap: 15 });
  if (patientMeta) draw(patientMeta, { size: 9.5, color: MUTED, gap: 16 });
  rule();

  // Chief complaint / vitals / diagnosis
  if (data.chiefComplaint) draw(`CHIEF COMPLAINT: ${data.chiefComplaint}`, { size: 9.5, gap: 16 });
  if (data.vitalsLine) draw(`VITALS: ${data.vitalsLine}`, { size: 9.5, gap: 16 });
  if (data.diagnosisText) {
    const icd = data.icdCode ? `   ·   ICD-10: ${data.icdCode}` : '';
    draw(`DIAGNOSIS: ${data.diagnosisText}${icd}`, { size: 9.5, f: bold, gap: 18 });
  }

  // Rx / medications — "Rx" (large, italic) and "Medications" (bold) share one baseline.
  ensureSpace(24);
  const rxBaseline = y - 15;
  page.drawText('Rx', { x: MARGIN, y: rxBaseline, size: 15, font: italic, color: ACCENT });
  page.drawText('Medications', { x: MARGIN + 24, y: rxBaseline + 3, size: 11, font: bold, color: INK });
  y -= 24;
  rule();

  data.lineItems.forEach((li, i) => {
    ensureSpace(30);
    const name = `${i + 1}. ${li.medicine_name}${li.strength ? `  ${li.strength}` : ''}`;
    draw(name, { size: 11, f: bold, gap: 13 });
    const meta = [li.duration, li.frequency, li.instructions].filter((v): v is string => !!v && v.length > 0).join('  ·  ');
    if (meta) draw(meta, { size: 9, color: MUTED, gap: 16, x: MARGIN + 14 });
    else y -= 4;
  });
  y -= 6;
  rule();

  // Advice
  if (data.advice && data.advice.length > 0) {
    draw('ADVICE', { size: 8.5, color: MUTED, f: bold, gap: 14 });
    for (const a of data.advice) draw(`•  ${a}`, { size: 9.5, gap: 14 });
    y -= 4;
  }

  // Follow-up
  if (data.followUpAfter) {
    draw('FOLLOW-UP', { size: 8.5, color: MUTED, f: bold, gap: 14 });
    const reason = data.followUpReason ? `  —  ${data.followUpReason}` : '';
    draw(`${followUpLabel(data.followUpAfter)}${reason}`, { size: 10, f: bold, gap: 20 });
  }

  // Signature block — a little below the last content line, but never closer to the bottom edge
  // than MARGIN + 60 (so a long prescription's signature still clears the page margin cleanly).
  ensureSpace(90);
  const sigY = Math.max(y - 40, MARGIN + 60);
  if (data.signatureBase64) {
    try {
      const bytes = Buffer.from(data.signatureBase64, 'base64');
      const png = await doc.embedPng(bytes);
      const dims = png.scaleToFit(110, 40);
      page.drawImage(png, { x: PAGE_WIDTH - MARGIN - dims.width, y: sigY + 14, width: dims.width, height: dims.height });
    } catch {
      // A malformed signature image shouldn't block issuing the prescription — fall through to
      // the printed-name fallback below via the italic line.
      page.drawText(data.providerName, { x: PAGE_WIDTH - MARGIN - 110, y: sigY + 18, size: 13, font: italic, color: ACCENT });
    }
  } else {
    page.drawText(data.providerName, { x: PAGE_WIDTH - MARGIN - 110, y: sigY + 18, size: 13, font: italic, color: ACCENT });
  }
  page.drawLine({ start: { x: PAGE_WIDTH - MARGIN - 110, y: sigY + 10 }, end: { x: PAGE_WIDTH - MARGIN, y: sigY + 10 }, thickness: 0.75, color: INK });
  page.drawText(data.providerName, { x: PAGE_WIDTH - MARGIN - 110, y: sigY, size: 8.5, font: bold, color: INK });
  page.drawText('This is a digitally generated prescription issued via ClinDesk.', { x: MARGIN, y: sigY, size: 7.5, font, color: MUTED });
  page.drawText('Valid without a physical signature.', { x: MARGIN, y: sigY - 10, size: 7.5, font, color: MUTED });

  const pageBytes = await doc.save();
  return Buffer.from(pageBytes);
}

/** Same one-line vitals summary format used everywhere else in the app (ClinDesk's
 * prescription_view_screen.dart / visit_summary_screen.dart _vitalsLine) — kept in sync
 * deliberately rather than reusing shared code across the Dart/TS boundary. */
export function vitalsLineFromLatest(v: Record<string, any> | undefined): string | null {
  if (!v) return null;
  const parts: string[] = [];
  if (v.systolic_bp != null || v.diastolic_bp != null) parts.push(`BP ${v.systolic_bp ?? '—'}/${v.diastolic_bp ?? '—'}`);
  if (v.heart_rate != null) parts.push(`Pulse ${v.heart_rate} bpm`);
  if (v.spo2 != null) parts.push(`SpO2 ${v.spo2}%`);
  if (v.temperature_f != null) parts.push(`Temp ${v.temperature_f}°F`);
  if (v.respiratory_rate != null) parts.push(`RR ${v.respiratory_rate}/min`);
  if (v.weight_kg != null) parts.push(`Weight ${v.weight_kg} kg`);
  if (v.height_cm != null) parts.push(`Height ${v.height_cm} cm`);
  return parts.length === 0 ? null : parts.join('  ·  ');
}
