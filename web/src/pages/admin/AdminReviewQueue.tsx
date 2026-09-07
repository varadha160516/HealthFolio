import { useEffect, useState } from 'react';
import { api } from '../../api/client';

const CATEGORIES = [
  'Vitals', 'CBC', 'Diabetes panel', 'Lipid panel', 'Liver function', 'Kidney function', 'Electrolytes',
  'Thyroid panel', 'Vitamins', 'Iron studies', 'Cardiac markers', 'Inflammatory markers', 'Coagulation',
  'Urine routine', 'Hormones', 'Serology', 'Cancer markers', 'Pancreatic function',
];

function ResolveForm({ candidate, onDone }: { candidate: any; onDone: () => void }) {
  const [mode, setMode] = useState<'new_param' | 'alias' | 'interpretive_index'>('alias');
  const [aliasTarget, setAliasTarget] = useState('');
  const [newId, setNewId] = useState('');
  const [displayName, setDisplayName] = useState(candidate.label_as_printed);
  const [category, setCategory] = useState('CBC');
  const [unit, setUnit] = useState(candidate.unit || 'unitless');
  const [rangeType, setRangeType] = useState('fixed_range');
  const [low, setLow] = useState('');
  const [high, setHigh] = useState('');

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (mode === 'alias') {
      await api.resolveCandidate(candidate.id, { resolution: 'alias', canonical_parameter_id: aliasTarget });
    } else if (mode === 'new_param') {
      await api.resolveCandidate(candidate.id, {
        resolution: 'new_param',
        canonical_parameter_id: newId,
        display_name: displayName,
        category,
        canonical_unit: unit,
        range_type: rangeType,
        typical_low: low ? Number(low) : null,
        typical_high: high ? Number(high) : null,
      });
    } else {
      await api.resolveCandidate(candidate.id, { resolution: 'interpretive_index', canonical_parameter_id: newId, display_name: displayName, category });
    }
    onDone();
  }

  return (
    <form onSubmit={submit} className="card" style={{ marginTop: 8 }}>
      <div className="tabs">
        <button type="button" className={mode === 'alias' ? 'active' : ''} onClick={() => setMode('alias')}>
          Alias of existing parameter
        </button>
        <button type="button" className={mode === 'new_param' ? 'active' : ''} onClick={() => setMode('new_param')}>
          Brand-new parameter
        </button>
        <button type="button" className={mode === 'interpretive_index' ? 'active' : ''} onClick={() => setMode('interpretive_index')}>
          Lab-specific derived index
        </button>
      </div>

      {mode === 'alias' && (
        <div className="form-row">
          <label>Existing canonical_parameter_id (e.g. "creatinine")</label>
          <input required value={aliasTarget} onChange={(e) => setAliasTarget(e.target.value)} />
        </div>
      )}

      {mode !== 'alias' && (
        <div className="grid cols-2">
          <div className="form-row">
            <label>New canonical_parameter_id (snake_case)</label>
            <input required value={newId} onChange={(e) => setNewId(e.target.value)} />
          </div>
          <div className="form-row">
            <label>Display name</label>
            <input required value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
          </div>
          <div className="form-row">
            <label>Category</label>
            <select value={category} onChange={(e) => setCategory(e.target.value)}>
              {CATEGORIES.map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
          </div>
          {mode === 'new_param' && (
            <>
              <div className="form-row">
                <label>Canonical unit</label>
                <input value={unit} onChange={(e) => setUnit(e.target.value)} />
              </div>
              <div className="form-row">
                <label>Range type</label>
                <select value={rangeType} onChange={(e) => setRangeType(e.target.value)}>
                  <option value="fixed_range">fixed_range</option>
                  <option value="open_upper_bound">open_upper_bound</option>
                  <option value="open_lower_bound">open_lower_bound</option>
                  <option value="qualitative">qualitative</option>
                  <option value="none">none</option>
                </select>
              </div>
              <div className="form-row">
                <label>Typical low</label>
                <input value={low} onChange={(e) => setLow(e.target.value)} />
              </div>
              <div className="form-row">
                <label>Typical high</label>
                <input value={high} onChange={(e) => setHigh(e.target.value)} />
              </div>
            </>
          )}
          {mode === 'interpretive_index' && (
            <div className="banner">
              Stored with range_type=interpretive_rule — raw value only, no automated flag until a clinician approves
              specific threshold logic (Section 4.6). This is a clinical-safety boundary, not a UI default.
            </div>
          )}
        </div>
      )}

      <button className="primary" type="submit">
        Resolve
      </button>
    </form>
  );
}

export function AdminReviewQueue() {
  const [candidates, setCandidates] = useState<any[]>([]);
  const [openId, setOpenId] = useState<string | null>(null);

  function load() {
    api.getCandidates('pending').then(setCandidates);
  }
  useEffect(load, []);

  return (
    <div>
      <h2>Dictionary governance queue</h2>
      <p className="muted">
        Every extracted label with no match at any of the three tiers lands here (Section 5.3) — never silently
        discarded, never silently stored under a guessed parameter.
      </p>
      {candidates.length === 0 && <div className="card muted">Nothing pending — the dictionary currently covers everything seen so far.</div>}
      {candidates.map((c) => (
        <div className="card" key={c.id}>
          <div className="flex between">
            <div>
              <strong>{c.label_as_printed}</strong>
              <div className="muted">
                value: {c.value} {c.unit}
              </div>
            </div>
            <button onClick={() => setOpenId(openId === c.id ? null : c.id)}>{openId === c.id ? 'Cancel' : 'Resolve'}</button>
          </div>
          {openId === c.id && (
            <ResolveForm
              candidate={c}
              onDone={() => {
                setOpenId(null);
                load();
              }}
            />
          )}
        </div>
      ))}
    </div>
  );
}
