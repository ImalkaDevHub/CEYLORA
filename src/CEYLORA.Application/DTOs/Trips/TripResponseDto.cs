namespace CEYLORA.Application.DTOs.Trips;

public class TripResponseDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public decimal Budget { get; set; }
    public string Status { get; set; } = string.Empty;
    public string TravelerName { get; set; } = string.Empty;
}
