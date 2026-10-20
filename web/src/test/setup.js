import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

// Vitest does not clean up between tests on its own (no globals).
afterEach(() => cleanup());
