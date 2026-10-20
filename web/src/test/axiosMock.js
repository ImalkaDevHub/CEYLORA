import { vi } from 'vitest';

// Kept free of other imports so a vi.mock factory can load it without a cycle.
export const mockedAxios = () => ({
  default: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() },
});
