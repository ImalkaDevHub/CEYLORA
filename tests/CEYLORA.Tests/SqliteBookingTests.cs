using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Bookings;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using CEYLORA.Infrastructure.Services;
using CEYLORA.Tests.Support;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Tests;

/// <summary>
/// The same booking rules on a real relational engine (SQLite). The in-memory provider has no
/// transactions or constraints, so this is where "all or nothing" and "the database itself
/// refuses overbooking" are actually proven.
/// </summary>
public class SqliteBookingTests : IDisposable
{
    private static readonly DateOnly Nov1 = BookingFixture.Nov1;

    private readonly SqliteConnection _connection;
    private readonly RaceInterceptor _race = new();
    private readonly DbContextOptions<ApplicationDbContext> _options;
    private readonly ApplicationDbContext _db;
    private readonly BookingService _bookings;
    private readonly TestClock _clock = new(new DateTimeOffset(2026, 10, 20, 10, 0, 0, TimeSpan.Zero));

    private readonly Guid _samId = Guid.NewGuid();
    private readonly Guid _tripId = Guid.NewGuid();
    private readonly Guid _stayId = Guid.NewGuid();
    private readonly Guid _destinationId = Guid.NewGuid();

    public SqliteBookingTests()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open(); // the in-memory database lives as long as this connection

        _options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseSqlite(_connection)
            .AddInterceptors(_race)
            .Options;
        _db = new ApplicationDbContext(_options);
        _db.Database.EnsureCreated();

        _db.Users.Add(new User
        {
            Id = _samId, Email = "sam@example.com", FullName = "Sam", PasswordHash = "x",
            RoleId = BookingFixture.TravelerRoleId
        });
        _db.Destinations.Add(new Destination
        {
            Id = _destinationId, Name = "Galle Fort", Region = "South", Description = "d",
            Category = TravelCategory.Culture
        });
        _db.Trips.Add(new Trip
        {
            Id = _tripId, TravelerId = _samId, Title = "Trip",
            StartDate = new DateTime(2026, 11, 1, 0, 0, 0, DateTimeKind.Utc),
            EndDate = new DateTime(2026, 11, 3, 0, 0, 0, DateTimeKind.Utc), Budget = 1000m
        });
        _db.Accommodations.Add(new Accommodation
        {
            Id = _stayId, DestinationId = _destinationId, Name = "Sea View", Description = "d",
            Type = AccommodationType.Hotel, PricePerNight = 20000m, MaxGuestsPerRoom = 2
        });
        for (var i = 0; i < 5; i++)
        {
            _db.Availabilities.Add(new Availability
            {
                Id = Guid.NewGuid(), AccommodationId = _stayId, Date = Nov1.AddDays(i), TotalRooms = 2
            });
        }
        _db.SaveChanges();

        _bookings = new BookingService(_db, _clock);
    }

    public void Dispose()
    {
        _db.Dispose();
        _connection.Dispose();
    }

    private ApplicationDbContext NewContext() => new(_options);

    private CreateBookingDto Request(int rooms, int nights = 2) => new()
    {
        TripId = _tripId,
        Items = new()
        {
            new() { AccommodationId = _stayId, CheckIn = Nov1, CheckOut = Nov1.AddDays(nights), Rooms = rooms, Guests = rooms }
        }
    };

    [Fact]
    public async Task Booking_ReservesRoomsAndStoresEverythingTogether()
    {
        var result = await _bookings.CreateAsync(_samId, Request(rooms: 2));

        Assert.True(result.Succeeded, result.Message);
        using var ctx = NewContext();
        Assert.Equal(1, ctx.Bookings.Count());
        Assert.Equal(1, ctx.BookingItems.Count());
        Assert.Equal(new[] { 2, 2, 0 }, ctx.Availabilities.OrderBy(a => a.Date).Take(3).Select(a => a.BookedRooms).ToArray());
        Assert.Equal(40000m * 2, (await _bookings.GetMineAsync(_samId)).Single().TotalAmount);
    }

    [Fact]
    public async Task ARaceForTheLastRoom_RollsTheWholeBookingBack()
    {
        // After Sam's service read two free rooms but before it saves, another traveler books one.
        _race.BeforeNextSave = () =>
        {
            using var other = NewContext();
            var night = other.Availabilities.Single(a => a.AccommodationId == _stayId && a.Date == Nov1);
            night.BookedRooms += 1;
            night.Version++;
            other.SaveChanges();
        };

        var result = await _bookings.CreateAsync(_samId, Request(rooms: 2, nights: 1));

        Assert.Equal(ServiceError.Conflict, result.Error);
        using var ctx = NewContext();
        // Atomic: no booking, no items, and the other traveler's single room is all that is held.
        Assert.Equal(0, ctx.Bookings.Count());
        Assert.Equal(0, ctx.BookingItems.Count());
        Assert.Equal(1, ctx.Availabilities.Single(a => a.Date == Nov1).BookedRooms);
    }

    [Fact]
    public async Task ARaceThatLeavesRoom_IsRetriedAndStillBooks()
    {
        _race.BeforeNextSave = () =>
        {
            using var other = NewContext();
            var night = other.Availabilities.Single(a => a.AccommodationId == _stayId && a.Date == Nov1);
            night.BookedRooms += 1;
            night.Version++;
            other.SaveChanges();
        };

        var result = await _bookings.CreateAsync(_samId, Request(rooms: 1, nights: 1));

        Assert.True(result.Succeeded, result.Message);
        using var ctx = NewContext();
        Assert.Equal(1, ctx.Bookings.Count());
        Assert.Equal(2, ctx.Availabilities.Single(a => a.Date == Nov1).BookedRooms);
    }

    [Fact]
    public async Task Cancel_GivesTheRoomsBack()
    {
        var booked = await _bookings.CreateAsync(_samId, Request(rooms: 2));

        var cancelled = await _bookings.CancelAsync(booked.Value!.Id, _samId, isStaff: false);

        Assert.True(cancelled.Succeeded);
        using var ctx = NewContext();
        Assert.All(ctx.Availabilities.ToList(), a => Assert.Equal(0, a.BookedRooms));
    }

    // ---- Constraints the database enforces on its own --------------------------------------

    [Fact]
    public void TheDatabaseRefusesMoreBookedRoomsThanExist()
    {
        using var ctx = NewContext();
        var night = ctx.Availabilities.First();
        night.BookedRooms = night.TotalRooms + 1;

        Assert.Throws<DbUpdateException>(() => ctx.SaveChanges());
    }

    [Fact]
    public void TheDatabaseRefusesANegativeBookedCount()
    {
        using var ctx = NewContext();
        ctx.Availabilities.First().BookedRooms = -1;

        Assert.Throws<DbUpdateException>(() => ctx.SaveChanges());
    }

    [Fact]
    public void TheDatabaseRefusesTwoInventoryRowsForTheSameNight()
    {
        using var ctx = NewContext();
        ctx.Availabilities.Add(new Availability
        {
            Id = Guid.NewGuid(), AccommodationId = _stayId, Date = Nov1, TotalRooms = 9
        });

        Assert.Throws<DbUpdateException>(() => ctx.SaveChanges());
    }

    [Fact]
    public void TheDatabaseRefusesTwoStaysWithTheSameNameInADestination()
    {
        using var ctx = NewContext();
        ctx.Accommodations.Add(new Accommodation
        {
            Id = Guid.NewGuid(), DestinationId = _destinationId, Name = "Sea View", Description = "d",
            PricePerNight = 1m, MaxGuestsPerRoom = 1
        });

        Assert.Throws<DbUpdateException>(() => ctx.SaveChanges());
    }

    [Fact]
    public void TheDatabaseRefusesABookingItemThatEndsBeforeItStarts()
    {
        var booking = new Booking { Id = Guid.NewGuid(), TravelerId = _samId, TripId = _tripId };
        booking.Items.Add(new BookingItem
        {
            Id = Guid.NewGuid(), AccommodationId = _stayId, CheckIn = Nov1, CheckOut = Nov1,
            Rooms = 1, Guests = 1, NightlyRate = 1m, Subtotal = 1m
        });
        using var ctx = NewContext();
        ctx.Bookings.Add(booking);

        Assert.Throws<DbUpdateException>(() => ctx.SaveChanges());
    }

    [Theory]
    [InlineData(0)]
    [InlineData(6)]
    public void TheDatabaseRefusesRatingsOutsideOneToFive(int rating)
    {
        var booking = new Booking { Id = Guid.NewGuid(), TravelerId = _samId, TripId = _tripId };
        using var ctx = NewContext();
        ctx.Bookings.Add(booking);
        ctx.Reviews.Add(new Review
        {
            Id = Guid.NewGuid(), AccommodationId = _stayId, TravelerId = _samId, BookingId = booking.Id,
            Rating = rating, Comment = "x"
        });

        Assert.Throws<DbUpdateException>(() => ctx.SaveChanges());
    }

    [Fact]
    public void TheDatabaseRefusesASecondReviewByTheSameTravelerForTheSameStay()
    {
        var booking = new Booking { Id = Guid.NewGuid(), TravelerId = _samId, TripId = _tripId };
        using (var ctx = NewContext())
        {
            ctx.Bookings.Add(booking);
            ctx.Reviews.Add(new Review
            {
                Id = Guid.NewGuid(), AccommodationId = _stayId, TravelerId = _samId, BookingId = booking.Id,
                Rating = 5, Comment = "great"
            });
            ctx.SaveChanges();
        }

        using var second = NewContext();
        second.Reviews.Add(new Review
        {
            Id = Guid.NewGuid(), AccommodationId = _stayId, TravelerId = _samId, BookingId = booking.Id,
            Rating = 1, Comment = "again"
        });

        Assert.Throws<DbUpdateException>(() => second.SaveChanges());
    }
}
