import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import AccommodationsPage from './AccommodationsPage';
import { acc, createStayBackend, night } from '../../test/stayBackend';
import { apiError, installApi, operatorAuth, renderWithStore } from '../../test/testUtils';
import { dateInputFromToday, formatDateOnly } from '../../utils/format';

vi.mock('../../api/axiosClient', async () => (await import('../../test/axiosMock')).mockedAxios());

describe('AccommodationsPage', () => {
  let backend;
  let calls;
  let user;

  beforeEach(() => {
    backend = createStayBackend();
    user = userEvent.setup();
  });

  const open = async () => {
    calls = installApi(backend.handler);
    const view = renderWithStore(<AccommodationsPage />, { preloadedState: operatorAuth });
    await screen.findAllByRole('button', { name: /^Edit / }); // the first rows have arrived
    return view;
  };

  // Number fields are set by change event: typing "-5" or "2.5" character by character
  // behaves differently in jsdom than in a browser.
  const setNumber = (label, value, scope = screen) =>
    fireEvent.change(scope.getByLabelText(label), { target: { value } });

  const listCalls = () => calls.to('get', '/api/accommodations');
  const lastListParams = () => listCalls().at(-1).params;

  const fillForm = async ({ destination = 'd1', name = 'Palm Villa', description = 'Quiet', type = 'Villa', price = '15000', guests = '3' } = {}) => {
    await screen.findByRole('option', { name: 'Galle Fort' });
    if (destination) await user.selectOptions(screen.getByLabelText('Destination'), destination);
    const nameInput = screen.getByLabelText('Name');
    await user.clear(nameInput);
    if (name) await user.type(nameInput, name);
    const desc = screen.getByLabelText('Description');
    await user.clear(desc);
    if (description) await user.type(desc, description);
    await user.selectOptions(screen.getByLabelText('Type'), type);
    setNumber('Price per night (LKR)', price);
    setNumber('Guests per room', guests);
  };

  describe('list', () => {
    it('shows each stay with destination, price, sleeps, rating and status', async () => {
      backend.accommodations = [
        acc(1, { name: 'Sea View', averageRating: 4.5, reviewCount: 8, pricePerNight: 20000, maxGuestsPerRoom: 3 }),
        acc(2, { name: 'Hill Villa', destinationName: 'Ella', type: 'Villa', pricePerNight: 35000 }),
      ];
      await open();

      const row = screen.getByRole('row', { name: /Sea View/ });
      expect(within(row).getByText('Galle Fort')).toBeInTheDocument();
      expect(within(row).getByText('LKR 20,000')).toBeInTheDocument();
      expect(within(row).getByText('3 / room')).toBeInTheDocument();
      expect(within(row).getByText('4.5 (8)')).toBeInTheDocument();
      expect(within(row).getByText('Active')).toBeInTheDocument();
      expect(within(screen.getByRole('row', { name: /Hill Villa/ })).getByText('—')).toBeInTheDocument();
    });

    it('asks for the first page, sorted by name, without filters', async () => {
      await open();

      expect(lastListParams()).toEqual({ sortBy: 'Name', sortDescending: false, page: 1, pageSize: 10 });
      expect(calls.to('get', '/api/destinations')).toHaveLength(1);
    });

    it('searches after a pause in typing, not on every key', async () => {
      await open();
      const before = listCalls().length;

      await user.type(screen.getByLabelText('Search accommodations'), 'stay 02');
      await waitFor(() => expect(lastListParams().search).toBe('stay 02'));

      expect(listCalls().length).toBe(before + 1);
      expect(screen.getByText('Stay 02')).toBeInTheDocument();
      expect(screen.queryByText('Stay 01')).not.toBeInTheDocument();
    });

    it('filters by type', async () => {
      backend.accommodations = [acc(1), acc(2, { name: 'Hill Villa', type: 'Villa' })];
      await open();

      await user.selectOptions(screen.getByLabelText('Filter by type'), 'Villa');

      await waitFor(() => expect(lastListParams().type).toBe('Villa'));
      expect(await screen.findByText('Hill Villa')).toBeInTheDocument();
      expect(screen.queryByText('Stay 01')).not.toBeInTheDocument();
    });

    it('sorts by price both ways and by rating', async () => {
      backend.accommodations = [acc(1, { name: 'Pricey', pricePerNight: 50000 }), acc(2, { name: 'Cheap', pricePerNight: 4000 })];
      await open();

      await user.selectOptions(screen.getByLabelText('Sort'), 'price-asc');
      await waitFor(() => expect(lastListParams()).toMatchObject({ sortBy: 'Price', sortDescending: false }));
      await waitFor(() => expect(screen.getAllByRole('row')[1]).toHaveTextContent('Cheap'));

      await user.selectOptions(screen.getByLabelText('Sort'), 'price-desc');
      await waitFor(() => expect(lastListParams()).toMatchObject({ sortBy: 'Price', sortDescending: true }));

      await user.selectOptions(screen.getByLabelText('Sort'), 'rating');
      await waitFor(() => expect(lastListParams()).toMatchObject({ sortBy: 'Rating', sortDescending: true }));
    });

    it('hides inactive stays until asked', async () => {
      backend.accommodations = [acc(1), acc(2, { name: 'Closed Inn', isActive: false })];
      await open();
      expect(screen.queryByText('Closed Inn')).not.toBeInTheDocument();

      await user.click(screen.getByLabelText('Show inactive'));

      const row = await screen.findByRole('row', { name: /Closed Inn/ });
      expect(within(row).getByText('Inactive')).toBeInTheDocument();
      expect(lastListParams().includeInactive).toBe(true);
    });

    it('pages through the results', async () => {
      backend.accommodations = Array.from({ length: 25 }, (_, i) => acc(i + 1));
      await open();
      expect(screen.getByText('Page 1 of 3')).toBeInTheDocument();
      expect(screen.getByText('25 total')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Prev' })).toBeDisabled();

      await user.click(screen.getByRole('button', { name: 'Next' }));
      expect(await screen.findByText('Page 2 of 3')).toBeInTheDocument();
      expect(lastListParams().page).toBe(2);
      expect(screen.getByText('Stay 11')).toBeInTheDocument();

      await user.click(screen.getByRole('button', { name: 'Next' }));
      expect(await screen.findByText('Page 3 of 3')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Next' })).toBeDisabled();
    });

    it('is not sent back to page one by the search timer when paging straight away', async () => {
      backend.accommodations = Array.from({ length: 25 }, (_, i) => acc(i + 1));
      await open();

      await user.click(screen.getByRole('button', { name: 'Next' }));
      await screen.findByText('Page 2 of 3');
      await new Promise((resolve) => setTimeout(resolve, 450)); // longer than the search delay

      expect(screen.getByText('Page 2 of 3')).toBeInTheDocument();
      expect(lastListParams().page).toBe(2);
    });

    it('goes back to page one when the search text changes', async () => {
      backend.accommodations = Array.from({ length: 25 }, (_, i) => acc(i + 1));
      await open();
      await user.click(screen.getByRole('button', { name: 'Next' }));
      await screen.findByText('Page 2 of 3');

      await user.type(screen.getByLabelText('Search accommodations'), 'stay');

      await waitFor(() => expect(lastListParams()).toMatchObject({ search: 'stay', page: 1 }));
    });

    it('goes back to page one when a filter changes', async () => {
      backend.accommodations = Array.from({ length: 25 }, (_, i) => acc(i + 1));
      await open();
      await user.click(screen.getByRole('button', { name: 'Next' }));
      await screen.findByText('Page 2 of 3');

      await user.selectOptions(screen.getByLabelText('Filter by type'), 'Hotel');

      await waitFor(() => expect(lastListParams()).toMatchObject({ type: 'Hotel', page: 1 }));
    });

    it('shows an error when the list cannot be loaded', async () => {
      backend.failures['GET /api/accommodations'] = apiError(500, {});
      calls = installApi(backend.handler);
      renderWithStore(<AccommodationsPage />, { preloadedState: operatorAuth });

      expect(await screen.findByRole('alert')).toHaveTextContent('Something went wrong on the server.');
    });

    it('says when nothing matches', async () => {
      backend.accommodations = [];
      calls = installApi(backend.handler);
      renderWithStore(<AccommodationsPage />, { preloadedState: operatorAuth });

      expect(await screen.findByText('No accommodations found.')).toBeInTheDocument();
    });
  });

  describe('create', () => {
    it('posts the stay, confirms, clears the form and shows the new row', async () => {
      await open();
      await fillForm();

      await user.click(screen.getByRole('button', { name: 'Create Accommodation' }));

      expect(await screen.findByRole('status')).toHaveTextContent('Created "Palm Villa".');
      expect(calls.to('post', '/api/accommodations')[0].body).toEqual({
        destinationId: 'd1',
        name: 'Palm Villa',
        description: 'Quiet',
        type: 'Villa',
        pricePerNight: 15000,
        maxGuestsPerRoom: 3,
      });
      expect(screen.getByLabelText('Name')).toHaveValue('');
      expect(await screen.findByText('Palm Villa')).toBeInTheDocument();
    });

    it('trims the name before sending', async () => {
      await open();
      await fillForm({ name: '  Palm Villa  ' });

      await user.click(screen.getByRole('button', { name: 'Create Accommodation' }));

      await screen.findByRole('status');
      expect(calls.to('post', '/api/accommodations')[0].body.name).toBe('Palm Villa');
    });

    it.each([
      [{ destination: '' }, 'Choose a destination.'],
      [{ name: 'A' }, 'Name must be 2 to 150 characters.'],
      [{ name: 'x'.repeat(151) }, 'Name must be 2 to 150 characters.'],
      [{ price: '' }, 'Price per night must be between 0 and 10,000,000.'],
      [{ price: '-5' }, 'Price per night must be between 0 and 10,000,000.'],
      [{ price: '10000001' }, 'Price per night must be between 0 and 10,000,000.'],
      [{ guests: '0' }, 'Guests per room must be a whole number from 1 to 20.'],
      [{ guests: '21' }, 'Guests per room must be a whole number from 1 to 20.'],
      [{ guests: '2.5' }, 'Guests per room must be a whole number from 1 to 20.'],
    ])('refuses %j before calling the API', async (overrides, message) => {
      await open();
      await fillForm(overrides);

      await user.click(screen.getByRole('button', { name: 'Create Accommodation' }));

      expect(await screen.findByRole('alert')).toHaveTextContent(message);
      expect(calls.to('post', '/api/accommodations')).toHaveLength(0);
    });

    it('accepts a free stay and the limits', async () => {
      await open();
      await fillForm({ price: '0', guests: '20' });

      await user.click(screen.getByRole('button', { name: 'Create Accommodation' }));

      await screen.findByRole('status');
      expect(calls.to('post', '/api/accommodations')[0].body).toMatchObject({ pricePerNight: 0, maxGuestsPerRoom: 20 });
    });

    it('shows the API conflict and keeps what was typed', async () => {
      await open();
      await fillForm({ name: 'stay 01' }); // already exists in Galle Fort

      await user.click(screen.getByRole('button', { name: 'Create Accommodation' }));

      expect(await screen.findByRole('alert')).toHaveTextContent('already has an accommodation');
      expect(screen.getByLabelText('Name')).toHaveValue('stay 01');
    });

    it("shows the API's validation message when it answers with problem details", async () => {
      backend.failures['POST /api/accommodations'] = apiError(400, {
        errors: { PricePerNight: ['The field PricePerNight must be between 0 and 10000000.'] },
      });
      await open();
      await fillForm();

      await user.click(screen.getByRole('button', { name: 'Create Accommodation' }));

      expect(await screen.findByRole('alert')).toHaveTextContent('The field PricePerNight must be between');
    });

    it('lists the destinations to choose from', async () => {
      await open();

      expect(await screen.findByRole('option', { name: 'Galle Fort' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: 'Ella' })).toBeInTheDocument();
    });
  });

  describe('edit', () => {
    it('loads the stay into the form, saves it, and returns to "add" mode', async () => {
      await open();

      await user.click(screen.getByRole('button', { name: 'Edit Stay 01' }));
      expect(screen.getByRole('heading', { name: 'Edit Accommodation' })).toBeInTheDocument();
      expect(screen.getByLabelText('Name')).toHaveValue('Stay 01');
      expect(screen.getByLabelText('Price per night (LKR)')).toHaveValue(20000);
      expect(screen.getByLabelText('Description')).toHaveValue('A lovely place');
      expect(screen.getByLabelText('Active (visible to travelers)')).toBeChecked();

      await user.clear(screen.getByLabelText('Name'));
      await user.type(screen.getByLabelText('Name'), 'Stay One');
      await user.click(screen.getByRole('button', { name: 'Save Changes' }));

      expect(await screen.findByRole('status')).toHaveTextContent('Changes saved.');
      expect(calls.to('put', '/api/accommodations/a1')[0].body).toEqual({
        destinationId: 'd1',
        name: 'Stay One',
        description: 'A lovely place',
        type: 'Hotel',
        pricePerNight: 20000,
        maxGuestsPerRoom: 2,
        isActive: true,
      });
      expect(screen.getByRole('heading', { name: 'Add New Accommodation' })).toBeInTheDocument();
      expect(await screen.findByText('Stay One')).toBeInTheDocument();
    });

    it('can switch a stay off from the form', async () => {
      await open();
      await user.click(screen.getByRole('button', { name: 'Edit Stay 01' }));

      await user.click(screen.getByLabelText('Active (visible to travelers)'));
      await user.click(screen.getByRole('button', { name: 'Save Changes' }));

      await screen.findByRole('status');
      expect(calls.to('put', '/api/accommodations/a1')[0].body.isActive).toBe(false);
    });

    it('Cancel discards the edit', async () => {
      await open();
      await user.click(screen.getByRole('button', { name: 'Edit Stay 01' }));

      await user.click(screen.getByRole('button', { name: 'Cancel' }));

      expect(screen.getByRole('heading', { name: 'Add New Accommodation' })).toBeInTheDocument();
      expect(screen.getByLabelText('Name')).toHaveValue('');
      expect(calls.to('put', '/api/accommodations/a1')).toHaveLength(0);
    });

    it('validates edits the same way as new stays', async () => {
      await open();
      await user.click(screen.getByRole('button', { name: 'Edit Stay 01' }));
      setNumber('Price per night (LKR)', '-1');

      await user.click(screen.getByRole('button', { name: 'Save Changes' }));

      expect(await screen.findByRole('alert')).toHaveTextContent('Price per night must be between');
      expect(calls.to('put', '/api/accommodations/a1')).toHaveLength(0);
    });

    it('shows the API error when saving fails', async () => {
      backend.failures['PUT /api/accommodations/a1'] = apiError(409, { message: 'Galle Fort already has an accommodation called "Stay 02".' });
      await open();
      await user.click(screen.getByRole('button', { name: 'Edit Stay 01' }));

      await user.click(screen.getByRole('button', { name: 'Save Changes' }));

      expect(await screen.findByRole('alert')).toHaveTextContent('already has an accommodation');
      expect(screen.getByRole('heading', { name: 'Edit Accommodation' })).toBeInTheDocument();
    });
  });

  describe('deactivate and reactivate', () => {
    it('asks first, and does nothing when declined', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(false);
      await open();

      await user.click(screen.getByRole('button', { name: 'Deactivate Stay 01' }));

      expect(window.confirm).toHaveBeenCalledWith(expect.stringContaining('Stay 01'));
      expect(calls.to('delete', '/api/accommodations/a1')).toHaveLength(0);
      expect(screen.getByText('Stay 01')).toBeInTheDocument();
    });

    it('deactivates after confirmation and the stay leaves the list', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(true);
      await open();

      await user.click(screen.getByRole('button', { name: 'Deactivate Stay 01' }));

      expect(await screen.findByRole('status')).toHaveTextContent('Deactivated "Stay 01".');
      expect(calls.to('delete', '/api/accommodations/a1')).toHaveLength(1);
      await waitFor(() => expect(screen.queryByText('Stay 01')).not.toBeInTheDocument());
    });

    it('shows the reason when deactivating fails', async () => {
      vi.spyOn(window, 'confirm').mockReturnValue(true);
      backend.failures['DELETE /api/accommodations/a1'] = apiError(403, {});
      await open();

      await user.click(screen.getByRole('button', { name: 'Deactivate Stay 01' }));

      expect(await screen.findByRole('alert')).toHaveTextContent('permission');
      expect(screen.getByText('Stay 01')).toBeInTheDocument();
    });

    it('reactivates an inactive stay with all its details', async () => {
      backend.accommodations = [acc(1), acc(2, { name: 'Closed Inn', isActive: false, pricePerNight: 9000, type: 'Hostel' })];
      await open();
      await user.click(screen.getByLabelText('Show inactive'));

      await user.click(await screen.findByRole('button', { name: 'Reactivate Closed Inn' }));

      expect(await screen.findByRole('status')).toHaveTextContent('Reactivated "Closed Inn".');
      expect(calls.to('put', '/api/accommodations/a2')[0].body).toEqual({
        destinationId: 'd1',
        name: 'Closed Inn',
        description: 'A lovely place',
        type: 'Hostel',
        pricePerNight: 9000,
        maxGuestsPerRoom: 2,
        isActive: true,
      });
      await waitFor(() =>
        expect(within(screen.getByRole('row', { name: /Closed Inn/ })).getByText('Active')).toBeInTheDocument());
    });
  });

  describe('availability', () => {
    const d = (n) => dateInputFromToday(n);

    beforeEach(() => {
      backend.availability.a1 = [night(d(0), 2, 1), night(d(1), 2, 2), night(d(2), 4)];
    });

    const openPanel = async (name = 'Stay 01') => {
      await open();
      await user.click(screen.getByRole('button', { name: `Availability for ${name}` }));
      return screen.findByRole('region', { name: `Availability for ${name}` });
    };

    it('shows every night with its total, booked and free rooms', async () => {
      const panel = await openPanel();

      const first = await within(panel).findByRole('row', { name: new RegExp(formatDateOnly(d(0))) });
      expect(within(first).getAllByRole('cell').map((c) => c.textContent)).toEqual([formatDateOnly(d(0)), '2', '1', '1']);
      const full = within(panel).getByRole('row', { name: new RegExp(formatDateOnly(d(1))) });
      expect(within(full).getByText('Sold out')).toBeInTheDocument();
      expect(calls.to('get', '/api/accommodations/a1/availability')[0].params).toEqual({ from: d(0), to: d(29) });
    });

    it('says when no rooms were ever set', async () => {
      await open();
      await user.click(screen.getByRole('button', { name: 'Availability for Stay 02' }));

      expect(await screen.findByText('No rooms have been set for these nights yet.')).toBeInTheDocument();
    });

    it('closes, and switches to another stay without showing the old nights', async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');

      await user.click(screen.getByRole('button', { name: 'Availability for Stay 02' }));

      expect(await screen.findByRole('region', { name: 'Availability for Stay 02' })).toBeInTheDocument();
      expect(screen.queryByRole('region', { name: 'Availability for Stay 01' })).not.toBeInTheDocument();
      expect(screen.queryByText('Sold out')).not.toBeInTheDocument();

      await user.click(screen.getByRole('button', { name: 'Close' }));
      expect(screen.queryByRole('region')).not.toBeInTheDocument();
    });

    it('refreshes the shown window', async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');
      const before = calls.to('get', '/api/accommodations/a1/availability').length;

      fireEvent.change(within(panel).getByLabelText('Show to'), { target: { value: d(5) } });
      await user.click(within(panel).getByRole('button', { name: 'Refresh' }));

      await waitFor(() =>
        expect(calls.to('get', '/api/accommodations/a1/availability').at(-1).params.to).toBe(d(5)));
      expect(calls.to('get', '/api/accommodations/a1/availability').length).toBe(before + 1);
    });

    it('refuses a reversed or oversized window without asking the API', async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');
      const before = calls.to('get', '/api/accommodations/a1/availability').length;

      fireEvent.change(within(panel).getByLabelText('Show to'), { target: { value: d(-3) } });
      await user.click(within(panel).getByRole('button', { name: 'Refresh' }));
      expect(await within(panel).findByRole('alert')).toHaveTextContent("'To' cannot be before 'From'.");

      fireEvent.change(within(panel).getByLabelText('Show to'), { target: { value: d(120) } });
      await user.click(within(panel).getByRole('button', { name: 'Refresh' }));
      expect(await within(panel).findByText('Show at most 120 nights at a time.')).toBeInTheDocument();

      expect(calls.to('get', '/api/accommodations/a1/availability').length).toBe(before);
    });

    it('shows the API error when the nights cannot be loaded', async () => {
      backend.failures['GET /api/accommodations/a1/availability'] = apiError(500, {});
      await open();
      await user.click(screen.getByRole('button', { name: 'Availability for Stay 01' }));

      expect(await within(await screen.findByRole('region')).findByRole('alert'))
        .toHaveTextContent('Something went wrong on the server.');
    });

    it('sets the rooms for a range of nights and reloads them', async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');

      fireEvent.change(within(panel).getByLabelText('Set from'), { target: { value: d(3) } });
      fireEvent.change(within(panel).getByLabelText('Set to'), { target: { value: d(5) } });
      await user.clear(within(panel).getByLabelText('Rooms per night'));
      await user.type(within(panel).getByLabelText('Rooms per night'), '4');
      await user.click(within(panel).getByRole('button', { name: 'Update rooms' }));

      expect(await within(panel).findByRole('status')).toHaveTextContent('Updated 3 nights to 4 rooms.');
      expect(calls.to('put', '/api/accommodations/a1/availability')[0].body).toEqual({
        from: d(3), to: d(5), totalRooms: 4,
      });
      // The table was reloaded and now includes the new nights.
      expect(await within(panel).findByRole('row', { name: new RegExp(formatDateOnly(d(5))) })).toBeInTheDocument();
    });

    it('says "1 room" and "1 night" in the singular', async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');

      fireEvent.change(within(panel).getByLabelText('Set from'), { target: { value: d(3) } });
      fireEvent.change(within(panel).getByLabelText('Set to'), { target: { value: d(3) } });
      await user.clear(within(panel).getByLabelText('Rooms per night'));
      await user.type(within(panel).getByLabelText('Rooms per night'), '1');
      await user.click(within(panel).getByRole('button', { name: 'Update rooms' }));

      expect(await within(panel).findByRole('status')).toHaveTextContent('Updated 1 night to 1 room.');
    });

    it('lets the operator close the nights completely with 0 rooms', async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');

      fireEvent.change(within(panel).getByLabelText('Set from'), { target: { value: d(2) } });
      fireEvent.change(within(panel).getByLabelText('Set to'), { target: { value: d(2) } });
      await user.clear(within(panel).getByLabelText('Rooms per night'));
      await user.type(within(panel).getByLabelText('Rooms per night'), '0');
      await user.click(within(panel).getByRole('button', { name: 'Update rooms' }));

      expect(await within(panel).findByRole('status')).toHaveTextContent('Updated 1 night to 0 rooms.');
      expect(calls.to('put', '/api/accommodations/a1/availability')[0].body.totalRooms).toBe(0);
    });

    it("shows the API's reason when fewer rooms than are booked are requested", async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');

      fireEvent.change(within(panel).getByLabelText('Set from'), { target: { value: d(0) } });
      fireEvent.change(within(panel).getByLabelText('Set to'), { target: { value: d(2) } });
      await user.clear(within(panel).getByLabelText('Rooms per night'));
      await user.type(within(panel).getByLabelText('Rooms per night'), '1');
      await user.click(within(panel).getByRole('button', { name: 'Update rooms' }));

      const alert = await within(panel).findByRole('alert');
      expect(alert).toHaveTextContent(`Cannot set 1 room(s) on ${d(1)}: 2 already booked.`);
      expect(within(panel).queryByRole('status')).not.toBeInTheDocument();
    });

    it.each([
      ['501', 'Rooms must be a whole number from 0 to 500.'],
      ['-1', 'Rooms must be a whole number from 0 to 500.'],
      ['2.5', 'Rooms must be a whole number from 0 to 500.'],
      ['', 'Rooms must be a whole number from 0 to 500.'],
    ])('refuses %j rooms without calling the API', async (rooms, message) => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');
      setNumber('Rooms per night', rooms, within(panel));

      await user.click(within(panel).getByRole('button', { name: 'Update rooms' }));

      expect(await within(panel).findByRole('alert')).toHaveTextContent(message);
      expect(calls.to('put', '/api/accommodations/a1/availability')).toHaveLength(0);
    });

    it('refuses past dates, reversed ranges and ranges over a year', async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');
      const submit = () => user.click(within(panel).getByRole('button', { name: 'Update rooms' }));

      fireEvent.change(within(panel).getByLabelText('Set from'), { target: { value: d(-1) } });
      await submit();
      expect(await within(panel).findByRole('alert')).toHaveTextContent('Availability can only be set for today or later.');

      fireEvent.change(within(panel).getByLabelText('Set from'), { target: { value: d(10) } });
      fireEvent.change(within(panel).getByLabelText('Set to'), { target: { value: d(5) } });
      await submit();
      expect(await within(panel).findByRole('alert')).toHaveTextContent("'To' cannot be before 'From'.");

      fireEvent.change(within(panel).getByLabelText('Set from'), { target: { value: d(0) } });
      fireEvent.change(within(panel).getByLabelText('Set to'), { target: { value: d(366) } });
      await submit();
      expect(await within(panel).findByRole('alert')).toHaveTextContent('Set at most 366 nights at a time.');

      expect(calls.to('put', '/api/accommodations/a1/availability')).toHaveLength(0);
    });

    it('allows exactly a year of nights, starting today', async () => {
      const panel = await openPanel();
      await within(panel).findByText('Sold out');

      fireEvent.change(within(panel).getByLabelText('Set from'), { target: { value: d(0) } });
      fireEvent.change(within(panel).getByLabelText('Set to'), { target: { value: d(365) } });
      await user.click(within(panel).getByRole('button', { name: 'Update rooms' }));

      expect(await within(panel).findByRole('status')).toHaveTextContent('Updated 366 nights');
    });
  });
});
