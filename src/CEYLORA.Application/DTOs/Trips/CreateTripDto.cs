namespace CEYLORA.Application.DTOs.Trips;

public class CreateTripDto
{
    public string Title { get; set; } = string.Empty;
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public decimal Budget { get; set; }
}
