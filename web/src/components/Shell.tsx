import { ReactNode } from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../AuthContext';

export function Shell({ children }: { children: ReactNode }) {
  const { session, logout } = useAuth();
  if (!session) return <>{children}</>;

  const isMember = session.role === 'member_primary' || session.role === 'member_dependent';
  const isProvider = session.role === 'provider_doctor' || session.role === 'provider_clinic_admin';

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <h1>CareLoop</h1>
        <div className="role-badge">{session.role.replace('_', ' ')}</div>
        <nav>
          {isMember && (
            <>
              <NavLink to="/family" className={({ isActive }) => (isActive ? 'active' : '')}>
                Family
              </NavLink>
              <NavLink to="/appointments" className={({ isActive }) => (isActive ? 'active' : '')}>
                Appointments
              </NavLink>
            </>
          )}
          {isProvider && (
            <NavLink to="/console" className={({ isActive }) => (isActive ? 'active' : '')}>
              Console
            </NavLink>
          )}
          {session.role === 'platform_admin' && (
            <NavLink to="/admin" className={({ isActive }) => (isActive ? 'active' : '')}>
              Review queue
            </NavLink>
          )}
        </nav>
        <div style={{ marginTop: 32 }}>
          <div className="muted" style={{ marginBottom: 8 }}>
            {session.displayName}
          </div>
          <button onClick={logout} style={{ width: '100%' }}>
            Log out
          </button>
        </div>
      </aside>
      <main className="main">{children}</main>
    </div>
  );
}
