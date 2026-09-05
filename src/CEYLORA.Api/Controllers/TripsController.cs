using System.Security.Claims;
using CEYLORA.Application.DTOs.Trips;
using CEYLORA.Application.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CEYLORA.Api.Controllers;

[ApiController]
[Route("api/trips")]
[Authorize]
public class TripsController : ControllerBase
{
    private readonly ITripService _tripService;

    public TripsController(ITripService tripService) => _tripService = tripService;

    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost]
    [Authorize(Roles = "Traveler")]
    public async Task<IActionResult> Create(CreateTripDto dto)
    {
        var result = await _tripService.CreateTripAsync(CurrentUserId, dto);
        if (result is null)
            return BadRequest(new { message = "End date cannot be before start date." });

        return CreatedAtAction(nameof(GetById), new { id = result.Id }, result);
    }

    [HttpGet("mine")]
    [Authorize(Roles = "Traveler")]
    public async Task<IActionResult> GetMine() =>
        Ok(await _tripService.GetMyTripsAsync(CurrentUserId));

    [HttpGet]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> GetAll() =>
        Ok(await _tripService.GetAllTripsAsync());

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var trip = await _tripService.GetTripByIdAsync(id);
        return trip is null ? NotFound() : Ok(trip);
    }

    [HttpPost("{id}/submit")]
    [Authorize(Roles = "Traveler")]
    public async Task<IActionResult> Submit(Guid id)
    {
        var result = await _tripService.SubmitTripAsync(id, CurrentUserId);
        if (result is null)
            return BadRequest(new { message = "Trip not found, not yours, or not in Draft status." });

        return Ok(result);
    }
}
