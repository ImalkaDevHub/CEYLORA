import { useEffect, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { fetchAvailability, setAvailability, clearAvailability } from './accommodationsSlice';
import { dateInputFromToday, formatDateOnly, nightsBetween } from '../../utils/format';

const MAX_WINDOW_NIGHTS = 120;
const MAX_SET_NIGHTS = 366;
const MAX_ROOMS = 500;

const field = { display: 'block', padding: 8, marginBottom: 8 };

/**
 * Room inventory of one accommodation: see the nights (total / booked / free) and set how
 * many rooms exist for a range of nights. The API refuses a total below what is already
 * booked, and says which night; that message is shown as it comes.
 */
export default function AvailabilityPanel({ accommodation, onClose }) {
  const dispatch = useDispatch();
  const { days, status, error } = useSelector((s) => s.accommodations.availability);

  const [showFrom, setShowFrom] = useState(dateInputFromToday(0));
  const [showTo, setShowTo] = useState(dateInputFromToday(29));
  const [setFrom, setSetFrom] = useState(dateInputFromToday(0));
  const [setTo, setSetTo] = useState(dateInputFromToday(29));
  const [rooms, setRooms] = useState('2');

  const [windowError, setWindowError] = useState(null);
  const [saveError, setSaveError] = useState(null);
  const [message, setMessage] = useState(null);
  const [saving, setSaving] = useState(false);

  const load = (from = showFrom, to = showTo) => {
    if (!from || !to) {
      setWindowError('Choose both dates.');
      return;
    }
    if (to < from) {
      setWindowError("'To' cannot be before 'From'.");
      return;
    }
    if (nightsBetween(from, to) + 1 > MAX_WINDOW_NIGHTS) {
      setWindowError(`Show at most ${MAX_WINDOW_NIGHTS} nights at a time.`);
      return;
    }
    setWindowError(null);
    dispatch(fetchAvailability({ id: accommodation.id, from, to }));
  };

  useEffect(() => {
    load();
    return () => {
      dispatch(clearAvailability());
    };
    // Reload only when a different accommodation is opened.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accommodation.id]);

  const handleSet = async (e) => {
    e.preventDefault();
    setMessage(null);

    const total = Number(rooms);
    if (!setFrom || !setTo) return setSaveError('Choose both dates.');
    if (setFrom < dateInputFromToday(0)) return setSaveError('Availability can only be set for today or later.');
    if (setTo < setFrom) return setSaveError("'To' cannot be before 'From'.");
    if (nightsBetween(setFrom, setTo) + 1 > MAX_SET_NIGHTS) {
      return setSaveError(`Set at most ${MAX_SET_NIGHTS} nights at a time.`);
    }
    if (rooms === '' || !Number.isInteger(total) || total < 0 || total > MAX_ROOMS) {
      return setSaveError(`Rooms must be a whole number from 0 to ${MAX_ROOMS}.`);
    }

    setSaveError(null);
    setSaving(true);
    const result = await dispatch(
      setAvailability({ id: accommodation.id, dto: { from: setFrom, to: setTo, totalRooms: total } })
    );
    setSaving(false);

    if (setAvailability.fulfilled.match(result)) {
      const count = result.payload.days.length;
      setMessage(`Updated ${count} night${count === 1 ? '' : 's'} to ${total} room${total === 1 ? '' : 's'}.`);
      load();
    } else {
      setSaveError(result.payload);
    }
  };

  return (
    <section
      aria-label={`Availability for ${accommodation.name}`}
      style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, marginTop: 24 }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ margin: 0 }}>Room availability — {accommodation.name}</h3>
        <button type="button" onClick={onClose}>Close</button>
      </div>

      <div style={{ display: 'flex', gap: 12, alignItems: 'flex-end', marginTop: 12, flexWrap: 'wrap' }}>
        <div>
          <label htmlFor="avail-show-from">Show from</label>
          <input id="avail-show-from" type="date" value={showFrom} style={field}
            onChange={(e) => setShowFrom(e.target.value)} />
        </div>
        <div>
          <label htmlFor="avail-show-to">Show to</label>
          <input id="avail-show-to" type="date" value={showTo} style={field}
            onChange={(e) => setShowTo(e.target.value)} />
        </div>
        <button type="button" onClick={() => load()} style={{ ...field, marginBottom: 8 }}>Refresh</button>
      </div>
      {windowError && <p role="alert" style={{ color: 'red' }}>{windowError}</p>}

      {status === 'loading' && <p>Loading availability...</p>}
      {status === 'failed' && <p role="alert" style={{ color: 'red' }}>{error}</p>}

      {status === 'succeeded' && days.length === 0 && (
        <p>No rooms have been set for these nights yet.</p>
      )}
      {days.length > 0 && (
        <table style={{ width: '100%', borderCollapse: 'collapse', marginBottom: 16 }}>
          <thead>
            <tr style={{ textAlign: 'left', borderBottom: '2px solid #333' }}>
              <th>Night</th><th>Total rooms</th><th>Booked</th><th>Free</th>
            </tr>
          </thead>
          <tbody>
            {days.map((d) => (
              <tr key={d.date} style={{ borderBottom: '1px solid #eee' }}>
                <td>{formatDateOnly(d.date)}</td>
                <td>{d.totalRooms}</td>
                <td>{d.bookedRooms}</td>
                <td style={{ color: d.availableRooms === 0 ? 'crimson' : undefined }}>
                  {d.availableRooms === 0 ? 'Sold out' : d.availableRooms}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <form onSubmit={handleSet} noValidate style={{ borderTop: '1px solid #eee', paddingTop: 12 }}>
        <h4 style={{ marginTop: 0 }}>Set rooms for a range of nights</h4>
        <div style={{ display: 'flex', gap: 12, alignItems: 'flex-end', flexWrap: 'wrap' }}>
          <div>
            <label htmlFor="avail-set-from">Set from</label>
            <input id="avail-set-from" type="date" value={setFrom} style={field}
              onChange={(e) => setSetFrom(e.target.value)} />
          </div>
          <div>
            <label htmlFor="avail-set-to">Set to</label>
            <input id="avail-set-to" type="date" value={setTo} style={field}
              onChange={(e) => setSetTo(e.target.value)} />
          </div>
          <div>
            <label htmlFor="avail-rooms">Rooms per night</label>
            <input id="avail-rooms" type="number" min="0" max={MAX_ROOMS} value={rooms} style={{ ...field, width: 100 }}
              onChange={(e) => setRooms(e.target.value)} />
          </div>
          <button type="submit" disabled={saving} style={{ ...field, marginBottom: 8 }}>
            {saving ? 'Saving...' : 'Update rooms'}
          </button>
        </div>
        {saveError && <p role="alert" style={{ color: 'red' }}>{saveError}</p>}
        {message && <p role="status" style={{ color: 'green' }}>{message}</p>}
        <p style={{ fontSize: 13, color: '#555' }}>
          Nights that already have bookings keep them; you cannot set fewer rooms than are booked.
        </p>
      </form>
    </section>
  );
}
