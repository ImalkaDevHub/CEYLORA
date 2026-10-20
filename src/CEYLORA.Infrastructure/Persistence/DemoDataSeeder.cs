using CEYLORA.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Infrastructure.Persistence;

/// <summary>
/// Fills an empty database with a believable Sri Lanka catalogue so the apps have something
/// to browse and book: destinations, experiences, accommodations and 120 nights of room
/// inventory. Strictly opt-in (<c>Seed:DemoData=true</c>) and additive: it never changes or
/// deletes existing rows, and does nothing once accommodations exist.
/// </summary>
public static class DemoDataSeeder
{
    public const int AvailabilityNights = 120;
    public const int MaxDestinationsToStock = 6;

    private static readonly (string Name, string Region, TravelCategory Category, string Blurb)[] Destinations =
    {
        ("Galle Fort", "Southern Province", TravelCategory.Culture, "A walled Dutch-era fort town above the Indian Ocean."),
        ("Mirissa", "Southern Province", TravelCategory.Beach, "Palm-lined beaches and whale watching."),
        ("Ella", "Uva Province", TravelCategory.Nature, "Tea hills, waterfalls and the Nine Arch Bridge."),
        ("Sigiriya", "Central Province", TravelCategory.Culture, "The Lion Rock fortress and ancient frescoes."),
        ("Yala", "Southern Province", TravelCategory.Wildlife, "Leopard safaris in Sri Lanka's best-known national park."),
        ("Colombo", "Western Province", TravelCategory.CityLife, "Markets, colonial architecture and street food.")
    };

    // One entry per kind of stay offered at every stocked destination.
    private static readonly (string Suffix, AccommodationType Type, decimal Price, int GuestsPerRoom, int Rooms, string Blurb)[] Stays =
    {
        ("Grand Hotel", AccommodationType.Hotel, 18000m, 2, 6, "Comfortable rooms with breakfast included."),
        ("Guesthouse", AccommodationType.Guesthouse, 7500m, 2, 4, "A friendly family-run place close to the sights."),
        ("Retreat Villa", AccommodationType.Villa, 26000m, 4, 2, "A private villa with a garden, sleeps four per room.")
    };

    /// <returns>How many accommodations were created (0 when the database was already stocked).</returns>
    public static async Task<int> SeedAsync(ApplicationDbContext db, TimeProvider clock, CancellationToken ct = default)
    {
        if (await db.Accommodations.AnyAsync(ct)) return 0;

        var now = clock.GetUtcNow().UtcDateTime;
        var today = DateOnly.FromDateTime(now);

        // Use the destinations that already exist; only invent some when there are none.
        var destinations = await db.Destinations.Where(d => d.IsActive)
            .OrderBy(d => d.Name).Take(MaxDestinationsToStock).ToListAsync(ct);

        if (destinations.Count == 0)
        {
            foreach (var (name, region, category, blurb) in Destinations)
            {
                var destination = new Destination
                {
                    Id = Guid.NewGuid(), Name = name, Region = region, Description = blurb,
                    Category = category, IsActive = true, CreatedAt = now, UpdatedAt = now
                };
                destination.Experiences.Add(new Experience
                {
                    Id = Guid.NewGuid(), DestinationId = destination.Id, Name = $"Guided {name} walk",
                    Description = $"A local guide shows you the best of {name}.", Price = 4500m,
                    DurationHours = 3, Category = category, IsActive = true, CreatedAt = now
                });
                destination.Experiences.Add(new Experience
                {
                    Id = Guid.NewGuid(), DestinationId = destination.Id, Name = $"{name} sunset experience",
                    Description = $"An evening in {name} with dinner included.", Price = 9000m,
                    DurationHours = 4, Category = category, IsActive = true, CreatedAt = now
                });
                db.Destinations.Add(destination);
                destinations.Add(destination);
            }
        }

        var created = 0;
        foreach (var destination in destinations)
        {
            foreach (var (suffix, type, price, guests, rooms, blurb) in Stays)
            {
                var stay = new Accommodation
                {
                    Id = Guid.NewGuid(),
                    DestinationId = destination.Id,
                    Name = $"{destination.Name} {suffix}",
                    Description = blurb,
                    Type = type,
                    PricePerNight = price,
                    MaxGuestsPerRoom = guests,
                    IsActive = true,
                    CreatedAt = now,
                    UpdatedAt = now
                };
                db.Accommodations.Add(stay);

                for (var i = 0; i < AvailabilityNights; i++)
                {
                    db.Availabilities.Add(new Availability
                    {
                        Id = Guid.NewGuid(), AccommodationId = stay.Id, Date = today.AddDays(i),
                        TotalRooms = rooms, BookedRooms = 0, Version = 0
                    });
                }
                created++;
            }
        }

        await db.SaveChangesAsync(ct);
        return created;
    }
}
