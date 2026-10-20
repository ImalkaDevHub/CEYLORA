using System.ComponentModel.DataAnnotations;

namespace CEYLORA.Application.DTOs.Bookings;

public class CreateBookingItemDto
{
    [Required]
    public Guid AccommodationId { get; set; }

    public DateOnly CheckIn { get; set; }
    public DateOnly CheckOut { get; set; }

    [Range(1, 10)]
    public int Rooms { get; set; } = 1;

    [Range(1, 200)]
    public int Guests { get; set; } = 1;
}

public class CreateBookingDto
{
    [Required]
    public Guid TripId { get; set; }

    [Required, MinLength(1), MaxLength(10)]
    public List<CreateBookingItemDto> Items { get; set; } = new();

    [StringLength(500)]
    public string? Notes { get; set; }
}

public class BookingItemResponseDto
{
    public Guid Id { get; set; }
    public Guid AccommodationId { get; set; }
    public string AccommodationName { get; set; } = string.Empty;
    public string DestinationName { get; set; } = string.Empty;
    public DateOnly CheckIn { get; set; }
    public DateOnly CheckOut { get; set; }
    public int Nights { get; set; }
    public int Rooms { get; set; }
    public int Guests { get; set; }
    public decimal NightlyRate { get; set; }
    public decimal Subtotal { get; set; }
}

public class BookingResponseDto
{
    public Guid Id { get; set; }
    public Guid TripId { get; set; }
    public string TripTitle { get; set; } = string.Empty;
    public Guid TravelerId { get; set; }
    public string TravelerName { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public decimal TotalAmount { get; set; }
    public string? Notes { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? CancelledAt { get; set; }
    public List<BookingItemResponseDto> Items { get; set; } = new();
}

/// <summary>Operator/Admin listing filters.</summary>
public class BookingQueryParams
{
    public string? Status { get; set; }
    public Guid? TripId { get; set; }
    public Guid? AccommodationId { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
}
