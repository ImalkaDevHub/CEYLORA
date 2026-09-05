using CEYLORA.Domain.Entities;

namespace CEYLORA.Application.DTOs.Destinations;

public class CreateDestinationDto
{
    public string Name { get; set; } = string.Empty;
    public string Region { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public TravelCategory Category { get; set; }
    public string? ImageUrl { get; set; }
}

public class UpdateDestinationDto : CreateDestinationDto
{
    public bool IsActive { get; set; } = true;
}

public class DestinationResponseDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Region { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string? ImageUrl { get; set; }
    public bool IsActive { get; set; }
}

// Business-specific operation output — beyond plain CRUD
public class DestinationSummaryDto
{
    public Guid DestinationId { get; set; }
    public string Name { get; set; } = string.Empty;
    public int ExperienceCount { get; set; }
    public decimal MinPrice { get; set; }
    public decimal MaxPrice { get; set; }
    public decimal AveragePrice { get; set; }
}

// Query params for search/filter/sort/pagination — required by Section 4.1
public class DestinationQueryParams
{
    public string? Search { get; set; }
    public TravelCategory? Category { get; set; }
    public string? SortBy { get; set; } = "Name"; // Name | Region
    public bool SortDescending { get; set; } = false;
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
}

public class PagedResult<T>
{
    public List<T> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
}
