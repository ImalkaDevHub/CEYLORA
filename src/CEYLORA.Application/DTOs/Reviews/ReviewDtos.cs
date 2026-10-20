using System.ComponentModel.DataAnnotations;

namespace CEYLORA.Application.DTOs.Reviews;

public class CreateReviewDto
{
    [Range(1, 5)]
    public int Rating { get; set; }

    [StringLength(1000)]
    public string Comment { get; set; } = string.Empty;
}

public class ReviewResponseDto
{
    public Guid Id { get; set; }
    public Guid AccommodationId { get; set; }
    public Guid TravelerId { get; set; }
    public string TravelerName { get; set; } = string.Empty;
    public int Rating { get; set; }
    public string Comment { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
