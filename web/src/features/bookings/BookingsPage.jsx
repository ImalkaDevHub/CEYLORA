import { useEffect, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { fetchBookings, fetchStayOptions, cancelBooking } from './bookingsSlice';
import { formatDateOnly, formatLkr, formatTimestamp } from '../../utils/format';

const STATUSES = ['Confirmed', 'Cancelled'];
const PAGE_SIZE = 20;

const staySummary = (item) =>
  `${item.accommodationName} · ${formatDateOnly(item.checkIn)} → ${formatDateOnly(item.checkOut)} · ` +
  `${item.rooms} room${item.rooms === 1 ? '' : 's'}`;

/** Every traveler's bookings, for operators: filter by status or stay, and cancel one. */
export default function BookingsPage() {
  const dispatch = useDispatch();
  const { items, totalCount, page, pageSize, status, error, stayOptions } = useSelector((s) => s.bookings);

  const [statusFilter, setStatusFilter] = useState('');
  const [stayFilter, setStayFilter] = useState('');
  const [currentPage, setCurrentPage] = useState(1);
  const [message, setMessage] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [cancellingId, setCancellingId] = useState(null);

  useEffect(() => {
    dispatch(fetchStayOptions());
  }, [dispatch]);

  const load = () => {
    dispatch(fetchBookings({
      status: statusFilter || undefined,
      accommodationId: stayFilter || undefined,
      page: currentPage,
      pageSize: PAGE_SIZE,
    }));
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [statusFilter, stayFilter, currentPage]);

  const handleCancel = async (booking) => {
    const stays = booking.items.map((i) => i.accommodationName).join(', ');
    const sure = window.confirm(
      `Cancel ${booking.travelerName}'s booking (${stays})? The rooms will be released for other travelers.`
    );
    if (!sure) return;

    setMessage(null);
    setActionError(null);
    setCancellingId(booking.id);
    const result = await dispatch(cancelBooking(booking.id));
    setCancellingId(null);

    if (cancelBooking.fulfilled.match(result)) {
      setMessage(`Cancelled ${booking.travelerName}'s booking.`);
    } else {
      setActionError(result.payload);
    }
  };

  const totalPages = Math.max(Math.ceil(totalCount / pageSize), 1);

  return (
    <div style={{ maxWidth: 1100, margin: '40px auto' }}>
      <h2>Bookings</h2>

      <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        <select aria-label="Filter by status" value={statusFilter} style={{ padding: 8 }}
          onChange={(e) => { setStatusFilter(e.target.value); setCurrentPage(1); }}>
          <option value="">All statuses</option>
          {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
        <select aria-label="Filter by accommodation" value={stayFilter} style={{ padding: 8 }}
          onChange={(e) => { setStayFilter(e.target.value); setCurrentPage(1); }}>
          <option value="">All accommodations</option>
          {stayOptions.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
        </select>
      </div>

      {message && <p role="status" style={{ color: 'green' }}>{message}</p>}
      {actionError && <p role="alert" style={{ color: 'red' }}>{actionError}</p>}
      {status === 'loading' && <p>Loading...</p>}
      {status === 'failed' && <p role="alert" style={{ color: 'red' }}>{error}</p>}

      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr style={{ textAlign: 'left', borderBottom: '2px solid #333' }}>
            <th>Booked</th><th>Traveler</th><th>Trip</th><th>Stays</th>
            <th>Total</th><th>Status</th><th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {items.map((b) => (
            <tr key={b.id} style={{ borderBottom: '1px solid #eee', verticalAlign: 'top' }}>
              <td>{formatTimestamp(b.createdAt)}</td>
              <td>{b.travelerName}</td>
              <td>{b.tripTitle}</td>
              <td>
                {b.items.map((i) => <div key={i.id}>{staySummary(i)}</div>)}
                {b.notes && <div style={{ fontSize: 13, color: '#555' }}>Note: {b.notes}</div>}
              </td>
              <td>{formatLkr(b.totalAmount)}</td>
              <td style={{ color: b.status === 'Cancelled' ? 'crimson' : undefined }}>{b.status}</td>
              <td>
                {b.status === 'Confirmed' && (
                  <button onClick={() => handleCancel(b)} disabled={cancellingId === b.id}
                    aria-label={`Cancel booking of ${b.travelerName}`}>
                    {cancellingId === b.id ? 'Cancelling...' : 'Cancel'}
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {items.length === 0 && status === 'succeeded' && <p>No bookings found.</p>}

      <div style={{ marginTop: 12 }}>
        <button disabled={currentPage <= 1} onClick={() => setCurrentPage((p) => p - 1)}>Prev</button>
        <span style={{ margin: '0 10px' }}>Page {page} of {totalPages}</span>
        <button disabled={currentPage >= totalPages} onClick={() => setCurrentPage((p) => p + 1)}>Next</button>
        <span style={{ marginLeft: 12, color: '#555' }}>{totalCount} total</span>
      </div>
    </div>
  );
}
