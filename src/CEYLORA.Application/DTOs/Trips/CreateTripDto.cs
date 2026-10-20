using System.ComponentModel.DataAnnotations;
using CEYLORA.Application.Validation;

namespace CEYLORA.Application.DTOs.Trips;

public class CreateTripDto : IValidatableObject
{
    [Required(ErrorMessage = "Title is required.")]
    [StringLength(120, MinimumLength = 2, ErrorMessage = "Title must be 2 to 120 characters.")]
    public string Title { get; set; } = string.Empty;

    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }

    [Range(typeof(decimal), "0", "1000000000", ErrorMessage = "Budget must be between 0 and 1,000,000,000 LKR.")]
    public decimal Budget { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (StartDate == default)
            yield return new ValidationResult("Start date is required.", new[] { nameof(StartDate) });
        if (EndDate == default)
            yield return new ValidationResult("End date is required.", new[] { nameof(EndDate) });
        if (StartDate == default || EndDate == default) yield break;

        if (EndDate.Date < StartDate.Date)
        {
            yield return new ValidationResult("End date cannot be before start date.", new[] { nameof(EndDate) });
            yield break;
        }

        if (StartDate.Date < ValidationRules.EarliestStart(validationContext))
            yield return new ValidationResult("Start date cannot be in the past.", new[] { nameof(StartDate) });

        if (StartDate.Date > ValidationRules.LatestStart(validationContext))
        {
            yield return new ValidationResult(
                $"Start date is too far ahead (at most {ValidationRules.MaxYearsAhead} years).", new[] { nameof(StartDate) });
        }

        if ((EndDate.Date - StartDate.Date).TotalDays + 1 > ValidationRules.MaxTripDays)
        {
            yield return new ValidationResult(
                $"A trip can be at most {ValidationRules.MaxTripDays} days long.", new[] { nameof(EndDate) });
        }
    }
}
