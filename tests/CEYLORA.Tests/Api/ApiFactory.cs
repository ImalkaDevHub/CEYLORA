using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using CEYLORA.Application.DTOs.AiPlanning;
using CEYLORA.Application.Interfaces;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

namespace CEYLORA.Tests.Api;

/// <summary>The AI service, replaced: answers with a canned plan, or fails on demand.</summary>
public sealed class FakeAiPlanningClient : IAiPlanningClient
{
    public Exception? Failure { get; set; }
    public List<AiPlanRequest> Requests { get; } = new();
    public string OverallStatus { get; set; } = "PASS";
    public bool RequiresApproval { get; set; }

    public Task<AiPlanResponse> RequestPlanAsync(AiPlanRequest request, CancellationToken ct = default)
    {
        Requests.Add(request);
        if (Failure is not null) return Task.FromException<AiPlanResponse>(Failure);

        return Task.FromResult(new AiPlanResponse
        {
            Goal = request.Goal,
            Days = request.Days,
            Budget = request.Budget,
            Interests = request.Interests,
            Plan = "Day 1: Galle Fort",
            GeneratedBy = "fake",
            OverallStatus = OverallStatus,
            RequiresApproval = RequiresApproval,
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
        });
    }
}

/// <summary>
/// The real API running in memory: real routing, JSON, JWT authentication, role checks and
/// validation. Only the database (in-memory) and the AI service (fake) are swapped out.
/// </summary>
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    public const string JwtKey = "test-signing-key-test-signing-key-0123456789";
    public const string StrongPassword = "Passw0rd-Test";

    private readonly string _databaseName = Guid.NewGuid().ToString();

    public FakeAiPlanningClient Ai { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // A name that is not "Development", so the developer exception page is not in play.
        builder.UseEnvironment("Testing");

        // UseSetting (not ConfigureAppConfiguration): Program.cs reads these while it builds.
        builder.UseSetting("Jwt:Key", JwtKey);
        builder.UseSetting("Jwt:Issuer", "ceylora-tests");
        builder.UseSetting("Jwt:Audience", "ceylora-test-clients");
        builder.UseSetting("ConnectionStrings:DefaultConnection", "Host=not-used");

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<ApplicationDbContext>>();
            services.RemoveAll(typeof(IDbContextOptionsConfiguration<ApplicationDbContext>));
            services.AddDbContext<ApplicationDbContext>(o => o.UseInMemoryDatabase(_databaseName));

            services.RemoveAll<IAiPlanningClient>();
            services.AddSingleton<IAiPlanningClient>(Ai);
        });
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        var host = base.CreateHost(builder);
        using var scope = host.Services.CreateScope();
        // Creates the schema and the seeded roles (Traveler, Operator, Admin).
        scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Database.EnsureCreated();
        return host;
    }

    public static string UniqueEmail(string prefix = "user") => $"{prefix}-{Guid.NewGuid():N}@example.com";

    /// <summary>Registers an account through the API and returns its token.</summary>
    public async Task<string> RegisterAsync(string role = "Traveler", string? email = null)
    {
        using var client = CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/register", new
        {
            email = email ?? UniqueEmail(role.ToLowerInvariant()),
            password = StrongPassword,
            fullName = $"Test {role}",
            roleName = role
        });
        response.EnsureSuccessStatusCode();
        using var body = await response.ReadJsonAsync();
        return body.RootElement.GetProperty("token").GetString()!;
    }

    public HttpClient ClientFor(string? token)
    {
        var client = CreateClient();
        if (token is not null)
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    public async Task<HttpClient> TravelerAsync() => ClientFor(await RegisterAsync("Traveler"));
    public async Task<HttpClient> OperatorAsync() => ClientFor(await RegisterAsync("Operator"));
}

public static class HttpTestExtensions
{
    public static async Task<JsonDocument> ReadJsonAsync(this HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync());

    /// <summary>
    /// Every error from the API must look the same: JSON with a human "message", optionally an
    /// "errors" map, and nothing else (no stack trace, no ProblemDetails "type"/"traceId").
    /// </summary>
    public static async Task<JsonElement> ExpectErrorAsync(this HttpResponseMessage response, int status, string? messageContains = null)
    {
        Assert.Equal(status, (int)response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);

        var raw = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(raw);
        var root = doc.RootElement.Clone();

        Assert.Equal(JsonValueKind.Object, root.ValueKind);
        var message = root.GetProperty("message").GetString();
        Assert.False(string.IsNullOrWhiteSpace(message), "error message is empty");
        foreach (var property in root.EnumerateObject())
            Assert.Contains(property.Name, new[] { "message", "errors" });

        // Nothing internal may leak.
        Assert.DoesNotContain("   at ", raw);
        Assert.DoesNotContain("Exception", raw);

        if (messageContains is not null) Assert.Contains(messageContains, message, StringComparison.OrdinalIgnoreCase);
        return root;
    }

    /// <summary>The messages listed for one field of a validation error.</summary>
    public static string[] FieldErrors(this JsonElement error, string field) =>
        error.GetProperty("errors").GetProperty(field).EnumerateArray().Select(e => e.GetString()!).ToArray();
}
