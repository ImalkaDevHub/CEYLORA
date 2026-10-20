using CEYLORA.Application.DTOs.Trips;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Infrastructure.Services;

public class TripService : ITripService
{
    private readonly ApplicationDbContext _db;

    public TripService(ApplicationDbContext db) => _db = db;

    public async Task<TripResponseDto?> CreateTripAsync(Guid travelerId, CreateTripDto dto)
    {
        // Business rule: trip end date cannot precede start date
        if (dto.EndDate < dto.StartDate)
            return null;

        var trip = new Trip
        {
            Id = Guid.NewGuid(),
            TravelerId = travelerId,
            Title = dto.Title.Trim(),
            // Npgsql refuses to write DateTime.Kind=Unspecified into a "timestamp with time zone"
            // column, and that's exactly what an <input type="date"> sends (e.g. "2026-11-01",
            // no offset). Trip dates are calendar dates with no inherent timezone, so treat them
            // as UTC midnight rather than rejecting them.
            StartDate = DateTime.SpecifyKind(dto.StartDate, DateTimeKind.Utc),
            EndDate = DateTime.SpecifyKind(dto.EndDate, DateTimeKind.Utc),
            Budget = dto.Budget,
            Status = TripStatus.Draft
        };

        _db.Trips.Add(trip);
        await _db.SaveChangesAsync();

        return await GetTripByIdAsync(trip.Id);
    }

    public async Task<List<TripResponseDto>> GetMyTripsAsync(Guid travelerId)
    {
        return await _db.Trips
            .Include(t => t.Traveler)
            .Where(t => t.TravelerId == travelerId)
            .Select(t => MapToDto(t))
            .ToListAsync();
    }

    public async Task<List<TripResponseDto>> GetAllTripsAsync()
    {
        return await _db.Trips
            .Include(t => t.Traveler)
            .Select(t => MapToDto(t))
            .ToListAsync();
    }

    public async Task<TripResponseDto?> GetTripByIdAsync(Guid tripId)
    {
        var trip = await _db.Trips.Include(t => t.Traveler).FirstOrDefaultAsync(t => t.Id == tripId);
        return trip is null ? null : MapToDto(trip);
    }

    public async Task<TripResponseDto?> SubmitTripAsync(Guid tripId, Guid travelerId)
    {
        var trip = await _db.Trips.Include(t => t.Traveler).FirstOrDefaultAsync(t => t.Id == tripId);

        if (trip is null || trip.TravelerId != travelerId) return null; // not found or not owner
        if (trip.Status != TripStatus.Draft) return null; // can only submit a draft

        trip.Status = TripStatus.Submitted;
        trip.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return MapToDto(trip);
    }

    private static TripResponseDto MapToDto(Trip t) => new()
    {
        Id = t.Id,
        Title = t.Title,
        StartDate = t.StartDate,
        EndDate = t.EndDate,
        Budget = t.Budget,
        Status = t.Status.ToString(),
        TravelerName = t.Traveler.FullName
    };
}
