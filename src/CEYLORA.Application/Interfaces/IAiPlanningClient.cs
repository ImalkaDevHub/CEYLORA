using CEYLORA.Application.DTOs.AiPlanning;

namespace CEYLORA.Application.Interfaces;

/// <summary>
/// Talks to the external ceylora-ai-service (FastAPI/LangGraph) over HTTP.
/// This is a proof-of-integration slice — not the real AI subsystem yet.
/// </summary>
public interface IAiPlanningClient
{
    Task<AiPlanResponse> RequestPlanAsync(AiPlanRequest request, CancellationToken ct = default);
}
