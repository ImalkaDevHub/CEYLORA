using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Accommodations;
using CEYLORA.Application.DTOs.Destinations;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Infrastructure.Services;

public class AccommodationService : IAccommodationService
{
    public const int MaxPageSize = 50;
    public const int MaxAvailabilityWindowDays = 120;
    public const int MaxSetAvailabilityDays = 366;
    public const int MaxStayNights = 30;
    public const int MaxRoomsPerBooking = 10;

    private readonly ApplicationDbContext _db;
    private readonly TimeProvider _clock;

    public AccommodationService(ApplicationDbContext db, TimeProvider clock)
    {
        _db = db;
        _clock = clock;
    }

    private DateOnly Today => DateOnly.FromDateTime(_clock.GetUtcNow().UtcDateTime);

    public async Task<PagedResult<AccommodationResponseDto>> GetAccommodationsAsync(AccommodationQueryParams q)
    {
        var page = Math.Max(q.Page, 1);
        var pageSize = Math.Clamp(q.PageSize, 1, MaxPageSize);

        var query = _db.Accommodations.AsNoTracking().AsQueryable();

        if (!q.IncludeInactive)
            query = query.Where(a => a.IsActive);

        if (q.DestinationId.HasValue)
            query = query.Where(a => a.DestinationId == q.DestinationId.Value);

        if (q.Type.HasValue)
            query = query.Where(a => a.Type == q.Type.Value);

        if (q.MinPrice.HasValue)
            query = query.Where(a => a.PricePerNight >= q.MinPrice.Value);

        if (q.MaxPrice.HasValue)
            query = query.Where(a => a.PricePerNight <= q.MaxPrice.Value);

        if (!string.IsNullOrWhiteSpace(q.Search))
        {
            var term = q.Search.Trim().ToLower();
            query = query.Where(a => a.Name.ToLower().Contains(term) || a.Destination.Name.ToLower().Contains(term));
        }

        var rows = query.Select(a => new Row
        {
            Accommodation = a,
            DestinationName = a.Destination.Name,
            ReviewCount = a.Reviews.Count(),
            Average = a.Reviews.Average(r => (double?)r.Rating)
        });

        // Secondary keys keep paging stable when the primary values tie.
        var sorted = (q.SortBy?.ToLowerInvariant(), q.SortDescending) switch
        {
            ("price", false) => rows.OrderBy(r => r.Accommodation.PricePerNight).ThenBy(r => r.Accommodation.Name),
            ("price", true) => rows.OrderByDescending(r => r.Accommodation.PricePerNight).ThenBy(r => r.Accommodation.Name),
            ("rating", false) => rows.OrderBy(r => r.Average ?? 0).ThenBy(r => r.Accommodation.Name),
            ("rating", true) => rows.OrderByDescending(r => r.Average ?? 0).ThenBy(r => r.Accommodation.Name),
            (_, true) => rows.OrderByDescending(r => r.Accommodation.Name),
            _ => rows.OrderBy(r => r.Accommodation.Name)
        };

        var total = await sorted.CountAsync();
        var items = await sorted
            .ThenBy(r => r.Accommodation.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return new PagedResult<AccommodationResponseDto>
        {
            Items = items.Select(r => Map(r.Accommodation, r.DestinationName, r.Average, r.ReviewCount)).ToList(),
            TotalCount = total,
            Page = page,
            PageSize = pageSize
        };
    }

    public async Task<AccommodationResponseDto?> GetByIdAsync(Guid id)
    {
        var row = await _db.Accommodations.AsNoTracking()
            .Where(a => a.Id == id)
            .Select(a => new Row
            {
                Accommodation = a,
                DestinationName = a.Destination.Name,
                ReviewCount = a.Reviews.Count(),
                Average = a.Reviews.Average(r => (double?)r.Rating)
            })
            .FirstOrDefaultAsync();

        return row is null ? null : Map(row.Accommodation, row.DestinationName, row.Average, row.ReviewCount);
    }

    public async Task<ServiceResult<AccommodationResponseDto>> CreateAsync(CreateAccommodationDto dto)
    {
        var destination = await _db.Destinations.AsNoTracking()
            .FirstOrDefaultAsync(d => d.Id == dto.DestinationId && d.IsActive);
        if (destination is null)
            return ServiceResult<AccommodationResponseDto>.Invalid("Destination not found or no longer active.");

        var name = dto.Name.Trim();
        if (await NameTakenAsync(dto.DestinationId, name, exceptId: null))
            return ServiceResult<AccommodationResponseDto>.Conflict(
                $"{destination.Name} already has an accommodation called '{name}'.");

        var now = _clock.GetUtcNow().UtcDateTime;
        var accommodation = new Accommodation
        {
            Id = Guid.NewGuid(),
            DestinationId = dto.DestinationId,
            Name = name,
            Description = dto.Description?.Trim() ?? string.Empty,
            Type = dto.Type,
            PricePerNight = dto.PricePerNight,
            MaxGuestsPerRoom = dto.MaxGuestsPerRoom,
            IsActive = true,
            CreatedAt = now,
            UpdatedAt = now
        };

        _db.Accommodations.Add(accommodation);
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Lost a race against another create with the same name (unique index).
            return ServiceResult<AccommodationResponseDto>.Conflict(
                $"{destination.Name} already has an accommodation called '{name}'.");
        }

        return ServiceResult<AccommodationResponseDto>.Ok(
            Map(accommodation, destination.Name, average: null, reviewCount: 0));
    }

    public async Task<ServiceResult<AccommodationResponseDto>> UpdateAsync(Guid id, UpdateAccommodationDto dto)
    {
        var accommodation = await _db.Accommodations.FirstOrDefaultAsync(a => a.Id == id);
        if (accommodation is null)
            return ServiceResult<AccommodationResponseDto>.NotFound("Accommodation not found.");

        var destination = await _db.Destinations.AsNoTracking()
            .FirstOrDefaultAsync(d => d.Id == dto.DestinationId && d.IsActive);
        if (destination is null)
            return ServiceResult<AccommodationResponseDto>.Invalid("Destination not found or no longer active.");

        var name = dto.Name.Trim();
        if (await NameTakenAsync(dto.DestinationId, name, exceptId: id))
            return ServiceResult<AccommodationResponseDto>.Conflict(
                $"{destination.Name} already has an accommodation called '{name}'.");

        accommodation.DestinationId = dto.DestinationId;
        accommodation.Name = name;
        accommodation.Description = dto.Description?.Trim() ?? string.Empty;
        accommodation.Type = dto.Type;
        accommodation.PricePerNight = dto.PricePerNight;
        accommodation.MaxGuestsPerRoom = dto.MaxGuestsPerRoom;
        accommodation.IsActive = dto.IsActive;
        accommodation.UpdatedAt = _clock.GetUtcNow().UtcDateTime;

        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            return ServiceResult<AccommodationResponseDto>.Conflict(
                $"{destination.Name} already has an accommodation called '{name}'.");
        }

        return ServiceResult<AccommodationResponseDto>.Ok((await GetByIdAsync(id))!);
    }

    public async Task<bool> DeactivateAsync(Guid id)
    {
        var accommodation = await _db.Accommodations.FirstOrDefaultAsync(a => a.Id == id);
        if (accommodation is null) return false;

        accommodation.IsActive = false; // soft delete: bookings and reviews keep pointing at it
        accommodation.UpdatedAt = _clock.GetUtcNow().UtcDateTime;
        await _db.SaveChangesAsync();
        return true;
    }

    public async Task<ServiceResult<List<AvailabilityDayDto>>> GetAvailabilityAsync(Guid id, DateOnly from, DateOnly to)
    {
        if (to < from)
            return ServiceResult<List<AvailabilityDayDto>>.Invalid("'to' cannot be before 'from'.");
        if (to.DayNumber - from.DayNumber + 1 > MaxAvailabilityWindowDays)
            return ServiceResult<List<AvailabilityDayDto>>.Invalid(
                $"Ask for at most {MaxAvailabilityWindowDays} nights at a time.");

        if (!await _db.Accommodations.AnyAsync(a => a.Id == id))
            return ServiceResult<List<AvailabilityDayDto>>.NotFound("Accommodation not found.");

        var rows = await _db.Availabilities.AsNoTracking()
            .Where(a => a.AccommodationId == id && a.Date >= from && a.Date <= to)
            .OrderBy(a => a.Date)
            .ToListAsync();

        return ServiceResult<List<AvailabilityDayDto>>.Ok(rows.Select(MapDay).ToList());
    }

    public async Task<ServiceResult<List<AvailabilityDayDto>>> SetAvailabilityAsync(Guid id, SetAvailabilityDto dto)
    {
        if (dto.To < dto.From)
            return ServiceResult<List<AvailabilityDayDto>>.Invalid("'To' cannot be before 'From'.");
        if (dto.From < Today)
            return ServiceResult<List<AvailabilityDayDto>>.Invalid("Availability can only be set for today or later.");
        if (dto.To.DayNumber - dto.From.DayNumber + 1 > MaxSetAvailabilityDays)
            return ServiceResult<List<AvailabilityDayDto>>.Invalid(
                $"Set at most {MaxSetAvailabilityDays} nights at a time.");
        if (dto.TotalRooms < 0)
            return ServiceResult<List<AvailabilityDayDto>>.Invalid("Total rooms cannot be negative.");

        if (!await _db.Accommodations.AnyAsync(a => a.Id == id))
            return ServiceResult<List<AvailabilityDayDto>>.NotFound("Accommodation not found.");

        var existing = await _db.Availabilities
            .Where(a => a.AccommodationId == id && a.Date >= dto.From && a.Date <= dto.To)
            .ToDictionaryAsync(a => a.Date);

        // All or nothing: refuse the whole change if any night already has more rooms sold
        // than the new total.
        foreach (var row in existing.Values.OrderBy(r => r.Date))
        {
            if (dto.TotalRooms < row.BookedRooms)
                return ServiceResult<List<AvailabilityDayDto>>.Conflict(
                    $"Cannot set {dto.TotalRooms} room(s) on {row.Date:yyyy-MM-dd}: {row.BookedRooms} already booked.");
        }

        for (var date = dto.From; date <= dto.To; date = date.AddDays(1))
        {
            if (existing.TryGetValue(date, out var row))
            {
                if (row.TotalRooms == dto.TotalRooms) continue;
                row.TotalRooms = dto.TotalRooms;
                row.Version++;
            }
            else
            {
                var created = new Availability
                {
                    Id = Guid.NewGuid(),
                    AccommodationId = id,
                    Date = date,
                    TotalRooms = dto.TotalRooms,
                    BookedRooms = 0,
                    Version = 0
                };
                _db.Availabilities.Add(created);
                existing[date] = created;
            }
        }

        try
        {
            await _db.SaveChangesAsync();
        }
        catch (Exception ex) when (ex is DbUpdateConcurrencyException or DbUpdateException)
        {
            // A booking or another operator changed these nights while we were saving.
            return ServiceResult<List<AvailabilityDayDto>>.Conflict(
                "Availability changed while saving. Please try again.");
        }

        return ServiceResult<List<AvailabilityDayDto>>.Ok(
            existing.Values.OrderBy(r => r.Date).Select(MapDay).ToList());
    }

    public async Task<ServiceResult<AvailabilityQuoteDto>> QuoteAsync(
        Guid id, DateOnly checkIn, DateOnly checkOut, int rooms)
    {
        var nights = checkOut.DayNumber - checkIn.DayNumber;
        if (nights < 1)
            return ServiceResult<AvailabilityQuoteDto>.Invalid("Check-out must be after check-in.");
        if (nights > MaxStayNights)
            return ServiceResult<AvailabilityQuoteDto>.Invalid($"A stay can be at most {MaxStayNights} nights.");
        if (checkIn < Today)
            return ServiceResult<AvailabilityQuoteDto>.Invalid("Check-in cannot be in the past.");
        if (rooms < 1 || rooms > MaxRoomsPerBooking)
            return ServiceResult<AvailabilityQuoteDto>.Invalid($"Book between 1 and {MaxRoomsPerBooking} rooms.");

        var accommodation = await _db.Accommodations.AsNoTracking()
            .FirstOrDefaultAsync(a => a.Id == id && a.IsActive);
        if (accommodation is null)
            return ServiceResult<AvailabilityQuoteDto>.NotFound("Accommodation not found or no longer offered.");

        var rows = await _db.Availabilities.AsNoTracking()
            .Where(a => a.AccommodationId == id && a.Date >= checkIn && a.Date < checkOut)
            .ToDictionaryAsync(a => a.Date);

        // One entry per night; a night with no inventory row counts as zero rooms.
        var days = new List<AvailabilityDayDto>(nights);
        for (var date = checkIn; date < checkOut; date = date.AddDays(1))
        {
            days.Add(rows.TryGetValue(date, out var row)
                ? MapDay(row)
                : new AvailabilityDayDto { Date = date });
        }

        var maxRooms = days.Min(d => d.AvailableRooms);
        return ServiceResult<AvailabilityQuoteDto>.Ok(new AvailabilityQuoteDto
        {
            AccommodationId = accommodation.Id,
            AccommodationName = accommodation.Name,
            CheckIn = checkIn,
            CheckOut = checkOut,
            Nights = nights,
            Rooms = rooms,
            PricePerNight = accommodation.PricePerNight,
            TotalPrice = accommodation.PricePerNight * nights * rooms,
            IsAvailable = maxRooms >= rooms,
            MaxRoomsAvailable = Math.Max(maxRooms, 0),
            Days = days
        });
    }

    private Task<bool> NameTakenAsync(Guid destinationId, string name, Guid? exceptId)
    {
        var lowered = name.ToLower();
        return _db.Accommodations.AnyAsync(a =>
            a.DestinationId == destinationId && a.Id != exceptId && a.Name.ToLower() == lowered);
    }

    private static AvailabilityDayDto MapDay(Availability a) => new()
    {
        Date = a.Date,
        TotalRooms = a.TotalRooms,
        BookedRooms = a.BookedRooms,
        AvailableRooms = a.TotalRooms - a.BookedRooms
    };

    private static AccommodationResponseDto Map(
        Accommodation a, string destinationName, double? average, int reviewCount) => new()
    {
        Id = a.Id,
        DestinationId = a.DestinationId,
        DestinationName = destinationName,
        Name = a.Name,
        Description = a.Description,
        Type = a.Type.ToString(),
        PricePerNight = a.PricePerNight,
        MaxGuestsPerRoom = a.MaxGuestsPerRoom,
        IsActive = a.IsActive,
        AverageRating = average.HasValue ? Math.Round(average.Value, 1) : null,
        ReviewCount = reviewCount
    };

    // Projection target: a class (not an anonymous type) so it can be ordered through a switch.
    private sealed class Row
    {
        public Accommodation Accommodation { get; set; } = null!;
        public string DestinationName { get; set; } = string.Empty;
        public int ReviewCount { get; set; }
        public double? Average { get; set; }
    }
}
