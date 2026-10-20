import { beforeEach, describe, expect, it, vi } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import BookingsPage from './BookingsPage';
import { acc, booking, createStayBackend } from '../../test/stayBackend';
import { apiError, installApi, operatorAuth, renderWithStore } from '../../test/testUtils';

vi.mock('../../api/axiosClient', async () => (await import('../../test/axiosMock')).mockedAxios());

const item = (n, over = {}) => ({
  ...booking(n).items[0],
  id: `i${n}-${over.accommodationName ?? 'x'}`,
  ...over,
});

describe('BookingsPage', () => {
  let backend;
  let calls;
  let user;

  beforeEach(() => {
    backend = createStayBackend();
    backend.accommodations = [acc(1), acc(2, { name: 'Ella Inn' }), acc(3, { name: 'Old Lodge', isActive: false })];
    backend.bookings = [
      booking(1),
      booking(2, {
        travelerName: 'Kim Traveler',
        tripTitle: 'Hill country',
        totalAmount: 54000,
        notes: 'Late arrival',
        items: [item(2, { accommodationId: 'a2', accommodationName: 'Ella Inn', rooms: 2, nights: 3 })],
      }),
      booking(3, { status: 'Cancelled', travelerName: 'Lee Traveler', cancelledAt: '2026-10-22T09:00:00Z' }),
    ];
    user = userEvent.setup();
  });

  const open = async () => {
    calls = installApi(backend.handler);
    const view = renderWithStore(<BookingsPage />, { preloadedState: operatorAuth });
    await screen.findByText('Kim Traveler');
    return view;
  };

  const listCalls = () => calls.to('get', '/api/bookings');
  const lastParams = () => listCalls().at(-1).params;
  const rowOf = (name) => screen.getByRole('row', { name: new RegExp(name) });

  describe('list', () => {
    it("shows each booking's traveler, trip, stays, total and status", async () => {
      await open();

      const sam = rowOf('Sam Traveler');
      expect(within(sam).getByText('South coast')).toBeInTheDocument();
      expect(within(sam).getByText('Stay 01 · 1 Nov 2026 → 3 Nov 2026 · 1 room')).toBeInTheDocument();
      expect(within(sam).getByText('LKR 40,000')).toBeInTheDocument();
      expect(within(sam).getByText('Confirmed')).toBeInTheDocument();
      expect(within(sam).getByText('20 Oct 2026')).toBeInTheDocument();

      const kim = rowOf('Kim Traveler');
      expect(within(kim).getByText('Ella Inn · 1 Nov 2026 → 3 Nov 2026 · 2 rooms')).toBeInTheDocument();
      expect(within(kim).getByText('Note: Late arrival')).toBeInTheDocument();
    });

    it('shows several stays of one booking on separate lines', async () => {
      backend.bookings = [
        booking(1, {
          items: [
            item(1, { accommodationName: 'Stay 01' }),
            item(9, { accommodationName: 'Ella Inn', checkIn: '2026-11-03', checkOut: '2026-11-05' }),
          ],
        }),
      ];
      calls = installApi(backend.handler);
      renderWithStore(<BookingsPage />, { preloadedState: operatorAuth });

      expect(await screen.findByText(/^Stay 01 ·/)).toBeInTheDocument();
      expect(screen.getByText('Ella Inn · 3 Nov 2026 → 5 Nov 2026 · 1 room')).toBeInTheDocument();
    });

    it('asks for the first page of everything', async () => {
      await open();

      expect(lastParams()).toEqual({ page: 1, pageSize: 20 });
      expect(screen.getByText('Page 1 of 1')).toBeInTheDocument();
      expect(screen.getByText('3 total')).toBeInTheDocument();
    });

    it('offers every stay, inactive ones included, as a filter', async () => {
      await open();

      const select = screen.getByLabelText('Filter by accommodation');
      expect(within(select).getAllByRole('option').map((o) => o.textContent)).toEqual([
        'All accommodations', 'Stay 01', 'Ella Inn', 'Old Lodge',
      ].sort((a, b) => (a === 'All accommodations' ? -1 : b === 'All accommodations' ? 1 : a.localeCompare(b))));
      expect(calls.to('get', '/api/accommodations')[0].params.includeInactive).toBe(true);
    });

    it('filters by status', async () => {
      await open();

      await user.selectOptions(screen.getByLabelText('Filter by status'), 'Cancelled');

      await waitFor(() => expect(lastParams().status).toBe('Cancelled'));
      expect(await screen.findByText('Lee Traveler')).toBeInTheDocument();
      expect(screen.queryByText('Kim Traveler')).not.toBeInTheDocument();
    });

    it('filters by accommodation', async () => {
      await open();
      await screen.findByRole('option', { name: 'Ella Inn' });

      await user.selectOptions(screen.getByLabelText('Filter by accommodation'), 'a2');

      await waitFor(() => expect(lastParams().accommodationId).toBe('a2'));
      await waitFor(() => expect(screen.queryByText('Sam Traveler')).not.toBeInTheDocument());
      expect(screen.getByText('Kim Traveler')).toBeInTheDocument();
    });

    it('combines the filters and can clear them again', async () => {
      await open();
      await screen.findByRole('option', { name: 'Ella Inn' });

      await user.selectOptions(screen.getByLabelText('Filter by status'), 'Confirmed');
      await user.selectOptions(screen.getByLabelText('Filter by accommodation'), 'a1');
      await waitFor(() => expect(lastParams()).toMatchObject({ status: 'Confirmed', accommodationId: 'a1' }));

      await user.selectOptions(screen.getByLabelText('Filter by status'), '');
      await user.selectOptions(screen.getByLabelText('Filter by accommodation'), '');
      await waitFor(() => expect(lastParams()).toEqual({ page: 1, pageSize: 20 }));
    });

    it('pages through many bookings and returns to page one when filtering', async () => {
      backend.bookings = Array.from({ length: 45 }, (_, i) => booking(i + 1, { travelerName: `Traveler ${i + 1}` }));
      calls = installApi(backend.handler);
      renderWithStore(<BookingsPage />, { preloadedState: operatorAuth });
      await screen.findByText('Traveler 1');
      expect(screen.getByText('Page 1 of 3')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Prev' })).toBeDisabled();

      await user.click(screen.getByRole('button', { name: 'Next' }));
      expect(await screen.findByText('Traveler 21')).toBeInTheDocument();
      expect(lastParams().page).toBe(2);

      await user.selectOptions(screen.getByLabelText('Filter by status'), 'Confirmed');
      await waitFor(() => expect(lastParams()).toMatchObject({ status: 'Confirmed', page: 1 }));
    });

    it('says when there are no bookings', async () => {
      backend.bookings = [];
      calls = installApi(backend.handler);
      renderWithStore(<BookingsPage />, { preloadedState: operatorAuth });

      expect(await screen.findByText('No bookings found.')).toBeInTheDocument();
    });

    it('shows the error when the list cannot be loaded', async () => {
      backend.failures['GET /api/bookings'] = apiError(500, {});
      calls = installApi(backend.handler);
      renderWithStore(<BookingsPage />, { preloadedState: operatorAuth });

      expect(await screen.findByRole('alert')).toHaveTextContent('Something went wrong on the server.');
    });
  });

  describe('cancel', () => {
    it('only confirmed bookings can be cancelled', async () => {
      await open();

      expect(within(rowOf('Sam Traveler')).getByRole('button', { name: /Cancel booking of Sam/ })).toBeInTheDocument();
      expect(within(rowOf('Lee Traveler')).queryByRole('button')).not.toBeInTheDocument();
    });

    it('asks first, naming the traveler and the stays, and does nothing when declined', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(false);
      await open();

      await user.click(screen.getByRole('button', { name: 'Cancel booking of Kim Traveler' }));

      expect(window.confirm).toHaveBeenCalledWith(expect.stringContaining('Kim Traveler'));
      expect(window.confirm).toHaveBeenCalledWith(expect.stringContaining('Ella Inn'));
      expect(calls.to('post', '/api/bookings/b2/cancel')).toHaveLength(0);
      expect(within(rowOf('Kim Traveler')).getByText('Confirmed')).toBeInTheDocument();
    });

    it('cancels after confirmation and marks the row, without moving it', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(true);
      await open();
      const orderBefore = screen.getAllByRole('row').map((r) => r.textContent);

      await user.click(screen.getByRole('button', { name: 'Cancel booking of Sam Traveler' }));

      expect(await screen.findByRole('status')).toHaveTextContent("Cancelled Sam Traveler's booking.");
      expect(calls.to('post', '/api/bookings/b1/cancel')).toHaveLength(1);
      const sam = rowOf('Sam Traveler');
      expect(within(sam).getByText('Cancelled')).toBeInTheDocument();
      expect(within(sam).queryByRole('button')).not.toBeInTheDocument();
      expect(screen.getAllByRole('row')).toHaveLength(orderBefore.length);
      expect(screen.getAllByRole('row')[1]).toHaveTextContent('Sam Traveler');
    });

    it("shows the API's reason when the cancellation is refused", async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(true);
      backend.failures['POST /api/bookings/b1/cancel'] = apiError(409, { message: 'This booking is already cancelled.' });
      await open();

      await user.click(screen.getByRole('button', { name: 'Cancel booking of Sam Traveler' }));

      expect(await screen.findByRole('alert')).toHaveTextContent('This booking is already cancelled.');
      expect(within(rowOf('Sam Traveler')).getByText('Confirmed')).toBeInTheDocument();
      expect(screen.queryByRole('status')).not.toBeInTheDocument();
    });

    it('clears an old message when the next action starts', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(true);
      await open();
      await user.click(screen.getByRole('button', { name: 'Cancel booking of Sam Traveler' }));
      await screen.findByRole('status');

      backend.failures['POST /api/bookings/b2/cancel'] = apiError(500, {});
      await user.click(screen.getByRole('button', { name: 'Cancel booking of Kim Traveler' }));

      expect(await screen.findByRole('alert')).toHaveTextContent('Something went wrong on the server.');
      expect(screen.queryByRole('status')).not.toBeInTheDocument();
    });

    it('disables the button while the cancellation is in flight', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(true);
      let release;
      const gate = new Promise((resolve) => { release = resolve; });
      await open();
      const original = backend.handler;
      calls = installApi((call) => {
        if (call.url === '/api/bookings/b1/cancel') return gate.then(() => original(call));
        return original(call);
      });

      await user.click(screen.getByRole('button', { name: 'Cancel booking of Sam Traveler' }));

      expect(await screen.findByRole('button', { name: 'Cancel booking of Sam Traveler' })).toBeDisabled();
      expect(screen.getByRole('button', { name: 'Cancel booking of Sam Traveler' })).toHaveTextContent('Cancelling...');

      release();
      expect(await screen.findByRole('status')).toBeInTheDocument();
    });
  });
});
