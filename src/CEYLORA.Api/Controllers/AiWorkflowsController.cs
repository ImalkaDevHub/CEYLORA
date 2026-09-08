using System.Security.Claims;
using CEYLORA.Application.DTOs.AiWorkflows;
using CEYLORA.Application.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CEYLORA.Api.Controllers;

[ApiController]
[Route("api/ai/workflows")]
[Authorize]
public class AiWorkflowsController : ControllerBase
{
    private readonly IAiWorkflowService _workflowService;

    public AiWorkflowsController(IAiWorkflowService workflowService) => _workflowService = workflowService;

    private Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    private bool IsOperatorOrAdmin => User.IsInRole("Operator") || User.IsInRole("Admin");

    [HttpPost]
    [Authorize(Roles = "Traveler")]
    public async Task<IActionResult> Start(StartWorkflowDto dto, CancellationToken ct)
    {
        var result = await _workflowService.StartWorkflowAsync(CurrentUserId, dto, ct);
        return CreatedAtAction(nameof(GetById), new { id = result.Id }, result);
    }

    /// <summary>Operator/Admin approval queue.</summary>
    [HttpGet("pending")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> GetPending() =>
        Ok(await _workflowService.GetPendingApprovalsAsync());

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var workflow = await _workflowService.GetWorkflowAsync(id);
        if (workflow is null) return NotFound();

        // A traveler may only read their own runs; operators/admins may read any.
        if (workflow.TravelerId != CurrentUserId && !IsOperatorOrAdmin)
            return Forbid();

        return Ok(workflow);
    }

    [HttpPost("{id:guid}/approve")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Approve(Guid id) =>
        DecisionResult(await _workflowService.ApproveAsync(id, CurrentUserId));

    [HttpPost("{id:guid}/reject")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Reject(Guid id) =>
        DecisionResult(await _workflowService.RejectAsync(id, CurrentUserId));

    [HttpPost("{id:guid}/revise")]
    [Authorize(Roles = "Operator,Admin")]
    public async Task<IActionResult> Revise(Guid id) =>
        DecisionResult(await _workflowService.ReviseAsync(id, CurrentUserId));

    private IActionResult DecisionResult(AiWorkflowResponseDto? result) =>
        result is null
            ? BadRequest(new { message = "Workflow not found, or it is not awaiting approval." })
            : Ok(result);
}
