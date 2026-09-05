import { useEffect, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { fetchMyTrips, createTrip, submitTrip } from './tripsSlice';

export default function MyTripsPage() {
  const dispatch = useDispatch();
  const { items, status, error } = useSelector((state) => state.trips);
  const [form, setForm] = useState({ title: '', startDate: '', endDate: '', budget: '' });
  const [formError, setFormError] = useState(null);

  useEffect(() => {
    dispatch(fetchMyTrips());
  }, [dispatch]);

  const handleChange = (e) => setForm({ ...form, [e.target.name]: e.target.value });

  const handleSubmit = async (e) => {
    e.preventDefault();
    setFormError(null);
    const result = await dispatch(
      createTrip({
        title: form.title,
        startDate: form.startDate,
        endDate: form.endDate,
        budget: Number(form.budget),
      })
    );
    if (createTrip.rejected.match(result)) {
      setFormError(result.payload);
    } else {
      setForm({ title: '', startDate: '', endDate: '', budget: '' });
    }
  };

  return (
    <div style={{ maxWidth: 600, margin: '40px auto' }}>
      <h2>My Trips</h2>

      <form onSubmit={handleSubmit} style={{ marginBottom: 32, border: '1px solid #ddd', padding: 16, borderRadius: 8 }}>
        <h3>Plan a New Trip</h3>
        <input name="title" placeholder="Trip title" value={form.title} onChange={handleChange} required
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <label>Start date</label>
        <input name="startDate" type="date" value={form.startDate} onChange={handleChange} required
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <label>End date</label>
        <input name="endDate" type="date" value={form.endDate} onChange={handleChange} required
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <input name="budget" type="number" placeholder="Budget (LKR)" value={form.budget} onChange={handleChange} required
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <button type="submit" style={{ padding: 8, width: '100%' }}>Create Trip</button>
        {formError && <p style={{ color: 'red' }}>{formError}</p>}
      </form>

      {status === 'loading' && <p>Loading trips...</p>}
      {status === 'failed' && <p style={{ color: 'red' }}>{error}</p>}
      {status === 'succeeded' && items.length === 0 && <p>No trips yet — create your first one above.</p>}

      {items.map((trip) => (
        <div key={trip.id} style={{ border: '1px solid #eee', padding: 12, marginBottom: 8, borderRadius: 6 }}>
          <strong>{trip.title}</strong> — {trip.status}
          <div>{trip.startDate?.slice(0, 10)} → {trip.endDate?.slice(0, 10)} · LKR {trip.budget}</div>
          {trip.status === 'Draft' && (
            <button onClick={() => dispatch(submitTrip(trip.id))} style={{ marginTop: 6 }}>
              Submit Trip
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
