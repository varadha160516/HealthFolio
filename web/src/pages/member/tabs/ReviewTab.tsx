import { useEffect, useState } from 'react';
import { api } from '../../../api/client';

const TIER_LABEL: Record<number, string> = {
  1: 'Tier 1 — exact alias',
  2: 'Tier 2 — fuzzy match',
  3: 'Tier 3 — semantic guess',
};

export function ReviewTab({ memberId, onChanged }: { memberId: string; onChanged: () => void }) {
  const [items, setItems] = useState<any[]>([]);
  const [editing, setEditing] = useState<Record<string, string>>({});

  function load() {
    api.getReviewQueue(memberId).then(setItems);
  }
  useEffect(load, [memberId]);

  async function confirm(id: string) {
    await api.confirmParameter(id);
    load();
    onChanged();
  }
  async function correct(id: string) {
    const value = Number(editing[id]);
    if (Number.isNaN(value)) return;
    await api.correctParameter(id, { canonical_value: value });
    load();
    onChanged();
  }
  async function reject(id: string) {
    await api.rejectParameter(id);
    load();
    onChanged();
  }

  if (items.length === 0) return <div className="card muted">Nothing pending review — everything extracted so far was confident enough to auto-accept.</div>;

  return (
    <div className="card">
      <p className="muted">
        These extracted values didn't clear the auto-accept bar (Section 4.5) — either the label match was uncertain,
        the value looked implausible, or the parameter isn't in the dictionary yet. Confirm, correct, or reject each one.
      </p>
      <table>
        <thead>
          <tr>
            <th>Label as printed</th>
            <th>Matched to</th>
            <th>Value</th>
            <th>Why it's here</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {items.map((row) => (
            <tr key={row.id}>
              <td>{row.raw_label_as_printed}</td>
              <td>{row.display_name ?? <span className="muted">no dictionary match — new candidate</span>}</td>
              <td>
                {row.canonical_parameter_id ? (
                  <input
                    style={{ width: 90 }}
                    defaultValue={row.canonical_value ?? row.value_raw}
                    onChange={(e) => setEditing({ ...editing, [row.id]: e.target.value })}
                  />
                ) : (
                  row.value_raw
                )}
                {row.unit_raw ? ` ${row.unit_raw}` : ''}
              </td>
              <td className="muted">{row.match_tier ? TIER_LABEL[row.match_tier] : 'No dictionary match'}</td>
              <td>
                <div className="flex gap">
                  {row.canonical_parameter_id && (
                    <>
                      <button onClick={() => confirm(row.id)}>Confirm</button>
                      <button onClick={() => correct(row.id)}>Save edit</button>
                    </>
                  )}
                  <button className="danger" onClick={() => reject(row.id)}>
                    Reject
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
