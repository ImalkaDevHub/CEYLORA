import { configureStore } from '@reduxjs/toolkit';
import authReducer from '../features/auth/authSlice';
import tripsReducer from '../features/trips/tripsSlice';
import aiWorkflowsReducer from '../features/aiWorkflows/aiWorkflowsSlice';
import destinationsReducer from '../features/destinations/destinationsSlice';
import accommodationsReducer from '../features/accommodations/accommodationsSlice';
import bookingsReducer from '../features/bookings/bookingsSlice';

const reducer = {
  auth: authReducer,
  trips: tripsReducer,
  aiWorkflows: aiWorkflowsReducer,
  destinations: destinationsReducer,
  accommodations: accommodationsReducer,
  bookings: bookingsReducer,
};

// A factory so tests can build a fresh store (optionally signed in) per test.
export const createAppStore = (preloadedState) => configureStore({ reducer, preloadedState });

export const store = createAppStore();
