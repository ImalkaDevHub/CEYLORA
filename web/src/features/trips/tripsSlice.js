import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import axiosClient from '../../api/axiosClient';

export const fetchMyTrips = createAsyncThunk('trips/fetchMine', async (_, { rejectWithValue }) => {
  try {
    const response = await axiosClient.get('/api/trips/mine');
    return response.data;
  } catch (err) {
    return rejectWithValue(err.response?.data?.message || 'Failed to load trips');
  }
});

export const createTrip = createAsyncThunk('trips/create', async (tripData, { rejectWithValue }) => {
  try {
    const response = await axiosClient.post('/api/trips', tripData);
    return response.data;
  } catch (err) {
    return rejectWithValue(err.response?.data?.message || 'Failed to create trip');
  }
});

export const submitTrip = createAsyncThunk('trips/submit', async (tripId, { rejectWithValue }) => {
  try {
    const response = await axiosClient.post(`/api/trips/${tripId}/submit`);
    return response.data;
  } catch (err) {
    return rejectWithValue(err.response?.data?.message || 'Failed to submit trip');
  }
});

const tripsSlice = createSlice({
  name: 'trips',
  initialState: {
    items: [],
    status: 'idle',
    error: null,
  },
  reducers: {},
  extraReducers: (builder) => {
    builder
      .addCase(fetchMyTrips.pending, (state) => {
        state.status = 'loading';
      })
      .addCase(fetchMyTrips.fulfilled, (state, action) => {
        state.status = 'succeeded';
        state.items = action.payload;
      })
      .addCase(fetchMyTrips.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.payload;
      })
      .addCase(createTrip.fulfilled, (state, action) => {
        state.items.push(action.payload);
      })
      .addCase(submitTrip.fulfilled, (state, action) => {
        const index = state.items.findIndex((t) => t.id === action.payload.id);
        if (index !== -1) state.items[index] = action.payload;
      });
  },
});

export default tripsSlice.reducer;
