import { useState } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { startWorkflow, clearCurrent } from './aiWorkflowsSlice';

const INTEREST_OPTIONS = ['beach', 'nature', 'culture', 'adventure', 'wildlife', 'citylife'];

export default function PlanTripPage() {
  const dispatch = useDispatch();
  const { current, status, error } = useSelector((state) => state.aiWorkflows);
  const [form, setForm] = useState({ goal: '', days: 5, budget: 100000, interests: ['beach'] });

  const toggleInterest = (interest) => {
    setForm((f) => ({
      ...f,
      interests: f.interests.includes(interest)
        ? f.interests.filter((i) => i !== interest)
        : [...f.interests, interest],
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    dispatch(clearCurrent());
    dispatch(startWorkflow(form));
  };

  return (
    <div style={{ maxWidth: 700, margin: '40px auto' }}>
      <h2>Plan My Trip with AI</h2>

      <form onSubmit={handleSubmit} style={{ border: '1px solid #ddd', padding: 16, borderRadius: 8, marginBottom: 24 }}>
        <input
          placeholder="Describe your trip (e.g. relaxing coastal trip)"
          value={form.goal}
          onChange={(e) => setForm({ ...form, goal: e.target.value })}
          required
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }}
        />
        <label>Days</label>
        <input type="number" min="1" value={form.days}
          onChange={(e) => setForm({ ...form, days: Number(e.target.value) })}
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <label>Budget (LKR)</label>
        <input type="number" min="0" value={form.budget}
          onChange={(e) => setForm({ ...form, budget: Number(e.target.value) })}
          style={{ display: 'block', width: '100%', marginBottom: 8, padding: 8 }} />
        <label>Interests</label>
        <div style={{ marginBottom: 12 }}>
          {INTEREST_OPTIONS.map((interest) => (
            <label key={interest} style={{ marginRight: 12 }}>
              <input
                type="checkbox"
                checked={form.interests.includes(interest)}
                onChange={() => toggleInterest(interest)}
              />{' '}
              {interest}
            </label>
          ))}
        </div>
        <button type="submit" disabled={status === 'loading'} style={{ padding: 8, width: '100%' }}>
          {status === 'loading' ? 'Planning your trip...' : 'Plan My Trip with AI'}
        </button>
        {error && <p style={{ color: 'red' }}>{error}</p>}
      </form>

      {current && (
        <div style={{ border: '1px solid #ccc', padding: 16, borderRadius: 8 }}>
          <h3>Workflow Result</h3>
          <p><strong>Status:</strong> {current.overallStatus}</p>
          <p>
            <strong>Approval:</strong>{' '}
            {current.approvalStatus === 'AwaitingApproval'
              ? '⏸ Awaiting operator approval'
              : current.approvalStatus}
          </p>

          <h4>Execution Trail</h4>
          <ol>
            {current.steps.map((step) => (
              <li key={step.id}>
                <strong>{step.agentName}</strong> — {step.status}
                {step.outputSummary && <div style={{ fontSize: 13, color: '#555' }}>{step.outputSummary}</div>}
              </li>
            ))}
          </ol>

          <h4>Proposed Plan</h4>
          <pre style={{ whiteSpace: 'pre-wrap', background: '#f9f9f9', padding: 12, borderRadius: 6 }}>
            {current.finalPlan}
          </pre>
        </div>
      )}
    </div>
  );
}
