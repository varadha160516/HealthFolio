import { useEffect, useState } from 'react';
import { api } from '../../../api/client';

export function DocumentsTab({ memberId }: { memberId: string }) {
  const [docs, setDocs] = useState<any[]>([]);
  const [prescriptions, setPrescriptions] = useState<any[]>([]);
  const [selected, setSelected] = useState<any>(null);

  useEffect(() => {
    api.getDocuments(memberId).then(setDocs);
    api.getPrescriptions(memberId).then(setPrescriptions);
  }, [memberId]);

  async function open(docId: string) {
    const d = await api.getDocument(docId);
    setSelected(d);
  }

  return (
    <div className="grid cols-2">
      <div className="card">
        <h3>Document library</h3>
        {docs.length === 0 && <div className="muted">No documents uploaded yet.</div>}
        <table>
          <tbody>
            {docs.map((d) => (
              <tr key={d.id} style={{ cursor: 'pointer' }} onClick={() => open(d.id)}>
                <td>{d.document_type.replace('_', ' ')}</td>
                <td className="muted">{d.source_lab_name || '—'}</td>
                <td className="muted">{d.test_date || d.upload_date?.slice(0, 10)}</td>
                <td>
                  <span className={`pill ${d.status === 'parsed' ? 'confirmed' : d.status === 'manual_entry_required' ? 'out_of_range' : 'pending_review'}`}>
                    {d.status}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        <h3 style={{ marginTop: 20 }}>Prescriptions</h3>
        {prescriptions.length === 0 && <div className="muted">None on file.</div>}
        {prescriptions.map((p) => (
          <div key={p.id} style={{ marginBottom: 10 }}>
            <div className="muted">
              {p.issued_at?.slice(0, 10)} {p.diagnosis_text ? `· ${p.diagnosis_text}` : ''}
            </div>
            <ul style={{ margin: '4px 0' }}>
              {p.line_items.map((li: any, i: number) => (
                <li key={i}>
                  {li.medicine_name} {[li.strength, li.dosage, li.frequency, li.duration].filter(Boolean).join(' · ')}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      <div className="card">
        <h3>Extracted values</h3>
        {!selected && <div className="muted">Select a document to see what was extracted from it.</div>}
        {selected && (
          <table>
            <thead>
              <tr>
                <th>Label</th>
                <th>Value</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {selected.parameters.map((p: any) => (
                <tr key={p.id}>
                  <td>{p.raw_label_as_printed}</td>
                  <td>
                    {p.canonical_value ?? p.value_raw} {p.canonical_unit ?? p.unit_raw}
                  </td>
                  <td>
                    <span className={`pill ${p.review_status}`}>{p.review_status}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
