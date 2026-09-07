import { useEffect, useState } from 'react';
import { api } from '../../../api/client';

export function YoYTab({ memberId }: { memberId: string }) {
  const [data, setData] = useState<any>(null);

  useEffect(() => {
    api.getYoY(memberId).then(setData);
  }, [memberId]);

  if (!data) return <div className="center-loading">Loading…</div>;
  if (!data.date1) return <div className="card muted">Need at least two dated panels sharing common parameters to compare.</div>;

  const byCategory: Record<string, any[]> = {};
  for (const row of data.comparison) (byCategory[row.category] ??= []).push(row);

  return (
    <div>
      <div className="banner info">
        Comparing <strong>{data.date1}</strong> vs <strong>{data.date2}</strong> — the two most recent dates sharing the
        most parameters in common (Section 6.2).
      </div>
      {Object.keys(byCategory).map((cat) => (
        <div className="card" key={cat}>
          <h3>{cat}</h3>
          <table>
            <thead>
              <tr>
                <th>Parameter</th>
                <th>{data.date1}</th>
                <th>{data.date2}</th>
                <th>Δ</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {byCategory[cat].map((row) => (
                <tr key={row.canonical_parameter_id}>
                  <td>{row.display_name}</td>
                  <td className="muted">
                    {row.prior_value} {row.unit}
                  </td>
                  <td>
                    {row.new_value} {row.unit}
                  </td>
                  <td className={row.delta > 0 ? 'muted' : 'muted'}>{row.delta != null ? (row.delta > 0 ? `+${row.delta.toFixed(2)}` : row.delta.toFixed(2)) : '—'}</td>
                  <td>{row.in_range_flag && <span className={`pill ${row.in_range_flag}`}>{row.in_range_flag.replace('_', ' ')}</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
    </div>
  );
}
