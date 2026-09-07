import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../../api/client';

const WAITING_STATES = new Set(['scheduled', 'checked_in', 'consent_requested']);

export function AppointmentWorkspace() {
  const { appointmentId } = useParams<{ appointmentId: string }>();
  const [appt, setAppt] = useState<any>(null);
  const [otpInput, setOtpInput] = useState('');
  const [lastOtp, setLastOtp] = useState<string | null>(null);
  const [lineItems, setLineItems] = useState([{ medicine_name: '', strength: '', dosage: '', frequency: '', duration: '', instructions: '' }]);
  const [diagnosis, setDiagnosis] = useState('');
  const [error, setError] = useState<string | null>(null);

  function load() {
    if (!appointmentId) return;
    api.getAppointment(appointmentId).then(setAppt);
  }
  useEffect(load, [appointmentId]);
  useEffect(() => {
    if (!appt || !WAITING_STATES.has(appt.status)) return;
    const t = setInterval(load, 2000); // live status poll while waiting on consent
    return () => clearInterval(t);
  }, [appt?.status]);

  if (!appt || !appointmentId) return <div className="center-loading">Loading…</div>;
  const id: string = appointmentId;

  async function act(fn: () => Promise<any>) {
    setError(null);
    try {
      const res = await fn();
      load();
      return res;
    } catch (err: any) {
      setError(err.message);
    }
  }

  async function requestConsent(method: 'in_app' | 'otp') {
    const res = await act(() => api.requestConsent(id, method));
    if (res?.otp) setLastOtp(res.otp);
  }
  async function resend(method: 'in_app' | 'otp') {
    const res = await act(() => api.resendConsent(id, method));
    if (res?.otp) setLastOtp(res.otp);
  }
  async function verifyOtp() {
    await act(() => api.verifyOtp(id, otpInput));
    setOtpInput('');
  }
  async function issuePrescription() {
    const items = lineItems.filter((li) => li.medicine_name.trim());
    if (items.length === 0) return;
    await act(() => api.issuePrescription(id, { diagnosis_text: diagnosis, line_items: items }));
    setLineItems([{ medicine_name: '', strength: '', dosage: '', frequency: '', duration: '', instructions: '' }]);
  }

  const unlocked = appt.status === 'consent_granted' || appt.status === 'in_consultation';

  return (
    <div>
      <div className="flex between" style={{ marginBottom: 12 }}>
        <div>
          <h2 style={{ margin: 0 }}>{appt.member?.name}</h2>
          <div className="muted">{new Date(appt.datetime).toLocaleString()}</div>
        </div>
        <span className={`pill status-${appt.status}`} style={{ fontSize: 13 }}>
          {appt.status.replace(/_/g, ' ')}
        </span>
      </div>

      {error && <div className="banner">{error}</div>}

      {appt.status === 'scheduled' && (
        <div className="card">
          <p className="muted">Grants no data access — only makes the consent-request action available (Section 7.1).</p>
          <button className="primary" onClick={() => act(() => api.checkIn(appointmentId))}>
            Check in
          </button>
        </div>
      )}

      {appt.status === 'checked_in' && (
        <div className="card">
          <h3>Request consent for this visit</h3>
          <div className="flex gap">
            <button className="primary" onClick={() => requestConsent('in_app')}>
              Send in-app request
            </button>
            <button onClick={() => requestConsent('otp')}>Use OTP fallback (no smartphone)</button>
          </div>
        </div>
      )}

      {appt.status === 'consent_requested' && (
        <div className="card">
          <div className="banner info">
            Waiting for the patient to respond ({appt.consentGrant?.method === 'otp' ? 'OTP fallback' : 'in-app'}) — expires{' '}
            {appt.consentGrant?.expires_at ? new Date(appt.consentGrant.expires_at).toLocaleTimeString() : ''}. This is
            not the same as a denial — the doctor must explicitly resend, never wait indefinitely (Section 7.1).
          </div>
          {appt.consentGrant?.method === 'otp' && (
            <div className="flex gap" style={{ marginBottom: 10 }}>
              <input placeholder="6-digit code read aloud by patient" value={otpInput} onChange={(e) => setOtpInput(e.target.value)} style={{ maxWidth: 220 }} />
              <button className="primary" onClick={verifyOtp}>
                Verify
              </button>
            </div>
          )}
          {lastOtp && <div className="muted">(demo only — no real SMS wired up — code sent was {lastOtp})</div>}
          <button onClick={() => resend(appt.consentGrant?.method === 'otp' ? 'otp' : 'in_app')}>Resend request</button>
        </div>
      )}

      {(appt.status === 'consent_denied' || appt.status === 'consent_expired') && (
        <div className="card">
          <div className="banner">
            {appt.status === 'consent_denied' ? 'The patient denied this consent request.' : 'The consent request expired without a response.'}
          </div>
          <button onClick={() => resend('in_app')}>Resend request</button>
        </div>
      )}

      {unlocked && appt.consentGrant?.granted_at && (
        <div className="banner info">
          Access granted at {new Date(appt.consentGrant.granted_at).toLocaleString()} · scope: {appt.consentGrant.scope}
        </div>
      )}

      {unlocked && appt.unlockedData && (
        <div className="grid cols-2">
          <div className="card">
            <h3>Allergies & conditions</h3>
            <div>
              <strong>Allergies:</strong> {appt.unlockedData.summary.allergies.map((a: any) => a.value).join(', ') || 'None'}
            </div>
            <div>
              <strong>Chronic conditions:</strong>{' '}
              {appt.unlockedData.summary.chronicConditions.map((c: any) => c.value).join(', ') || 'None'}
            </div>
            <div>
              <strong>Current medications:</strong>{' '}
              {appt.unlockedData.summary.currentMedications.map((m: any) => m.medicine_name).join(', ') || 'None'}
            </div>
          </div>
          <div className="card">
            <h3>Flagged history (out of range since last visit)</h3>
            {appt.unlockedData.flaggedHistory.length === 0 && <div className="muted">Nothing flagged.</div>}
            <table>
              <tbody>
                {appt.unlockedData.flaggedHistory.map((f: any) => (
                  <tr key={f.id}>
                    <td>{f.display_name}</td>
                    <td>
                      {f.canonical_value} {f.canonical_unit}
                    </td>
                    <td className="muted">{f.test_date}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="card" style={{ gridColumn: '1 / -1' }}>
            <h3>Document timeline</h3>
            <table>
              <tbody>
                {appt.unlockedData.documents.map((d: any) => (
                  <tr key={d.id}>
                    <td>{d.document_type.replace('_', ' ')}</td>
                    <td className="muted">{d.source_lab_name || '—'}</td>
                    <td className="muted">{d.test_date || d.upload_date?.slice(0, 10)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {appt.status === 'consent_granted' && (
        <div className="card">
          <button className="primary" onClick={() => act(() => api.startConsultation(appointmentId))}>
            Begin consultation
          </button>
        </div>
      )}

      {appt.status === 'in_consultation' && (
        <div className="card">
          <h3>e-Prescription</h3>
          <div className="form-row">
            <label>Diagnosis</label>
            <input value={diagnosis} onChange={(e) => setDiagnosis(e.target.value)} />
          </div>
          {lineItems.map((li, i) => (
            <div className="grid cols-3" key={i} style={{ marginBottom: 8 }}>
              <input
                placeholder="Medicine"
                value={li.medicine_name}
                onChange={(e) => {
                  const next = [...lineItems];
                  next[i] = { ...li, medicine_name: e.target.value };
                  setLineItems(next);
                }}
              />
              <input
                placeholder="Dosage (e.g. 500mg)"
                value={li.dosage}
                onChange={(e) => {
                  const next = [...lineItems];
                  next[i] = { ...li, dosage: e.target.value };
                  setLineItems(next);
                }}
              />
              <input
                placeholder="Frequency / duration"
                value={li.frequency}
                onChange={(e) => {
                  const next = [...lineItems];
                  next[i] = { ...li, frequency: e.target.value };
                  setLineItems(next);
                }}
              />
            </div>
          ))}
          <div className="flex gap" style={{ marginBottom: 12 }}>
            <button onClick={() => setLineItems([...lineItems, { medicine_name: '', strength: '', dosage: '', frequency: '', duration: '', instructions: '' }])}>
              + Add medicine
            </button>
            <button onClick={issuePrescription}>Sign & issue prescription</button>
          </div>
          <button className="primary" onClick={() => act(() => api.completeVisit(appointmentId))}>
            Complete visit
          </button>
        </div>
      )}

      {appt.status === 'completed' && (
        <div className="card">
          <div className="banner info">Visit completed — access to this patient's records was revoked immediately (Section 7.1).</div>
        </div>
      )}
    </div>
  );
}
