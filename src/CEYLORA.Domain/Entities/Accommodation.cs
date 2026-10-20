namespace CEYLORA.Domain.Entities;

public enum AccommodationType
{
    Hotel,
    Villa,
    Guesthouse,
    Resort,
    Hostel
}

/// <summary>A place to stay at a destination, offered by the operator.</summary>
public class Accommodation
{
    public Guid Id { get; set; }

    public Guid DestinationId { get; set; }
    public Destination Destination { get; set; } = null!;

    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public AccommodationType Type { get; set; }

    /// <summary>Price for one room for one night, in LKR.</summary>
    public decimal PricePerNight { get; set; }

    /// <summary>How many guests one room sleeps.</summary>
    public int MaxGuestsPerRoom { get; set; } = 2;

    /// <summary>Soft delete: an inactive stay is hidden but keeps its bookings and reviews.</summary>
    public bool IsActive { get; set; } = true;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<Availability> Availabilities { get; set; } = new List<Availability>();
    public ICollection<Review> Reviews { get; set; } = new List<Review>();
}
