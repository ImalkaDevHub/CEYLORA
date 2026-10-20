using CEYLORA.Application.DTOs.AiPlanning;
using CEYLORA.Application.DTOs.AiWorkflows;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using CEYLORA.Infrastructure.Services;
using CEYLORA.Infrastructure.Services.Http;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Tests;

/// <summary>
/// Covers how an AI workflow drives the traveler's Trip: created at start (status from the
/// approval gate), then confirmed or cancelled by the operator's decision. Uses the EF
/// in-memory provider and a fake AI client, so it needs no database and no AI service.
/// </summary>
public class AiWorkflowServiceTests : IDisposable
{
    private static readonly Guid TravelerRoleId = new("c023fa33-20bf-4166-b56c-aeb11838c85c");

    private readonly ApplicationDbContext _db;
    private readonly FakeAiClient _ai = new();
    private readonly AiWorkflowService _service;
    private readonly User _traveler;
    private readonly User _operator;

    public AiWorkflowServiceTests()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        _db = new ApplicationDbContext(options);
        _db.Database.EnsureCreated(); // applies the seeded roles

        _traveler = AddUser("sam@example.com", "Sam Traveler");
        _operator = AddUser("olu@example.com", "Olu Operator");
        _service = new AiWorkflowService(_db, _ai);
    }

    public void Dispose() => _db.Dispose();

    private User AddUser(string email, string name)
    {
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            FullName = name,
            PasswordHash = "x",
            RoleId = TravelerRoleId
        };
        _db.Users.Add(user);
        _db.SaveChanges();
        return user;
    }

    private static StartWorkflowDto Request(
        string goal = "Relaxed south-coast beach trip", int days = 5,
        decimal budget = 120000m, DateTime? startDate = null) => new()
    {
        Goal = goal,
        Days = days,
        Budget = budget,
        Interests = new List<string> { "beach" },
        StartDate = startDate
    };

    private Task<Trip> TripOf(AiWorkflowResponseDto workflow) =>
        _db.Trips.SingleAsync(t => t.Id == workflow.TripId);

    // ---- Trip creation at start ---------------------------------------------------------

    [Fact]
    public async Task Start_WhenApprovalRequired_CreatesSubmittedTripLinkedToWorkflow()
    {
        _ai.Next = Ai(status: "PASS", requiresApproval: true);

        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request());

        Assert.NotNull(workflow.TripId);
        Assert.Equal("AwaitingApproval", workflow.ApprovalStatus);
        var trip = await TripOf(workflow);
        Assert.Equal(TripStatus.Submitted, trip.Status);
        Assert.Equal(_traveler.Id, trip.TravelerId);
        Assert.Equal("Relaxed south-coast beach trip", trip.Title);
        Assert.Equal(120000m, trip.Budget);
    }

    [Fact]
    public async Task Start_WhenValidationPassesWithoutGate_CreatesConfirmedTrip()
    {
        _ai.Next = Ai(status: "PASS", requiresApproval: false);

        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request());

        Assert.Equal("NotRequired", workflow.ApprovalStatus);
        Assert.Equal(TripStatus.Confirmed, (await TripOf(workflow)).Status);
    }

    [Fact]
    public async Task Start_WhenValidationFlagsProblemsWithoutGate_CreatesDraftTrip()
    {
        _ai.Next = Ai(status: "NEEDS_REVISION", requiresApproval: false);

        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request());

        Assert.Equal(TripStatus.Draft, (await TripOf(workflow)).Status);
    }

    [Fact]
    public async Task Start_WithoutStartDate_BeginsTomorrowAndSpansTheRequestedDays()
    {
        _ai.Next = Ai();

        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request(days: 5));

        var trip = await TripOf(workflow);
        var tomorrow = DateTime.UtcNow.Date.AddDays(1);
        Assert.Equal(tomorrow, trip.StartDate);
        Assert.Equal(DateTimeKind.Utc, trip.StartDate.Kind);
        Assert.Equal(tomorrow.AddDays(4), trip.EndDate); // 5 days inclusive
    }

    [Fact]
    public async Task Start_WithStartDate_UsesItAsAUtcCalendarDate()
    {
        _ai.Next = Ai();
        var picked = new DateTime(2026, 12, 20, 15, 30, 0, DateTimeKind.Unspecified);

        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request(days: 3, startDate: picked));

        var trip = await TripOf(workflow);
        Assert.Equal(new DateTime(2026, 12, 20, 0, 0, 0, DateTimeKind.Utc), trip.StartDate);
        Assert.Equal(new DateTime(2026, 12, 22, 0, 0, 0, DateTimeKind.Utc), trip.EndDate);
        Assert.Equal(DateTimeKind.Utc, trip.EndDate.Kind);
    }

    [Fact]
    public async Task Start_WithOneDay_StartsAndEndsOnTheSameDay()
    {
        _ai.Next = Ai();

        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request(days: 1));

        var trip = await TripOf(workflow);
        Assert.Equal(trip.StartDate, trip.EndDate);
    }

    [Fact]
    public async Task Start_WithZeroDays_NeverProducesAnEndBeforeStart()
    {
        _ai.Next = Ai();

        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request(days: 0));

        var trip = await TripOf(workflow);
        Assert.True(trip.EndDate >= trip.StartDate);
    }

    [Fact]
    public async Task Start_WithVeryLongGoal_TruncatesTheTripTitle()
    {
        _ai.Next = Ai();
        var goal = new string('a', 300);

        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request(goal: goal));

        var trip = await TripOf(workflow);
        Assert.Equal(120, trip.Title.Length);
        Assert.EndsWith("…", trip.Title);
        Assert.Equal(goal, workflow.Goal); // the workflow keeps the full goal
    }

    [Fact]
    public async Task Start_WhenTheAiServiceFails_PersistsNothing()
    {
        _ai.Failure = new AiPlanningClientException("ceylora-ai-service returned 500");

        await Assert.ThrowsAsync<AiPlanningClientException>(
            () => _service.StartWorkflowAsync(_traveler.Id, Request()));

        Assert.Empty(_db.Trips);
        Assert.Empty(_db.AIWorkflows);
    }

    // ---- Operator decisions -------------------------------------------------------------

    [Fact]
    public async Task Approve_ConfirmsTheTrip()
    {
        var workflow = await StartAwaitingApproval();

        var result = await _service.ApproveAsync(workflow.Id, _operator.Id);

        Assert.Equal("Approved", result!.ApprovalStatus);
        Assert.Equal(_operator.Id, result.ApprovedByUserId);
        Assert.Equal(TripStatus.Confirmed, (await TripOf(workflow)).Status);
    }

    [Fact]
    public async Task Reject_CancelsTheTrip()
    {
        var workflow = await StartAwaitingApproval();

        var result = await _service.RejectAsync(workflow.Id, _operator.Id);

        Assert.Equal("Rejected", result!.ApprovalStatus);
        Assert.Equal(TripStatus.Cancelled, (await TripOf(workflow)).Status);
    }

    [Fact]
    public async Task Revise_CancelsTheTrip()
    {
        var workflow = await StartAwaitingApproval();

        var result = await _service.ReviseAsync(workflow.Id, _operator.Id);

        Assert.Equal("RevisionRequested", result!.ApprovalStatus);
        Assert.Equal(TripStatus.Cancelled, (await TripOf(workflow)).Status);
    }

    [Fact]
    public async Task Decision_CanOnlyBeMadeOnce_AndTheTripKeepsItsFirstOutcome()
    {
        var workflow = await StartAwaitingApproval();
        await _service.ApproveAsync(workflow.Id, _operator.Id);

        var second = await _service.RejectAsync(workflow.Id, _operator.Id);

        Assert.Null(second);
        Assert.Equal(TripStatus.Confirmed, (await TripOf(workflow)).Status);
    }

    [Fact]
    public async Task Decision_OnAWorkflowThatNeverNeededApproval_ReturnsNullAndLeavesTheTrip()
    {
        _ai.Next = Ai(status: "PASS", requiresApproval: false);
        var workflow = await _service.StartWorkflowAsync(_traveler.Id, Request());

        var result = await _service.RejectAsync(workflow.Id, _operator.Id);

        Assert.Null(result);
        Assert.Equal(TripStatus.Confirmed, (await TripOf(workflow)).Status);
    }

    [Fact]
    public async Task Decision_OnAnUnknownWorkflow_ReturnsNull()
    {
        Assert.Null(await _service.ApproveAsync(Guid.NewGuid(), _operator.Id));
    }

    [Fact]
    public async Task Decision_WhenTheTripWasDeleted_StillRecordsTheDecision()
    {
        var workflow = await StartAwaitingApproval();
        _db.Trips.Remove(await TripOf(workflow));
        await _db.SaveChangesAsync();

        var result = await _service.ApproveAsync(workflow.Id, _operator.Id);

        Assert.Equal("Approved", result!.ApprovalStatus);
    }

    // ---- Queries ------------------------------------------------------------------------

    [Fact]
    public async Task GetMine_ReturnsOnlyTheCallersWorkflows_NewestFirst()
    {
        var other = AddUser("kim@example.com", "Kim Other");
        _ai.Next = Ai();
        var first = await _service.StartWorkflowAsync(_traveler.Id, Request(goal: "first"));
        await Task.Delay(5);
        var second = await _service.StartWorkflowAsync(_traveler.Id, Request(goal: "second"));
        await _service.StartWorkflowAsync(other.Id, Request(goal: "not mine"));

        var mine = await _service.GetMyWorkflowsAsync(_traveler.Id);

        Assert.Equal(new[] { second.Id, first.Id }, mine.Select(w => w.Id).ToArray());
        Assert.All(mine, w => Assert.Equal(_traveler.Id, w.TravelerId));
    }

    [Fact]
    public async Task GetMine_WithNoWorkflows_ReturnsAnEmptyList()
    {
        Assert.Empty(await _service.GetMyWorkflowsAsync(_traveler.Id));
    }

    [Fact]
    public async Task Pending_ListsOnlyWorkflowsAwaitingApproval()
    {
        _ai.Next = Ai(requiresApproval: true);
        var waiting = await _service.StartWorkflowAsync(_traveler.Id, Request(goal: "waiting"));
        _ai.Next = Ai(requiresApproval: false);
        await _service.StartWorkflowAsync(_traveler.Id, Request(goal: "auto"));

        var pending = await _service.GetPendingApprovalsAsync();

        Assert.Equal(waiting.Id, Assert.Single(pending).Id);
    }

    // ---- Helpers ------------------------------------------------------------------------

    private async Task<AiWorkflowResponseDto> StartAwaitingApproval()
    {
        _ai.Next = Ai(status: "PASS", requiresApproval: true);
        return await _service.StartWorkflowAsync(_traveler.Id, Request());
    }

    private static AiPlanResponse Ai(string status = "PASS", bool requiresApproval = false) => new()
    {
        Plan = "Day 1: Galle Fort",
        GeneratedBy = "planner_agent (stub)",
        OverallStatus = status,
        RequiresApproval = requiresApproval,
        Steps = new List<AiPlanStepDto>
        {
            new()
            {
                Agent = "planner",
                Status = "completed",
                StartedAt = DateTimeOffset.UtcNow,
                CompletedAt = DateTimeOffset.UtcNow,
                OutputSummary = "drafted"
            }
        }
    };

    private sealed class FakeAiClient : IAiPlanningClient
    {
        public AiPlanResponse Next { get; set; } = Ai();
        public Exception? Failure { get; set; }

        public Task<AiPlanResponse> RequestPlanAsync(AiPlanRequest request, CancellationToken ct = default) =>
            Failure is null ? Task.FromResult(Next) : Task.FromException<AiPlanResponse>(Failure);
    }
}
