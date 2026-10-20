using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Bookings;
using CEYLORA.Application.DTOs.Destinations;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Infrastructure.Services;

public class BookingService : IBookingService
{
    /// <summary>How many times to redo a booking when someone else changed the same nights meanwhile.</summary>
    public const int MaxAttempts = 3;

    public const int MaxItemsPerBooking = 10;
    public const int MaxPageSize = 50;

    private readonly ApplicationDbContext _db;
    private readonly TimeProvider _clock;

    public BookingService(ApplicationDbContext db, TimeProvider clock)
    {
        _db = db;
        _clock = clock;
    }

    private DateOnly Today => DateOnly.FromDateTime(_clock.GetUtcNow().UtcDateTime);

    // ---- Create -------------------------------------------------------------------------

    public async Task<ServiceResult<BookingResponseDto>> CreateAsync(Guid travelerId, CreateBookingDto dto)
    {
        var invalid = ValidateItems(dto);
        if (invalid is not null) return invalid;

        for (var attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            // Start every attempt from what is really in the database.
            _db.ChangeTracker.Clear();

            var (result, raced) = await TryCreateAsync(travelerId, dto);
            if (!raced)
            {
                // A refused booking may have tentatively reserved rooms in memory before it
                // failed; make sure none of that can ever be saved later.
                if (!result!.Succeeded) _db.ChangeTracker.Clear();
                return result;
            }
        }
        _db.ChangeTracker.Clear();

        return ServiceResult<BookingResponseDto>.Conflict(
            "Availability changed while you were booking. Please try again.");
    }

    private ServiceResult<BookingResponseDto>? ValidateItems(CreateBookingDto dto)
    {
        if (dto.Items is null || dto.Items.Count == 0)
            return ServiceResult<BookingResponseDto>.Invalid("A booking needs at least one stay.");
        if (dto.Items.Count > MaxItemsPerBooking)
            return ServiceResult<BookingResponseDto>.Invalid(
                $"A booking can have at most {MaxItemsPerBooking} stays.");

        var today = Today;
        foreach (var item in dto.Items)
        {
            var nights = item.CheckOut.DayNumber - item.CheckIn.DayNumber;
            if (nights < 1)
                return ServiceResult<BookingResponseDto>.Invalid("Check-out must be after check-in.");
            if (nights > AccommodationService.MaxStayNights)
                return ServiceResult<BookingResponseDto>.Invalid(
                    $"A stay can be at most {AccommodationService.MaxStayNights} nights.");
            if (item.CheckIn < today)
                return ServiceResult<BookingResponseDto>.Invalid("Check-in cannot be in the past.");
            if (item.Rooms < 1 || item.Rooms > AccommodationService.MaxRoomsPerBooking)
                return ServiceResult<BookingResponseDto>.Invalid(
                    $"Book between 1 and {AccommodationService.MaxRoomsPerBooking} rooms per stay.");
            if (item.Guests < 1)
                return ServiceResult<BookingResponseDto>.Invalid("At least one guest is needed.");
        }

        return null;
    }

    /// <summary>One attempt. <c>raced</c> is true when someone else changed the nights first.</summary>
    private async Task<(ServiceResult<BookingResponseDto>? Result, bool Raced)> TryCreateAsync(
        Guid travelerId, CreateBookingDto dto)
    {
        var trip = await _db.Trips.AsNoTracking()
            .FirstOrDefaultAsync(t => t.Id == dto.TripId && t.TravelerId == travelerId);
        if (trip is null)
            return (ServiceResult<BookingResponseDto>.NotFound("Trip not found."), false);
        if (trip.Status == TripStatus.Cancelled)
            return (ServiceResult<BookingResponseDto>.Invalid("This trip is cancelled."), false);

        var accommodationIds = dto.Items.Select(i => i.AccommodationId).Distinct().ToList();
        var accommodations = await _db.Accommodations.AsNoTracking()
            .Include(a => a.Destination)
            .Where(a => accommodationIds.Contains(a.Id) && a.IsActive)
            .ToDictionaryAsync(a => a.Id);

        foreach (var item in dto.Items)
        {
            if (!accommodations.TryGetValue(item.AccommodationId, out var stay))
                return (ServiceResult<BookingResponseDto>.NotFound(
                    "An accommodation in your booking was not found or is no longer offered."), false);

            var capacity = item.Rooms * stay.MaxGuestsPerRoom;
            if (item.Guests > capacity)
                return (ServiceResult<BookingResponseDto>.Invalid(
                    $"{stay.Name} sleeps at most {capacity} guest(s) with {item.Rooms} room(s)."), false);
        }

        // Load (and track) every night we are about to touch. Items that share a night see each
        // other's reservations because they share these tracked rows.
        var firstNight = dto.Items.Min(i => i.CheckIn);
        var lastCheckOut = dto.Items.Max(i => i.CheckOut);
        var rows = await _db.Availabilities
            .Where(a => accommodationIds.Contains(a.AccommodationId) && a.Date >= firstNight && a.Date < lastCheckOut)
            .ToDictionaryAsync(a => (a.AccommodationId, a.Date));

        var now = _clock.GetUtcNow().UtcDateTime;
        var booking = new Booking
        {
            Id = Guid.NewGuid(),
            TravelerId = travelerId,
            TripId = trip.Id,
            Status = BookingStatus.Confirmed,
            Notes = string.IsNullOrWhiteSpace(dto.Notes) ? null : dto.Notes.Trim(),
            CreatedAt = now,
            UpdatedAt = now
        };

        foreach (var item in dto.Items)
        {
            var stay = accommodations[item.AccommodationId];
            var nights = item.CheckOut.DayNumber - item.CheckIn.DayNumber;

            for (var date = item.CheckIn; date < item.CheckOut; date = date.AddDays(1))
            {
                if (!rows.TryGetValue((stay.Id, date), out var night) || night.AvailableRooms < item.Rooms)
                {
                    return (ServiceResult<BookingResponseDto>.Conflict(
                        $"{stay.Name} does not have {item.Rooms} room(s) free on {date:yyyy-MM-dd}."), false);
                }

                night.BookedRooms += item.Rooms;
                night.Version++;
            }

            booking.Items.Add(new BookingItem
            {
                Id = Guid.NewGuid(),
                BookingId = booking.Id,
                AccommodationId = stay.Id,
                CheckIn = item.CheckIn,
                CheckOut = item.CheckOut,
                Rooms = item.Rooms,
                Guests = item.Guests,
                NightlyRate = stay.PricePerNight,
                Subtotal = stay.PricePerNight * nights * item.Rooms
            });
        }

        booking.TotalAmount = booking.Items.Sum(i => i.Subtotal);
        _db.Bookings.Add(booking);

        try
        {
            // One save: the booking, its items and the reserved rooms are stored together.
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateConcurrencyException)
        {
            return (null, true);
        }
        catch (DbUpdateException)
        {
            // The database's own overbooking check fired: someone else took the rooms.
            return (null, true);
        }

        var saved = await LoadFullAsync(booking.Id);
        return (ServiceResult<BookingResponseDto>.Ok(MapToDto(saved!)), false);
    }

    // ---- Read ---------------------------------------------------------------------------

    public async Task<List<BookingResponseDto>> GetMineAsync(Guid travelerId)
    {
        var bookings = await FullQuery()
            .Where(b => b.TravelerId == travelerId)
            .OrderByDescending(b => b.CreatedAt)
            .ToListAsync();

        return bookings.Select(MapToDto).ToList();
    }

    public async Task<PagedResult<BookingResponseDto>> GetAllAsync(BookingQueryParams q)
    {
        var page = Math.Max(q.Page, 1);
        var pageSize = Math.Clamp(q.PageSize, 1, MaxPageSize);

        var query = FullQuery();

        if (!string.IsNullOrWhiteSpace(q.Status))
        {
            // An unknown status can match nothing.
            if (!Enum.TryParse<BookingStatus>(q.Status, ignoreCase: true, out var status))
            {
                return new PagedResult<BookingResponseDto> { Page = page, PageSize = pageSize };
            }
            query = query.Where(b => b.Status == status);
        }

        if (q.TripId.HasValue)
            query = query.Where(b => b.TripId == q.TripId.Value);

        if (q.AccommodationId.HasValue)
            query = query.Where(b => b.Items.Any(i => i.AccommodationId == q.AccommodationId.Value));

        var total = await query.CountAsync();
        var items = await query
            .OrderByDescending(b => b.CreatedAt)
            .ThenBy(b => b.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return new PagedResult<BookingResponseDto>
        {
            Items = items.Select(MapToDto).ToList(),
            TotalCount = total,
            Page = page,
            PageSize = pageSize
        };
    }

    public async Task<ServiceResult<BookingResponseDto>> GetByIdAsync(Guid id, Guid userId, bool isStaff)
    {
        var booking = await LoadFullAsync(id);
        if (booking is null)
            return ServiceResult<BookingResponseDto>.NotFound("Booking not found.");
        if (!isStaff && booking.TravelerId != userId)
            return ServiceResult<BookingResponseDto>.Forbidden("This booking belongs to another traveler.");

        return ServiceResult<BookingResponseDto>.Ok(MapToDto(booking));
    }

    // ---- Cancel -------------------------------------------------------------------------

    public async Task<ServiceResult<BookingResponseDto>> CancelAsync(Guid id, Guid userId, bool isStaff)
    {
        for (var attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            _db.ChangeTracker.Clear();

            var booking = await _db.Bookings.Include(b => b.Items).FirstOrDefaultAsync(b => b.Id == id);
            if (booking is null)
                return ServiceResult<BookingResponseDto>.NotFound("Booking not found.");
            if (!isStaff && booking.TravelerId != userId)
                return ServiceResult<BookingResponseDto>.Forbidden("This booking belongs to another traveler.");
            if (booking.Status != BookingStatus.Confirmed)
                return ServiceResult<BookingResponseDto>.Conflict("This booking is already cancelled.");

            // Travelers can back out until the first stay begins; staff can step in later.
            var firstCheckIn = booking.Items.Min(i => i.CheckIn);
            if (!isStaff && firstCheckIn <= Today)
                return ServiceResult<BookingResponseDto>.Invalid(
                    "This booking can no longer be cancelled because the first stay has started.");

            var accommodationIds = booking.Items.Select(i => i.AccommodationId).Distinct().ToList();
            var lastCheckOut = booking.Items.Max(i => i.CheckOut);
            var rows = await _db.Availabilities
                .Where(a => accommodationIds.Contains(a.AccommodationId) && a.Date >= firstCheckIn && a.Date < lastCheckOut)
                .ToDictionaryAsync(a => (a.AccommodationId, a.Date));

            // Give every reserved room back.
            foreach (var item in booking.Items)
            {
                for (var date = item.CheckIn; date < item.CheckOut; date = date.AddDays(1))
                {
                    if (!rows.TryGetValue((item.AccommodationId, date), out var night)) continue;
                    night.BookedRooms = Math.Max(0, night.BookedRooms - item.Rooms);
                    night.Version++;
                }
            }

            var now = _clock.GetUtcNow().UtcDateTime;
            booking.Status = BookingStatus.Cancelled;
            booking.CancelledAt = now;
            booking.UpdatedAt = now;

            try
            {
                await _db.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                continue; // inventory moved under us: redo from fresh numbers
            }

            return ServiceResult<BookingResponseDto>.Ok(MapToDto((await LoadFullAsync(id))!));
        }

        return ServiceResult<BookingResponseDto>.Conflict(
            "Availability changed while cancelling. Please try again.");
    }

    // ---- Helpers ------------------------------------------------------------------------

    private IQueryable<Booking> FullQuery() =>
        _db.Bookings.AsNoTracking()
            .Include(b => b.Traveler)
            .Include(b => b.Trip)
            .Include(b => b.Items).ThenInclude(i => i.Accommodation).ThenInclude(a => a.Destination);

    private Task<Booking?> LoadFullAsync(Guid id) =>
        FullQuery().FirstOrDefaultAsync(b => b.Id == id);

    private static BookingResponseDto MapToDto(Booking b) => new()
    {
        Id = b.Id,
        TripId = b.TripId,
        TripTitle = b.Trip?.Title ?? string.Empty,
        TravelerId = b.TravelerId,
        TravelerName = b.Traveler?.FullName ?? string.Empty,
        Status = b.Status.ToString(),
        TotalAmount = b.TotalAmount,
        Notes = b.Notes,
        CreatedAt = b.CreatedAt,
        CancelledAt = b.CancelledAt,
        Items = b.Items
            .OrderBy(i => i.CheckIn)
            .ThenBy(i => i.Id)
            .Select(i => new BookingItemResponseDto
            {
                Id = i.Id,
                AccommodationId = i.AccommodationId,
                AccommodationName = i.Accommodation?.Name ?? string.Empty,
                DestinationName = i.Accommodation?.Destination?.Name ?? string.Empty,
                CheckIn = i.CheckIn,
                CheckOut = i.CheckOut,
                Nights = i.Nights,
                Rooms = i.Rooms,
                Guests = i.Guests,
                NightlyRate = i.NightlyRate,
                Subtotal = i.Subtotal
            })
            .ToList()
    };
}
