import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import axiosClient from '../../api/axiosClient';

export const startWorkflow = createAsyncThunk('aiWorkflows/start', async (requestDto, { rejectWithValue }) => {
  try {
    const response = await axiosClient.post('/api/ai/workflows', requestDto);
    return response.data;
  } catch (err) {
    return rejectWithValue(err.response?.data?.message || 'Failed to start AI workflow');
  }
});

export const fetchWorkflow = createAsyncThunk('aiWorkflows/fetchOne', async (id, { rejectWithValue }) => {
  try {
    const response = await axiosClient.get(`/api/ai/workflows/${id}`);
    return response.data;
  } catch (err) {
    return rejectWithValue(err.response?.data?.message || 'Failed to load workflow');
  }
});

export const fetchPendingApprovals = createAsyncThunk('aiWorkflows/fetchPending', async (_, { rejectWithValue }) => {
  try {
    const response = await axiosClient.get('/api/ai/workflows/pending');
    return response.data;
  } catch (err) {
    return rejectWithValue(err.response?.data?.message || 'Failed to load pending approvals');
  }
});

const decide = (action) =>
  createAsyncThunk(`aiWorkflows/${action}`, async (id, { rejectWithValue }) => {
    try {
      const response = await axiosClient.post(`/api/ai/workflows/${id}/${action}`);
      return response.data;
    } catch (err) {
      return rejectWithValue(err.response?.data?.message || `Failed to ${action} workflow`);
    }
  });

export const approveWorkflow = decide('approve');
export const rejectWorkflow = decide('reject');
export const reviseWorkflow = decide('revise');

const aiWorkflowsSlice = createSlice({
  name: 'aiWorkflows',
  initialState: {
    current: null,       // the workflow just started/viewed (Traveler side)
    pending: [],          // the approval queue (Operator/Admin side)
    status: 'idle',
    error: null,
  },
  reducers: {
    clearCurrent: (state) => {
      state.current = null;
      state.error = null;
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(startWorkflow.pending, (state) => {
        state.status = 'loading';
        state.error = null;
      })
      .addCase(startWorkflow.fulfilled, (state, action) => {
        state.status = 'succeeded';
        state.current = action.payload;
      })
      .addCase(startWorkflow.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.payload;
      })
      .addCase(fetchWorkflow.fulfilled, (state, action) => {
        state.current = action.payload;
      })
      .addCase(fetchPendingApprovals.pending, (state) => {
        state.status = 'loading';
      })
      .addCase(fetchPendingApprovals.fulfilled, (state, action) => {
        state.status = 'succeeded';
        state.pending = action.payload;
      })
      .addCase(fetchPendingApprovals.rejected, (state, action) => {
        state.status = 'failed';
        state.error = action.payload;
      });

    // All three decisions do the same thing to state: remove the decided
    // workflow from the pending queue once it's no longer awaiting approval.
    [approveWorkflow, rejectWorkflow, reviseWorkflow].forEach((thunk) => {
      builder.addCase(thunk.fulfilled, (state, action) => {
        state.pending = state.pending.filter((w) => w.id !== action.payload.id);
      });
    });
  },
});

export const { clearCurrent } = aiWorkflowsSlice.actions;
export default aiWorkflowsSlice.reducer;
