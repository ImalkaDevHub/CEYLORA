using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Accommodations;
using CEYLORA.Application.DTOs.Destinations;

namespace CEYLORA.Application.Interfaces;

public interface IAccommodationService
{
    Task<PagedResult<AccommodationResponseDto>> GetAccommodationsAsync(AccommodationQueryParams query);
    Task<AccommodationResponseDto?> GetByIdAsync(Guid id);

    Task<ServiceResult<AccommodationResponseDto>> CreateAsync(CreateAccommodationDto dto);
    Task<ServiceResult<AccommodationResponseDto>> UpdateAsync(Guid id, UpdateAccommodationDto dto);

    /// <summary>Soft delete: hides the stay but keeps its bookings and reviews.</summary>
    Task<bool> DeactivateAsync(Guid id);

    /// <summary>Nightly inventory for From..To (inclusive; at most 120 nights).</summary>
    Task<ServiceResult<List<AvailabilityDayDto>>> GetAvailabilityAsync(Guid id, DateOnly from, DateOnly to);

    /// <summary>Operator sets the room count for every night From..To, creating or updating rows.</summary>
    Task<ServiceResult<List<AvailabilityDayDto>>> SetAvailabilityAsync(Guid id, SetAvailabilityDto dto);

    /// <summary>Business operation: availability and price for a stay.</summary>
    Task<ServiceResult<AvailabilityQuoteDto>> QuoteAsync(Guid id, DateOnly checkIn, DateOnly checkOut, int rooms);
}
