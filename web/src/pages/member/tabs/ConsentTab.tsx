import { useEffect, useState } from 'react';
import { api } from '../../../api/client';

export function ConsentTab({ memberId }: { memberId: string }) {
  const [appointments, setAppointments] = useState<any[]>([]);
  const [audit, setAudit] = useState<any[]>([]);

  function load() {
    api.getAppointments().then((all) => setAppointments(all.filter((a) => a.member?.id === memberId)));
    api.getAudit(memberId).then(setAudit);
  }
  useEffect(load, [memberId]);

  const pendingConsent = appointments.filter((a) => a.status === 'consent_requested');

  async function respond(id: string, approve: boolean) {
    await api.respondConsent(id, approve);
    load();
  }

  return (
    <div>
      {pendingConsent.length > 0 && (
        <div className="card">
          <h3>Consent requests waiting on you</h3>
          {pendingConsent.map((a) => (
            <div key={a.id} className="banner">
              <div style={{ marginBottom: 8 }}>
                <strong>{a.provider?.name}</strong> is requesting <strong>{a.consentGrant?.scope || 'full history'}</strong> access
                for today's visit.
              </div>
              <div className="flex gap">
                <button className="primary" onClick={() => respond(a.id, true)}>
                  Approve
                </button>
                <button className="danger" onClick={() => respond(a.id, false)}>
                  Deny
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="card">
        <h3>Consent & access log</h3>
        {audit.length === 0 && <div className="muted">No provider or payer has accessed this record yet.</div>}
        <table>
          <tbody>
            {audit.map((entry: any) => (
              <tr key={entry.id}>
                <td className="muted">{new Date(entry.timestamp).toLocaleString()}</td>
                <td>{entry.action.replace(/_/g, ' ')}</td>
                <td className="muted">{entry.actor_role.replace(/_/g, ' ')}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
