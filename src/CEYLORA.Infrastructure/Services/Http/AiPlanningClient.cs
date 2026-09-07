using System.Net.Http.Json;
using System.Text.Json;
using CEYLORA.Application.DTOs.AiPlanning;
using CEYLORA.Application.Interfaces;

namespace CEYLORA.Infrastructure.Services.Http;

/// <summary>
/// HTTP client for ceylora-ai-service. The <see cref="HttpClient"/> is supplied
/// by DI (AddHttpClient&lt;IAiPlanningClient, AiPlanningClient&gt;) — never
/// constructed here — so its BaseAddress, timeout and handler lifetime are
/// managed centrally in Program.cs.
/// </summary>
public class AiPlanningClient : IAiPlanningClient
{
    private const string PlanPath = "/api/workflow/plan";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _http;

    public AiPlanningClient(HttpClient http) => _http = http;

    public async Task<AiPlanResponse> RequestPlanAsync(AiPlanRequest request, CancellationToken ct = default)
    {
        using var httpResponse = await _http.PostAsJsonAsync(PlanPath, request, JsonOptions, ct);

        var body = await httpResponse.Content.ReadAsStringAsync(ct);

        if (!httpResponse.IsSuccessStatusCode)
        {
            throw new AiPlanningClientException(
                $"ceylora-ai-service returned {(int)httpResponse.StatusCode} {httpResponse.ReasonPhrase} " +
                $"for POST {PlanPath}. Response body: {body}");
        }

        AiPlanResponse? result;
        try
        {
            result = JsonSerializer.Deserialize<AiPlanResponse>(body, JsonOptions);
        }
        catch (JsonException ex)
        {
            throw new AiPlanningClientException(
                $"ceylora-ai-service returned a success status but the body could not be parsed as " +
                $"{nameof(AiPlanResponse)}. Response body: {body}", ex);
        }

        if (result is null)
        {
            throw new AiPlanningClientException(
                $"ceylora-ai-service returned a success status but the body deserialized to null. " +
                $"Response body: {body}");
        }

        return result;
    }
}

/// <summary>Raised when the AI service call fails or returns something unusable.</summary>
public class AiPlanningClientException : Exception
{
    public AiPlanningClientException(string message) : base(message) { }

    public AiPlanningClientException(string message, Exception innerException)
        : base(message, innerException) { }
}
