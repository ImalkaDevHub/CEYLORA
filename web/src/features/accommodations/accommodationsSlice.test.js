import { beforeEach, describe, expect, it, vi } from 'vitest';
import { configureStore } from '@reduxjs/toolkit';
import reducer, {
  clearAvailability,
  createAccommodation,
  deactivateAccommodation,
  fetchAccommodations,
  fetchAvailability,
  fetchDestinationOptions,
  setAvailability,
  updateAccommodation,
} from './accommodationsSlice';
import { acc, createStayBackend, night } from '../../test/stayBackend';
import { apiError, installApi } from '../../test/testUtils';

vi.mock('../../api/axiosClient', async () => (await import('../../test/axiosMock')).mockedAxios());

const makeStore = () => configureStore({ reducer: { accommodations: reducer } });

describe('accommodationsSlice', () => {
  let backend;
  let calls;
  let store;

  beforeEach(() => {
    backend = createStayBackend();
    calls = installApi(backend.handler);
    store = makeStore();
  });

  const state = () => store.getState().accommodations;

  it('loads a page and remembers the paging', async () => {
    await store.dispatch(fetchAccommodations({ page: 1, pageSize: 2 }));

    expect(state().status).toBe('succeeded');
    expect(state().items).toHaveLength(2);
    expect(state().totalCount).toBe(3);
    expect(state().pageSize).toBe(2);
    expect(calls.to('get', '/api/accommodations')[0].params).toEqual({ page: 1, pageSize: 2 });
  });

  it('keeps the API message when loading fails', async () => {
    backend.failures['GET /api/accommodations'] = apiError(500, {});

    await store.dispatch(fetchAccommodations({}));

    expect(state().status).toBe('failed');
    expect(state().error).toBe('Something went wrong on the server.');
  });

  it('loads destination options as id and name only', async () => {
    await store.dispatch(fetchDestinationOptions());

    expect(state().destinationOptions).toEqual([
      { id: 'd1', name: 'Galle Fort' },
      { id: 'd2', name: 'Ella' },
    ]);
    expect(calls.to('get', '/api/destinations')[0].params).toEqual({ pageSize: 100, sortBy: 'Name' });
  });

  it('rejects a create with the API message', async () => {
    const result = await store.dispatch(
      createAccommodation({ destinationId: 'd1', name: 'stay 01', pricePerNight: 1, maxGuestsPerRoom: 1 })
    );

    expect(createAccommodation.rejected.match(result)).toBe(true);
    expect(result.payload).toContain('already has an accommodation');
  });

  it('replaces an updated stay in the list', async () => {
    await store.dispatch(fetchAccommodations({}));
    await store.dispatch(
      updateAccommodation({ id: 'a1', dto: { destinationId: 'd1', name: 'Renamed', pricePerNight: 1, maxGuestsPerRoom: 2, isActive: true } })
    );

    expect(state().items.find((a) => a.id === 'a1').name).toBe('Renamed');
  });

  it('marks a deactivated stay inactive in place', async () => {
    await store.dispatch(fetchAccommodations({}));
    await store.dispatch(deactivateAccommodation('a2'));

    expect(state().items.find((a) => a.id === 'a2').isActive).toBe(false);
    expect(calls.to('delete', '/api/accommodations/a2')).toHaveLength(1);
  });

  it('reports a failed deactivate', async () => {
    const result = await store.dispatch(deactivateAccommodation('missing'));

    expect(result.payload).toBe('Accommodation not found.');
  });

  describe('availability', () => {
    beforeEach(() => {
      backend.availability.a1 = [night('2026-11-01', 2, 1), night('2026-11-02', 2)];
      backend.availability.a2 = [night('2026-11-01', 5)];
    });

    it('loads the nights of a stay', async () => {
      await store.dispatch(fetchAvailability({ id: 'a1', from: '2026-11-01', to: '2026-11-05' }));

      expect(state().availability.accommodationId).toBe('a1');
      expect(state().availability.days).toHaveLength(2);
      expect(state().availability.status).toBe('succeeded');
    });

    it("does not show the previous stay's nights while another one loads", async () => {
      await store.dispatch(fetchAvailability({ id: 'a1', from: '2026-11-01', to: '2026-11-05' }));

      const pending = store.dispatch(fetchAvailability({ id: 'a2', from: '2026-11-01', to: '2026-11-05' }));
      expect(state().availability.days).toEqual([]);
      expect(state().availability.accommodationId).toBe('a2');
      await pending;
      expect(state().availability.days).toHaveLength(1);
    });

    it('ignores an answer for a stay that is no longer open', async () => {
      store.dispatch({
        type: fetchAvailability.pending.type,
        meta: { arg: { id: 'a2' }, requestId: 'r2', requestStatus: 'pending' },
      });
      store.dispatch({
        type: fetchAvailability.fulfilled.type,
        payload: { id: 'a1', days: [night('2026-11-01', 9)] },
        meta: { arg: { id: 'a1' }, requestId: 'r1', requestStatus: 'fulfilled' },
      });

      expect(state().availability.days).toEqual([]);
      expect(state().availability.status).toBe('loading');
    });

    it('clearAvailability forgets everything', async () => {
      await store.dispatch(fetchAvailability({ id: 'a1', from: '2026-11-01', to: '2026-11-05' }));

      store.dispatch(clearAvailability());

      expect(state().availability).toEqual({ accommodationId: null, days: [], status: 'idle', error: null });
    });

    it('reports a failed load', async () => {
      backend.failures['GET /api/accommodations/a1/availability'] = apiError(404, { message: 'Accommodation not found.' });

      await store.dispatch(fetchAvailability({ id: 'a1', from: '2026-11-01', to: '2026-11-05' }));

      expect(state().availability.status).toBe('failed');
      expect(state().availability.error).toBe('Accommodation not found.');
    });

    it('setAvailability returns the touched nights', async () => {
      const result = await store.dispatch(
        setAvailability({ id: 'a1', dto: { from: '2026-11-03', to: '2026-11-04', totalRooms: 4 } })
      );

      expect(result.payload.days.map((d) => d.date)).toEqual(['2026-11-03', '2026-11-04']);
    });

    it('setAvailability refuses to drop below what is booked, with the API reason', async () => {
      const result = await store.dispatch(
        setAvailability({ id: 'a1', dto: { from: '2026-11-01', to: '2026-11-02', totalRooms: 0 } })
      );

      expect(setAvailability.rejected.match(result)).toBe(true);
      expect(result.payload).toContain('1 already booked');
    });
  });

  it('starts empty', () => {
    expect(state().items).toEqual([]);
    expect(state().status).toBe('idle');
    expect(acc(1).isActive).toBe(true);
  });
});
