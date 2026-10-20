namespace CEYLORA.Application.DTOs.AiWorkflows;

/// <summary>Body for POST /api/ai/workflows — what the traveler wants planned.</summary>
public class StartWorkflowDto
{
    public string Goal { get; set; } = string.Empty;
    public int Days { get; set; }
    public decimal Budget { get; set; }
    public List<string> Interests { get; set; } = new();

    /// <summary>
    /// Optional first day of the trip (calendar date). Defaults to tomorrow (UTC) when
    /// omitted, so existing clients that don't send it keep working.
    /// </summary>
    public DateTime? StartDate { get; set; }
}

/// <summary>One agent's execution record — the observability trail for a run.</summary>
public class AiWorkflowStepDto
{
    public Guid Id { get; set; }
    public string AgentName { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public string? OutputSummary { get; set; }
    public string? ErrorMessage { get; set; }
}

/// <summary>Full detail of one persisted agentic run, including its per-agent steps.</summary>
public class AiWorkflowResponseDto
{
    public Guid Id { get; set; }
    public Guid? TripId { get; set; }
    public Guid TravelerId { get; set; }
    public string TravelerName { get; set; } = string.Empty;

    public string Goal { get; set; } = string.Empty;
    public int Days { get; set; }
    public decimal Budget { get; set; }
    public List<string> Interests { get; set; } = new();

    public string? FinalPlan { get; set; }
    public string OverallStatus { get; set; } = string.Empty;
    public bool RequiresApproval { get; set; }
    public string ApprovalStatus { get; set; } = string.Empty;

    public Guid? ApprovedByUserId { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? CompletedAt { get; set; }

    public List<AiWorkflowStepDto> Steps { get; set; } = new();
}
