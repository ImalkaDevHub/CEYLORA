import { useEffect } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { fetchPendingApprovals, approveWorkflow, rejectWorkflow, reviseWorkflow } from './aiWorkflowsSlice';

export default function ApprovalsQueuePage() {
  const dispatch = useDispatch();
  const { pending, status, error } = useSelector((state) => state.aiWorkflows);

  useEffect(() => {
    dispatch(fetchPendingApprovals());
  }, [dispatch]);

  return (
    <div style={{ maxWidth: 800, margin: '40px auto' }}>
      <h2>Pending AI Workflow Approvals</h2>

      {status === 'loading' && <p>Loading...</p>}
      {error && <p style={{ color: 'red' }}>{error}</p>}
      {status === 'succeeded' && pending.length === 0 && <p>No workflows awaiting approval.</p>}

      {pending.map((wf) => (
        <div key={wf.id} style={{ border: '1px solid #ccc', padding: 16, borderRadius: 8, marginBottom: 16 }}>
          <p><strong>{wf.travelerName}</strong> — {wf.goal} ({wf.days} days, LKR {wf.budget})</p>
          <p><strong>Overall status:</strong> {wf.overallStatus}</p>

          <details>
            <summary>View execution trail & plan</summary>
            <ol>
              {wf.steps.map((step) => (
                <li key={step.id}>
                  <strong>{step.agentName}</strong> — {step.status}
                  {step.outputSummary && <div style={{ fontSize: 13, color: '#555' }}>{step.outputSummary}</div>}
                </li>
              ))}
            </ol>
            <pre style={{ whiteSpace: 'pre-wrap', background: '#f9f9f9', padding: 12, borderRadius: 6 }}>
              {wf.finalPlan}
            </pre>
          </details>

          <div style={{ marginTop: 10 }}>
            <button onClick={() => dispatch(approveWorkflow(wf.id))} style={{ marginRight: 8 }}>
              Approve
            </button>
            <button onClick={() => dispatch(rejectWorkflow(wf.id))} style={{ marginRight: 8 }}>
              Reject
            </button>
            <button onClick={() => dispatch(reviseWorkflow(wf.id))}>
              Request Revision
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
