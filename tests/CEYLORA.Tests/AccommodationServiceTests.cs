using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Accommodations;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Services;
using CEYLORA.Tests.Support;

namespace CEYLORA.Tests;

public class AccommodationServiceTests : IDisposable
{
    private readonly BookingFixture _f = new();
    public void Dispose() => _f.Dispose();

    private static CreateAccommodationDto NewStay(Guid destinationId, string name = "Palm Villa",
        decimal price = 15000m, AccommodationType type = AccommodationType.Villa, int guests = 3) => new()
    {
        DestinationId = destinationId,
        Name = name,
        Description = "  A quiet villa  ",
        Type = type,
        PricePerNight = price,
        MaxGuestsPerRoom = guests
    };

    // ---- Create / update / deactivate -----------------------------------------------------

    [Fact]
    public async Task Create_StoresTheStayAndReportsItsDestination()
    {
        var result = await _f.Accommodations.CreateAsync(NewStay(_f.Ella.Id));

        Assert.True(result.Succeeded);
        var dto = result.Value!;
        Assert.Equal("Palm Villa", dto.Name);
        Assert.Equal("Ella", dto.DestinationName);
        Assert.Equal("A quiet villa", dto.Description); // trimmed
        Assert.Equal("Villa", dto.Type);
        Assert.True(dto.IsActive);
        Assert.Null(dto.AverageRating);
        Assert.Equal(0, dto.ReviewCount);
    }

    [Fact]
    public async Task Create_WithAnUnknownDestination_IsInvalid()
    {
        var result = await _f.Accommodations.CreateAsync(NewStay(Guid.NewGuid()));

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Create_WithAnInactiveDestination_IsInvalid()
    {
        var closed = _f.AddDestination("Closed Cove", active: false);

        var result = await _f.Accommodations.CreateAsync(NewStay(closed.Id));

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Create_RejectsTheSameNameInTheSameDestination_IgnoringCase()
    {
        var clash = await _f.Accommodations.CreateAsync(NewStay(_f.Galle.Id, name: "  sea VIEW "));

        Assert.Equal(ServiceError.Conflict, clash.Error);
    }

    [Fact]
    public async Task Create_AllowsTheSameNameInAnotherDestination()
    {
        var result = await _f.Accommodations.CreateAsync(NewStay(_f.Ella.Id, name: "Sea View"));

        Assert.True(result.Succeeded);
    }

    [Fact]
    public async Task Update_ChangesTheFields()
    {
        var update = new UpdateAccommodationDto
        {
            DestinationId = _f.Ella.Id,
            Name = "Sea View Deluxe",
            Description = "Renovated",
            Type = AccommodationType.Resort,
            PricePerNight = 30000m,
            MaxGuestsPerRoom = 4,
            IsActive = true
        };

        var result = await _f.Accommodations.UpdateAsync(_f.SeaView.Id, update);

        Assert.True(result.Succeeded);
        Assert.Equal("Sea View Deluxe", result.Value!.Name);
        Assert.Equal("Ella", result.Value.DestinationName);
        Assert.Equal(30000m, result.Value.PricePerNight);
        Assert.Equal("Resort", result.Value.Type);
        Assert.Equal(4, result.Value.MaxGuestsPerRoom);
    }

    [Fact]
    public async Task Update_KeepingItsOwnNameIsNotAConflict()
    {
        var update = new UpdateAccommodationDto
        {
            DestinationId = _f.Galle.Id,
            Name = "Sea View",
            PricePerNight = 25000m,
            MaxGuestsPerRoom = 2
        };

        var result = await _f.Accommodations.UpdateAsync(_f.SeaView.Id, update);

        Assert.True(result.Succeeded);
        Assert.Equal(25000m, result.Value!.PricePerNight);
    }

    [Fact]
    public async Task Update_CannotTakeAnotherStaysName()
    {
        var other = _f.AddAccommodation(_f.Galle, "Harbour Inn", 10000m);
        var update = new UpdateAccommodationDto
        {
            DestinationId = _f.Galle.Id,
            Name = "Sea View",
            PricePerNight = 10000m,
            MaxGuestsPerRoom = 2
        };

        var result = await _f.Accommodations.UpdateAsync(other.Id, update);

        Assert.Equal(ServiceError.Conflict, result.Error);
    }

    [Fact]
    public async Task Update_OfAnUnknownStay_IsNotFound()
    {
        var result = await _f.Accommodations.UpdateAsync(Guid.NewGuid(), new UpdateAccommodationDto
        {
            DestinationId = _f.Galle.Id, Name = "x", PricePerNight = 1, MaxGuestsPerRoom = 1
        });

        Assert.Equal(ServiceError.NotFound, result.Error);
    }

    [Fact]
    public async Task Deactivate_HidesTheStayFromTheListButKeepsIt()
    {
        Assert.True(await _f.Accommodations.DeactivateAsync(_f.SeaView.Id));

        var list = await _f.Accommodations.GetAccommodationsAsync(new AccommodationQueryParams());
        Assert.Empty(list.Items);

        var withInactive = await _f.Accommodations.GetAccommodationsAsync(
            new AccommodationQueryParams { IncludeInactive = true });
        Assert.Single(withInactive.Items);

        var stay = await _f.Accommodations.GetByIdAsync(_f.SeaView.Id);
        Assert.False(stay!.IsActive);
    }

    [Fact]
    public async Task Deactivate_OfAnUnknownStay_ReturnsFalse()
    {
        Assert.False(await _f.Accommodations.DeactivateAsync(Guid.NewGuid()));
    }

    [Fact]
    public async Task GetById_OfAnUnknownStay_ReturnsNull()
    {
        Assert.Null(await _f.Accommodations.GetByIdAsync(Guid.NewGuid()));
    }

    // ---- Search / filter / sort / paging ---------------------------------------------------

    private void SeedCatalogue()
    {
        _f.AddAccommodation(_f.Galle, "Fort Guesthouse", 8000m, type: AccommodationType.Guesthouse);
        _f.AddAccommodation(_f.Ella, "Mountain Resort", 45000m, type: AccommodationType.Resort);
        _f.AddAccommodation(_f.Ella, "Tea Hostel", 3000m, type: AccommodationType.Hostel);
    }

    private async Task<List<string>> Names(AccommodationQueryParams q) =>
        (await _f.Accommodations.GetAccommodationsAsync(q)).Items.Select(i => i.Name).ToList();

    [Fact]
    public async Task List_DefaultsToNameOrder()
    {
        SeedCatalogue();

        Assert.Equal(
            new[] { "Fort Guesthouse", "Mountain Resort", "Sea View", "Tea Hostel" },
            await Names(new AccommodationQueryParams()));
    }

    [Fact]
    public async Task List_SearchMatchesNameOrDestination_IgnoringCase()
    {
        SeedCatalogue();

        Assert.Equal(new[] { "Mountain Resort", "Tea Hostel" }, await Names(new AccommodationQueryParams { Search = "ELLA" }));
        Assert.Equal(new[] { "Mountain Resort" }, await Names(new AccommodationQueryParams { Search = " resort " }));
        Assert.Empty(await Names(new AccommodationQueryParams { Search = "zzz" }));
    }

    [Fact]
    public async Task List_FiltersByDestinationTypeAndPriceRange()
    {
        SeedCatalogue();

        Assert.Equal(new[] { "Fort Guesthouse", "Sea View" },
            await Names(new AccommodationQueryParams { DestinationId = _f.Galle.Id }));
        Assert.Equal(new[] { "Tea Hostel" },
            await Names(new AccommodationQueryParams { Type = AccommodationType.Hostel }));
        Assert.Equal(new[] { "Fort Guesthouse", "Sea View" },
            await Names(new AccommodationQueryParams { MinPrice = 8000m, MaxPrice = 20000m }));
    }

    [Fact]
    public async Task List_SortsByPriceBothWays()
    {
        SeedCatalogue();

        Assert.Equal(new[] { "Tea Hostel", "Fort Guesthouse", "Sea View", "Mountain Resort" },
            await Names(new AccommodationQueryParams { SortBy = "Price" }));
        Assert.Equal(new[] { "Mountain Resort", "Sea View", "Fort Guesthouse", "Tea Hostel" },
            await Names(new AccommodationQueryParams { SortBy = "price", SortDescending = true }));
    }

    [Fact]
    public async Task List_SortsByAverageRating_UnratedCountAsZero()
    {
        SeedCatalogue();
        var tea = _f.Db.Accommodations.Single(a => a.Name == "Tea Hostel");
        AddReview(tea, _f.Sam, 5);
        AddReview(_f.SeaView, _f.Sam, 3);

        Assert.Equal(new[] { "Tea Hostel", "Sea View" },
            (await Names(new AccommodationQueryParams { SortBy = "Rating", SortDescending = true })).Take(2));
    }

    [Fact]
    public async Task List_SortsByNameDescending()
    {
        SeedCatalogue();

        Assert.Equal(new[] { "Tea Hostel", "Sea View", "Mountain Resort", "Fort Guesthouse" },
            await Names(new AccommodationQueryParams { SortDescending = true }));
    }

    [Fact]
    public async Task List_PagesAndReportsTheTotal()
    {
        SeedCatalogue();

        var page2 = await _f.Accommodations.GetAccommodationsAsync(
            new AccommodationQueryParams { Page = 2, PageSize = 3 });

        Assert.Equal(4, page2.TotalCount);
        Assert.Equal(2, page2.Page);
        Assert.Equal(3, page2.PageSize);
        Assert.Equal(new[] { "Tea Hostel" }, page2.Items.Select(i => i.Name));
    }

    [Fact]
    public async Task List_ClampsBadPagingValues()
    {
        var result = await _f.Accommodations.GetAccommodationsAsync(
            new AccommodationQueryParams { Page = -4, PageSize = 5000 });

        Assert.Equal(1, result.Page);
        Assert.Equal(AccommodationService.MaxPageSize, result.PageSize);
    }

    [Fact]
    public async Task Rating_IsTheMeanRoundedToOneDecimal_WithItsCount()
    {
        AddReview(_f.SeaView, _f.Sam, 5);
        AddReview(_f.SeaView, _f.Kim, 4);
        var third = _f.AddUser("lee@example.com", "Lee");
        AddReview(_f.SeaView, third, 4); // (5+4+4)/3 = 4.333...

        var stay = await _f.Accommodations.GetByIdAsync(_f.SeaView.Id);

        Assert.Equal(4.3, stay!.AverageRating);
        Assert.Equal(3, stay.ReviewCount);
    }

    private void AddReview(Accommodation stay, User traveler, int rating)
    {
        var booking = new Booking
        {
            Id = Guid.NewGuid(), TravelerId = traveler.Id,
            TripId = (traveler.Id == _f.Sam.Id ? _f.SamTrip : _f.KimTrip).Id
        };
        _f.Db.Bookings.Add(booking);
        _f.Db.Reviews.Add(new Review
        {
            Id = Guid.NewGuid(), AccommodationId = stay.Id, TravelerId = traveler.Id,
            BookingId = booking.Id, Rating = rating, Comment = "ok"
        });
        _f.Db.SaveChanges();
    }

    // ---- Availability ----------------------------------------------------------------------

    [Fact]
    public async Task SetAvailability_CreatesOneRowPerNight_Inclusive()
    {
        var result = await _f.Accommodations.SetAvailabilityAsync(_f.SeaView.Id, new SetAvailabilityDto
        {
            From = new DateOnly(2026, 12, 1), To = new DateOnly(2026, 12, 3), TotalRooms = 5
        });

        Assert.True(result.Succeeded);
        Assert.Equal(3, result.Value!.Count);
        Assert.All(result.Value, d => { Assert.Equal(5, d.TotalRooms); Assert.Equal(5, d.AvailableRooms); });
        Assert.Equal(3, _f.NewContext().Availabilities.Count(a => a.Date >= new DateOnly(2026, 12, 1)));
    }

    [Fact]
    public async Task SetAvailability_UpdatesExistingNights_AndKeepsWhatIsBooked()
    {
        var night = _f.Night(_f.SeaView, BookingFixture.Nov1);
        await BookOneRoom();

        var result = await _f.Accommodations.SetAvailabilityAsync(_f.SeaView.Id, new SetAvailabilityDto
        {
            From = BookingFixture.Nov1, To = BookingFixture.Nov1, TotalRooms = 6
        });

        Assert.True(result.Succeeded);
        var after = _f.Night(_f.SeaView, BookingFixture.Nov1);
        Assert.Equal(6, after.TotalRooms);
        Assert.Equal(1, after.BookedRooms);
        Assert.True(after.Version > night.Version); // concurrency token moved
    }

    [Fact]
    public async Task SetAvailability_WithTheSameTotal_ChangesNothing()
    {
        var before = _f.Night(_f.SeaView, BookingFixture.Nov1);

        await _f.Accommodations.SetAvailabilityAsync(_f.SeaView.Id, new SetAvailabilityDto
        {
            From = BookingFixture.Nov1, To = BookingFixture.Nov1, TotalRooms = 2
        });

        Assert.Equal(before.Version, _f.Night(_f.SeaView, BookingFixture.Nov1).Version);
    }

    [Fact]
    public async Task SetAvailability_CannotDropBelowWhatIsAlreadyBooked_AndChangesNothing()
    {
        await BookOneRoom(); // 1 room booked on each of Nov 1 and Nov 2

        var result = await _f.Accommodations.SetAvailabilityAsync(_f.SeaView.Id, new SetAvailabilityDto
        {
            From = BookingFixture.Nov1, To = BookingFixture.Nov1.AddDays(3), TotalRooms = 0
        });

        Assert.Equal(ServiceError.Conflict, result.Error);
        Assert.Contains("already booked", result.Message);
        // All or nothing: even the un-booked nights kept their rooms.
        Assert.Equal(2, _f.Night(_f.SeaView, BookingFixture.Nov1.AddDays(3)).TotalRooms);
        Assert.Equal(2, _f.Night(_f.SeaView, BookingFixture.Nov1).TotalRooms);
    }

    [Fact]
    public async Task SetAvailability_RefusesThePast()
    {
        var result = await _f.Accommodations.SetAvailabilityAsync(_f.SeaView.Id, new SetAvailabilityDto
        {
            From = BookingFixture.Today.AddDays(-1), To = BookingFixture.Today.AddDays(2), TotalRooms = 3
        });

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task SetAvailability_AllowsToday()
    {
        var result = await _f.Accommodations.SetAvailabilityAsync(_f.SeaView.Id, new SetAvailabilityDto
        {
            From = BookingFixture.Today, To = BookingFixture.Today, TotalRooms = 3
        });

        Assert.True(result.Succeeded);
    }

    [Fact]
    public async Task SetAvailability_RefusesAReversedRange()
    {
        var result = await _f.Accommodations.SetAvailabilityAsync(_f.SeaView.Id, new SetAvailabilityDto
        {
            From = BookingFixture.Nov1.AddDays(5), To = BookingFixture.Nov1, TotalRooms = 3
        });

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task SetAvailability_RefusesAnOversizedRange()
    {
        var result = await _f.Accommodations.SetAvailabilityAsync(_f.SeaView.Id, new SetAvailabilityDto
        {
            From = BookingFixture.Nov1,
            To = BookingFixture.Nov1.AddDays(AccommodationService.MaxSetAvailabilityDays),
            TotalRooms = 3
        });

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task SetAvailability_OfAnUnknownStay_IsNotFound()
    {
        var result = await _f.Accommodations.SetAvailabilityAsync(Guid.NewGuid(), new SetAvailabilityDto
        {
            From = BookingFixture.Nov1, To = BookingFixture.Nov1, TotalRooms = 3
        });

        Assert.Equal(ServiceError.NotFound, result.Error);
    }

    [Fact]
    public async Task GetAvailability_ReturnsTheNightsInOrder()
    {
        var result = await _f.Accommodations.GetAvailabilityAsync(
            _f.SeaView.Id, BookingFixture.Nov1.AddDays(2), BookingFixture.Nov1.AddDays(4));

        Assert.True(result.Succeeded);
        Assert.Equal(
            new[] { BookingFixture.Nov1.AddDays(2), BookingFixture.Nov1.AddDays(3), BookingFixture.Nov1.AddDays(4) },
            result.Value!.Select(d => d.Date));
    }

    [Fact]
    public async Task GetAvailability_OnlyListsNightsThatHaveInventory()
    {
        var result = await _f.Accommodations.GetAvailabilityAsync(
            _f.SeaView.Id, BookingFixture.Nov1.AddDays(8), BookingFixture.Nov1.AddDays(20));

        Assert.Equal(2, result.Value!.Count); // 9 and 10 November only
    }

    [Fact]
    public async Task GetAvailability_ValidatesTheWindow()
    {
        var reversed = await _f.Accommodations.GetAvailabilityAsync(
            _f.SeaView.Id, BookingFixture.Nov1.AddDays(3), BookingFixture.Nov1);
        var tooWide = await _f.Accommodations.GetAvailabilityAsync(
            _f.SeaView.Id, BookingFixture.Nov1, BookingFixture.Nov1.AddDays(AccommodationService.MaxAvailabilityWindowDays));
        var unknown = await _f.Accommodations.GetAvailabilityAsync(
            Guid.NewGuid(), BookingFixture.Nov1, BookingFixture.Nov1.AddDays(2));

        Assert.Equal(ServiceError.Invalid, reversed.Error);
        Assert.Equal(ServiceError.Invalid, tooWide.Error);
        Assert.Equal(ServiceError.NotFound, unknown.Error);
    }

    // ---- Quote (the business operation) -----------------------------------------------------

    [Fact]
    public async Task Quote_PricesTheStayAndConfirmsAvailability()
    {
        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1, BookingFixture.Nov1.AddDays(3), rooms: 2);

        var quote = result.Value!;
        Assert.True(quote.IsAvailable);
        Assert.Equal(3, quote.Nights);
        Assert.Equal(20000m, quote.PricePerNight);
        Assert.Equal(120000m, quote.TotalPrice); // 3 nights x 2 rooms x 20,000
        Assert.Equal(2, quote.MaxRoomsAvailable);
        Assert.Equal(3, quote.Days.Count);
        Assert.Equal("Sea View", quote.AccommodationName);
    }

    [Fact]
    public async Task Quote_CheckoutNightIsNotCharged()
    {
        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1, BookingFixture.Nov1.AddDays(1), rooms: 1);

        Assert.Equal(1, result.Value!.Nights);
        Assert.Equal(20000m, result.Value.TotalPrice);
        Assert.Equal(BookingFixture.Nov1, Assert.Single(result.Value.Days).Date);
    }

    [Fact]
    public async Task Quote_SaysNoWhenTheTightestNightHasTooFewRooms()
    {
        await BookOneRoom(); // Nov 1-2 now have 1 room left

        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1, BookingFixture.Nov1.AddDays(4), rooms: 2);

        Assert.False(result.Value!.IsAvailable);
        Assert.Equal(1, result.Value.MaxRoomsAvailable);
    }

    [Fact]
    public async Task Quote_TreatsANightWithoutInventoryAsSoldOut()
    {
        // Inventory ends on 10 November; the 11th has no row.
        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1.AddDays(9), BookingFixture.Nov1.AddDays(11), rooms: 1);

        Assert.False(result.Value!.IsAvailable);
        Assert.Equal(0, result.Value.MaxRoomsAvailable);
        Assert.Equal(2, result.Value.Days.Count);
        Assert.Equal(0, result.Value.Days[1].TotalRooms);
    }

    [Theory]
    [InlineData(0, 0)]   // same day
    [InlineData(5, 2)]   // check-out before check-in
    public async Task Quote_NeedsCheckoutAfterCheckin(int checkInOffset, int checkOutOffset)
    {
        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1.AddDays(checkInOffset), BookingFixture.Nov1.AddDays(checkOutOffset), 1);

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Quote_RefusesTooLongAStay()
    {
        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1, BookingFixture.Nov1.AddDays(AccommodationService.MaxStayNights + 1), 1);

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Quote_AllowsTheLongestStay()
    {
        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1, BookingFixture.Nov1.AddDays(AccommodationService.MaxStayNights), 1);

        Assert.True(result.Succeeded);
        Assert.Equal(AccommodationService.MaxStayNights, result.Value!.Nights);
    }

    [Fact]
    public async Task Quote_RefusesThePast()
    {
        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Today.AddDays(-1), BookingFixture.Today.AddDays(1), 1);

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(11)]
    public async Task Quote_RefusesRoomCountsOutsideTheLimits(int rooms)
    {
        var result = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1, BookingFixture.Nov1.AddDays(1), rooms);

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Quote_OfAnInactiveOrUnknownStay_IsNotFound()
    {
        await _f.Accommodations.DeactivateAsync(_f.SeaView.Id);

        var inactive = await _f.Accommodations.QuoteAsync(
            _f.SeaView.Id, BookingFixture.Nov1, BookingFixture.Nov1.AddDays(1), 1);
        var unknown = await _f.Accommodations.QuoteAsync(
            Guid.NewGuid(), BookingFixture.Nov1, BookingFixture.Nov1.AddDays(1), 1);

        Assert.Equal(ServiceError.NotFound, inactive.Error);
        Assert.Equal(ServiceError.NotFound, unknown.Error);
    }

    private async Task BookOneRoom()
    {
        var booked = await _f.Bookings.CreateAsync(_f.Sam.Id, new CEYLORA.Application.DTOs.Bookings.CreateBookingDto
        {
            TripId = _f.SamTrip.Id,
            Items = new()
            {
                new() { AccommodationId = _f.SeaView.Id, CheckIn = BookingFixture.Nov1,
                        CheckOut = BookingFixture.Nov1.AddDays(2), Rooms = 1, Guests = 2 }
            }
        });
        Assert.True(booked.Succeeded, booked.Message);
    }
}
