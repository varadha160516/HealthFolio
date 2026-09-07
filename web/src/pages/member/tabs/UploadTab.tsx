import { useState } from 'react';
import { api } from '../../../api/client';

const DOC_TYPES = [
  { value: 'lab_report', label: 'Lab report' },
  { value: 'prescription', label: 'Prescription' },
  { value: 'radiology_scan', label: 'Radiology scan' },
  { value: 'discharge_summary', label: 'Discharge summary' },
  { value: 'vaccination_record', label: 'Vaccination record' },
  { value: 'insurance_policy', label: 'Insurance policy' },
  { value: 'other', label: 'Other' },
];

export function UploadTab({ memberId, onUploaded }: { memberId: string; onUploaded: () => void }) {
  const [documentType, setDocumentType] = useState('lab_report');
  const [files, setFiles] = useState<FileList | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent, mockFixture?: string) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const form = new FormData();
      form.append('member_id', memberId);
      form.append('document_type', documentType);
      if (mockFixture) form.append('mock_fixture', mockFixture);

      if (mockFixture) {
        // Golden-sample demo path: the server replays a fixture regardless of file bytes,
        // but the endpoint still requires at least one file per the intake stage contract.
        form.append('pages', new Blob(['sample']), 'sample.png');
      } else {
        if (!files || files.length === 0) {
          setError('Choose at least one page (photo or PDF).');
          setBusy(false);
          return;
        }
        for (const f of Array.from(files)) form.append('pages', f);
      }

      const res = await api.uploadDocument(form);
      setResult(res);
      onUploaded();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div className="banner info">
        The extraction pipeline (Section 4 of the PRD) runs a vision-capable model over the rendered pages. This
        deployment is running in <strong>mock mode</strong> unless an ANTHROPIC_API_KEY is configured on the
        server — use the golden-sample buttons below to see the full pipeline (matching, range resolution,
        confidence routing) work end to end without needing a real lab report photo on hand.
      </div>

      <div className="card">
        <h2>Upload a document</h2>
        <form onSubmit={(e) => submit(e)}>
          <div className="form-row">
            <label>Document type</label>
            <select value={documentType} onChange={(e) => setDocumentType(e.target.value)}>
              {DOC_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>
          <div className="form-row">
            <label>Pages (photo/PDF — select all pages of one report together)</label>
            <input type="file" multiple accept="image/*,.pdf" onChange={(e) => setFiles(e.target.files)} />
          </div>
          <button className="primary" type="submit" disabled={busy}>
            {busy ? 'Uploading…' : 'Upload & extract'}
          </button>
        </form>

        {documentType === 'lab_report' && (
          <div style={{ marginTop: 14 }}>
            <div className="muted" style={{ marginBottom: 6 }}>
              Or try the golden test set (Section 4.8) — two real report layouts this pipeline was validated against:
            </div>
            <div className="flex gap">
              <button type="button" disabled={busy} onClick={(e) => submit(e as any, 'golden_report_a')}>
                Load Tata 1mg-style CBC report
              </button>
              <button type="button" disabled={busy} onClick={(e) => submit(e as any, 'golden_report_b')}>
                Load PharmEasy/Thyrocare trends report
              </button>
            </div>
          </div>
        )}

        {error && <div className="banner" style={{ marginTop: 12 }}>{error}</div>}
        {result && (
          <div className="banner info" style={{ marginTop: 12 }}>
            {result.pipeline ? (
              <>
                Extracted {result.pipeline.extractedCount} values — {result.pipeline.autoAcceptedCount} auto-accepted,{' '}
                {result.pipeline.pendingReviewCount} need review, {result.pipeline.newCandidateCount} are new/unmatched
                parameters sent to platform admin. Check the "Review queue" and "Trends" tabs.
              </>
            ) : (
              'Document stored.'
            )}
          </div>
        )}
      </div>
    </div>
  );
}
