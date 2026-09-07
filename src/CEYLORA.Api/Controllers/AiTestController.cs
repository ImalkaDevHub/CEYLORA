using CEYLORA.Application.DTOs.AiPlanning;
using CEYLORA.Application.Interfaces;
using Microsoft.AspNetCore.Mvc;

namespace CEYLORA.Api.Controllers;

// ---------------------------------------------------------------------------
// TEMPORARY — proof-of-integration only. Delete this controller once the real
// AI planning flow is wired into TripsController. No auth on purpose so the
// .NET -> Python round-trip can be exercised manually via Swagger/curl.
// ---------------------------------------------------------------------------
[ApiController]
[Route("api/ai-test")]
public class AiTestController : ControllerBase
{
    private readonly IAiPlanningClient _aiPlanningClient;

    public AiTestController(IAiPlanningClient aiPlanningClient) => _aiPlanningClient = aiPlanningClient;

    [HttpPost]
    public async Task<IActionResult> Plan(AiPlanRequest request, CancellationToken ct)
    {
        var result = await _aiPlanningClient.RequestPlanAsync(request, ct);
        return Ok(result);
    }
}
