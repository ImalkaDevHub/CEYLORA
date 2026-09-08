using System.Text.Json.Serialization;

namespace CEYLORA.Application.DTOs.AiPlanning;

/// <summary>
/// Mirrors the Python service's PlanResponse schema
/// (ceylora-ai-service/app/schemas/responses.py) field-for-field.
/// </summary>
public class AiPlanResponse
{
    [JsonPropertyName("goal")]
    public string Goal { get; set; } = string.Empty;

    [JsonPropertyName("days")]
    public int Days { get; set; }

    [JsonPropertyName("budget")]
    public decimal Budget { get; set; }

    [JsonPropertyName("interests")]
    public List<string> Interests { get; set; } = new();

    /// <summary>Human-readable itinerary text accumulated across the agent chain.</summary>
    [JsonPropertyName("plan")]
    public string Plan { get; set; } = string.Empty;

    /// <summary>Marker from the AI service, e.g. "planner_agent (gemini)".</summary>
    [JsonPropertyName("generated_by")]
    public string GeneratedBy { get; set; } = string.Empty;

    /// <summary>Verdict from the validation_safety agent: "PASS" or "NEEDS_REVISION".</summary>
    [JsonPropertyName("overall_status")]
    public string OverallStatus { get; set; } = "Pending";

    /// <summary>
    /// Whether a human operator must approve before confirmation. Advisory input
    /// only — this API decides the actual ApprovalStatus, the AI never grants itself approval.
    /// </summary>
    [JsonPropertyName("requires_approval")]
    public bool RequiresApproval { get; set; }

    /// <summary>Per-agent execution records, in the order the graph ran them.</summary>
    [JsonPropertyName("steps")]
    public List<AiPlanStepDto> Steps { get; set; } = new();
}

/// <summary>One agent's execution record, as reported by ceylora-ai-service.</summary>
public class AiPlanStepDto
{
    [JsonPropertyName("agent")]
    public string Agent { get; set; } = string.Empty;

    /// <summary>"completed" or "error".</summary>
    [JsonPropertyName("status")]
    public string Status { get; set; } = string.Empty;

    // DateTimeOffset because the AI service sends ISO-8601 with a UTC offset;
    // .UtcDateTime then gives the Kind=Utc DateTime Npgsql requires for timestamptz.
    [JsonPropertyName("started_at")]
    public DateTimeOffset StartedAt { get; set; }

    [JsonPropertyName("completed_at")]
    public DateTimeOffset? CompletedAt { get; set; }

    [JsonPropertyName("output_summary")]
    public string? OutputSummary { get; set; }

    [JsonPropertyName("error_message")]
    public string? ErrorMessage { get; set; }
}
