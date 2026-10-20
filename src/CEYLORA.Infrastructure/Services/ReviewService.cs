using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Destinations;
using CEYLORA.Application.DTOs.Reviews;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Infrastructure.Services;

public class ReviewService : IReviewService
{
    public const int MaxPageSize = 50;

    private readonly ApplicationDbContext _db;
    private readonly TimeProvider _clock;

    public ReviewService(ApplicationDbContext db, TimeProvider clock)
    {
        _db = db;
        _clock = clock;
    }

    private DateOnly Today => DateOnly.FromDateTime(_clock.GetUtcNow().UtcDateTime);

    public async Task<ServiceResult<ReviewResponseDto>> CreateAsync(
        Guid accommodationId, Guid travelerId, CreateReviewDto dto)
    {
        if (dto.Rating < 1 || dto.Rating > 5)
            return ServiceResult<ReviewResponseDto>.Invalid("Rating must be between 1 and 5.");

        if (!await _db.Accommodations.AnyAsync(a => a.Id == accommodationId))
            return ServiceResult<ReviewResponseDto>.NotFound("Accommodation not found.");

        // The stay must be confirmed and over. The latest such booking is recorded as the proof.
        var today = Today;
        var qualifyingBookingId = await _db.Bookings.AsNoTracking()
            .Where(b => b.TravelerId == travelerId
                        && b.Status == BookingStatus.Confirmed
                        && b.Items.Any(i => i.AccommodationId == accommodationId && i.CheckOut <= today))
            .OrderByDescending(b => b.CreatedAt)
            .Select(b => (Guid?)b.Id)
            .FirstOrDefaultAsync();

        if (qualifyingBookingId is null)
            return ServiceResult<ReviewResponseDto>.Forbidden(
                "You can review a place only after your stay there has ended.");

        if (await _db.Reviews.AnyAsync(r => r.AccommodationId == accommodationId && r.TravelerId == travelerId))
            return ServiceResult<ReviewResponseDto>.Conflict("You have already reviewed this accommodation.");

        var review = new Review
        {
            Id = Guid.NewGuid(),
            AccommodationId = accommodationId,
            TravelerId = travelerId,
            BookingId = qualifyingBookingId.Value,
            Rating = dto.Rating,
            Comment = dto.Comment?.Trim() ?? string.Empty,
            CreatedAt = _clock.GetUtcNow().UtcDateTime
        };

        _db.Reviews.Add(review);
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Two submissions raced past the check; the unique index let only one through.
            return ServiceResult<ReviewResponseDto>.Conflict("You have already reviewed this accommodation.");
        }

        var author = await _db.Users.AsNoTracking()
            .Where(u => u.Id == travelerId)
            .Select(u => u.FullName)
            .FirstOrDefaultAsync();

        return ServiceResult<ReviewResponseDto>.Ok(Map(review, author ?? string.Empty));
    }

    public async Task<ServiceResult<PagedResult<ReviewResponseDto>>> GetForAccommodationAsync(
        Guid accommodationId, int page, int pageSize)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        if (!await _db.Accommodations.AnyAsync(a => a.Id == accommodationId))
            return ServiceResult<PagedResult<ReviewResponseDto>>.NotFound("Accommodation not found.");

        var query = _db.Reviews.AsNoTracking().Where(r => r.AccommodationId == accommodationId);

        var total = await query.CountAsync();
        var rows = await query
            .OrderByDescending(r => r.CreatedAt)
            .ThenBy(r => r.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(r => new { Review = r, Author = r.Traveler.FullName })
            .ToListAsync();

        return ServiceResult<PagedResult<ReviewResponseDto>>.Ok(new PagedResult<ReviewResponseDto>
        {
            Items = rows.Select(r => Map(r.Review, r.Author)).ToList(),
            TotalCount = total,
            Page = page,
            PageSize = pageSize
        });
    }

    public async Task<ServiceResult<bool>> DeleteAsync(Guid reviewId, Guid userId, bool isAdmin)
    {
        var review = await _db.Reviews.FirstOrDefaultAsync(r => r.Id == reviewId);
        if (review is null)
            return ServiceResult<bool>.NotFound("Review not found.");
        if (review.TravelerId != userId && !isAdmin)
            return ServiceResult<bool>.Forbidden("You can only delete your own review.");

        _db.Reviews.Remove(review);
        await _db.SaveChangesAsync();
        return ServiceResult<bool>.Ok(true);
    }

    private static ReviewResponseDto Map(Review r, string authorName) => new()
    {
        Id = r.Id,
        AccommodationId = r.AccommodationId,
        TravelerId = r.TravelerId,
        TravelerName = authorName,
        Rating = r.Rating,
        Comment = r.Comment,
        CreatedAt = r.CreatedAt
    };
}
