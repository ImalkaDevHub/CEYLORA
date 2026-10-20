using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Destinations;
using CEYLORA.Application.DTOs.Reviews;

namespace CEYLORA.Application.Interfaces;

public interface IReviewService
{
    /// <summary>
    /// Adds the traveler's review. Allowed only after a confirmed stay there has ended, and
    /// only once per accommodation.
    /// </summary>
    Task<ServiceResult<ReviewResponseDto>> CreateAsync(Guid accommodationId, Guid travelerId, CreateReviewDto dto);

    /// <summary>Newest first.</summary>
    Task<ServiceResult<PagedResult<ReviewResponseDto>>> GetForAccommodationAsync(Guid accommodationId, int page, int pageSize);

    /// <summary>The author or an admin may delete a review.</summary>
    Task<ServiceResult<bool>> DeleteAsync(Guid reviewId, Guid userId, bool isAdmin);
}
