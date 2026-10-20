using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using CEYLORA.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Update;

namespace CEYLORA.Tests.Support;

/// <summary>A clock the test can move.</summary>
public sealed class TestClock : TimeProvider
{
    private DateTimeOffset _now;
    public TestClock(DateTimeOffset now) => _now = now;
    public void Set(DateTimeOffset now) => _now = now;
    public override DateTimeOffset GetUtcNow() => _now;
}

/// <summary>
/// Simulates other travelers (or a flaky database) interfering with a save, so the
/// retry and overbooking paths can be tested deterministically.
/// </summary>
public sealed class RaceInterceptor : SaveChangesInterceptor
{
    /// <summary>Throw a concurrency conflict from this many upcoming async saves.</summary>
    public int FailConcurrencyTimes { get; set; }

    /// <summary>Runs once, just before the next async save (e.g. "someone else books the last room").</summary>
    public Action? BeforeNextSave { get; set; }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        if (BeforeNextSave is { } hook)
        {
            BeforeNextSave = null;
            hook();
        }

        if (FailConcurrencyTimes > 0)
        {
            FailConcurrencyTimes--;
            throw new DbUpdateConcurrencyException("simulated race", Array.Empty<IUpdateEntry>());
        }

        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }
}

/// <summary>
/// One in-memory database with a small world: two travelers (Sam, Kim), an operator, two
/// destinations, a trip each, and one accommodation (Sea View) with 2 rooms free every night
/// from 1 to 10 November 2026. "Today" is 20 October 2026.
/// </summary>
public sealed class BookingFixture : IDisposable
{
    public static readonly DateOnly Today = new(2026, 10, 20);
    public static readonly DateOnly Nov1 = new(2026, 11, 1);
    public static readonly Guid TravelerRoleId = new("c023fa33-20bf-4166-b56c-aeb11838c85c");

    private readonly DbContextOptions<ApplicationDbContext> _options;

    public TestClock Clock { get; } = new(new DateTimeOffset(2026, 10, 20, 10, 0, 0, TimeSpan.Zero));
    public RaceInterceptor Race { get; } = new();
    public ApplicationDbContext Db { get; }

    public AccommodationService Accommodations { get; }
    public BookingService Bookings { get; }
    public ReviewService Reviews { get; }

    public User Sam { get; }
    public User Kim { get; }
    public User Olu { get; }
    public Destination Galle { get; }
    public Destination Ella { get; }
    public Trip SamTrip { get; }
    public Trip KimTrip { get; }
    public Accommodation SeaView { get; }

    public BookingFixture()
    {
        _options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .AddInterceptors(Race)
            .Options;
        Db = new ApplicationDbContext(_options);
        Db.Database.EnsureCreated();

        Sam = AddUser("sam@example.com", "Sam Traveler");
        Kim = AddUser("kim@example.com", "Kim Traveler");
        Olu = AddUser("olu@example.com", "Olu Operator");

        Galle = AddDestination("Galle Fort");
        Ella = AddDestination("Ella");

        SamTrip = AddTrip(Sam, "Sam's south coast trip");
        KimTrip = AddTrip(Kim, "Kim's hill country trip");

        SeaView = AddAccommodation(Galle, "Sea View", 20000m, maxGuestsPerRoom: 2);
        SetRooms(SeaView, Nov1, Nov1.AddDays(9), totalRooms: 2); // nights 1..10 Nov

        Accommodations = new AccommodationService(Db, Clock);
        Bookings = new BookingService(Db, Clock);
        Reviews = new ReviewService(Db, Clock);
    }

    public void Dispose() => Db.Dispose();

    /// <summary>A separate context on the same data, to see what was really saved.</summary>
    public ApplicationDbContext NewContext() => new(_options);

    public User AddUser(string email, string name)
    {
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            FullName = name,
            PasswordHash = "x",
            RoleId = TravelerRoleId
        };
        Db.Users.Add(user);
        Db.SaveChanges();
        return user;
    }

    public Destination AddDestination(string name, bool active = true)
    {
        var d = new Destination
        {
            Id = Guid.NewGuid(),
            Name = name,
            Region = "Sri Lanka",
            Description = name + " description",
            Category = TravelCategory.Culture,
            IsActive = active
        };
        Db.Destinations.Add(d);
        Db.SaveChanges();
        return d;
    }

    public Trip AddTrip(User traveler, string title, TripStatus status = TripStatus.Draft)
    {
        var t = new Trip
        {
            Id = Guid.NewGuid(),
            TravelerId = traveler.Id,
            Title = title,
            StartDate = new DateTime(2026, 11, 1, 0, 0, 0, DateTimeKind.Utc),
            EndDate = new DateTime(2026, 11, 5, 0, 0, 0, DateTimeKind.Utc),
            Budget = 200000m,
            Status = status
        };
        Db.Trips.Add(t);
        Db.SaveChanges();
        return t;
    }

    public Accommodation AddAccommodation(
        Destination destination, string name, decimal price,
        int maxGuestsPerRoom = 2, AccommodationType type = AccommodationType.Hotel, bool active = true)
    {
        var a = new Accommodation
        {
            Id = Guid.NewGuid(),
            DestinationId = destination.Id,
            Name = name,
            Description = name + " description",
            Type = type,
            PricePerNight = price,
            MaxGuestsPerRoom = maxGuestsPerRoom,
            IsActive = active
        };
        Db.Accommodations.Add(a);
        Db.SaveChanges();
        return a;
    }

    public void SetRooms(Accommodation accommodation, DateOnly from, DateOnly to, int totalRooms)
    {
        for (var d = from; d <= to; d = d.AddDays(1))
        {
            Db.Availabilities.Add(new Availability
            {
                Id = Guid.NewGuid(),
                AccommodationId = accommodation.Id,
                Date = d,
                TotalRooms = totalRooms
            });
        }
        Db.SaveChanges();
    }

    /// <summary>What is stored for one night, read through a fresh context.</summary>
    public Availability Night(Accommodation accommodation, DateOnly date)
    {
        using var ctx = NewContext();
        return ctx.Availabilities.Single(a => a.AccommodationId == accommodation.Id && a.Date == date);
    }

    public int BookedRooms(Accommodation accommodation, DateOnly date) => Night(accommodation, date).BookedRooms;

    public int BookingCount()
    {
        using var ctx = NewContext();
        return ctx.Bookings.Count();
    }

    public void MoveClockTo(DateOnly date) =>
        Clock.Set(new DateTimeOffset(date.ToDateTime(new TimeOnly(10, 0)), TimeSpan.Zero));
}
