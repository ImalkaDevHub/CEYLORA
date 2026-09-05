namespace CEYLORA.Domain.Entities;

public class Experience
{
    public Guid Id { get; set; }
    public Guid DestinationId { get; set; }
    public Destination Destination { get; set; } = null!;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public int DurationHours { get; set; }
    public TravelCategory Category { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
