using CEYLORA.Application.DTOs.AiWorkflows;

namespace CEYLORA.Application.Interfaces;

/// <summary>
/// Runs the agentic planning chain via ceylora-ai-service and persists each run
/// as an AIWorkflow (+ its AIWorkflowStep rows), gated on human approval.
///
/// Approval is a backend business rule: the AI service only *advises* via
/// `requires_approval`; this service decides and records the actual status.
/// </summary>
public interface IAiWorkflowService
{
    Task<AiWorkflowResponseDto> StartWorkflowAsync(Guid travelerId, StartWorkflowDto dto, CancellationToken ct = default);

    Task<AiWorkflowResponseDto?> GetWorkflowAsync(Guid id);

    /// <summary>Operator/Admin queue: workflows sitting in AwaitingApproval.</summary>
    Task<List<AiWorkflowResponseDto>> GetPendingApprovalsAsync();

    // The three decision operations below are only valid while ApprovalStatus is
    // AwaitingApproval; they return null for "not found or already decided".
    Task<AiWorkflowResponseDto?> ApproveAsync(Guid workflowId, Guid operatorId);
    Task<AiWorkflowResponseDto?> RejectAsync(Guid workflowId, Guid operatorId);
    Task<AiWorkflowResponseDto?> ReviseAsync(Guid workflowId, Guid operatorId);
}
