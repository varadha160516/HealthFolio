import { useEffect, useState } from 'react';
import { api } from '../../../api/client';

// Section 3.2 #4 — the one screen a member can show a new doctor in ten seconds.
export function OverviewTab({ memberId }: { memberId: string }) {
  const [summary, setSummary] = useState<any>(null);
  const [newAllergy, setNewAllergy] = useState('');
  const [newCondition, setNewCondition] = useState('');

  function load() {
    api.getSummary(memberId).then(setSummary);
  }
  useEffect(load, [memberId]);

  if (!summary) return <div className="center-loading">Loading…</div>;

  return (
    <div className="grid cols-2">
      <div className="card">
        <h3>Allergies</h3>
        {summary.allergies.length === 0 && <div className="muted">None recorded.</div>}
        <ul>
          {summary.allergies.map((a: any) => (
            <li key={a.id}>{a.value}</li>
          ))}
        </ul>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            if (!newAllergy.trim()) return;
            await api.addAllergy(memberId, newAllergy.trim());
            setNewAllergy('');
            load();
          }}
          className="flex gap"
        >
          <input value={newAllergy} onChange={(e) => setNewAllergy(e.target.value)} placeholder="Add allergy" />
          <button type="submit">Add</button>
        </form>
      </div>

      <div className="card">
        <h3>Chronic conditions</h3>
        {summary.chronicConditions.length === 0 && <div className="muted">None recorded.</div>}
        <ul>
          {summary.chronicConditions.map((c: any) => (
            <li key={c.id}>{c.value}</li>
          ))}
        </ul>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            if (!newCondition.trim()) return;
            await api.addChronicCondition(memberId, newCondition.trim());
            setNewCondition('');
            load();
          }}
          className="flex gap"
        >
          <input value={newCondition} onChange={(e) => setNewCondition(e.target.value)} placeholder="Add condition" />
          <button type="submit">Add</button>
        </form>
      </div>

      <div className="card">
        <h3>Current medications</h3>
        {summary.currentMedications.length === 0 && <div className="muted">None on file.</div>}
        <table>
          <tbody>
            {summary.currentMedications.map((m: any, i: number) => (
              <tr key={i}>
                <td>{m.medicine_name}</td>
                <td className="muted">
                  {[m.dosage, m.frequency, m.duration].filter(Boolean).join(' · ')}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Recent out-of-range flags</h3>
        {summary.recentOutOfRangeFlags.length === 0 && <div className="muted">Nothing flagged in the latest results.</div>}
        <table>
          <tbody>
            {summary.recentOutOfRangeFlags.map((f: any, i: number) => (
              <tr key={i}>
                <td>{f.display_name}</td>
                <td>
                  {f.canonical_value} {f.canonical_unit}
                </td>
                <td className="muted">{f.test_date}</td>
                <td>
                  <span className="pill out_of_range">out of range</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
