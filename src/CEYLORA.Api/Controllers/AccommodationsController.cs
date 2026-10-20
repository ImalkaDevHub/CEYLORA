using CEYLORA.Application.DTOs.Accommodations;
using CEYLORA.Application.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CEYLORA.Api.Controllers;

[Route("api/accommodations")]
[Authorize]
public class AccommodationsController : ApiControllerBase
{
    private readonly IAccommodationService _service;
    public AccommodationsController(IAccommodationService service) => _service = service;

    /// <summary>Search, filter, sort and page the stays on offer.</summary>
    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] AccommodationQueryParams query)
    {
        // Only staff may look at deactivated stays.
        if (!IsStaff) query.IncludeInactive = false;
        return Ok(await _service.GetAccommodationsAsync(query));
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var result = await _service.GetByIdAsync(id);
        if (result is null) return NotFound(new { message = "Accommodation not found." });

        // A deactivated stay is hidden from travelers; only staff can still open it.
        if (!result.IsActive && !IsStaff) return NotFound(new { message = "Accommodation not found." });
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Create(CreateAccommodationDto dto) =>
        ToActionResult(await _service.CreateAsync(dto),
            created => CreatedAtAction(nameof(GetById), new { id = created.Id }, created));

    [HttpPut("{id:guid}")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Update(Guid id, UpdateAccommodationDto dto) =>
        ToActionResult(await _service.UpdateAsync(id, dto));

    [HttpDelete("{id:guid}")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Deactivate(Guid id) =>
        await _service.DeactivateAsync(id)
            ? NoContent()
            : NotFound(new { message = "Accommodation not found." });

    /// <summary>Nightly room inventory between two dates (inclusive).</summary>
    [HttpGet("{id:guid}/availability")]
    public async Task<IActionResult> GetAvailability(Guid id, [FromQuery] DateOnly from, [FromQuery] DateOnly to) =>
        ToActionResult(await _service.GetAvailabilityAsync(id, from, to));

    /// <summary>Operator sets how many rooms exist for every night in a range.</summary>
    [HttpPut("{id:guid}/availability")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> SetAvailability(Guid id, SetAvailabilityDto dto) =>
        ToActionResult(await _service.SetAvailabilityAsync(id, dto));

    /// <summary>Can I stay here from check-in to check-out with N rooms, and what does it cost?</summary>
    [HttpGet("{id:guid}/quote")]
    public async Task<IActionResult> Quote(
        Guid id, [FromQuery] DateOnly checkIn, [FromQuery] DateOnly checkOut, [FromQuery] int rooms = 1) =>
        ToActionResult(await _service.QuoteAsync(id, checkIn, checkOut, rooms));
}
