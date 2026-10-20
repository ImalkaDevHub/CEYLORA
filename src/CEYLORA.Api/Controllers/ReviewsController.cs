using CEYLORA.Application.DTOs.Reviews;
using CEYLORA.Application.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CEYLORA.Api.Controllers;

[Route("api")]
[Authorize]
public class ReviewsController : ApiControllerBase
{
    private readonly IReviewService _service;
    public ReviewsController(IReviewService service) => _service = service;

    /// <summary>Reviews of a stay, newest first.</summary>
    [HttpGet("accommodations/{accommodationId:guid}/reviews")]
    public async Task<IActionResult> GetForAccommodation(
        Guid accommodationId, [FromQuery] int page = 1, [FromQuery] int pageSize = 10) =>
        ToActionResult(await _service.GetForAccommodationAsync(accommodationId, page, pageSize));

    /// <summary>Review a stay after your visit there has ended (once per stay).</summary>
    [HttpPost("accommodations/{accommodationId:guid}/reviews")]
    [Authorize(Roles = "Traveler")]
    public async Task<IActionResult> Create(Guid accommodationId, CreateReviewDto dto) =>
        ToActionResult(await _service.CreateAsync(accommodationId, CurrentUserId, dto),
            created => Created($"api/accommodations/{accommodationId}/reviews", created));

    /// <summary>The author or an admin removes a review.</summary>
    [HttpDelete("reviews/{id:guid}")]
    public async Task<IActionResult> Delete(Guid id) =>
        ToActionResult(await _service.DeleteAsync(id, CurrentUserId, IsAdmin), _ => NoContent());
}
