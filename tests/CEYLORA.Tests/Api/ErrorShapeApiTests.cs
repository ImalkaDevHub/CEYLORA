using System.Net;
using System.Net.Http.Json;
using CEYLORA.Infrastructure.Services.Http;

namespace CEYLORA.Tests.Api;

/// <summary>Whatever goes wrong, the client gets the same JSON error and nothing internal.</summary>
public class ErrorShapeApiTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public ErrorShapeApiTests(ApiFactory factory) => _factory = factory;

    private static object PlanRequest => new { goal = "Beach trip", days = 3, budget = 100000, interests = new[] { "beach" } };

    [Fact]
    public async Task NoToken_Is401WithAMessage()
    {
        using var client = _factory.CreateClient();

        var response = await client.GetAsync("/api/trips/mine");

        await response.ExpectErrorAsync(401, "sign in");
    }

    [Fact]
    public async Task ABrokenToken_Is401()
    {
        using var client = _factory.ClientFor("not.a.jwt");

        var response = await client.GetAsync("/api/trips/mine");

        await response.ExpectErrorAsync(401);
    }

    [Fact]
    public async Task TheWrongRole_Is403WithAMessage()
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await traveler.PostAsJsonAsync("/api/destinations", new { name = "Ella", region = "Uva", category = "Nature" });

        await response.ExpectErrorAsync(403, "permission");
    }

    [Fact]
    public async Task AnOperatorCannotUseTravelerOnlyEndpoints()
    {
        using var op = await _factory.OperatorAsync();

        var response = await op.GetAsync("/api/trips/mine");

        await response.ExpectErrorAsync(403);
    }

    [Fact]
    public async Task AnUnknownRoute_Is404WithAMessage()
    {
        using var client = _factory.CreateClient();

        var response = await client.GetAsync("/api/does-not-exist");

        await response.ExpectErrorAsync(404, "not found");
    }

    [Fact]
    public async Task AControllerThatReturnsNotFound_GetsTheSameBody()
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await traveler.GetAsync($"/api/trips/{Guid.NewGuid()}");

        await response.ExpectErrorAsync(404);
    }

    [Fact]
    public async Task TheWrongHttpMethod_Is405WithAMessage()
    {
        using var client = _factory.CreateClient();

        var response = await client.DeleteAsync("/api/auth/login");

        await response.ExpectErrorAsync(405);
    }

    [Fact]
    public async Task AnotherTravelersWorkflow_Is403WithAMessage()
    {
        using var owner = await _factory.TravelerAsync();
        using var other = await _factory.TravelerAsync();
        var started = await owner.PostAsJsonAsync("/api/ai/workflows", PlanRequest);
        using var body = await started.ReadJsonAsync();
        var id = body.RootElement.GetProperty("id").GetString();

        var response = await other.GetAsync($"/api/ai/workflows/{id}");

        await response.ExpectErrorAsync(403);
    }

    [Fact]
    public async Task AnUnexpectedFailure_Is500_WithAGenericMessage_AndNoDetails()
    {
        _factory.Ai.Failure = new InvalidOperationException("db password is hunter2 at host secret.internal");
        using var traveler = await _factory.TravelerAsync();
        try
        {
            var response = await traveler.PostAsJsonAsync("/api/ai/workflows", PlanRequest);

            var error = await response.ExpectErrorAsync(500, "something went wrong");
            var raw = error.ToString();
            Assert.DoesNotContain("hunter2", raw);
            Assert.DoesNotContain("secret.internal", raw);
            Assert.DoesNotContain("InvalidOperation", raw);
        }
        finally { _factory.Ai.Failure = null; }
    }

    [Fact]
    public async Task TheAiServiceBeingDown_Is503_NotAnInternalError()
    {
        _factory.Ai.Failure = new AiPlanningClientException("ceylora-ai-service returned 500. Response body: <stack trace>");
        using var traveler = await _factory.TravelerAsync();
        try
        {
            var response = await traveler.PostAsJsonAsync("/api/ai/workflows", PlanRequest);

            var error = await response.ExpectErrorAsync(503, "AI planner is unavailable");
            Assert.DoesNotContain("stack trace", error.ToString());
        }
        finally { _factory.Ai.Failure = null; }
    }

    [Fact]
    public async Task ValidationErrors_ListEveryProblemUnderErrors_AndNeverUseTheStockProblemShape()
    {
        using var client = _factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/register", new { email = "x", password = "y", fullName = "" });

        var error = await response.ExpectErrorAsync(400); // only "message" and "errors" are allowed
        Assert.True(error.GetProperty("errors").EnumerateObject().Count() >= 3);
    }

    [Fact]
    public async Task Health_StillWorks()
    {
        using var client = _factory.CreateClient();

        var response = await client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
