import { describe, expect, it } from 'vitest';
import { apiErrorMessage } from './errors';

const failure = (status, data) => ({ response: { status, data } });

describe('apiErrorMessage', () => {
  it("uses the API's message when there is one", () => {
    expect(apiErrorMessage(failure(409, { message: 'Sold out on 2026-11-02.' }))).toBe('Sold out on 2026-11-02.');
  });

  it('reads the first validation error from ASP.NET problem details', () => {
    const err = failure(400, {
      title: 'One or more validation errors occurred.',
      errors: { PricePerNight: ['The field PricePerNight must be between 0 and 10000000.'], Name: ['Too short'] },
    });
    expect(apiErrorMessage(err)).toBe('The field PricePerNight must be between 0 and 10000000.');
  });

  it('prefers a message over validation errors', () => {
    expect(apiErrorMessage(failure(400, { message: 'm', errors: { A: ['a'] } }))).toBe('m');
  });

  it('explains common statuses without a body', () => {
    expect(apiErrorMessage(failure(401, {}))).toMatch(/session has expired/i);
    expect(apiErrorMessage(failure(403, {}))).toMatch(/permission/i);
    expect(apiErrorMessage(failure(500, {}))).toBe('Something went wrong on the server.');
    expect(apiErrorMessage(failure(503, null))).toBe('Something went wrong on the server.');
  });

  it('falls back to the problem title, then to the caller fallback', () => {
    expect(apiErrorMessage(failure(404, { title: 'Not Found' }), 'x')).toBe('Not Found');
    expect(apiErrorMessage(failure(418, {}), 'Custom fallback')).toBe('Custom fallback');
    expect(apiErrorMessage(failure(418, {}))).toBe('Something went wrong.');
  });

  it('says so when the server cannot be reached', () => {
    expect(apiErrorMessage(new Error('Network Error'))).toMatch(/cannot reach the server/i);
    expect(apiErrorMessage(undefined)).toMatch(/cannot reach the server/i);
  });
});
