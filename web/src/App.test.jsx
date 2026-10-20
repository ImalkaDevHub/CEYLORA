import { beforeEach, describe, expect, it, vi } from 'vitest';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from './App';
import { createStayBackend } from './test/stayBackend';
import { installApi, operatorAuth, renderWithStore, travelerAuth } from './test/testUtils';

vi.mock('./api/axiosClient', async () => (await import('./test/axiosMock')).mockedAxios());

const adminAuth = {
  auth: {
    token: 'jwt',
    user: { email: 'ada@example.com', fullName: 'Ada Admin', role: 'Admin' },
    status: 'succeeded',
    error: null,
  },
};

describe('App routing for stays and bookings', () => {
  beforeEach(() => {
    const backend = createStayBackend();
    installApi((call) => {
      if (call.url === '/api/trips/mine') return { data: [] };
      return backend.handler(call);
    });
  });

  const nav = () => screen.getByRole('navigation');

  describe('navigation links', () => {
    it.each([
      ['an operator', operatorAuth],
      ['an admin', adminAuth],
    ])('%s sees Accommodations and Bookings', (_who, auth) => {
      renderWithStore(<App />, { preloadedState: auth, route: '/approvals' });

      expect(nav()).toHaveTextContent('Accommodations');
      expect(nav()).toHaveTextContent('Bookings');
      expect(nav()).toHaveTextContent('Destinations');
    });

    it('a traveler does not', () => {
      renderWithStore(<App />, { preloadedState: travelerAuth, route: '/dashboard' });

      expect(nav()).not.toHaveTextContent('Accommodations');
      expect(nav()).not.toHaveTextContent('Bookings');
    });

    it('the links lead to the pages', async () => {
      const user = userEvent.setup();
      renderWithStore(<App />, { preloadedState: operatorAuth, route: '/approvals' });

      await user.click(screen.getByRole('link', { name: 'Accommodations' }));
      expect(await screen.findByRole('heading', { name: 'Manage Accommodations' })).toBeInTheDocument();

      await user.click(screen.getByRole('link', { name: 'Bookings' }));
      expect(await screen.findByRole('heading', { name: 'Bookings' })).toBeInTheDocument();
    });
  });

  describe('access', () => {
    it.each([
      ['/accommodations', 'Manage Accommodations'],
      ['/bookings', 'Bookings'],
    ])('an operator can open %s', async (route, heading) => {
      renderWithStore(<App />, { preloadedState: operatorAuth, route });

      expect(await screen.findByRole('heading', { name: heading })).toBeInTheDocument();
    });

    it.each(['/accommodations', '/bookings'])('an admin can open %s', async (route) => {
      renderWithStore(<App />, { preloadedState: adminAuth, route });

      expect(await screen.findByRole('table')).toBeInTheDocument();
    });

    it.each(['/accommodations', '/bookings'])('a traveler is sent back to the dashboard from %s', async (route) => {
      renderWithStore(<App />, { preloadedState: travelerAuth, route });

      expect(await screen.findByRole('heading', { name: 'My Trips' })).toBeInTheDocument();
      expect(screen.queryByRole('heading', { name: 'Manage Accommodations' })).not.toBeInTheDocument();
    });

    it.each(['/accommodations', '/bookings'])('someone signed out is sent to login from %s', (route) => {
      renderWithStore(<App />, { route });

      expect(screen.getByRole('heading', { name: /Operator Login/ })).toBeInTheDocument();
    });
  });
});
