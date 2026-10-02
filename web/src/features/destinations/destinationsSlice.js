import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import axiosClient from '../../api/axiosClient';

export const fetchDestinations = createAsyncThunk(
  'destinations/fetch',
  async (params, { rejectWithValue }) => {
    try {
      const response = await axiosClient.get('/api/destinations', { params });
      return response.data;
    } catch (err) {
      return rejectWithValue(err.response?.data?.message || 'Failed to load destinations');
    }
  }
);

export const createDestination = createAsyncThunk(
  'destinations/create',
  async (dto, { rejectWithValue }) => {
    try {
      const response = await axiosClient.post('/api/destinations', dto);
      return response.data;
    } catch (err) {
      return rejectWithValue(err.response?.data?.message || 'Failed to create destination');
    }
  }
);

export const updateDestination = createAsyncThunk(
  'destinations/update',
  async ({ id, dto }, { rejectWithValue }) => {
    try {
      const response = await axiosClient.put(`/api/destinations/${id}`, dto);
      return response.data;
    } catch (err) {
      return rejectWithValue(err.response?.data?.message || 'Failed to update destination');
    }
  }
);

export const deactivateDestination = createAsyncThunk(
  'destinations/deactivate',
  async (id, { rejectWithValue }) => {
    try {
      await axiosClient.delete(`/api/destinations/${id}`);
      return id;
    } catch (err) {
      return rejectWithValue(err.response?.data?.message || 'Failed to deactivate destination');
    }
  }
);

const destinationsSlice = createSlice({
  name: 'destinations',
  initialState: {
    items: [],
    totalCount: 0,
    page: 1,
    pageSize: 10,
    status: 'idle',
    error: null,
  },
  reducers: {},
  extraReducers: (builder) => {
    builder
      .addCase(fetchDestinations.pending, (state) => {
        state.status = 'loading';
      })
      .addCase(fetchDestinations.fulfilled, (state, action) => {
        state.status = 'succeeded';
        state.items = action.payload.items;
        state.totalCount = action.payload.totalCount;
        state.page = action.payload.page;
        state.pageSize = action.payload.pageSize;
      })
      .addCase(fetchDestinations.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.payload;
      })
      .addCase(createDestination.fulfilled, (state, action) => {
        state.items.unshift(action.payload);
      })
      .addCase(updateDestination.fulfilled, (state, action) => {
        const index = state.items.findIndex((d) => d.id === action.payload.id);
        if (index !== -1) state.items[index] = action.payload;
      })
      .addCase(deactivateDestination.fulfilled, (state, action) => {
        state.items = state.items.filter((d) => d.id !== action.payload);
      });
  },
});

export default destinationsSlice.reducer;
