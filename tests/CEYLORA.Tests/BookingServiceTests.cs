using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Bookings;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Services;
using CEYLORA.Tests.Support;

namespace CEYLORA.Tests;

public class BookingServiceTests : IDisposable
{
    private readonly BookingFixture _f = new();
    private static readonly DateOnly Nov1 = BookingFixture.Nov1;

    public void Dispose() => _f.Dispose();

    private CreateBookingItemDto Item(int checkInOffset = 0, int nights = 2, int rooms = 1, int guests = 2,
        Accommodation? stay = null) => new()
    {
        AccommodationId = (stay ?? _f.SeaView).Id,
        CheckIn = Nov1.AddDays(checkInOffset),
        CheckOut = Nov1.AddDays(checkInOffset + nights),
        Rooms = rooms,
        Guests = guests
    };

    private CreateBookingDto Request(params CreateBookingItemDto[] items) => new()
    {
        TripId = _f.SamTrip.Id,
        Items = items.ToList()
    };

    private async Task<BookingResponseDto> BookAsync(User? who = null, params CreateBookingItemDto[] items)
    {
        var traveler = who ?? _f.Sam;
        var dto = new CreateBookingDto
        {
            TripId = (traveler.Id == _f.Kim.Id ? _f.KimTrip : _f.SamTrip).Id,
            Items = (items.Length == 0 ? new[] { Item() } : items).ToList()
        };
        var result = await _f.Bookings.CreateAsync(traveler.Id, dto);
        Assert.True(result.Succeeded, result.Message);
        return result.Value!;
    }

    // ---- Create: the happy path --------------------------------------------------------------

    [Fact]
    public async Task Create_ConfirmsTheBooking_AndPricesIt()
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(nights: 3, rooms: 2, guests: 4)));

        Assert.True(result.Succeeded);
        var booking = result.Value!;
        Assert.Equal("Confirmed", booking.Status);
        Assert.Equal(120000m, booking.TotalAmount); // 3 nights x 2 rooms x 20,000
        Assert.Equal(_f.SamTrip.Id, booking.TripId);
        Assert.Equal("Sam's south coast trip", booking.TripTitle);
        Assert.Equal("Sam Traveler", booking.TravelerName);
        var item = Assert.Single(booking.Items);
        Assert.Equal("Sea View", item.AccommodationName);
        Assert.Equal("Galle Fort", item.DestinationName);
        Assert.Equal(3, item.Nights);
        Assert.Equal(20000m, item.NightlyRate);
        Assert.Equal(120000m, item.Subtotal);
        Assert.Equal(new DateTime(2026, 10, 20, 10, 0, 0, DateTimeKind.Utc), booking.CreatedAt);
    }

    [Fact]
    public async Task Create_ReservesTheRoomsOnEveryStayedNight_ButNotTheCheckoutDay()
    {
        await BookAsync(items: Item(checkInOffset: 0, nights: 3, rooms: 2));

        Assert.Equal(2, _f.BookedRooms(_f.SeaView, Nov1));
        Assert.Equal(2, _f.BookedRooms(_f.SeaView, Nov1.AddDays(1)));
        Assert.Equal(2, _f.BookedRooms(_f.SeaView, Nov1.AddDays(2)));
        Assert.Equal(0, _f.BookedRooms(_f.SeaView, Nov1.AddDays(3))); // check-out morning
    }

    [Fact]
    public async Task Create_BumpsTheConcurrencyVersionOfEveryTouchedNight()
    {
        var before = _f.Night(_f.SeaView, Nov1).Version;

        await BookAsync();

        Assert.Equal(before + 1, _f.Night(_f.SeaView, Nov1).Version);
    }

    [Fact]
    public async Task Create_KeepsTheOldPriceWhenTheRateChangesLater()
    {
        var booking = await BookAsync();

        _f.Db.Accommodations.Single(a => a.Id == _f.SeaView.Id).PricePerNight = 99999m;
        _f.Db.SaveChanges();

        var again = await _f.Bookings.GetByIdAsync(booking.Id, _f.Sam.Id, isStaff: false);
        Assert.Equal(40000m, again.Value!.TotalAmount);
        Assert.Equal(20000m, again.Value.Items[0].NightlyRate);
    }

    [Fact]
    public async Task Create_CanBookSeveralStaysAcrossDestinations()
    {
        var inn = _f.AddAccommodation(_f.Ella, "Ella Inn", 9000m, maxGuestsPerRoom: 3);
        _f.SetRooms(inn, Nov1, Nov1.AddDays(9), 1);

        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(
            Item(nights: 2, rooms: 1, guests: 2),
            Item(checkInOffset: 2, nights: 3, rooms: 1, guests: 3, stay: inn)));

        Assert.True(result.Succeeded);
        Assert.Equal(40000m + 27000m, result.Value!.TotalAmount);
        Assert.Equal(2, result.Value.Items.Count);
        Assert.Equal(new[] { "Galle Fort", "Ella" }, result.Value.Items.Select(i => i.DestinationName));
    }

    [Fact]
    public async Task Create_TrimsTheNotes()
    {
        var dto = Request(Item());
        dto.Notes = "  late arrival ";

        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, dto);

        Assert.Equal("late arrival", result.Value!.Notes);
    }

    [Fact]
    public async Task Create_AllowsBookingFromTodayAndTheLongestStay()
    {
        _f.SetRooms(_f.SeaView, BookingFixture.Today, Nov1.AddDays(-1), 1);
        _f.SetRooms(_f.SeaView, Nov1.AddDays(10), Nov1.AddDays(40), 1);

        var today = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(new CreateBookingItemDto
        {
            AccommodationId = _f.SeaView.Id, CheckIn = BookingFixture.Today, CheckOut = BookingFixture.Today.AddDays(1),
            Rooms = 1, Guests = 1
        }));
        Assert.True(today.Succeeded, today.Message);
    }

    // ---- Create: availability rules ----------------------------------------------------------

    [Fact]
    public async Task Create_WhenSoldOut_IsAConflictNamingTheNight_AndChangesNothing()
    {
        await BookAsync(items: Item(nights: 2, rooms: 2)); // Nov 1-2 full

        var result = await _f.Bookings.CreateAsync(_f.Kim.Id, new CreateBookingDto
        {
            TripId = _f.KimTrip.Id,
            Items = new() { Item(checkInOffset: 1, nights: 3, rooms: 1) } // Nov 2 is gone
        });

        Assert.Equal(ServiceError.Conflict, result.Error);
        Assert.Contains("2026-11-02", result.Message);
        Assert.Equal(1, _f.BookingCount());
        Assert.Equal(0, _f.BookedRooms(_f.SeaView, Nov1.AddDays(3))); // the free nights were not touched
    }

    [Fact]
    public async Task Create_TheLastRoomGoesToOnlyOneTraveler()
    {
        await BookAsync(items: Item(rooms: 1));
        await BookAsync(items: Item(rooms: 1)); // both rooms taken now

        var third = await _f.Bookings.CreateAsync(_f.Kim.Id, new CreateBookingDto
        {
            TripId = _f.KimTrip.Id,
            Items = new() { Item(rooms: 1) }
        });

        Assert.Equal(ServiceError.Conflict, third.Error);
        Assert.Equal(2, _f.BookedRooms(_f.SeaView, Nov1));
    }

    [Fact]
    public async Task Create_ItemsInOneBookingCompeteForTheSameRooms()
    {
        // Two stays at the same place on the same nights, 2 rooms each: only 2 exist.
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(
            Item(nights: 2, rooms: 2), Item(nights: 2, rooms: 2)));

        Assert.Equal(ServiceError.Conflict, result.Error);
        Assert.Equal(0, _f.BookingCount());
        Assert.Equal(0, _f.BookedRooms(_f.SeaView, Nov1)); // not even the first item stuck
    }

    [Fact]
    public async Task Create_ANightWithNoInventoryCannotBeBooked()
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(checkInOffset: 9, nights: 3)));

        Assert.Equal(ServiceError.Conflict, result.Error);
        Assert.Contains("2026-11-11", result.Message);
    }

    [Fact]
    public async Task Create_SoldOutNightsCanBeBookedAgainOnceReleased()
    {
        var first = await BookAsync(items: Item(rooms: 2));
        Assert.Equal(ServiceError.Conflict, (await _f.Bookings.CreateAsync(_f.Kim.Id,
            new CreateBookingDto { TripId = _f.KimTrip.Id, Items = new() { Item(rooms: 1) } })).Error);

        await _f.Bookings.CancelAsync(first.Id, _f.Sam.Id, isStaff: false);

        var retry = await _f.Bookings.CreateAsync(_f.Kim.Id,
            new CreateBookingDto { TripId = _f.KimTrip.Id, Items = new() { Item(rooms: 1) } });
        Assert.True(retry.Succeeded);
    }

    // ---- Create: validation ------------------------------------------------------------------

    [Fact]
    public async Task Create_NeedsAtLeastOneStay()
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request());

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Create_RefusesTooManyStays()
    {
        var items = Enumerable.Range(0, BookingService.MaxItemsPerBooking + 1).Select(_ => Item()).ToArray();

        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(items));

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Theory]
    [InlineData(0, 0)]  // same-day checkout
    [InlineData(2, -1)] // checkout before check-in
    public async Task Create_NeedsCheckoutAfterCheckin(int checkInOffset, int nights)
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(checkInOffset, nights)));

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Create_RefusesTheEndlessStay()
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id,
            Request(Item(nights: AccommodationService.MaxStayNights + 1)));

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Create_RefusesCheckInInThePast()
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(new CreateBookingItemDto
        {
            AccommodationId = _f.SeaView.Id, CheckIn = BookingFixture.Today.AddDays(-1),
            CheckOut = BookingFixture.Today.AddDays(1), Rooms = 1, Guests = 1
        }));

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(-2, 1)]
    [InlineData(11, 1)]
    [InlineData(1, 0)]
    public async Task Create_RefusesBadRoomOrGuestCounts(int rooms, int guests)
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(rooms: rooms, guests: guests)));

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Create_RefusesMoreGuestsThanTheRoomsSleep()
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(rooms: 1, guests: 3))); // sleeps 2

        Assert.Equal(ServiceError.Invalid, result.Error);
        Assert.Contains("at most 2", result.Message);
    }

    [Fact]
    public async Task Create_AllowsExactlyFullRooms()
    {
        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(rooms: 2, guests: 4)));

        Assert.True(result.Succeeded);
    }

    [Fact]
    public async Task Create_RequiresAnExistingTripOfTheCaller()
    {
        var unknown = await _f.Bookings.CreateAsync(_f.Sam.Id, new CreateBookingDto
        {
            TripId = Guid.NewGuid(), Items = new() { Item() }
        });
        var someoneElses = await _f.Bookings.CreateAsync(_f.Sam.Id, new CreateBookingDto
        {
            TripId = _f.KimTrip.Id, Items = new() { Item() }
        });

        Assert.Equal(ServiceError.NotFound, unknown.Error);
        Assert.Equal(ServiceError.NotFound, someoneElses.Error);
        Assert.Equal(0, _f.BookingCount());
    }

    [Fact]
    public async Task Create_RefusesACancelledTrip()
    {
        var cancelled = _f.AddTrip(_f.Sam, "Called off", TripStatus.Cancelled);

        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, new CreateBookingDto
        {
            TripId = cancelled.Id, Items = new() { Item() }
        });

        Assert.Equal(ServiceError.Invalid, result.Error);
    }

    [Fact]
    public async Task Create_RefusesUnknownOrInactiveStays()
    {
        var hidden = _f.AddAccommodation(_f.Galle, "Closed Inn", 5000m, active: false);
        _f.SetRooms(hidden, Nov1, Nov1.AddDays(5), 3);

        var inactive = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(stay: hidden)));
        var unknown = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(new CreateBookingItemDto
        {
            AccommodationId = Guid.NewGuid(), CheckIn = Nov1, CheckOut = Nov1.AddDays(1), Rooms = 1, Guests = 1
        }));

        Assert.Equal(ServiceError.NotFound, inactive.Error);
        Assert.Equal(ServiceError.NotFound, unknown.Error);
    }

    // ---- Create: races ------------------------------------------------------------------------

    [Fact]
    public async Task Create_RetriesAfterAConcurrencyConflict_AndReservesOnlyOnce()
    {
        _f.Race.FailConcurrencyTimes = 1; // the first save loses a race

        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(rooms: 1)));

        Assert.True(result.Succeeded, result.Message);
        Assert.Equal(1, _f.BookedRooms(_f.SeaView, Nov1)); // not 2: the failed attempt left no trace
        Assert.Equal(1, _f.BookingCount());
    }

    [Fact]
    public async Task Create_GivesUpWithAConflictAfterTooManyRaces()
    {
        _f.Race.FailConcurrencyTimes = 100;

        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item()));

        Assert.Equal(ServiceError.Conflict, result.Error);
        Assert.Contains("try again", result.Message);
        Assert.Equal(0, _f.BookingCount());
        Assert.Equal(0, _f.BookedRooms(_f.SeaView, Nov1));
    }

    [Fact]
    public async Task Create_WhenSomeoneElseTakesTheLastRoomMidFlight_ItDoesNotOverbook()
    {
        // Sam asks for both rooms. After Sam's service has read the free rooms but before it
        // saves, Kim (a second connection) books one room.
        _f.Race.BeforeNextSave = () =>
        {
            using var other = _f.NewContext();
            var night = other.Availabilities.Single(a => a.AccommodationId == _f.SeaView.Id && a.Date == Nov1);
            night.BookedRooms += 1;
            night.Version++;
            other.SaveChanges();
        };

        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(nights: 1, rooms: 2)));

        Assert.Equal(ServiceError.Conflict, result.Error);
        Assert.Contains("2026-11-01", result.Message);
        // Only Kim's room is counted. (That the booking row is rolled back too needs a real
        // transaction, which the in-memory provider lacks: see SqliteBookingTests.)
        Assert.Equal(1, _f.BookedRooms(_f.SeaView, Nov1));
    }

    [Fact]
    public async Task Create_WhenSomeoneElseTakesAnOtherRoomMidFlight_StillSucceedsOnRetry()
    {
        _f.Race.BeforeNextSave = () =>
        {
            using var other = _f.NewContext();
            var night = other.Availabilities.Single(a => a.AccommodationId == _f.SeaView.Id && a.Date == Nov1);
            night.BookedRooms += 1;
            night.Version++;
            other.SaveChanges();
        };

        var result = await _f.Bookings.CreateAsync(_f.Sam.Id, Request(Item(nights: 1, rooms: 1)));

        Assert.True(result.Succeeded, result.Message);
        Assert.Equal(2, _f.BookedRooms(_f.SeaView, Nov1)); // Kim's room plus Sam's
    }

    // ---- Cancel -------------------------------------------------------------------------------

    [Fact]
    public async Task Cancel_ReleasesTheRooms_AndMarksTheBooking()
    {
        var booking = await BookAsync(items: Item(nights: 3, rooms: 2));

        var result = await _f.Bookings.CancelAsync(booking.Id, _f.Sam.Id, isStaff: false);

        Assert.True(result.Succeeded);
        Assert.Equal("Cancelled", result.Value!.Status);
        Assert.Equal(new DateTime(2026, 10, 20, 10, 0, 0, DateTimeKind.Utc), result.Value.CancelledAt);
        for (var i = 0; i < 3; i++) Assert.Equal(0, _f.BookedRooms(_f.SeaView, Nov1.AddDays(i)));
    }

    [Fact]
    public async Task Cancel_OnlyReleasesItsOwnRooms()
    {
        var a = await BookAsync(items: Item(rooms: 1));
        await BookAsync(_f.Kim, Item(rooms: 1));

        await _f.Bookings.CancelAsync(a.Id, _f.Sam.Id, isStaff: false);

        Assert.Equal(1, _f.BookedRooms(_f.SeaView, Nov1)); // Kim's room is still held
    }

    [Fact]
    public async Task Cancel_Twice_IsAConflict_AndDoesNotReleaseTwice()
    {
        var a = await BookAsync(items: Item(rooms: 1));
        await BookAsync(_f.Kim, Item(rooms: 1));

        await _f.Bookings.CancelAsync(a.Id, _f.Sam.Id, isStaff: false);
        var again = await _f.Bookings.CancelAsync(a.Id, _f.Sam.Id, isStaff: false);

        Assert.Equal(ServiceError.Conflict, again.Error);
        Assert.Equal(1, _f.BookedRooms(_f.SeaView, Nov1));
    }

    [Fact]
    public async Task Cancel_IsRefusedForAnotherTraveler()
    {
        var booking = await BookAsync();

        var result = await _f.Bookings.CancelAsync(booking.Id, _f.Kim.Id, isStaff: false);

        Assert.Equal(ServiceError.Forbidden, result.Error);
        Assert.Equal(2, _f.BookedRooms(_f.SeaView, Nov1) + 1); // still reserved (1 room)
    }

    [Fact]
    public async Task Cancel_StaffCanCancelAnyBooking()
    {
        var booking = await BookAsync();

        var result = await _f.Bookings.CancelAsync(booking.Id, _f.Olu.Id, isStaff: true);

        Assert.True(result.Succeeded);
        Assert.Equal(0, _f.BookedRooms(_f.SeaView, Nov1));
    }

    [Fact]
    public async Task Cancel_TravelerCannotCancelOnceTheFirstStayHasStarted()
    {
        var booking = await BookAsync();
        _f.MoveClockTo(Nov1); // check-in day

        var traveler = await _f.Bookings.CancelAsync(booking.Id, _f.Sam.Id, isStaff: false);
        var staff = await _f.Bookings.CancelAsync(booking.Id, _f.Olu.Id, isStaff: true);

        Assert.Equal(ServiceError.Invalid, traveler.Error);
        Assert.True(staff.Succeeded); // staff can still step in
    }

    [Fact]
    public async Task Cancel_TravelerCanCancelUpToTheDayBeforeCheckIn()
    {
        var booking = await BookAsync();
        _f.MoveClockTo(Nov1.AddDays(-1));

        var result = await _f.Bookings.CancelAsync(booking.Id, _f.Sam.Id, isStaff: false);

        Assert.True(result.Succeeded);
    }

    [Fact]
    public async Task Cancel_OfAnUnknownBooking_IsNotFound()
    {
        var result = await _f.Bookings.CancelAsync(Guid.NewGuid(), _f.Sam.Id, isStaff: false);

        Assert.Equal(ServiceError.NotFound, result.Error);
    }

    [Fact]
    public async Task Cancel_NeverLeavesANegativeCount()
    {
        var booking = await BookAsync(items: Item(rooms: 2));
        // Someone (an operator edit gone wrong) already zeroed the counters.
        using (var ctx = _f.NewContext())
        {
            foreach (var n in ctx.Availabilities.Where(a => a.AccommodationId == _f.SeaView.Id))
                n.BookedRooms = 0;
            ctx.SaveChanges();
        }

        await _f.Bookings.CancelAsync(booking.Id, _f.Sam.Id, isStaff: false);

        Assert.Equal(0, _f.BookedRooms(_f.SeaView, Nov1));
    }

    [Fact]
    public async Task Cancel_RetriesAfterAConcurrencyConflict()
    {
        var booking = await BookAsync(items: Item(rooms: 1));
        _f.Race.FailConcurrencyTimes = 1;

        var result = await _f.Bookings.CancelAsync(booking.Id, _f.Sam.Id, isStaff: false);

        Assert.True(result.Succeeded, result.Message);
        Assert.Equal(0, _f.BookedRooms(_f.SeaView, Nov1)); // released once, not twice
    }

    [Fact]
    public async Task Cancel_GivesUpAfterTooManyRaces_AndKeepsTheBooking()
    {
        var booking = await BookAsync(items: Item(rooms: 1));
        _f.Race.FailConcurrencyTimes = 100;

        var result = await _f.Bookings.CancelAsync(booking.Id, _f.Sam.Id, isStaff: false);

        Assert.Equal(ServiceError.Conflict, result.Error);
        var stored = await _f.Bookings.GetByIdAsync(booking.Id, _f.Sam.Id, isStaff: false);
        Assert.Equal("Confirmed", stored.Value!.Status);
        Assert.Equal(1, _f.BookedRooms(_f.SeaView, Nov1));
    }

    // ---- Read ---------------------------------------------------------------------------------

    [Fact]
    public async Task GetMine_ReturnsOnlyTheCallersBookings_NewestFirst()
    {
        var first = await BookAsync();
        _f.Clock.Set(_f.Clock.GetUtcNow().AddHours(1));
        var second = await BookAsync(items: Item(checkInOffset: 4));
        await BookAsync(_f.Kim);

        var mine = await _f.Bookings.GetMineAsync(_f.Sam.Id);

        Assert.Equal(new[] { second.Id, first.Id }, mine.Select(b => b.Id));
    }

    [Fact]
    public async Task GetMine_WithNoBookings_IsEmpty()
    {
        Assert.Empty(await _f.Bookings.GetMineAsync(_f.Sam.Id));
    }

    [Fact]
    public async Task GetById_OwnerAndStaffCanSee_OthersCannot()
    {
        var booking = await BookAsync();

        Assert.True((await _f.Bookings.GetByIdAsync(booking.Id, _f.Sam.Id, false)).Succeeded);
        Assert.True((await _f.Bookings.GetByIdAsync(booking.Id, _f.Olu.Id, true)).Succeeded);
        Assert.Equal(ServiceError.Forbidden, (await _f.Bookings.GetByIdAsync(booking.Id, _f.Kim.Id, false)).Error);
        Assert.Equal(ServiceError.NotFound, (await _f.Bookings.GetByIdAsync(Guid.NewGuid(), _f.Sam.Id, true)).Error);
    }

    [Fact]
    public async Task GetAll_FiltersByStatus_IgnoringCase()
    {
        var a = await BookAsync();
        await BookAsync(_f.Kim, Item(checkInOffset: 5));
        await _f.Bookings.CancelAsync(a.Id, _f.Sam.Id, false);

        var cancelled = await _f.Bookings.GetAllAsync(new BookingQueryParams { Status = "cancelled" });
        var confirmed = await _f.Bookings.GetAllAsync(new BookingQueryParams { Status = "CONFIRMED" });

        Assert.Equal(new[] { a.Id }, cancelled.Items.Select(b => b.Id));
        Assert.Single(confirmed.Items);
        Assert.Equal(2, (await _f.Bookings.GetAllAsync(new BookingQueryParams())).TotalCount);
    }

    [Fact]
    public async Task GetAll_AnUnknownStatusMatchesNothing()
    {
        await BookAsync();

        var result = await _f.Bookings.GetAllAsync(new BookingQueryParams { Status = "Banana" });

        Assert.Empty(result.Items);
        Assert.Equal(0, result.TotalCount);
    }

    [Fact]
    public async Task GetAll_FiltersByTripAndAccommodation()
    {
        var inn = _f.AddAccommodation(_f.Ella, "Ella Inn", 9000m);
        _f.SetRooms(inn, Nov1, Nov1.AddDays(5), 2);
        var seaView = await BookAsync();
        var atInn = await BookAsync(_f.Kim, Item(stay: inn));

        var byTrip = await _f.Bookings.GetAllAsync(new BookingQueryParams { TripId = _f.KimTrip.Id });
        var byStay = await _f.Bookings.GetAllAsync(new BookingQueryParams { AccommodationId = _f.SeaView.Id });

        Assert.Equal(new[] { atInn.Id }, byTrip.Items.Select(b => b.Id));
        Assert.Equal(new[] { seaView.Id }, byStay.Items.Select(b => b.Id));
    }

    [Fact]
    public async Task GetAll_PagesNewestFirst_AndClampsPageSize()
    {
        for (var i = 0; i < 3; i++)
        {
            _f.Clock.Set(_f.Clock.GetUtcNow().AddMinutes(1));
            await BookAsync(items: Item(checkInOffset: i * 2, nights: 1, rooms: 1, guests: 1));
        }

        var page = await _f.Bookings.GetAllAsync(new BookingQueryParams { Page = 2, PageSize = 2 });
        var clamped = await _f.Bookings.GetAllAsync(new BookingQueryParams { Page = 0, PageSize = 9999 });

        Assert.Equal(3, page.TotalCount);
        Assert.Single(page.Items); // the oldest
        Assert.Equal(1, clamped.Page);
        Assert.Equal(BookingService.MaxPageSize, clamped.PageSize);
    }
}
