using CEYLORA.Application.DTOs.Destinations;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Infrastructure.Services;

public class DestinationService : IDestinationService
{
    private readonly ApplicationDbContext _db;
    public DestinationService(ApplicationDbContext db) => _db = db;

    public async Task<PagedResult<DestinationResponseDto>> GetDestinationsAsync(DestinationQueryParams q)
    {
        var query = _db.Destinations.Where(d => d.IsActive).AsQueryable();

        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            // Postgres LIKE (what .Contains() translates to) is case-sensitive, so a plain
            // Contains() would miss "Ella" on a search for "ella" — use ILIKE instead.
            var pattern = $"%{q.Search}%";
            query = query.Where(d => EF.Functions.ILike(d.Name, pattern) || EF.Functions.ILike(d.Region, pattern));
        }

        if (q.Category.HasValue)
            query = query.Where(d => d.Category == q.Category.Value);

        query = q.SortBy switch
        {
            "Region" => q.SortDescending ? query.OrderByDescending(d => d.Region) : query.OrderBy(d => d.Region),
            _ => q.SortDescending ? query.OrderByDescending(d => d.Name) : query.OrderBy(d => d.Name)
        };

        var total = await query.CountAsync();
        var items = await query
            .Skip((q.Page - 1) * q.PageSize)
            .Take(q.PageSize)
            .Select(d => MapToDto(d))
            .ToListAsync();

        return new PagedResult<DestinationResponseDto>
        {
            Items = items,
            TotalCount = total,
            Page = q.Page,
            PageSize = q.PageSize
        };
    }

    public async Task<DestinationResponseDto?> GetByIdAsync(Guid id)
    {
        var d = await _db.Destinations.FindAsync(id);
        return d is null ? null : MapToDto(d);
    }

    public async Task<DestinationResponseDto> CreateAsync(CreateDestinationDto dto)
    {
        var destination = new Destination
        {
            Id = Guid.NewGuid(),
            Name = dto.Name,
            Region = dto.Region,
            Description = dto.Description,
            Category = dto.Category,
            ImageUrl = dto.ImageUrl
        };
        _db.Destinations.Add(destination);
        await _db.SaveChangesAsync();
        return MapToDto(destination);
    }

    public async Task<DestinationResponseDto?> UpdateAsync(Guid id, UpdateDestinationDto dto)
    {
        var destination = await _db.Destinations.FindAsync(id);
        if (destination is null) return null;

        destination.Name = dto.Name;
        destination.Region = dto.Region;
        destination.Description = dto.Description;
        destination.Category = dto.Category;
        destination.ImageUrl = dto.ImageUrl;
        destination.IsActive = dto.IsActive;
        destination.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync();
        return MapToDto(destination);
    }

    public async Task<bool> DeactivateAsync(Guid id)
    {
        var destination = await _db.Destinations.FindAsync(id);
        if (destination is null) return false;

        destination.IsActive = false; // soft delete — preserves history/FK integrity
        destination.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return true;
    }

    public async Task<DestinationSummaryDto?> GetSummaryAsync(Guid id)
    {
        var destination = await _db.Destinations
            .Include(d => d.Experiences)
            .FirstOrDefaultAsync(d => d.Id == id);

        if (destination is null) return null;

        var activeExperiences = destination.Experiences.Where(e => e.IsActive).ToList();

        return new DestinationSummaryDto
        {
            DestinationId = destination.Id,
            Name = destination.Name,
            ExperienceCount = activeExperiences.Count,
            MinPrice = activeExperiences.Any() ? activeExperiences.Min(e => e.Price) : 0,
            MaxPrice = activeExperiences.Any() ? activeExperiences.Max(e => e.Price) : 0,
            AveragePrice = activeExperiences.Any() ? activeExperiences.Average(e => e.Price) : 0
        };
    }

    private static DestinationResponseDto MapToDto(Destination d) => new()
    {
        Id = d.Id,
        Name = d.Name,
        Region = d.Region,
        Description = d.Description,
        Category = d.Category.ToString(),
        ImageUrl = d.ImageUrl,
        IsActive = d.IsActive
    };
}
