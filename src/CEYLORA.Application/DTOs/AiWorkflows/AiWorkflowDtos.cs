using System.ComponentModel.DataAnnotations;
using CEYLORA.Application.Validation;

namespace CEYLORA.Application.DTOs.AiWorkflows;

/// <summary>Body for POST /api/ai/workflows — what the traveler wants planned.</summary>
public class StartWorkflowDto : IValidatableObject
{
    public const int MaxInterests = 10;
    public const int MaxInterestLength = 30;

    [Required(ErrorMessage = "Describe the trip you want.")]
    [StringLength(1000, MinimumLength = 3, ErrorMessage = "Trip goal must be 3 to 1000 characters.")]
    public string Goal { get; set; } = string.Empty;

    // The AI service accepts 1..60 days; checking here gives a clear 400 instead of a failed call.
    [Range(1, 60, ErrorMessage = "Days must be between 1 and 60.")]
    public int Days { get; set; }

    [Range(typeof(decimal), "0", "1000000000", ErrorMessage = "Budget must be between 0 and 1,000,000,000 LKR.")]
    public decimal Budget { get; set; }

    [MaxLength(MaxInterests, ErrorMessage = "Choose at most 10 interests.")]
    public List<string> Interests { get; set; } = new();

    /// <summary>
    /// Optional first day of the trip (calendar date). Defaults to tomorrow (UTC) when
    /// omitted, so existing clients that don't send it keep working.
    /// </summary>
    public DateTime? StartDate { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Interests is not null)
        {
            foreach (var interest in Interests)
            {
                if (string.IsNullOrWhiteSpace(interest) || interest.Length > MaxInterestLength)
                {
                    yield return new ValidationResult(
                        $"Each interest must be 1 to {MaxInterestLength} characters.", new[] { nameof(Interests) });
                    break;
                }
            }
        }

        if (StartDate is { } start)
        {
            if (start.Date < ValidationRules.EarliestStart(validationContext))
                yield return new ValidationResult("Start date cannot be in the past.", new[] { nameof(StartDate) });
            else if (start.Date > ValidationRules.LatestStart(validationContext))
                yield return new ValidationResult(
                    $"Start date is too far ahead (at most {ValidationRules.MaxYearsAhead} years).", new[] { nameof(StartDate) });
        }
    }
}

/// <summary>One agent's execution record — the observability trail for a run.</summary>
public class AiWorkflowStepDto
{
    public Guid Id { get; set; }
    public string AgentName { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public string? OutputSummary { get; set; }
    public string? ErrorMessage { get; set; }
}

/// <summary>Full detail of one persisted agentic run, including its per-agent steps.</summary>
public class AiWorkflowResponseDto
{
    public Guid Id { get; set; }
    public Guid? TripId { get; set; }
    public Guid TravelerId { get; set; }
    public string TravelerName { get; set; } = string.Empty;

    public string Goal { get; set; } = string.Empty;
    public int Days { get; set; }
    public decimal Budget { get; set; }
    public List<string> Interests { get; set; } = new();

    public string? FinalPlan { get; set; }
    public string OverallStatus { get; set; } = string.Empty;
    public bool RequiresApproval { get; set; }
    public string ApprovalStatus { get; set; } = string.Empty;

    public Guid? ApprovedByUserId { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? CompletedAt { get; set; }

    public List<AiWorkflowStepDto> Steps { get; set; } = new();
}
