using CEYLORA.Infrastructure.Services.Http;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Api.Errors;

/// <summary>
/// Last line of defence: anything a controller or service did not handle becomes the same JSON
/// error as everything else. The exception (with its stack trace) goes to the log only, never to
/// the client.
/// </summary>
public sealed class ApiExceptionHandler : IExceptionHandler
{
    private readonly ILogger<ApiExceptionHandler> _logger;

    public ApiExceptionHandler(ILogger<ApiExceptionHandler> logger) => _logger = logger;

    public async ValueTask<bool> TryHandleAsync(HttpContext context, Exception exception, CancellationToken cancellationToken)
    {
        // The caller hung up; nobody is left to read an answer.
        if (exception is OperationCanceledException && context.RequestAborted.IsCancellationRequested)
        {
            context.Response.StatusCode = 499;
            return true;
        }

        var (status, message) = exception switch
        {
            // The AI service is down, slow or answered with garbage: the planner is unavailable, not us.
            AiPlanningClientException =>
                (StatusCodes.Status503ServiceUnavailable, "The AI planner is unavailable right now. Please try again in a moment."),

            // Someone else changed the same row between our read and write.
            DbUpdateConcurrencyException =>
                (StatusCodes.Status409Conflict, "This was changed by someone else. Reload and try again."),

            BadHttpRequestException bad =>
                (bad.StatusCode, "The request could not be read."),

            _ => (StatusCodes.Status500InternalServerError, ApiErrors.GenericServerError)
        };

        if (status >= 500)
            _logger.LogError(exception, "Unhandled exception on {Method} {Path}", context.Request.Method, context.Request.Path);
        else
            _logger.LogWarning(exception, "Request failed with {Status} on {Method} {Path}", status, context.Request.Method, context.Request.Path);

        context.Response.StatusCode = status;
        await context.Response.WriteAsJsonAsync(new { message }, cancellationToken);
        return true;
    }
}
