import { describe, expect, it } from 'vitest';
import {
  dateInputFromToday,
  formatDateOnly,
  formatLkr,
  formatTimestamp,
  nightsBetween,
  toDateInput,
} from './format';

describe('formatLkr', () => {
  it('groups thousands and drops zero cents', () => {
    expect(formatLkr(20000)).toBe('LKR 20,000');
    expect(formatLkr(999)).toBe('LKR 999');
    expect(formatLkr(0)).toBe('LKR 0');
  });

  it('keeps cents only when present', () => {
    expect(formatLkr(1234567.5)).toBe('LKR 1,234,567.50');
  });

  it('accepts numeric strings and refuses junk', () => {
    expect(formatLkr('45000')).toBe('LKR 45,000');
    expect(formatLkr('abc')).toBe('');
    expect(formatLkr(undefined)).toBe('');
  });
});

describe('formatDateOnly', () => {
  it('reads a calendar date without any time-zone shift', () => {
    expect(formatDateOnly('2026-11-01')).toBe('1 Nov 2026');
    expect(formatDateOnly('2026-12-31')).toBe('31 Dec 2026');
  });

  it('ignores a time part and tolerates bad input', () => {
    expect(formatDateOnly('2026-11-01T00:00:00Z')).toBe('1 Nov 2026');
    expect(formatDateOnly('soon')).toBe('soon');
    expect(formatDateOnly(undefined)).toBe('');
  });
});

describe('formatTimestamp', () => {
  it('shows the UTC calendar day', () => {
    expect(formatTimestamp('2026-10-20T23:59:00Z')).toBe('20 Oct 2026');
    expect(formatTimestamp('2026-10-21T00:00:00Z')).toBe('21 Oct 2026');
  });

  it('is empty for missing or invalid values', () => {
    expect(formatTimestamp(null)).toBe('');
    expect(formatTimestamp('nope')).toBe('');
  });
});

describe('date inputs', () => {
  it('toDateInput pads month and day from local fields', () => {
    expect(toDateInput(new Date(2026, 2, 5))).toBe('2026-03-05');
  });

  it('dateInputFromToday offsets from today', () => {
    const today = dateInputFromToday(0);
    expect(dateInputFromToday(1)).not.toBe(today);
    expect(nightsBetween(today, dateInputFromToday(29))).toBe(29);
  });

  it('nightsBetween counts whole nights, across month ends', () => {
    expect(nightsBetween('2026-11-01', '2026-11-03')).toBe(2);
    expect(nightsBetween('2026-10-30', '2026-11-02')).toBe(3);
    expect(nightsBetween('2026-11-03', '2026-11-01')).toBe(-2);
  });
});
