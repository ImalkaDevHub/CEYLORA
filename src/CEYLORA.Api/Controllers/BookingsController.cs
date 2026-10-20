using CEYLORA.Application.DTOs.Bookings;
using CEYLORA.Application.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CEYLORA.Api.Controllers;

[Route("api/bookings")]
[Authorize]
public class BookingsController : ApiControllerBase
{
    private readonly IBookingService _service;
    public BookingsController(IBookingService service) => _service = service;

    /// <summary>Book stays for one of the caller's trips; rooms are reserved in the same step.</summary>
    [HttpPost]
    [Authorize(Roles = "Traveler")]
    public async Task<IActionResult> Create(CreateBookingDto dto) =>
        ToActionResult(await _service.CreateAsync(CurrentUserId, dto),
            created => CreatedAtAction(nameof(GetById), new { id = created.Id }, created));

    [HttpGet("mine")]
    [Authorize(Roles = "Traveler")]
    public async Task<IActionResult> GetMine() =>
        Ok(await _service.GetMineAsync(CurrentUserId));

    /// <summary>Every booking, for the operator's screen.</summary>
    [HttpGet]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> GetAll([FromQuery] BookingQueryParams query) =>
        Ok(await _service.GetAllAsync(query));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id) =>
        ToActionResult(await _service.GetByIdAsync(id, CurrentUserId, IsStaff));

    /// <summary>Cancel a booking and give its rooms back.</summary>
    [HttpPost("{id:guid}/cancel")]
    public async Task<IActionResult> Cancel(Guid id) =>
        ToActionResult(await _service.CancelAsync(id, CurrentUserId, IsStaff));
}
