import { useEffect, useState } from 'react';
import { api } from '../../api/client';

export function AppointmentsPage() {
  const [appointments, setAppointments] = useState<any[]>([]);
  const [providers, setProviders] = useState<any[]>([]);
  const [members, setMembers] = useState<any[]>([]);
  const [form, setForm] = useState({ member_id: '', provider_id: '', datetime: '', sharing_preference: 'full_history' });

  function load() {
    api.getAppointments().then(setAppointments);
  }

  useEffect(() => {
    load();
    api.getProviders().then(setProviders);
    api.getFamily().then((f) => {
      setMembers(f.members);
      setForm((s) => ({ ...s, member_id: f.members[0]?.id ?? '' }));
    });
  }, []);

  async function book(e: React.FormEvent) {
    e.preventDefault();
    if (!form.provider_id || !form.datetime) return;
    await api.bookAppointment(form);
    load();
  }

  async function respond(id: string, approve: boolean) {
    await api.respondConsent(id, approve);
    load();
  }

  return (
    <div>
      <div className="card">
        <h2>Book an appointment</h2>
        <form onSubmit={book}>
          <div className="grid cols-3">
            <div className="form-row">
              <label>For</label>
              <select value={form.member_id} onChange={(e) => setForm({ ...form, member_id: e.target.value })}>
                {members.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.name}
                  </option>
                ))}
              </select>
            </div>
            <div className="form-row">
              <label>Doctor</label>
              <select value={form.provider_id} onChange={(e) => setForm({ ...form, provider_id: e.target.value })}>
                <option value="">Select…</option>
                {providers.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name} · {p.specialty}
                  </option>
                ))}
              </select>
            </div>
            <div className="form-row">
              <label>Date & time</label>
              <input type="datetime-local" value={form.datetime} onChange={(e) => setForm({ ...form, datetime: e.target.value })} />
            </div>
          </div>
          <div className="form-row" style={{ maxWidth: 260 }}>
            <label>Sharing preference (a hint only — grants no access, Section 8.1)</label>
            <select value={form.sharing_preference} onChange={(e) => setForm({ ...form, sharing_preference: e.target.value })}>
              <option value="summary_card">Summary card</option>
              <option value="full_history">Full history</option>
            </select>
          </div>
          <button className="primary" type="submit">
            Book
          </button>
        </form>
      </div>

      <div className="card">
        <h2>Your appointments</h2>
        <table>
          <thead>
            <tr>
              <th>Patient</th>
              <th>Doctor</th>
              <th>When</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {appointments.map((a) => (
              <tr key={a.id}>
                <td>{a.member?.name}</td>
                <td>{a.provider?.name}</td>
                <td className="muted">{new Date(a.datetime).toLocaleString()}</td>
                <td>
                  <span className={`pill status-${a.status}`}>{a.status.replace(/_/g, ' ')}</span>
                </td>
                <td>
                  {a.status === 'consent_requested' && (
                    <div className="flex gap">
                      <button onClick={() => respond(a.id, true)}>Approve</button>
                      <button className="danger" onClick={() => respond(a.id, false)}>
                        Deny
                      </button>
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
