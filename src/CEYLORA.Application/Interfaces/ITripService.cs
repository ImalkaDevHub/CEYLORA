using CEYLORA.Application.DTOs.Trips;

namespace CEYLORA.Application.Interfaces;

public interface ITripService
{
    Task<TripResponseDto?> CreateTripAsync(Guid travelerId, CreateTripDto dto);
    Task<List<TripResponseDto>> GetMyTripsAsync(Guid travelerId);
    Task<List<TripResponseDto>> GetAllTripsAsync(); // for Operator/Admin
    Task<TripResponseDto?> GetTripByIdAsync(Guid tripId);
    Task<TripResponseDto?> SubmitTripAsync(Guid tripId, Guid travelerId); // business-specific operation
}
