using System.Text.Json.Serialization;

namespace CEYLORA.Application.DTOs.AiPlanning;

/// <summary>
/// Sent to ceylora-ai-service POST /api/workflow/plan.
/// Field names are lowercase single words, so they serialize to the exact JSON
/// keys the Python PlanRequest schema expects (goal, days, budget, interests).
/// </summary>
public class AiPlanRequest
{
    [JsonPropertyName("goal")]
    public string Goal { get; set; } = string.Empty;

    [JsonPropertyName("days")]
    public int Days { get; set; }

    [JsonPropertyName("budget")]
    public decimal Budget { get; set; }

    [JsonPropertyName("interests")]
    public List<string> Interests { get; set; } = new();
}
