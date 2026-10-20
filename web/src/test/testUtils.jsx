import { render } from '@testing-library/react';
import { Provider } from 'react-redux';
import { MemoryRouter } from 'react-router-dom';
import axiosClient from '../api/axiosClient';
import { createAppStore } from '../app/store';

/** An axios-style failure: `err.response.status` / `err.response.data`. */
export function apiError(status, data = {}) {
  const err = new Error(`Request failed with status code ${status}`);
  err.response = { status, data };
  return err;
}

/**
 * Routes every call of the (mocked) axios client through one handler:
 *   handler({ method, url, params, body }) -> { data } | throws apiError(...)
 * Calls are recorded in the returned array, so tests can assert on what was sent.
 * The test file must `vi.mock('<path>/api/axiosClient', ...)` first.
 */
export function installApi(handler) {
  const calls = [];
  const route = (method) => (url, a, b) => {
    const hasBody = method === 'post' || method === 'put';
    const call = {
      method,
      url,
      body: hasBody ? a : undefined,
      params: (hasBody ? b : a)?.params ?? {},
    };
    calls.push(call);
    try {
      return Promise.resolve(handler(call));
    } catch (err) {
      return Promise.reject(err);
    }
  };
  axiosClient.get.mockImplementation(route('get'));
  axiosClient.post.mockImplementation(route('post'));
  axiosClient.put.mockImplementation(route('put'));
  axiosClient.delete.mockImplementation(route('delete'));

  /** Calls to a method + exact url. */
  calls.to = (method, url) => calls.filter((c) => c.method === method && c.url === url);
  return calls;
}

export const operatorAuth = {
  auth: {
    token: 'jwt',
    user: { email: 'olu@example.com', fullName: 'Olu Operator', role: 'Operator' },
    status: 'succeeded',
    error: null,
  },
};

export const travelerAuth = {
  auth: {
    token: 'jwt',
    user: { email: 'sam@example.com', fullName: 'Sam Traveler', role: 'Traveler' },
    status: 'succeeded',
    error: null,
  },
};

export function renderWithStore(ui, { preloadedState, route = '/' } = {}) {
  const store = createAppStore(preloadedState);
  const result = render(
    <Provider store={store}>
      <MemoryRouter initialEntries={[route]}>{ui}</MemoryRouter>
    </Provider>
  );
  return { store, ...result };
}
