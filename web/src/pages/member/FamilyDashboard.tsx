import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../../api/client';

function age(dob: string | null): string {
  if (!dob) return '';
  const diff = Date.now() - new Date(dob).getTime();
  return `${Math.floor(diff / (365.25 * 24 * 3600 * 1000))} yrs`;
}

export function FamilyDashboard() {
  const [members, setMembers] = useState<any[]>([]);
  const [showAdd, setShowAdd] = useState(false);
  const [form, setForm] = useState({ name: '', dob: '', sex: '', blood_group: '', relationship_to_primary: 'child' });
  const [loading, setLoading] = useState(true);

  function load() {
    api.getFamily().then((f) => {
      setMembers(f.members);
      setLoading(false);
    });
  }
  useEffect(load, []);

  async function addMember(e: React.FormEvent) {
    e.preventDefault();
    await api.addMember(form);
    setShowAdd(false);
    setForm({ name: '', dob: '', sex: '', blood_group: '', relationship_to_primary: 'child' });
    load();
  }

  if (loading) return <div className="center-loading">Loading…</div>;

  return (
    <div>
      <div className="flex between">
        <h2 style={{ margin: '0 0 16px' }}>Your family</h2>
        <button onClick={() => setShowAdd((s) => !s)}>{showAdd ? 'Cancel' : '+ Add dependent'}</button>
      </div>

      {showAdd && (
        <div className="card">
          <form onSubmit={addMember}>
            <div className="grid cols-2">
              <div className="form-row">
                <label>Name</label>
                <input required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
              </div>
              <div className="form-row">
                <label>Relationship</label>
                <select value={form.relationship_to_primary} onChange={(e) => setForm({ ...form, relationship_to_primary: e.target.value })}>
                  <option value="spouse">Spouse</option>
                  <option value="child">Child</option>
                  <option value="parent">Parent</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div className="form-row">
                <label>Date of birth</label>
                <input type="date" value={form.dob} onChange={(e) => setForm({ ...form, dob: e.target.value })} />
              </div>
              <div className="form-row">
                <label>Sex</label>
                <select value={form.sex} onChange={(e) => setForm({ ...form, sex: e.target.value })}>
                  <option value="">—</option>
                  <option value="male">Male</option>
                  <option value="female">Female</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div className="form-row">
                <label>Blood group</label>
                <input value={form.blood_group} onChange={(e) => setForm({ ...form, blood_group: e.target.value })} placeholder="O+" />
              </div>
            </div>
            <button className="primary" type="submit">
              Add to family
            </button>
          </form>
        </div>
      )}

      <div className="card">
        {members.map((m) => (
          <Link key={m.id} to={`/members/${m.id}`} className="member-list-item">
            <div>
              <strong>{m.name}</strong>
              <div className="muted">
                {m.relationship_to_primary} · {age(m.dob)} {m.blood_group ? `· ${m.blood_group}` : ''}
              </div>
            </div>
            <span className="muted">View profile →</span>
          </Link>
        ))}
      </div>
    </div>
  );
}
