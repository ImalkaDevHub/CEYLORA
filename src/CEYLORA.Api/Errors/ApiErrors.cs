using System.Text.Json;
using Microsoft.AspNetCore.Http.Extensions;
using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace CEYLORA.Api.Errors;

/// <summary>
/// The one shape every error response has: <c>{ "message": "..." }</c>. Validation failures add
/// <c>"errors": { "field": ["..."] }</c>. Clients show <c>message</c>; forms can use <c>errors</c>.
/// </summary>
public static class ApiErrors
{
    public const string GenericServerError = "Something went wrong on the server.";

    /// <summary>Message for a response that came back with only a status code and no body.</summary>
    public static string MessageFor(int statusCode) => statusCode switch
    {
        StatusCodes.Status400BadRequest => "The request is not valid.",
        StatusCodes.Status401Unauthorized => "Authentication required. Please sign in.",
        StatusCodes.Status403Forbidden => "You don't have permission to do that.",
        StatusCodes.Status404NotFound => "Not found.",
        StatusCodes.Status405MethodNotAllowed => "That method is not allowed here.",
        StatusCodes.Status409Conflict => "That conflicts with the current state.",
        StatusCodes.Status415UnsupportedMediaType => "Send the request as application/json.",
        StatusCodes.Status429TooManyRequests => "Too many requests. Please wait and try again.",
        >= 500 => GenericServerError,
        _ => "The request could not be completed."
    };

    /// <summary>
    /// Builds the 400 body for a model that failed validation (or could not be read at all).
    /// The first problem becomes the top-level message.
    /// </summary>
    public static object ValidationBody(ModelStateDictionary modelState)
    {
        var errors = new Dictionary<string, List<string>>();
        string? first = null;

        // When the JSON itself could not be read (a bad date, a word where a number belongs),
        // MVC also reports the whole model as "required", which only hides the real cause.
        var readerFailed = modelState.Any(e => e.Value?.Errors.Count > 0 && IsReaderKey(e.Key));

        foreach (var (key, entry) in modelState)
        {
            if (entry.Errors.Count == 0) continue;
            var field = FieldName(key);

            foreach (var error in entry.Errors)
            {
                if (readerFailed && !IsReaderKey(key) && IsWholeModelRequired(key, error)) continue;

                var message = ReadableMessage(error, key, field);
                first ??= message;

                if (!errors.TryGetValue(field, out var list)) errors[field] = list = new List<string>();
                if (!list.Contains(message)) list.Add(message);
            }
        }

        return new { message = first ?? MessageFor(StatusCodes.Status400BadRequest), errors };
    }

    private static bool IsReaderKey(string key) => key.Length == 0 || key[0] == '$';

    // "The dto field is required." for the action parameter itself (no dots or brackets in its key).
    private static bool IsWholeModelRequired(string key, ModelError error) =>
        key.Length > 0 && !key.Contains('.') && !key.Contains('[')
        && error.ErrorMessage.StartsWith("The ", StringComparison.Ordinal)
        && error.ErrorMessage.EndsWith(" field is required.", StringComparison.Ordinal);

    /// <summary>"Items[0].CheckIn" / "$.category" / "Category" -> "items[0].checkIn" / "category" / "category".</summary>
    internal static string FieldName(string key)
    {
        if (string.IsNullOrEmpty(key) || key == "$") return "request";
        if (key.StartsWith("$.", StringComparison.Ordinal)) key = key[2..];

        var parts = key.Split('.');
        for (var i = 0; i < parts.Length; i++)
        {
            if (parts[i].Length > 0) parts[i] = char.ToLowerInvariant(parts[i][0]) + parts[i][1..];
        }
        return string.Join('.', parts);
    }

    private static string ReadableMessage(ModelError error, string key, string field)
    {
        // Errors keyed "" or "$..." come from reading the JSON itself: a broken body, or a value
        // of the wrong type (an unknown enum name, text where a number belongs). Their text is
        // the parser's ("'n' is an invalid start of a property name..."), so say it plainly.
        var fromReader = key.Length == 0 || key[0] == '$' || error.Exception is not null;
        var fromBinder = error.ErrorMessage.Contains("could not be converted", StringComparison.Ordinal)
                         || error.ErrorMessage.Contains("is not valid", StringComparison.Ordinal);

        if (fromReader || fromBinder)
        {
            if (field != "request") return $"Invalid value for '{field}'.";
            return error.ErrorMessage.Contains("non-empty request body", StringComparison.OrdinalIgnoreCase)
                ? "The request body is empty."
                : "The request body is not valid JSON.";
        }

        return string.IsNullOrWhiteSpace(error.ErrorMessage)
            ? $"Invalid value for '{field}'."
            : error.ErrorMessage;
    }
}
