using CEYLORA.Application.DTOs.Destinations;

namespace CEYLORA.Application.Interfaces;

public interface IDestinationService
{
    Task<PagedResult<DestinationResponseDto>> GetDestinationsAsync(DestinationQueryParams query);
    Task<DestinationResponseDto?> GetByIdAsync(Guid id);
    Task<DestinationResponseDto> CreateAsync(CreateDestinationDto dto);
    Task<DestinationResponseDto?> UpdateAsync(Guid id, UpdateDestinationDto dto);
    Task<bool> DeactivateAsync(Guid id);
    Task<DestinationSummaryDto?> GetSummaryAsync(Guid id); // the business-specific operation
}
