using CEYLORA.Application.DTOs.Destinations;
using CEYLORA.Application.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CEYLORA.Api.Controllers;

[ApiController]
[Route("api/destinations")]
[Authorize]
public class DestinationsController : ControllerBase
{
    private readonly IDestinationService _service;
    public DestinationsController(IDestinationService service) => _service = service;

    [HttpGet]
    public async Task<IActionResult> GetAll([FromQuery] DestinationQueryParams query) =>
        Ok(await _service.GetDestinationsAsync(query));

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var result = await _service.GetByIdAsync(id);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpGet("{id}/summary")]
    public async Task<IActionResult> GetSummary(Guid id)
    {
        var result = await _service.GetSummaryAsync(id);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPost]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Create(CreateDestinationDto dto)
    {
        var result = await _service.CreateAsync(dto);
        return CreatedAtAction(nameof(GetById), new { id = result.Id }, result);
    }

    [HttpPut("{id}")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Update(Guid id, UpdateDestinationDto dto)
    {
        var result = await _service.UpdateAsync(id, dto);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Deactivate(Guid id)
    {
        var success = await _service.DeactivateAsync(id);
        return success ? NoContent() : NotFound();
    }
}
