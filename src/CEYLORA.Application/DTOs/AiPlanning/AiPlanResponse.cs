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

    /// <summary>Human-readable itinerary text (currently a stub, no LLM).</summary>
    [JsonPropertyName("plan")]
    public string Plan { get; set; } = string.Empty;

    /// <summary>Marker from the AI service, e.g. "planner_agent (stub)".</summary>
    [JsonPropertyName("generated_by")]
    public string GeneratedBy { get; set; } = string.Empty;
}
