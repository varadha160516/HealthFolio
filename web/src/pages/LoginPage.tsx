import { FormEvent, useState } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../AuthContext';

const DEMO_ACCOUNTS = [
  { label: 'Family coordinator — Priya Sharma', email: 'priya@example.com' },
  { label: 'Doctor — Dr. Ananya Rao', email: 'dr.rao@example.com' },
  { label: 'Clinic front desk', email: 'frontdesk@example.com' },
  { label: 'Platform admin', email: 'admin@careloop.app' },
];

export function LoginPage() {
  const { session, login } = useAuth();
  const [email, setEmail] = useState('priya@example.com');
  const [password, setPassword] = useState('password123');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (session) return <Navigate to="/" replace />;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await login(email, password);
    } catch (err: any) {
      setError(err.message || 'Login failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <div className="login-box card">
        <h2>CareLoop</h2>
        <p className="muted">Sign in to continue.</p>
        <form onSubmit={onSubmit}>
          <div className="form-row">
            <label>Email</label>
            <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" required />
          </div>
          <div className="form-row">
            <label>Password</label>
            <input value={password} onChange={(e) => setPassword(e.target.value)} type="password" required />
          </div>
          {error && <div className="banner">{error}</div>}
          <button className="primary" type="submit" disabled={busy} style={{ width: '100%' }}>
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
        <div style={{ marginTop: 18 }}>
          <div className="muted" style={{ marginBottom: 6 }}>
            Demo accounts (password: password123)
          </div>
          {DEMO_ACCOUNTS.map((a) => (
            <button
              key={a.email}
              type="button"
              style={{ display: 'block', width: '100%', textAlign: 'left', marginBottom: 6 }}
              onClick={() => setEmail(a.email)}
            >
              {a.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
