namespace CEYLORA.Domain.Entities;

/// <summary>A traveler's rating of an accommodation they have stayed at (one per traveler per stay place).</summary>
public class Review
{
    public Guid Id { get; set; }

    public Guid AccommodationId { get; set; }
    public Accommodation Accommodation { get; set; } = null!;

    public Guid TravelerId { get; set; }
    public User Traveler { get; set; } = null!;

    /// <summary>The completed booking that makes this review eligible.</summary>
    public Guid BookingId { get; set; }
    public Booking Booking { get; set; } = null!;

    /// <summary>1 (poor) to 5 (excellent).</summary>
    public int Rating { get; set; }

    public string Comment { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
