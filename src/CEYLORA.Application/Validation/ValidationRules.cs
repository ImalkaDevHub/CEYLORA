using System.ComponentModel.DataAnnotations;

namespace CEYLORA.Application.Validation;

/// <summary>Shared pieces for request validation, so every DTO applies the same rules.</summary>
public static class ValidationRules
{
    /// <summary>How far ahead a trip or plan may start.</summary>
    public const int MaxYearsAhead = 5;

    /// <summary>Longest trip, in days.</summary>
    public const int MaxTripDays = 365;

    /// <summary>
    /// Today in UTC. Taken from the registered <see cref="TimeProvider"/> when there is one, so
    /// tests can pin the date; a trip may start up to a day before this to allow for time zones
    /// that are ahead of UTC (a traveler in Sri Lanka is already "tomorrow" while UTC is not).
    /// </summary>
    public static DateTime TodayUtc(ValidationContext context)
    {
        var clock = context.GetService(typeof(TimeProvider)) as TimeProvider ?? TimeProvider.System;
        return clock.GetUtcNow().UtcDateTime.Date;
    }

    /// <summary>Earliest allowed start date: yesterday (UTC), see <see cref="TodayUtc"/>.</summary>
    public static DateTime EarliestStart(ValidationContext context) => TodayUtc(context).AddDays(-1);

    public static DateTime LatestStart(ValidationContext context) => TodayUtc(context).AddYears(MaxYearsAhead);
}

/// <summary>An optional absolute http(s) URL. Anything else (javascript:, file:, ftp:) is refused.</summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter)]
public sealed class HttpUrlAttribute : ValidationAttribute
{
    public HttpUrlAttribute() : base("Enter a link that starts with http:// or https://.") { }

    public override bool IsValid(object? value)
    {
        if (value is null) return true;
        if (value is not string text) return false;
        if (string.IsNullOrWhiteSpace(text)) return true; // optional

        return Uri.TryCreate(text.Trim(), UriKind.Absolute, out var uri)
               && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps)
               && !string.IsNullOrEmpty(uri.Host);
    }
}
