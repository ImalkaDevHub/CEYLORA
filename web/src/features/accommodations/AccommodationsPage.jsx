import { useEffect, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import {
  fetchAccommodations,
  fetchDestinationOptions,
  createAccommodation,
  updateAccommodation,
  deactivateAccommodation,
} from './accommodationsSlice';
import AvailabilityPanel from './AvailabilityPanel';
import { formatLkr } from '../../utils/format';

const TYPES = ['Hotel', 'Villa', 'Guesthouse', 'Resort', 'Hostel'];

const SORTS = {
  name: { label: 'Sort: Name (A–Z)', sortBy: 'Name', sortDescending: false },
  'price-asc': { label: 'Sort: Price (low to high)', sortBy: 'Price', sortDescending: false },
  'price-desc': { label: 'Sort: Price (high to low)', sortBy: 'Price', sortDescending: true },
  rating: { label: 'Sort: Top rated', sortBy: 'Rating', sortDescending: true },
};

const EMPTY_FORM = {
  destinationId: '',
  name: '',
  description: '',
  type: 'Hotel',
  pricePerNight: '',
  maxGuestsPerRoom: '2',
  isActive: true,
};

const SEARCH_DELAY_MS = 300;
const input = { display: 'block', width: '100%', marginBottom: 8, padding: 8 };

/** Checks the form the way the API will, so the operator gets the message before a round trip. */
function validate(form) {
  const name = form.name.trim();
  if (!form.destinationId) return 'Choose a destination.';
  if (name.length < 2 || name.length > 150) return 'Name must be 2 to 150 characters.';
  const price = Number(form.pricePerNight);
  if (form.pricePerNight === '' || !Number.isFinite(price) || price < 0 || price > 10_000_000) {
    return 'Price per night must be between 0 and 10,000,000.';
  }
  const guests = Number(form.maxGuestsPerRoom);
  if (!Number.isInteger(guests) || guests < 1 || guests > 20) {
    return 'Guests per room must be a whole number from 1 to 20.';
  }
  return null;
}

const toDto = (form) => ({
  destinationId: form.destinationId,
  name: form.name.trim(),
  description: form.description.trim(),
  type: form.type,
  pricePerNight: Number(form.pricePerNight),
  maxGuestsPerRoom: Number(form.maxGuestsPerRoom),
});

const fromAccommodation = (a) => ({
  destinationId: a.destinationId,
  name: a.name,
  description: a.description ?? '',
  type: a.type,
  pricePerNight: String(a.pricePerNight),
  maxGuestsPerRoom: String(a.maxGuestsPerRoom),
  isActive: a.isActive,
});

export default function AccommodationsPage() {
  const dispatch = useDispatch();
  const { items, totalCount, page, pageSize, status, error, destinationOptions } = useSelector(
    (s) => s.accommodations
  );

  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [type, setType] = useState('');
  const [includeInactive, setIncludeInactive] = useState(false);
  const [sortKey, setSortKey] = useState('name');
  const [currentPage, setCurrentPage] = useState(1);

  const [form, setForm] = useState(EMPTY_FORM);
  const [editingId, setEditingId] = useState(null);
  const [formError, setFormError] = useState(null);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [availabilityFor, setAvailabilityFor] = useState(null);

  useEffect(() => {
    dispatch(fetchDestinationOptions());
  }, [dispatch]);

  // Wait for a pause in typing before searching. Only a real change of the search text
  // goes back to page one, so paging right after opening the page is not undone.
  useEffect(() => {
    const timer = setTimeout(() => {
      const next = searchInput.trim();
      if (next !== search) {
        setSearch(next);
        setCurrentPage(1);
      }
    }, SEARCH_DELAY_MS);
    return () => clearTimeout(timer);
  }, [searchInput, search]);

  const load = () => {
    const { sortBy, sortDescending } = SORTS[sortKey];
    dispatch(fetchAccommodations({
      search: search || undefined,
      type: type || undefined,
      includeInactive: includeInactive || undefined,
      sortBy,
      sortDescending,
      page: currentPage,
      pageSize: 10,
    }));
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search, type, includeInactive, sortKey, currentPage]);

  const resetForm = () => {
    setForm(EMPTY_FORM);
    setEditingId(null);
    setFormError(null);
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setMessage(null);
    setActionError(null);

    const problem = validate(form);
    if (problem) {
      setFormError(problem);
      return;
    }

    setFormError(null);
    setSaving(true);
    const dto = toDto(form);
    const result = editingId
      ? await dispatch(updateAccommodation({ id: editingId, dto: { ...dto, isActive: form.isActive } }))
      : await dispatch(createAccommodation(dto));
    setSaving(false);

    const ok = editingId
      ? updateAccommodation.fulfilled.match(result)
      : createAccommodation.fulfilled.match(result);
    if (!ok) {
      setFormError(result.payload);
      return;
    }

    setMessage(editingId ? 'Changes saved.' : `Created "${dto.name}".`);
    resetForm();
    load();
  };

  const startEdit = (accommodation) => {
    setMessage(null);
    setActionError(null);
    setFormError(null);
    setEditingId(accommodation.id);
    setForm(fromAccommodation(accommodation));
  };

  const handleDeactivate = async (accommodation) => {
    const sure = window.confirm(
      `Deactivate "${accommodation.name}"? Travelers will no longer see it. Existing bookings and reviews are kept.`
    );
    if (!sure) return;
    setMessage(null);
    setActionError(null);
    const result = await dispatch(deactivateAccommodation(accommodation.id));
    if (deactivateAccommodation.fulfilled.match(result)) {
      setMessage(`Deactivated "${accommodation.name}".`);
      load();
    } else {
      setActionError(result.payload);
    }
  };

  const handleReactivate = async (accommodation) => {
    setMessage(null);
    setActionError(null);
    const dto = { ...toDto(fromAccommodation(accommodation)), isActive: true };
    const result = await dispatch(updateAccommodation({ id: accommodation.id, dto }));
    if (updateAccommodation.fulfilled.match(result)) {
      setMessage(`Reactivated "${accommodation.name}".`);
      load();
    } else {
      setActionError(result.payload);
    }
  };

  const totalPages = Math.max(Math.ceil(totalCount / pageSize), 1);

  return (
    <div style={{ maxWidth: 1000, margin: '40px auto' }}>
      <h2>Manage Accommodations</h2>

      <form
        onSubmit={handleSubmit}
        noValidate
        aria-label={editingId ? 'Edit accommodation' : 'Add accommodation'}
        style={{ border: '1px solid #ddd', padding: 16, borderRadius: 8, marginBottom: 24 }}
      >
        <h3>{editingId ? 'Edit Accommodation' : 'Add New Accommodation'}</h3>

        <label htmlFor="acc-destination">Destination</label>
        <select id="acc-destination" value={form.destinationId} style={input}
          onChange={(e) => setForm({ ...form, destinationId: e.target.value })}>
          <option value="">Choose a destination…</option>
          {destinationOptions.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>

        <label htmlFor="acc-name">Name</label>
        <input id="acc-name" value={form.name} style={input}
          onChange={(e) => setForm({ ...form, name: e.target.value })} />

        <label htmlFor="acc-description">Description</label>
        <textarea id="acc-description" value={form.description} style={input}
          onChange={(e) => setForm({ ...form, description: e.target.value })} />

        <div style={{ display: 'flex', gap: 12 }}>
          <div style={{ flex: 1 }}>
            <label htmlFor="acc-type">Type</label>
            <select id="acc-type" value={form.type} style={input}
              onChange={(e) => setForm({ ...form, type: e.target.value })}>
              {TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
          </div>
          <div style={{ flex: 1 }}>
            <label htmlFor="acc-price">Price per night (LKR)</label>
            <input id="acc-price" type="number" min="0" value={form.pricePerNight} style={input}
              onChange={(e) => setForm({ ...form, pricePerNight: e.target.value })} />
          </div>
          <div style={{ flex: 1 }}>
            <label htmlFor="acc-guests">Guests per room</label>
            <input id="acc-guests" type="number" min="1" max="20" value={form.maxGuestsPerRoom} style={input}
              onChange={(e) => setForm({ ...form, maxGuestsPerRoom: e.target.value })} />
          </div>
        </div>

        {editingId && (
          <label style={{ display: 'block', marginBottom: 8 }}>
            <input type="checkbox" checked={form.isActive}
              onChange={(e) => setForm({ ...form, isActive: e.target.checked })} />{' '}
            Active (visible to travelers)
          </label>
        )}

        {formError && <p role="alert" style={{ color: 'red' }}>{formError}</p>}

        <button type="submit" disabled={saving} style={{ padding: 8, marginRight: 8 }}>
          {saving ? 'Saving...' : editingId ? 'Save Changes' : 'Create Accommodation'}
        </button>
        {editingId && <button type="button" onClick={resetForm}>Cancel</button>}
      </form>

      {message && <p role="status" style={{ color: 'green' }}>{message}</p>}
      {actionError && <p role="alert" style={{ color: 'red' }}>{actionError}</p>}

      <div style={{ display: 'flex', gap: 8, marginBottom: 16, alignItems: 'center' }}>
        <input aria-label="Search accommodations" placeholder="Search name or destination..."
          value={searchInput} onChange={(e) => setSearchInput(e.target.value)} style={{ flex: 1, padding: 8 }} />
        <select aria-label="Filter by type" value={type} style={{ padding: 8 }}
          onChange={(e) => { setType(e.target.value); setCurrentPage(1); }}>
          <option value="">All types</option>
          {TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
        </select>
        <select aria-label="Sort" value={sortKey} style={{ padding: 8 }}
          onChange={(e) => { setSortKey(e.target.value); setCurrentPage(1); }}>
          {Object.entries(SORTS).map(([key, s]) => <option key={key} value={key}>{s.label}</option>)}
        </select>
        <label style={{ whiteSpace: 'nowrap' }}>
          <input type="checkbox" checked={includeInactive}
            onChange={(e) => { setIncludeInactive(e.target.checked); setCurrentPage(1); }} />{' '}
          Show inactive
        </label>
      </div>

      {status === 'loading' && <p>Loading...</p>}
      {status === 'failed' && <p role="alert" style={{ color: 'red' }}>{error}</p>}

      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr style={{ textAlign: 'left', borderBottom: '2px solid #333' }}>
            <th>Name</th><th>Destination</th><th>Type</th><th>Price / night</th>
            <th>Sleeps</th><th>Rating</th><th>Status</th><th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {items.map((a) => (
            <tr key={a.id} style={{ borderBottom: '1px solid #eee', opacity: a.isActive ? 1 : 0.6 }}>
              <td>{a.name}</td>
              <td>{a.destinationName}</td>
              <td>{a.type}</td>
              <td>{formatLkr(a.pricePerNight)}</td>
              <td>{a.maxGuestsPerRoom} / room</td>
              <td>{a.averageRating == null ? '—' : `${a.averageRating.toFixed(1)} (${a.reviewCount})`}</td>
              <td>{a.isActive ? 'Active' : 'Inactive'}</td>
              <td style={{ whiteSpace: 'nowrap' }}>
                <button onClick={() => startEdit(a)} style={{ marginRight: 6 }}
                  aria-label={`Edit ${a.name}`}>Edit</button>
                <button onClick={() => setAvailabilityFor(a)} style={{ marginRight: 6 }}
                  aria-label={`Availability for ${a.name}`}>Availability</button>
                {a.isActive ? (
                  <button onClick={() => handleDeactivate(a)} aria-label={`Deactivate ${a.name}`}>Deactivate</button>
                ) : (
                  <button onClick={() => handleReactivate(a)} aria-label={`Reactivate ${a.name}`}>Reactivate</button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {items.length === 0 && status === 'succeeded' && <p>No accommodations found.</p>}

      <div style={{ marginTop: 12 }}>
        <button disabled={currentPage <= 1} onClick={() => setCurrentPage((p) => p - 1)}>Prev</button>
        <span style={{ margin: '0 10px' }}>Page {page} of {totalPages}</span>
        <button disabled={currentPage >= totalPages} onClick={() => setCurrentPage((p) => p + 1)}>Next</button>
        <span style={{ marginLeft: 12, color: '#555' }}>{totalCount} total</span>
      </div>

      {availabilityFor && (
        <AvailabilityPanel
          key={availabilityFor.id}
          accommodation={availabilityFor}
          onClose={() => setAvailabilityFor(null)}
        />
      )}
    </div>
  );
}
