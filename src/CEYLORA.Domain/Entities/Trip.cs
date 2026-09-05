namespace CEYLORA.Domain.Entities;

public enum TripStatus
{
    Draft,
    Submitted,
    Confirmed,
    Cancelled
}

public class Trip
{
    public Guid Id { get; set; }
    public Guid TravelerId { get; set; }
    public User Traveler { get; set; } = null!;
    public string Title { get; set; } = string.Empty;
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public decimal Budget { get; set; }
    public TripStatus Status { get; set; } = TripStatus.Draft;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
