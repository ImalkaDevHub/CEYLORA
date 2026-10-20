import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import axiosClient from '../../api/axiosClient';
import { apiErrorMessage } from '../../api/errors';

export const fetchBookings = createAsyncThunk(
  'bookings/fetch',
  async (params, { rejectWithValue }) => {
    try {
      const response = await axiosClient.get('/api/bookings', { params });
      return response.data;
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to load bookings'));
    }
  }
);

/** Every stay (including inactive ones, which can still have bookings) for the filter. */
export const fetchStayOptions = createAsyncThunk(
  'bookings/fetchStayOptions',
  async (_, { rejectWithValue }) => {
    try {
      const response = await axiosClient.get('/api/accommodations', {
        params: { includeInactive: true, pageSize: 50, sortBy: 'Name' },
      });
      return response.data.items.map((a) => ({ id: a.id, name: a.name }));
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to load accommodations'));
    }
  }
);

export const cancelBooking = createAsyncThunk(
  'bookings/cancel',
  async (id, { rejectWithValue }) => {
    try {
      const response = await axiosClient.post(`/api/bookings/${id}/cancel`);
      return response.data;
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to cancel booking'));
    }
  }
);

const bookingsSlice = createSlice({
  name: 'bookings',
  initialState: {
    items: [],
    totalCount: 0,
    page: 1,
    pageSize: 20,
    status: 'idle',
    error: null,
    stayOptions: [],
  },
  reducers: {},
  extraReducers: (builder) => {
    builder
      .addCase(fetchBookings.pending, (state) => {
        state.status = 'loading';
        state.error = null;
      })
      .addCase(fetchBookings.fulfilled, (state, action) => {
        state.status = 'succeeded';
        state.items = action.payload.items;
        state.totalCount = action.payload.totalCount;
        state.page = action.payload.page;
        state.pageSize = action.payload.pageSize;
      })
      .addCase(fetchBookings.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.payload ?? action.error.message;
      })
      .addCase(fetchStayOptions.fulfilled, (state, action) => {
        state.stayOptions = action.payload;
      })
      .addCase(cancelBooking.fulfilled, (state, action) => {
        // Replace in place so the row stays where it is, now marked Cancelled.
        const index = state.items.findIndex((b) => b.id === action.payload.id);
        if (index !== -1) state.items[index] = action.payload;
      });
  },
});

export default bookingsSlice.reducer;
