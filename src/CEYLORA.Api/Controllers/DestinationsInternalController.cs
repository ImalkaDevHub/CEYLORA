using CEYLORA.Application.DTOs.Destinations;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;

namespace CEYLORA.Api.Controllers;

// ---------------------------------------------------------------------------
// Service-to-service endpoint for the CEYLORA AI microservice (ceylora-ai-service).
//
// This is DELIBERATELY different from the public /api/destinations endpoints:
//   - /api/destinations is called by the React / Flutter clients on behalf of a
//     signed-in user, and is protected by that user's [Authorize] JWT.
//   - This endpoint is called by another backend service — no user, no JWT. It
//     is protected instead by a shared secret sent in the `X-Internal-Api-Key`
//     header, matched against `Internal:ApiKey` in configuration.
//
// Viva answer to "why is this endpoint different?": the caller is a trusted
// backend service, not an end user, so it uses a different auth mechanism
// (shared secret instead of a user JWT) and returns a narrower, read-only
// payload shaped for the AI agent.
// ---------------------------------------------------------------------------
[ApiController]
[Route("api/internal/destinations")]
public class DestinationsInternalController : ControllerBase
{
    private const string ApiKeyHeader = "X-Internal-Api-Key";

    private readonly IDestinationService _service;
    private readonly IConfiguration _config;

    public DestinationsInternalController(IDestinationService service, IConfiguration config)
    {
        _service = service;
        _config = config;
    }

    [HttpGet]
    public async Task<IActionResult> Get([FromQuery] string? category, [FromQuery] string? search)
    {
        var expectedKey = _config["Internal:ApiKey"];
        if (string.IsNullOrEmpty(expectedKey)
            || !Request.Headers.TryGetValue(ApiKeyHeader, out var provided)
            || !string.Equals(provided.ToString(), expectedKey, StringComparison.Ordinal))
        {
            return Unauthorized(new { message = $"Missing or invalid {ApiKeyHeader} header." });
        }

        var query = new DestinationQueryParams
        {
            Search = search,
            Page = 1,
            PageSize = 500 // fixed large page — the AI agent wants the whole active catalog
        };

        // category matches TravelCategory by name (case-insensitive); ignored if it doesn't.
        if (!string.IsNullOrWhiteSpace(category)
            && Enum.TryParse<TravelCategory>(category, ignoreCase: true, out var parsed))
        {
            query.Category = parsed;
        }

        // GetDestinationsAsync already restricts to IsActive == true.
        var page = await _service.GetDestinationsAsync(query);

        var result = page.Items.Select(d => new InternalDestinationDto(
            d.Id, d.Name, d.Region, d.Category, d.Description));

        return Ok(result);
    }
}

/// <summary>Lightweight destination shape returned to the AI service.</summary>
public record InternalDestinationDto(Guid Id, string Name, string Region, string Category, string Description);
