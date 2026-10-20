using System.ComponentModel.DataAnnotations;
using CEYLORA.Application.Validation;
using CEYLORA.Domain.Entities;

namespace CEYLORA.Application.DTOs.Destinations;

public class CreateDestinationDto
{
    [Required(ErrorMessage = "Name is required.")]
    [StringLength(150, MinimumLength = 2, ErrorMessage = "Name must be 2 to 150 characters.")]
    public string Name { get; set; } = string.Empty;

    [Required(ErrorMessage = "Region is required.")]
    [StringLength(100, MinimumLength = 2, ErrorMessage = "Region must be 2 to 100 characters.")]
    public string Region { get; set; } = string.Empty;

    [StringLength(4000, ErrorMessage = "Description is too long (at most 4000 characters).")]
    public string Description { get; set; } = string.Empty;

    [EnumDataType(typeof(TravelCategory), ErrorMessage = "Choose a valid category.")]
    public TravelCategory Category { get; set; }

    [StringLength(2048, ErrorMessage = "Image link is too long.")]
    [HttpUrl]
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
    [StringLength(100, ErrorMessage = "Search text is too long (at most 100 characters).")]
    public string? Search { get; set; }

    [EnumDataType(typeof(TravelCategory), ErrorMessage = "Choose a valid category.")]
    public TravelCategory? Category { get; set; }

    [RegularExpression("^(?i)(name|region)$", ErrorMessage = "Sort by 'Name' or 'Region'.")]
    public string? SortBy { get; set; } = "Name"; // Name | Region

    public bool SortDescending { get; set; } = false;

    [Range(1, 100_000, ErrorMessage = "Page must be 1 or more.")]
    public int Page { get; set; } = 1;

    [Range(1, 100, ErrorMessage = "Page size must be between 1 and 100.")]
    public int PageSize { get; set; } = 10;
}

public class PagedResult<T>
{
    public List<T> Items { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
}
