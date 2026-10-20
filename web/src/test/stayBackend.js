import { apiError } from './testUtils';

export const acc = (n, over = {}) => ({
  id: `a${n}`,
  destinationId: 'd1',
  destinationName: 'Galle Fort',
  name: `Stay ${String(n).padStart(2, '0')}`,
  description: 'A lovely place',
  type: 'Hotel',
  pricePerNight: 20000,
  maxGuestsPerRoom: 2,
  isActive: true,
  averageRating: null,
  reviewCount: 0,
  ...over,
});

export const booking = (n, over = {}) => ({
  id: `b${n}`,
  tripId: 't1',
  tripTitle: 'South coast',
  travelerId: 'u1',
  travelerName: 'Sam Traveler',
  status: 'Confirmed',
  totalAmount: 40000,
  notes: null,
  createdAt: '2026-10-20T10:00:00Z',
  cancelledAt: null,
  items: [
    {
      id: `i${n}`,
      accommodationId: 'a1',
      accommodationName: 'Stay 01',
      destinationName: 'Galle Fort',
      checkIn: '2026-11-01',
      checkOut: '2026-11-03',
      nights: 2,
      rooms: 1,
      guests: 2,
      nightlyRate: 20000,
      subtotal: 40000,
    },
  ],
  ...over,
});

export const night = (date, total, booked = 0) => ({
  date,
  totalRooms: total,
  bookedRooms: booked,
  availableRooms: total - booked,
});

/** "yyyy-MM-dd" plus n days, via UTC so it never depends on the machine's time zone. */
export function addDays(date, n) {
  const [y, m, d] = date.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return `${t.getUTCFullYear()}-${String(t.getUTCMonth() + 1).padStart(2, '0')}-${String(t.getUTCDate()).padStart(2, '0')}`;
}

const page = (rows, params) => {
  const p = Number(params.page ?? 1);
  const size = Number(params.pageSize ?? 10);
  return { items: rows.slice((p - 1) * size, p * size), totalCount: rows.length, page: p, pageSize: size };
};

/**
 * In-memory stand-in for the accommodation, availability and booking endpoints.
 * Mutate the public fields to steer a test; `handler` plugs into installApi().
 */
export function createStayBackend() {
  const state = {
    destinations: [
      { id: 'd1', name: 'Galle Fort' },
      { id: 'd2', name: 'Ella' },
    ],
    accommodations: [acc(1), acc(2), acc(3)],
    bookings: [booking(1)],
    availability: {}, // accommodationId -> [night, ...]
    failures: {}, // 'GET /api/bookings' -> apiError(...) for the next matching call
  };

  const failureFor = (key) => {
    const failure = state.failures[key];
    if (failure) return failure;
    return null;
  };

  state.handler = ({ method, url, params, body }) => {
    const key = `${method.toUpperCase()} ${url}`;
    const fail = failureFor(key);
    if (fail) throw fail;

    if (key === 'GET /api/destinations') {
      return { data: { items: state.destinations, totalCount: state.destinations.length, page: 1, pageSize: 100 } };
    }

    if (key === 'GET /api/accommodations') {
      let rows = state.accommodations.filter((a) => params.includeInactive || a.isActive);
      if (params.search) {
        const q = params.search.toLowerCase();
        rows = rows.filter((a) => a.name.toLowerCase().includes(q) || a.destinationName.toLowerCase().includes(q));
      }
      if (params.type) rows = rows.filter((a) => a.type === params.type);
      const by = { Name: (a) => a.name, Price: (a) => a.pricePerNight, Rating: (a) => a.averageRating ?? 0 }[params.sortBy ?? 'Name'];
      rows = [...rows].sort((a, b) => (by(a) > by(b) ? 1 : by(a) < by(b) ? -1 : 0));
      if (params.sortDescending) rows.reverse();
      return { data: page(rows, params) };
    }

    if (key === 'POST /api/accommodations') {
      const taken = state.accommodations.some(
        (a) => a.destinationId === body.destinationId && a.name.toLowerCase() === body.name.toLowerCase()
      );
      if (taken) throw apiError(409, { message: `Galle Fort already has an accommodation called '${body.name}'.` });
      const dest = state.destinations.find((d) => d.id === body.destinationId);
      const created = acc(state.accommodations.length + 1, { ...body, destinationName: dest?.name ?? '' });
      state.accommodations.push(created);
      return { data: created, status: 201 };
    }

    const stay = /^\/api\/accommodations\/([^/]+)(\/availability)?$/.exec(url);
    if (stay) {
      const id = stay[1];
      const index = state.accommodations.findIndex((a) => a.id === id);
      if (index === -1) throw apiError(404, { message: 'Accommodation not found.' });

      if (!stay[2] && method === 'put') {
        const dest = state.destinations.find((d) => d.id === body.destinationId);
        state.accommodations[index] = { ...state.accommodations[index], ...body, destinationName: dest?.name ?? '' };
        return { data: state.accommodations[index] };
      }
      if (!stay[2] && method === 'delete') {
        state.accommodations[index] = { ...state.accommodations[index], isActive: false };
        return { data: null, status: 204 };
      }
      if (stay[2] && method === 'get') {
        const rows = (state.availability[id] ?? []).filter((n) => n.date >= params.from && n.date <= params.to);
        return { data: rows };
      }
      if (stay[2] && method === 'put') {
        const rows = state.availability[id] ?? [];
        for (let d = body.from; d <= body.to; d = addDays(d, 1)) {
          const existing = rows.find((n) => n.date === d);
          if (existing && body.totalRooms < existing.bookedRooms) {
            throw apiError(409, {
              message: `Cannot set ${body.totalRooms} room(s) on ${d}: ${existing.bookedRooms} already booked.`,
            });
          }
        }
        const touched = [];
        for (let d = body.from; d <= body.to; d = addDays(d, 1)) {
          const i = rows.findIndex((n) => n.date === d);
          const updated = night(d, body.totalRooms, i === -1 ? 0 : rows[i].bookedRooms);
          if (i === -1) rows.push(updated);
          else rows[i] = updated;
          touched.push(updated);
        }
        rows.sort((a, b) => (a.date > b.date ? 1 : -1));
        state.availability[id] = rows;
        return { data: touched };
      }
    }

    if (key === 'GET /api/bookings') {
      let rows = [...state.bookings];
      if (params.status) rows = rows.filter((b) => b.status === params.status);
      if (params.accommodationId) {
        rows = rows.filter((b) => b.items.some((i) => i.accommodationId === params.accommodationId));
      }
      return { data: page(rows, { pageSize: 20, ...params }) };
    }

    const cancel = /^\/api\/bookings\/([^/]+)\/cancel$/.exec(url);
    if (cancel && method === 'post') {
      const index = state.bookings.findIndex((b) => b.id === cancel[1]);
      if (index === -1) throw apiError(404, { message: 'Booking not found.' });
      state.bookings[index] = { ...state.bookings[index], status: 'Cancelled', cancelledAt: '2026-10-21T10:00:00Z' };
      return { data: state.bookings[index] };
    }

    throw apiError(404, { message: `No fake route for ${key}` });
  };

  return state;
}
