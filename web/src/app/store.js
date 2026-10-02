import { configureStore } from '@reduxjs/toolkit';
import authReducer from '../features/auth/authSlice';
import tripsReducer from '../features/trips/tripsSlice';
import aiWorkflowsReducer from '../features/aiWorkflows/aiWorkflowsSlice';

export const store = configureStore({
  reducer: {
    auth: authReducer,
    trips: tripsReducer,
    aiWorkflows: aiWorkflowsReducer,
  },
});
