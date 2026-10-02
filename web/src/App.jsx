import { Routes, Route, Navigate, Link } from 'react-router-dom';
import { useDispatch, useSelector } from 'react-redux';
import LoginPage from './features/auth/LoginPage';
import MyTripsPage from './features/trips/MyTripsPage';
import PlanTripPage from './features/aiWorkflows/PlanTripPage';
import ApprovalsQueuePage from './features/aiWorkflows/ApprovalsQueuePage';
import DestinationsPage from './features/destinations/DestinationsPage';
import { logout } from './features/auth/authSlice';

function ProtectedRoute({ allowedRoles, children }) {
  const { token, user } = useSelector((state) => state.auth);
  if (!token) return <Navigate to="/login" replace />;
  if (allowedRoles && !allowedRoles.includes(user?.role)) return <Navigate to="/dashboard" replace />;
  return children;
}

function NavBar() {
  const { user, token } = useSelector((state) => state.auth);
  const dispatch = useDispatch();
  if (!token) return null;

  return (
    <nav style={{ padding: 12, borderBottom: '1px solid #ddd', marginBottom: 16 }}>
      <Link to="/dashboard" style={{ marginRight: 12 }}>My Trips</Link>
      {user?.role === 'Traveler' && <Link to="/plan-trip" style={{ marginRight: 12 }}>Plan with AI</Link>}
      {(user?.role === 'Operator' || user?.role === 'Admin') && (
        <>
          <Link to="/approvals" style={{ marginRight: 12 }}>Approvals</Link>
          <Link to="/destinations" style={{ marginRight: 12 }}>Destinations</Link>
        </>
      )}
      <span style={{ marginRight: 12 }}>{user?.fullName} ({user?.role})</span>
      <button onClick={() => dispatch(logout())}>Logout</button>
    </nav>
  );
}

export default function App() {
  return (
    <>
      <NavBar />
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/dashboard" element={<ProtectedRoute><MyTripsPage /></ProtectedRoute>} />
        <Route
          path="/plan-trip"
          element={<ProtectedRoute allowedRoles={['Traveler']}><PlanTripPage /></ProtectedRoute>}
        />
        <Route
          path="/approvals"
          element={<ProtectedRoute allowedRoles={['Operator', 'Admin']}><ApprovalsQueuePage /></ProtectedRoute>}
        />
        <Route
          path="/destinations"
          element={<ProtectedRoute allowedRoles={['Operator', 'Admin']}><DestinationsPage /></ProtectedRoute>}
        />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    </>
  );
}
