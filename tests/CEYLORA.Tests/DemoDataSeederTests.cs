using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using CEYLORA.Tests.Support;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Tests;

public class DemoDataSeederTests
{
    private static readonly TestClock Clock = new(new DateTimeOffset(2026, 10, 20, 10, 0, 0, TimeSpan.Zero));

    private static ApplicationDbContext NewDb()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        var db = new ApplicationDbContext(options);
        db.Database.EnsureCreated();
        return db;
    }

    [Fact]
    public async Task OnAnEmptyDatabase_CreatesDestinationsExperiencesStaysAndInventory()
    {
        using var db = NewDb();

        var created = await DemoDataSeeder.SeedAsync(db, Clock);

        Assert.Equal(18, created); // 6 destinations x 3 stays
        Assert.Equal(6, db.Destinations.Count());
        Assert.Equal(12, db.Experiences.Count());
        Assert.Equal(18, db.Accommodations.Count());
        Assert.Equal(18 * DemoDataSeeder.AvailabilityNights, db.Availabilities.Count());
    }

    [Fact]
    public async Task InventoryStartsToday_AndRunsForTheWholeWindow_WithNothingBooked()
    {
        using var db = NewDb();
        await DemoDataSeeder.SeedAsync(db, Clock);

        var stay = db.Accommodations.First();
        var nights = db.Availabilities.Where(a => a.AccommodationId == stay.Id).OrderBy(a => a.Date).ToList();

        Assert.Equal(BookingFixture.Today, nights.First().Date);
        Assert.Equal(BookingFixture.Today.AddDays(DemoDataSeeder.AvailabilityNights - 1), nights.Last().Date);
        Assert.All(nights, n => { Assert.Equal(0, n.BookedRooms); Assert.True(n.TotalRooms > 0); });
    }

    [Fact]
    public async Task StayNamesAreUniquePerDestination()
    {
        using var db = NewDb();
        await DemoDataSeeder.SeedAsync(db, Clock);

        var clashes = db.Accommodations.AsEnumerable()
            .GroupBy(a => (a.DestinationId, a.Name.ToLower()))
            .Where(g => g.Count() > 1);
        Assert.Empty(clashes);
    }

    [Fact]
    public async Task RunningTwice_DoesNothingTheSecondTime()
    {
        using var db = NewDb();
        await DemoDataSeeder.SeedAsync(db, Clock);

        var again = await DemoDataSeeder.SeedAsync(db, Clock);

        Assert.Equal(0, again);
        Assert.Equal(18, db.Accommodations.Count());
        Assert.Equal(6, db.Destinations.Count());
    }

    [Fact]
    public async Task WhenDestinationsAlreadyExist_StocksThoseAndInventsNone()
    {
        using var db = NewDb();
        db.Destinations.Add(new Destination { Id = Guid.NewGuid(), Name = "My Own Place", Region = "X", Description = "d", Category = TravelCategory.Nature });
        await db.SaveChangesAsync();

        var created = await DemoDataSeeder.SeedAsync(db, Clock);

        Assert.Equal(3, created);
        Assert.Equal(1, db.Destinations.Count());
        Assert.Equal(0, db.Experiences.Count());
        Assert.All(db.Accommodations.ToList(), a => Assert.StartsWith("My Own Place ", a.Name));
    }

    [Fact]
    public async Task InactiveDestinationsAreNotStocked_SoSeedingMakesNewOnes()
    {
        using var db = NewDb();
        db.Destinations.Add(new Destination { Id = Guid.NewGuid(), Name = "Closed", Region = "X", Description = "d", IsActive = false });
        await db.SaveChangesAsync();

        await DemoDataSeeder.SeedAsync(db, Clock);

        Assert.DoesNotContain(db.Accommodations.ToList(), a => a.Name.StartsWith("Closed "));
    }

    [Fact]
    public async Task NeverStocksMoreThanTheCap()
    {
        using var db = NewDb();
        for (var i = 0; i < 9; i++)
            db.Destinations.Add(new Destination { Id = Guid.NewGuid(), Name = $"Place {i}", Region = "X", Description = "d" });
        await db.SaveChangesAsync();

        var created = await DemoDataSeeder.SeedAsync(db, Clock);

        Assert.Equal(DemoDataSeeder.MaxDestinationsToStock * 3, created);
    }

    [Fact]
    public async Task ExistingAccommodations_AreLeftAlone()
    {
        using var db = NewDb();
        var dest = new Destination { Id = Guid.NewGuid(), Name = "Real", Region = "X", Description = "d" };
        db.Destinations.Add(dest);
        db.Accommodations.Add(new Accommodation { Id = Guid.NewGuid(), DestinationId = dest.Id, Name = "Mine", PricePerNight = 1m, MaxGuestsPerRoom = 1 });
        await db.SaveChangesAsync();

        var created = await DemoDataSeeder.SeedAsync(db, Clock);

        Assert.Equal(0, created);
        Assert.Equal("Mine", Assert.Single(db.Accommodations).Name);
        Assert.Empty(db.Availabilities);
    }
}
