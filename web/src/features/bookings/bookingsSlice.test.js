import { beforeEach, describe, expect, it, vi } from 'vitest';
import { configureStore } from '@reduxjs/toolkit';
import reducer, { cancelBooking, fetchBookings, fetchStayOptions } from './bookingsSlice';
import { acc, booking, createStayBackend } from '../../test/stayBackend';
import { apiError, installApi } from '../../test/testUtils';

vi.mock('../../api/axiosClient', async () => (await import('../../test/axiosMock')).mockedAxios());

describe('bookingsSlice', () => {
  let backend;
  let calls;
  let store;
  const state = () => store.getState().bookings;

  beforeEach(() => {
    backend = createStayBackend();
    backend.bookings = [booking(1), booking(2, { status: 'Cancelled' }), booking(3)];
    calls = installApi(backend.handler);
    store = configureStore({ reducer: { bookings: reducer } });
  });

  it('loads bookings with their paging', async () => {
    await store.dispatch(fetchBookings({ page: 1, pageSize: 20 }));

    expect(state().status).toBe('succeeded');
    expect(state().items).toHaveLength(3);
    expect(state().totalCount).toBe(3);
  });

  it('passes the filters to the API', async () => {
    await store.dispatch(fetchBookings({ status: 'Cancelled', accommodationId: 'a1', page: 2 }));

    expect(calls.to('get', '/api/bookings')[0].params).toEqual({ status: 'Cancelled', accommodationId: 'a1', page: 2 });
    expect(state().items.map((b) => b.id)).toEqual([]); // page 2 of a single page
  });

  it('keeps the API message when loading fails', async () => {
    backend.failures['GET /api/bookings'] = apiError(403, {});

    await store.dispatch(fetchBookings({}));

    expect(state().status).toBe('failed');
    expect(state().error).toMatch(/permission/i);
  });

  it('loads every stay (inactive included) as filter options', async () => {
    backend.accommodations = [acc(1), acc(2, { isActive: false })];

    await store.dispatch(fetchStayOptions());

    expect(state().stayOptions.map((o) => o.id)).toEqual(['a1', 'a2']);
    expect(calls.to('get', '/api/accommodations')[0].params).toEqual({
      includeInactive: true,
      pageSize: 50,
      sortBy: 'Name',
    });
  });

  it('replaces a cancelled booking in place', async () => {
    await store.dispatch(fetchBookings({}));

    await store.dispatch(cancelBooking('b1'));

    expect(state().items.map((b) => [b.id, b.status])).toEqual([
      ['b1', 'Cancelled'],
      ['b2', 'Cancelled'],
      ['b3', 'Confirmed'],
    ]);
    expect(calls.to('post', '/api/bookings/b1/cancel')).toHaveLength(1);
  });

  it('rejects a cancel with the API message', async () => {
    backend.failures['POST /api/bookings/b1/cancel'] = apiError(409, { message: 'This booking is already cancelled.' });

    const result = await store.dispatch(cancelBooking('b1'));

    expect(cancelBooking.rejected.match(result)).toBe(true);
    expect(result.payload).toBe('This booking is already cancelled.');
  });
});
