using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using CEYLORA.Infrastructure.Services.Http;

namespace CEYLORA.Tests.Api;

public class AiWorkflowApiTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public AiWorkflowApiTests(ApiFactory factory)
    {
        _factory = factory;
        // The AI fake is shared by this class; start every test from "healthy, no approval".
        _factory.Ai.Failure = null;
        _factory.Ai.OverallStatus = "PASS";
        _factory.Ai.RequiresApproval = false;
    }

    private static string Day(int offset) => DateTime.UtcNow.Date.AddDays(offset).ToString("yyyy-MM-dd");

    private static object Plan(string goal = "Relaxed beach trip", int days = 5, object? budget = null,
        string[]? interests = null, string? startDate = null) =>
        new { goal, days, budget = budget ?? 120000, interests = interests ?? new[] { "beach" }, startDate };

    private Task<HttpResponseMessage> Start(HttpClient client, object body) =>
        client.PostAsJsonAsync("/api/ai/workflows", body);

    // ---- Start: success ----------------------------------------------------------------------

    [Fact]
    public async Task Start_ReturnsThePlan_AndCreatesTheTrip()
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await Start(traveler, Plan(startDate: Day(20)));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        using var body = await response.ReadJsonAsync();
        var root = body.RootElement;
        Assert.Equal("NotRequired", root.GetProperty("approvalStatus").GetString());
        Assert.Equal("Day 1: Galle Fort", root.GetProperty("finalPlan").GetString());
        Assert.NotEqual(JsonValueKind.Null, root.GetProperty("tripId").ValueKind);

        var trips = await (await traveler.GetAsync("/api/trips/mine")).ReadJsonAsync();
        var trip = Assert.Single(trips.RootElement.EnumerateArray());
        Assert.Equal("Confirmed", trip.GetProperty("status").GetString());
        Assert.StartsWith(Day(20), trip.GetProperty("startDate").GetString());
        Assert.StartsWith(Day(24), trip.GetProperty("endDate").GetString()); // 5 days
    }

    [Fact]
    public async Task Start_PassesTheRequestOnToTheAiService()
    {
        using var traveler = await _factory.TravelerAsync();
        _factory.Ai.Requests.Clear();

        await Start(traveler, Plan(goal: "Wildlife and temples", days: 7, budget: 250000, interests: new[] { "wildlife", "culture" }));

        var sent = Assert.Single(_factory.Ai.Requests);
        Assert.Equal("Wildlife and temples", sent.Goal);
        Assert.Equal(7, sent.Days);
        Assert.Equal(250000m, sent.Budget);
        Assert.Equal(new[] { "wildlife", "culture" }, sent.Interests);
    }

    [Fact]
    public async Task Start_AcceptsTheBoundaries()
    {
        using var traveler = await _factory.TravelerAsync();
        var tenInterests = Enumerable.Range(0, 10).Select(i => new string((char)('a' + i), 30)).ToArray();

        Assert.Equal(HttpStatusCode.Created, (await Start(traveler, Plan(goal: "abc", days: 1, budget: 0))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Start(traveler, Plan(days: 60, interests: tenInterests))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Start(traveler, Plan(goal: new string('g', 1000)))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Start(traveler, Plan(interests: Array.Empty<string>()))).StatusCode);
    }

    // ---- Start: validation (and the AI service is never bothered) ----------------------------

    [Theory]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData("ab")]
    public async Task Start_NeedsARealGoal(string goal)
    {
        using var traveler = await _factory.TravelerAsync();
        _factory.Ai.Requests.Clear();

        var error = await (await Start(traveler, Plan(goal: goal))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("goal"));
        Assert.Empty(_factory.Ai.Requests);
    }

    [Fact]
    public async Task Start_RefusesAGoalOver1000Characters()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Start(traveler, Plan(goal: new string('g', 1001)))).ExpectErrorAsync(400);

        Assert.Contains("3 to 1000", error.FieldErrors("goal")[0]);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(61)]
    public async Task Start_RefusesADayCountOutsideOneToSixty(int days)
    {
        using var traveler = await _factory.TravelerAsync();
        _factory.Ai.Requests.Clear();

        var error = await (await Start(traveler, Plan(days: days))).ExpectErrorAsync(400, "between 1 and 60");

        Assert.NotEmpty(error.FieldErrors("days"));
        Assert.Empty(_factory.Ai.Requests);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(1000000001)]
    public async Task Start_RefusesABudgetOutOfRange(long budget)
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Start(traveler, Plan(budget: budget))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("budget"));
    }

    [Fact]
    public async Task Start_RefusesMoreThanTenInterests()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Start(traveler, Plan(interests: Enumerable.Range(0, 11).Select(i => $"i{i}").ToArray()))).ExpectErrorAsync(400, "at most 10");

        Assert.NotEmpty(error.FieldErrors("interests"));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Start_RefusesABlankInterest(string interest)
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Start(traveler, Plan(interests: new[] { "beach", interest }))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("interests"));
    }

    [Fact]
    public async Task Start_RefusesAnInterestOver30Characters()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Start(traveler, Plan(interests: new[] { new string('x', 31) }))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("interests"));
    }

    [Fact]
    public async Task Start_RefusesAStartDateInThePastOrTooFarAhead()
    {
        using var traveler = await _factory.TravelerAsync();

        var past = await (await Start(traveler, Plan(startDate: Day(-3)))).ExpectErrorAsync(400, "in the past");
        var far = await (await Start(traveler, Plan(startDate: DateTime.UtcNow.Date.AddYears(6).ToString("yyyy-MM-dd")))).ExpectErrorAsync(400, "too far ahead");

        Assert.NotEmpty(past.FieldErrors("startDate"));
        Assert.NotEmpty(far.FieldErrors("startDate"));
    }

    [Fact]
    public async Task Start_ANullStartDateMeansTomorrow()
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await Start(traveler, Plan());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var trips = await (await traveler.GetAsync("/api/trips/mine")).ReadJsonAsync();
        Assert.StartsWith(Day(1), trips.RootElement[0].GetProperty("startDate").GetString());
    }

    [Fact]
    public async Task Start_NeedsATraveler()
    {
        using var op = await _factory.OperatorAsync();
        using var anonymous = _factory.CreateClient();

        await (await Start(op, Plan())).ExpectErrorAsync(403);
        await (await Start(anonymous, Plan())).ExpectErrorAsync(401);
    }

    // ---- Start: the AI service misbehaves ----------------------------------------------------

    [Fact]
    public async Task Start_WhenTheAiServiceIsDown_Is503_AndLeavesNothingBehind()
    {
        using var traveler = await _factory.TravelerAsync();
        _factory.Ai.Failure = new AiPlanningClientException("down");

        await (await Start(traveler, Plan())).ExpectErrorAsync(503);

        var trips = await (await traveler.GetAsync("/api/trips/mine")).ReadJsonAsync();
        var plans = await (await traveler.GetAsync("/api/ai/workflows/mine")).ReadJsonAsync();
        Assert.Empty(trips.RootElement.EnumerateArray());
        Assert.Empty(plans.RootElement.EnumerateArray());
    }

    // ---- The approval gate over HTTP ---------------------------------------------------------

    private async Task<(HttpClient Traveler, string WorkflowId, string TripId)> StartNeedingApproval()
    {
        _factory.Ai.RequiresApproval = true;
        var traveler = await _factory.TravelerAsync();
        using var body = await (await Start(traveler, Plan())).ReadJsonAsync();
        return (traveler, body.RootElement.GetProperty("id").GetString()!, body.RootElement.GetProperty("tripId").GetString()!);
    }

    private static async Task<string> TripStatus(HttpClient traveler, string tripId)
    {
        using var trip = await (await traveler.GetAsync($"/api/trips/{tripId}")).ReadJsonAsync();
        return trip.RootElement.GetProperty("status").GetString()!;
    }

    [Fact]
    public async Task APlanNeedingApproval_WaitsInTheQueue_WithASubmittedTrip()
    {
        var (traveler, workflowId, tripId) = await StartNeedingApproval();
        using var op = await _factory.OperatorAsync();

        using var pending = await (await op.GetAsync("/api/ai/workflows/pending")).ReadJsonAsync();

        Assert.Contains(pending.RootElement.EnumerateArray(), w => w.GetProperty("id").GetString() == workflowId);
        Assert.Equal("Submitted", await TripStatus(traveler, tripId));
    }

    [Fact]
    public async Task TheOperatorApproving_ConfirmsTheTravelersTrip()
    {
        var (traveler, workflowId, tripId) = await StartNeedingApproval();
        using var op = await _factory.OperatorAsync();

        var response = await op.PostAsync($"/api/ai/workflows/{workflowId}/approve", null);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await response.ReadJsonAsync();
        Assert.Equal("Approved", body.RootElement.GetProperty("approvalStatus").GetString());
        Assert.Equal("Confirmed", await TripStatus(traveler, tripId));
    }

    [Theory]
    [InlineData("reject", "Rejected")]
    [InlineData("revise", "RevisionRequested")]
    public async Task TheOperatorRejectingOrRequestingChanges_CancelsTheTrip(string action, string expectedStatus)
    {
        var (traveler, workflowId, tripId) = await StartNeedingApproval();
        using var op = await _factory.OperatorAsync();

        var response = await op.PostAsync($"/api/ai/workflows/{workflowId}/{action}", null);

        using var body = await response.ReadJsonAsync();
        Assert.Equal(expectedStatus, body.RootElement.GetProperty("approvalStatus").GetString());
        Assert.Equal("Cancelled", await TripStatus(traveler, tripId));
    }

    [Fact]
    public async Task ADecisionCanOnlyBeMadeOnce()
    {
        var (_, workflowId, _) = await StartNeedingApproval();
        using var op = await _factory.OperatorAsync();
        await op.PostAsync($"/api/ai/workflows/{workflowId}/approve", null);

        var second = await op.PostAsync($"/api/ai/workflows/{workflowId}/reject", null);

        await second.ExpectErrorAsync(400, "not awaiting approval");
    }

    [Fact]
    public async Task ATravelerCannotApproveTheirOwnPlan()
    {
        var (traveler, workflowId, tripId) = await StartNeedingApproval();

        var response = await traveler.PostAsync($"/api/ai/workflows/{workflowId}/approve", null);

        await response.ExpectErrorAsync(403);
        Assert.Equal("Submitted", await TripStatus(traveler, tripId));
    }

    [Fact]
    public async Task Get_IsForTheOwnerOrStaff()
    {
        var (traveler, workflowId, _) = await StartNeedingApproval();
        using var other = await _factory.TravelerAsync();
        using var op = await _factory.OperatorAsync();

        Assert.Equal(HttpStatusCode.OK, (await traveler.GetAsync($"/api/ai/workflows/{workflowId}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await op.GetAsync($"/api/ai/workflows/{workflowId}")).StatusCode);
        await (await other.GetAsync($"/api/ai/workflows/{workflowId}")).ExpectErrorAsync(403);
        await (await traveler.GetAsync($"/api/ai/workflows/{Guid.NewGuid()}")).ExpectErrorAsync(404);
    }

    [Fact]
    public async Task Mine_ListsOnlyTheCallersPlans()
    {
        using var sam = await _factory.TravelerAsync();
        using var kim = await _factory.TravelerAsync();
        await Start(sam, Plan(goal: "Sam's plan"));
        await Start(kim, Plan(goal: "Kim's plan"));

        using var mine = await (await sam.GetAsync("/api/ai/workflows/mine")).ReadJsonAsync();

        var goals = mine.RootElement.EnumerateArray().Select(w => w.GetProperty("goal").GetString());
        Assert.Equal(new[] { "Sam's plan" }, goals);
    }
}
