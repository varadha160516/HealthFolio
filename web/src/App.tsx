import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './AuthContext';
import { Shell } from './components/Shell';
import { LoginPage } from './pages/LoginPage';
import { FamilyDashboard } from './pages/member/FamilyDashboard';
import { MemberProfile } from './pages/member/MemberProfile';
import { AppointmentsPage } from './pages/member/AppointmentsPage';
import { ProviderConsole } from './pages/provider/ProviderConsole';
import { AppointmentWorkspace } from './pages/provider/AppointmentWorkspace';
import { AdminReviewQueue } from './pages/admin/AdminReviewQueue';

function HomeRedirect() {
  const { session } = useAuth();
  if (!session) return <Navigate to="/login" replace />;
  if (session.role === 'member_primary' || session.role === 'member_dependent') return <Navigate to="/family" replace />;
  if (session.role === 'provider_doctor' || session.role === 'provider_clinic_admin') return <Navigate to="/console" replace />;
  return <Navigate to="/admin" replace />;
}

function RequireAuth({ children }: { children: JSX.Element }) {
  const { session, loading } = useAuth();
  if (loading) return <div className="center-loading">Loading…</div>;
  if (!session) return <Navigate to="/login" replace />;
  return children;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/*"
        element={
          <RequireAuth>
            <Shell>
              <Routes>
                <Route path="/" element={<HomeRedirect />} />
                <Route path="/family" element={<FamilyDashboard />} />
                <Route path="/members/:memberId/*" element={<MemberProfile />} />
                <Route path="/appointments" element={<AppointmentsPage />} />
                <Route path="/console" element={<ProviderConsole />} />
                <Route path="/console/:appointmentId" element={<AppointmentWorkspace />} />
                <Route path="/admin" element={<AdminReviewQueue />} />
              </Routes>
            </Shell>
          </RequireAuth>
        }
      />
    </Routes>
  );
}
