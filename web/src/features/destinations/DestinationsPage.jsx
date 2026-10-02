import { useEffect, useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import {
  fetchDestinations,
  createDestination,
  updateDestination,
  deactivateDestination,
} from './destinationsSlice';

const CATEGORIES = ['Beach', 'Nature', 'Culture', 'Adventure', 'Wildlife', 'CityLife'];
const EMPTY_FORM = { name: '', region: '', description: '', category: 'Nature', imageUrl: '' };

export default function DestinationsPage() {
  const dispatch = useDispatch();
  const { items, totalCount, page, pageSize, status, error } = useSelector((s) => s.destinations);

  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('');
  const [sortBy, setSortBy] = useState('Name');
  const [currentPage, setCurrentPage] = useState(1);

  const [form, setForm] = useState(EMPTY_FORM);
  const [editingId, setEditingId] = useState(null);

  const loadDestinations = () => {
    dispatch(fetchDestinations({
      search: search || undefined,
      category: category || undefined,
      sortBy,
      page: currentPage,
      pageSize: 10,
    }));
  };

  useEffect(() => {
    loadDestinations();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search, category, sortBy, currentPage]);

  const handleFormSubmit = async (e) => {
    e.preventDefault();
    if (editingId) {
      await dispatch(updateDestination({ id: editingId, dto: { ...form, isActive: true } }));
    } else {
      await dispatch(createDestination(form));
    }
    setForm(EMPTY_FORM);
    setEditingId(null);
    loadDestinations();
  };

  const startEdit = (destination) => {
    setEditingId(destination.id);
    setForm({
      name: destination.name,
      region: destination.region,
      description: destination.description,
      category: destination.category,
      imageUrl: destination.imageUrl || '',
    });
  };

  const totalPages = Math.max(Math.ceil(totalCount / pageSize), 1);

  return (
    <div style={{ maxWidth: 900, margin: '40px auto' }}>
      <h2>Manage Destinations</h2>

      {/* Create / Edit form */}
      <form onSubmit={handleFormSubmit} style={{ border: '1px solid #ddd', padding: 16, borderRadius: 8, marginBottom: 24 }}>
        <h3>{editingId ? 'Edit Destination' : 'Add New Destination'}</h3>
        <input placeholder="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <input placeholder="Region" value={form.region} onChange={(e) => setForm({ ...form, region: e.target.value })} required
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <textarea placeholder="Description" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} required
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }}>
          {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
        <input placeholder="Image URL (optional)" value={form.imageUrl} onChange={(e) => setForm({ ...form, imageUrl: e.target.value })}
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <button type="submit" style={{ padding: 8, marginRight: 8 }}>
          {editingId ? 'Save Changes' : 'Create Destination'}
        </button>
        {editingId && (
          <button type="button" onClick={() => { setEditingId(null); setForm(EMPTY_FORM); }}>
            Cancel
          </button>
        )}
      </form>

      {/* Search / filter / sort */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        <input placeholder="Search name or region..." value={search}
          onChange={(e) => { setSearch(e.target.value); setCurrentPage(1); }}
          style={{ flex: 1, padding: 8 }} />
        <select value={category} onChange={(e) => { setCategory(e.target.value); setCurrentPage(1); }} style={{ padding: 8 }}>
          <option value="">All categories</option>
          {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
        <select value={sortBy} onChange={(e) => setSortBy(e.target.value)} style={{ padding: 8 }}>
          <option value="Name">Sort: Name</option>
          <option value="Region">Sort: Region</option>
        </select>
      </div>

      {status === 'loading' && <p>Loading...</p>}
      {error && <p style={{ color: 'red' }}>{error}</p>}

      {/* Results table */}
      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr style={{ textAlign: 'left', borderBottom: '2px solid #333' }}>
            <th>Name</th><th>Region</th><th>Category</th><th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {items.map((d) => (
            <tr key={d.id} style={{ borderBottom: '1px solid #eee' }}>
              <td>{d.name}</td>
              <td>{d.region}</td>
              <td>{d.category}</td>
              <td>
                <button onClick={() => startEdit(d)} style={{ marginRight: 6 }}>Edit</button>
                <button onClick={() => dispatch(deactivateDestination(d.id)).then(loadDestinations)}>
                  Deactivate
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {items.length === 0 && status === 'succeeded' && <p>No destinations found.</p>}

      {/* Pagination */}
      <div style={{ marginTop: 12 }}>
        <button disabled={currentPage <= 1} onClick={() => setCurrentPage((p) => p - 1)}>Prev</button>
        <span style={{ margin: '0 10px' }}>Page {page} of {totalPages}</span>
        <button disabled={currentPage >= totalPages} onClick={() => setCurrentPage((p) => p + 1)}>Next</button>
      </div>
    </div>
  );
}
