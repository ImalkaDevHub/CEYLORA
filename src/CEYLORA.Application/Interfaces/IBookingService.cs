using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Bookings;
using CEYLORA.Application.DTOs.Destinations;

namespace CEYLORA.Application.Interfaces;

public interface IBookingService
{
    /// <summary>
    /// Books stays for one of the traveler's trips. Checks every night's availability and
    /// reserves the rooms in the same save as the booking, so it either all happens or none of it.
    /// </summary>
    Task<ServiceResult<BookingResponseDto>> CreateAsync(Guid travelerId, CreateBookingDto dto);

    Task<List<BookingResponseDto>> GetMineAsync(Guid travelerId);

    /// <summary>Operator/Admin view of every booking.</summary>
    Task<PagedResult<BookingResponseDto>> GetAllAsync(BookingQueryParams query);

    /// <summary>The booking, if the caller owns it or is staff.</summary>
    Task<ServiceResult<BookingResponseDto>> GetByIdAsync(Guid id, Guid userId, bool isStaff);

    /// <summary>
    /// Cancels a confirmed booking and gives its rooms back. Travelers can cancel until the
    /// day the first stay starts; staff can cancel any time.
    /// </summary>
    Task<ServiceResult<BookingResponseDto>> CancelAsync(Guid id, Guid userId, bool isStaff);
}
