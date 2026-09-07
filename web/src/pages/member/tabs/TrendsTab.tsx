import { useEffect, useState } from 'react';
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceArea, ReferenceLine, CartesianGrid } from 'recharts';
import { api } from '../../../api/client';

function dotColor(flag: string | null): string {
  if (flag === 'out_of_range') return '#c0392b';
  if (flag === 'in_range') return '#1e8e5a';
  return '#62707d';
}

function ParameterChart({ param }: { param: any }) {
  const range = param.points[param.points.length - 1]?.resolved_reference_range;
  return (
    <div className="card">
      <div className="flex between">
        <strong>{param.display_name}</strong>
        <span className="muted">{param.unit}</span>
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <LineChart data={param.points} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#eee" />
          <XAxis dataKey="test_date" tick={{ fontSize: 11 }} />
          <YAxis tick={{ fontSize: 11 }} domain={['auto', 'auto']} />
          <Tooltip />
          {param.range_type === 'fixed_range' && range?.low != null && range?.high != null && (
            <ReferenceArea y1={range.low} y2={range.high} fill="#1e8e5a" fillOpacity={0.08} ifOverflow="extendDomain" />
          )}
          {(param.range_type === 'open_upper_bound' || param.range_type === 'open_lower_bound') && range?.low != null && (
            <ReferenceLine y={range.low} stroke="#b7791f" strokeDasharray="4 4" label={{ value: 'lower bound', fontSize: 10 }} ifOverflow="extendDomain" />
          )}
          <Line
            type="monotone"
            dataKey="value"
            stroke="#0f766e"
            strokeWidth={2}
            isAnimationActive={false}
            dot={(props: any) => {
              const flag = param.range_type === 'interpretive_rule' ? null : props.payload.in_range_flag;
              return <circle key={props.payload.test_date} cx={props.cx} cy={props.cy} r={4} fill={dotColor(flag)} />;
            }}
          />
        </LineChart>
      </ResponsiveContainer>
      {param.range_type === 'interpretive_rule' && (
        <div className="muted">Interpretive index — raw value shown, no automated flag (Section 4.6).</div>
      )}
    </div>
  );
}

function QualitativeTimeline({ param }: { param: any }) {
  return (
    <div className="card">
      <strong>{param.display_name}</strong>
      <div className="flex gap wrap" style={{ marginTop: 8 }}>
        {param.points.map((p: any, i: number) => (
          <span key={i} className="pill no_flag">
            {p.test_date}: {p.raw_value}
          </span>
        ))}
      </div>
    </div>
  );
}

export function TrendsTab({ memberId }: { memberId: string }) {
  const [data, setData] = useState<any>(null);

  useEffect(() => {
    api.getTrends(memberId).then(setData);
  }, [memberId]);

  if (!data) return <div className="center-loading">Loading…</div>;

  const categories = Object.keys(data.groupedByCategory);
  if (categories.length === 0 && data.qualitativeTimelines.length === 0) {
    return <div className="card muted">Not enough confirmed results yet — trend graphs need at least 2 confirmed data points per parameter.</div>;
  }

  return (
    <div>
      {categories.map((cat) => (
        <div key={cat} style={{ marginBottom: 24 }}>
          <h3>{cat}</h3>
          <div className="grid cols-2">
            {data.groupedByCategory[cat].map((p: any) => (
              <ParameterChart key={p.canonical_parameter_id} param={p} />
            ))}
          </div>
        </div>
      ))}

      {data.qualitativeTimelines.length > 0 && (
        <div>
          <h3>Status timelines</h3>
          <div className="grid cols-2">
            {data.qualitativeTimelines.map((p: any) => (
              <QualitativeTimeline key={p.canonical_parameter_id} param={p} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
