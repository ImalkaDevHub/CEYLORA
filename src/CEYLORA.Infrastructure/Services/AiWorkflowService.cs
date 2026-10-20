using CEYLORA.Application.DTOs.AiPlanning;
using CEYLORA.Application.DTOs.AiWorkflows;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Infrastructure.Services;

public class AiWorkflowService : IAiWorkflowService
{
    private readonly ApplicationDbContext _db;
    private readonly IAiPlanningClient _aiPlanningClient;

    public AiWorkflowService(ApplicationDbContext db, IAiPlanningClient aiPlanningClient)
    {
        _db = db;
        _aiPlanningClient = aiPlanningClient;
    }

    public async Task<AiWorkflowResponseDto> StartWorkflowAsync(
        Guid travelerId, StartWorkflowDto dto, CancellationToken ct = default)
    {
        var interests = dto.Interests ?? new List<string>();

        var aiResponse = await _aiPlanningClient.RequestPlanAsync(
            new AiPlanRequest
            {
                Goal = dto.Goal,
                Days = dto.Days,
                Budget = dto.Budget,
                Interests = interests
            },
            ct);

        // The AI only advises. The gate itself is decided here: anything the chain
        // flagged goes into the operator queue, everything else needs no approval.
        var requiresApproval = aiResponse.RequiresApproval;
        var now = DateTime.UtcNow;

        // Every run gets a Trip so the plan shows up in the traveler's trips. Its status
        // follows the approval gate: Submitted while an operator must decide, Confirmed
        // once validation passed with no gate, Draft when validation flagged problems.
        var trip = CreateTripFor(travelerId, dto, aiResponse, requiresApproval, now);

        var workflow = new AIWorkflow
        {
            Id = Guid.NewGuid(),
            TripId = trip.Id,
            TravelerId = travelerId,
            Goal = dto.Goal,
            Days = dto.Days,
            Budget = dto.Budget,
            Interests = interests,
            FinalPlan = aiResponse.Plan,
            OverallStatus = aiResponse.OverallStatus,
            RequiresApproval = requiresApproval,
            ApprovalStatus = requiresApproval ? ApprovalStatus.AwaitingApproval : ApprovalStatus.NotRequired,
            CreatedAt = now,
            // Nothing left to wait on when no approval is needed.
            CompletedAt = requiresApproval ? null : now
        };

        foreach (var step in aiResponse.Steps)
        {
            workflow.Steps.Add(new AIWorkflowStep
            {
                Id = Guid.NewGuid(),
                AIWorkflowId = workflow.Id,
                AgentName = step.Agent,
                Status = step.Status,
                // .UtcDateTime yields Kind=Utc, which Npgsql requires for timestamptz.
                StartedAt = step.StartedAt.UtcDateTime,
                CompletedAt = step.CompletedAt?.UtcDateTime,
                OutputSummary = step.OutputSummary,
                ErrorMessage = step.ErrorMessage
            });
        }

        // Trip first: the workflow row references it through TripId.
        _db.Trips.Add(trip);
        _db.AIWorkflows.Add(workflow);
        await _db.SaveChangesAsync(ct);

        return (await GetWorkflowAsync(workflow.Id))!;
    }

    public async Task<AiWorkflowResponseDto?> GetWorkflowAsync(Guid id)
    {
        var workflow = await LoadFullAsync(id);
        return workflow is null ? null : MapToDto(workflow);
    }

    public async Task<List<AiWorkflowResponseDto>> GetMyWorkflowsAsync(Guid travelerId)
    {
        var workflows = await _db.AIWorkflows
            .Include(w => w.Traveler)
            .Include(w => w.Steps)
            .Where(w => w.TravelerId == travelerId)
            .OrderByDescending(w => w.CreatedAt)
            .ToListAsync();

        return workflows.Select(MapToDto).ToList();
    }

    public async Task<List<AiWorkflowResponseDto>> GetPendingApprovalsAsync()
    {
        var workflows = await _db.AIWorkflows
            .Include(w => w.Traveler)
            .Include(w => w.Steps)
            .Where(w => w.ApprovalStatus == ApprovalStatus.AwaitingApproval)
            .OrderBy(w => w.CreatedAt)
            .ToListAsync();

        return workflows.Select(MapToDto).ToList();
    }

    public Task<AiWorkflowResponseDto?> ApproveAsync(Guid workflowId, Guid operatorId) =>
        DecideAsync(workflowId, operatorId, ApprovalStatus.Approved);

    public Task<AiWorkflowResponseDto?> RejectAsync(Guid workflowId, Guid operatorId) =>
        DecideAsync(workflowId, operatorId, ApprovalStatus.Rejected);

    public Task<AiWorkflowResponseDto?> ReviseAsync(Guid workflowId, Guid operatorId) =>
        DecideAsync(workflowId, operatorId, ApprovalStatus.RevisionRequested);

    /// <summary>
    /// Shared guard for the three decision operations: a workflow can only be
    /// decided once, and only while it is AwaitingApproval. Returns null for
    /// "not found or already decided" — matching the null-means-failure
    /// convention used by TripService.SubmitTripAsync.
    /// </summary>
    private async Task<AiWorkflowResponseDto?> DecideAsync(
        Guid workflowId, Guid operatorId, ApprovalStatus decision)
    {
        var workflow = await LoadFullAsync(workflowId);

        if (workflow is null) return null;
        if (workflow.ApprovalStatus != ApprovalStatus.AwaitingApproval) return null;

        // The decision flows through to the traveler's trip: approval confirms it,
        // rejection or a revision request cancels it (a revision starts a new workflow).
        if (workflow.TripId is { } tripId)
        {
            var trip = await _db.Trips.FirstOrDefaultAsync(t => t.Id == tripId);
            if (trip is not null && trip.Status == TripStatus.Submitted)
            {
                trip.Status = decision == ApprovalStatus.Approved
                    ? TripStatus.Confirmed
                    : TripStatus.Cancelled;
                trip.UpdatedAt = DateTime.UtcNow;
            }
        }

        workflow.ApprovalStatus = decision;
        // ApprovedBy/ApprovedAt record who decided and when, for all three outcomes.
        workflow.ApprovedByUserId = operatorId;
        workflow.ApprovedAt = DateTime.UtcNow;
        workflow.CompletedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();

        return MapToDto(workflow);
    }

    private const int MaxTripTitleLength = 120;

    private static Trip CreateTripFor(
        Guid travelerId, StartWorkflowDto dto, AiPlanResponse ai, bool requiresApproval, DateTime now)
    {
        // Trip dates are calendar dates with no timezone: treat them as UTC midnight,
        // the same rule TripService.CreateTripAsync applies.
        var start = DateTime.SpecifyKind((dto.StartDate ?? now.AddDays(1)).Date, DateTimeKind.Utc);
        var days = Math.Max(dto.Days, 1);

        var title = dto.Goal.Trim();
        if (title.Length > MaxTripTitleLength)
            title = title[..(MaxTripTitleLength - 1)].TrimEnd() + "…";

        var status = requiresApproval
            ? TripStatus.Submitted
            : string.Equals(ai.OverallStatus, "PASS", StringComparison.OrdinalIgnoreCase)
                ? TripStatus.Confirmed
                : TripStatus.Draft;

        return new Trip
        {
            Id = Guid.NewGuid(),
            TravelerId = travelerId,
            Title = title,
            StartDate = start,
            EndDate = start.AddDays(days - 1),
            Budget = dto.Budget,
            Status = status,
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    private Task<AIWorkflow?> LoadFullAsync(Guid id) =>
        _db.AIWorkflows
            .Include(w => w.Traveler)
            .Include(w => w.Steps)
            .FirstOrDefaultAsync(w => w.Id == id);

    private static AiWorkflowResponseDto MapToDto(AIWorkflow w) => new()
    {
        Id = w.Id,
        TripId = w.TripId,
        TravelerId = w.TravelerId,
        TravelerName = w.Traveler?.FullName ?? string.Empty,
        Goal = w.Goal,
        Days = w.Days,
        Budget = w.Budget,
        Interests = w.Interests,
        FinalPlan = w.FinalPlan,
        OverallStatus = w.OverallStatus,
        RequiresApproval = w.RequiresApproval,
        ApprovalStatus = w.ApprovalStatus.ToString(),
        ApprovedByUserId = w.ApprovedByUserId,
        ApprovedAt = w.ApprovedAt,
        CreatedAt = w.CreatedAt,
        CompletedAt = w.CompletedAt,
        Steps = w.Steps
            .OrderBy(s => s.StartedAt)
            .Select(s => new AiWorkflowStepDto
            {
                Id = s.Id,
                AgentName = s.AgentName,
                Status = s.Status,
                StartedAt = s.StartedAt,
                CompletedAt = s.CompletedAt,
                OutputSummary = s.OutputSummary,
                ErrorMessage = s.ErrorMessage
            })
            .ToList()
    };
}
