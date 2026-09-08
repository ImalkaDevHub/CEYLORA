namespace CEYLORA.Domain.Entities;

/// <summary>
/// One agent's execution record inside an <see cref="AIWorkflow"/> run.
/// Mirrors a `steps[]` entry returned by ceylora-ai-service.
/// </summary>
public class AIWorkflowStep
{
    public Guid Id { get; set; }

    public Guid AIWorkflowId { get; set; }
    public AIWorkflow AIWorkflow { get; set; } = null!;

    /// <summary>Graph node name, e.g. "planner", "validation_safety".</summary>
    public string AgentName { get; set; } = string.Empty;

    /// <summary>"completed" or "error", as reported by the AI service.</summary>
    public string Status { get; set; } = string.Empty;

    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }

    public string? OutputSummary { get; set; }
    public string? ErrorMessage { get; set; }
}
