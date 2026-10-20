using System.ComponentModel.DataAnnotations;
using CEYLORA.Domain.Entities;

namespace CEYLORA.Application.DTOs.Accommodations;

public class CreateAccommodationDto
{
    [Required]
    public Guid DestinationId { get; set; }

    [Required, StringLength(150, MinimumLength = 2)]
    public string Name { get; set; } = string.Empty;

    [StringLength(2000)]
    public string Description { get; set; } = string.Empty;

    [EnumDataType(typeof(AccommodationType), ErrorMessage = "Choose a valid accommodation type.")]
    public AccommodationType Type { get; set; }

    /// <summary>LKR per room per night.</summary>
    [Range(0, 10_000_000)]
    public decimal PricePerNight { get; set; }

    [Range(1, 20)]
    public int MaxGuestsPerRoom { get; set; } = 2;
}

public class UpdateAccommodationDto : CreateAccommodationDto
{
    public bool IsActive { get; set; } = true;
}

public class AccommodationResponseDto
{
    public Guid Id { get; set; }
    public Guid DestinationId { get; set; }
    public string DestinationName { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public decimal PricePerNight { get; set; }
    public int MaxGuestsPerRoom { get; set; }
    public bool IsActive { get; set; }

    /// <summary>Mean of all reviews, or null when there are none.</summary>
    public double? AverageRating { get; set; }
    public int ReviewCount { get; set; }
}

/// <summary>Search, filter, sort and paging for GET /api/accommodations.</summary>
public class AccommodationQueryParams
{
    public string? Search { get; set; }
    public Guid? DestinationId { get; set; }
    public AccommodationType? Type { get; set; }
    public decimal? MinPrice { get; set; }
    public decimal? MaxPrice { get; set; }

    /// <summary>Operators and admins can include deactivated stays; the API ignores this for travelers.</summary>
    public bool IncludeInactive { get; set; }

    /// <summary>Name | Price | Rating</summary>
    public string? SortBy { get; set; } = "Name";
    public bool SortDescending { get; set; }

    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
}

/// <summary>Operator sets the room inventory for every night From..To (inclusive).</summary>
public class SetAvailabilityDto : IValidatableObject
{
    public DateOnly From { get; set; }
    public DateOnly To { get; set; }

    [Range(0, 500)]
    public int TotalRooms { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (To < From)
            yield return new ValidationResult("'To' cannot be before 'From'.", new[] { nameof(To) });
    }
}

public class AvailabilityDayDto
{
    public DateOnly Date { get; set; }
    public int TotalRooms { get; set; }
    public int BookedRooms { get; set; }
    public int AvailableRooms { get; set; }
}

/// <summary>
/// Answer to "can I stay here from X to Y with N rooms, and what will it cost?"
/// This is the business-specific operation of the accommodation area.
/// </summary>
public class AvailabilityQuoteDto
{
    public Guid AccommodationId { get; set; }
    public string AccommodationName { get; set; } = string.Empty;
    public DateOnly CheckIn { get; set; }
    public DateOnly CheckOut { get; set; }
    public int Nights { get; set; }
    public int Rooms { get; set; }
    public decimal PricePerNight { get; set; }
    public decimal TotalPrice { get; set; }

    /// <summary>True when every night has at least <see cref="Rooms"/> rooms free.</summary>
    public bool IsAvailable { get; set; }

    /// <summary>The tightest night: the most rooms that could be booked for the whole stay.</summary>
    public int MaxRoomsAvailable { get; set; }

    public List<AvailabilityDayDto> Days { get; set; } = new();
}
