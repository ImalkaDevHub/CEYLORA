namespace CEYLORA.Domain.Entities;

public enum BookingStatus
{
    Confirmed,
    Cancelled
}

/// <summary>A traveler's reservation of one or more stays for one of their trips.</summary>
public class Booking
{
    public Guid Id { get; set; }

    public Guid TravelerId { get; set; }
    public User Traveler { get; set; } = null!;

    public Guid TripId { get; set; }
    public Trip Trip { get; set; } = null!;

    public BookingStatus Status { get; set; } = BookingStatus.Confirmed;

    /// <summary>Sum of the item subtotals, in LKR, fixed at booking time.</summary>
    public decimal TotalAmount { get; set; }

    public string? Notes { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? CancelledAt { get; set; }

    public ICollection<BookingItem> Items { get; set; } = new List<BookingItem>();
}

/// <summary>One stay inside a booking. The price is copied so later price changes don't rewrite history.</summary>
public class BookingItem
{
    public Guid Id { get; set; }

    public Guid BookingId { get; set; }
    public Booking Booking { get; set; } = null!;

    public Guid AccommodationId { get; set; }
    public Accommodation Accommodation { get; set; } = null!;

    public DateOnly CheckIn { get; set; }
    public DateOnly CheckOut { get; set; }

    public int Rooms { get; set; }
    public int Guests { get; set; }

    /// <summary>Price per room per night when the booking was made.</summary>
    public decimal NightlyRate { get; set; }

    public decimal Subtotal { get; set; }

    public int Nights => CheckOut.DayNumber - CheckIn.DayNumber;
}
