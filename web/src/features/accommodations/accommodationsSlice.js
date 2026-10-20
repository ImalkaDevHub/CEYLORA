import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import axiosClient from '../../api/axiosClient';
import { apiErrorMessage } from '../../api/errors';

export const fetchAccommodations = createAsyncThunk(
  'accommodations/fetch',
  async (params, { rejectWithValue }) => {
    try {
      const response = await axiosClient.get('/api/accommodations', { params });
      return response.data;
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to load accommodations'));
    }
  }
);

/** Active destinations for the "Destination" dropdown of the form. */
export const fetchDestinationOptions = createAsyncThunk(
  'accommodations/fetchDestinationOptions',
  async (_, { rejectWithValue }) => {
    try {
      const response = await axiosClient.get('/api/destinations', {
        params: { pageSize: 100, sortBy: 'Name' },
      });
      return response.data.items.map((d) => ({ id: d.id, name: d.name }));
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to load destinations'));
    }
  }
);

export const createAccommodation = createAsyncThunk(
  'accommodations/create',
  async (dto, { rejectWithValue }) => {
    try {
      const response = await axiosClient.post('/api/accommodations', dto);
      return response.data;
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to create accommodation'));
    }
  }
);

export const updateAccommodation = createAsyncThunk(
  'accommodations/update',
  async ({ id, dto }, { rejectWithValue }) => {
    try {
      const response = await axiosClient.put(`/api/accommodations/${id}`, dto);
      return response.data;
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to update accommodation'));
    }
  }
);

export const deactivateAccommodation = createAsyncThunk(
  'accommodations/deactivate',
  async (id, { rejectWithValue }) => {
    try {
      await axiosClient.delete(`/api/accommodations/${id}`);
      return id;
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to deactivate accommodation'));
    }
  }
);

export const fetchAvailability = createAsyncThunk(
  'accommodations/fetchAvailability',
  async ({ id, from, to }, { rejectWithValue }) => {
    try {
      const response = await axiosClient.get(`/api/accommodations/${id}/availability`, {
        params: { from, to },
      });
      return { id, days: response.data };
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to load availability'));
    }
  }
);

export const setAvailability = createAsyncThunk(
  'accommodations/setAvailability',
  async ({ id, dto }, { rejectWithValue }) => {
    try {
      const response = await axiosClient.put(`/api/accommodations/${id}/availability`, dto);
      return { id, days: response.data };
    } catch (err) {
      return rejectWithValue(apiErrorMessage(err, 'Failed to update availability'));
    }
  }
);

const accommodationsSlice = createSlice({
  name: 'accommodations',
  initialState: {
    items: [],
    totalCount: 0,
    page: 1,
    pageSize: 10,
    status: 'idle',
    error: null,
    destinationOptions: [],
    availability: { accommodationId: null, days: [], status: 'idle', error: null },
  },
  reducers: {
    /** Forget the loaded nights when the availability panel is closed or switched. */
    clearAvailability: (state) => {
      state.availability = { accommodationId: null, days: [], status: 'idle', error: null };
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(fetchAccommodations.pending, (state) => {
        state.status = 'loading';
        state.error = null;
      })
      .addCase(fetchAccommodations.fulfilled, (state, action) => {
        state.status = 'succeeded';
        state.items = action.payload.items;
        state.totalCount = action.payload.totalCount;
        state.page = action.payload.page;
        state.pageSize = action.payload.pageSize;
      })
      .addCase(fetchAccommodations.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.payload ?? action.error.message;
      })
      .addCase(fetchDestinationOptions.fulfilled, (state, action) => {
        state.destinationOptions = action.payload;
      })
      .addCase(updateAccommodation.fulfilled, (state, action) => {
        const index = state.items.findIndex((a) => a.id === action.payload.id);
        if (index !== -1) state.items[index] = action.payload;
      })
      .addCase(deactivateAccommodation.fulfilled, (state, action) => {
        const item = state.items.find((a) => a.id === action.payload);
        if (item) item.isActive = false;
      })
      .addCase(fetchAvailability.pending, (state, action) => {
        const id = action.meta.arg.id;
        // Switching to another stay must not briefly show the previous stay's nights.
        if (state.availability.accommodationId !== id) state.availability.days = [];
        state.availability.accommodationId = id;
        state.availability.status = 'loading';
        state.availability.error = null;
      })
      .addCase(fetchAvailability.fulfilled, (state, action) => {
        // Ignore an answer for a stay that is no longer open.
        if (state.availability.accommodationId !== action.payload.id) return;
        state.availability.status = 'succeeded';
        state.availability.days = action.payload.days;
      })
      .addCase(fetchAvailability.rejected, (state, action) => {
        if (state.availability.accommodationId !== action.meta.arg.id) return;
        state.availability.status = 'failed';
        state.availability.error = action.payload ?? action.error.message;
      });
  },
});

export const { clearAvailability } = accommodationsSlice.actions;
export default accommodationsSlice.reducer;
