using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace CEYLORA.Tests.Api;

/// <summary>Component C through the real HTTP pipeline: JSON, DateOnly, enums, roles, validation.</summary>
public class StaysApiTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public StaysApiTests(ApiFactory factory) => _factory = factory;

    private static string Day(int offset) => DateTime.UtcNow.Date.AddDays(offset).ToString("yyyy-MM-dd");
    private static string Unique(string name) => $"{name} {Guid.NewGuid():N}"[..Math.Min(60, name.Length + 9)];

    private static async Task<string> IdOf(HttpResponseMessage response)
    {
        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());
        using var body = await response.ReadJsonAsync();
        return body.RootElement.GetProperty("id").GetString()!;
    }

    private async Task<string> CreateDestination(HttpClient op) =>
        await IdOf(await op.PostAsJsonAsync("/api/destinations", new { name = Unique("Place"), region = "South Coast", category = "Beach" }));

    private static object Stay(string destinationId, string? name = null, decimal price = 20000, object? type = null, int guests = 2) =>
        new { destinationId, name = name ?? Unique("Stay"), description = "Sea view", type = type ?? "Hotel", pricePerNight = price, maxGuestsPerRoom = guests };

    /// <summary>An operator, a destination, a stay with <paramref name="rooms"/> rooms for the next 30 nights.</summary>
    private async Task<(HttpClient Operator, string DestinationId, string StayId)> SeedStay(int rooms = 2, decimal price = 20000)
    {
        var op = await _factory.OperatorAsync();
        var destinationId = await CreateDestination(op);
        var stayId = await IdOf(await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, price: price)));
        var set = await op.PutAsJsonAsync($"/api/accommodations/{stayId}/availability", new { from = Day(0), to = Day(30), totalRooms = rooms });
        Assert.Equal(HttpStatusCode.OK, set.StatusCode);
        return (op, destinationId, stayId);
    }

    private async Task<string> CreateTrip(HttpClient traveler) =>
        await IdOf(await traveler.PostAsJsonAsync("/api/trips", new { title = "Stay trip", startDate = Day(5), endDate = Day(12), budget = 300000 }));

    private static object Booking(string tripId, string stayId, int checkIn = 5, int nights = 2, int rooms = 1, int guests = 2) =>
        new { tripId, items = new[] { new { accommodationId = stayId, checkIn = Day(checkIn), checkOut = Day(checkIn + nights), rooms, guests } } };

    // ---- The whole journey -------------------------------------------------------------------

    [Fact]
    public async Task OperatorStocks_TravelerQuotesBooksAndCancels()
    {
        var (op, _, stayId) = await SeedStay(rooms: 2, price: 20000);
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();
        var tripId = await CreateTrip(traveler);

        // The traveler finds it and asks the price.
        using var stay = await (await traveler.GetAsync($"/api/accommodations/{stayId}")).ReadJsonAsync();
        Assert.Equal("Hotel", stay.RootElement.GetProperty("type").GetString());
        Assert.Equal(JsonValueKind.Null, stay.RootElement.GetProperty("averageRating").ValueKind);

        using var quote = await (await traveler.GetAsync($"/api/accommodations/{stayId}/quote?checkIn={Day(5)}&checkOut={Day(8)}&rooms=2")).ReadJsonAsync();
        Assert.True(quote.RootElement.GetProperty("isAvailable").GetBoolean());
        Assert.Equal(120000m, quote.RootElement.GetProperty("totalPrice").GetDecimal()); // 3 nights x 2 rooms x 20,000
        Assert.Equal(Day(5), quote.RootElement.GetProperty("checkIn").GetString());      // DateOnly as yyyy-MM-dd

        // Books it.
        var booked = await traveler.PostAsJsonAsync("/api/bookings", Booking(tripId, stayId, checkIn: 5, nights: 3, rooms: 2, guests: 4));
        Assert.Equal(HttpStatusCode.Created, booked.StatusCode);
        using var booking = await booked.ReadJsonAsync();
        var bookingId = booking.RootElement.GetProperty("id").GetString();
        Assert.Equal("Confirmed", booking.RootElement.GetProperty("status").GetString());
        Assert.Equal(120000m, booking.RootElement.GetProperty("totalAmount").GetDecimal());
        Assert.Equal(Day(5), booking.RootElement.GetProperty("items")[0].GetProperty("checkIn").GetString());

        // The operator sees the nights as full.
        using var nights = await (await op.GetAsync($"/api/accommodations/{stayId}/availability?from={Day(5)}&to={Day(7)}")).ReadJsonAsync();
        Assert.All(nights.RootElement.EnumerateArray(), n => Assert.Equal(0, n.GetProperty("availableRooms").GetInt32()));

        // Another traveler cannot take them.
        using var other = await _factory.TravelerAsync();
        var otherTrip = await CreateTrip(other);
        var clash = await other.PostAsJsonAsync("/api/bookings", Booking(otherTrip, stayId, checkIn: 6, nights: 1, rooms: 1, guests: 1));
        var error = await clash.ExpectErrorAsync(409, "does not have");
        Assert.Contains(Day(6), error.GetProperty("message").GetString());

        // Cancelling frees them.
        var cancelled = await traveler.PostAsync($"/api/bookings/{bookingId}/cancel", null);
        Assert.Equal(HttpStatusCode.OK, cancelled.StatusCode);
        using var after = await (await op.GetAsync($"/api/accommodations/{stayId}/availability?from={Day(5)}&to={Day(7)}")).ReadJsonAsync();
        Assert.All(after.RootElement.EnumerateArray(), n => Assert.Equal(2, n.GetProperty("availableRooms").GetInt32()));
        Assert.Equal(HttpStatusCode.Created,
            (await other.PostAsJsonAsync("/api/bookings", Booking(otherTrip, stayId, checkIn: 6, nights: 1))).StatusCode);
    }

    [Fact]
    public async Task TheOperatorSeesEveryBooking_AndCanFilterByStatus()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();
        var tripId = await CreateTrip(traveler);
        var bookingId = await IdOf(await traveler.PostAsJsonAsync("/api/bookings", Booking(tripId, stayId)));

        using var confirmed = await (await op.GetAsync($"/api/bookings?status=Confirmed&accommodationId={stayId}")).ReadJsonAsync();
        Assert.Equal(1, confirmed.RootElement.GetProperty("totalCount").GetInt32());

        await op.PostAsync($"/api/bookings/{bookingId}/cancel", null);
        using var cancelled = await (await op.GetAsync($"/api/bookings?status=cancelled&accommodationId={stayId}")).ReadJsonAsync();
        Assert.Equal(1, cancelled.RootElement.GetProperty("totalCount").GetInt32());
    }

    // ---- Roles --------------------------------------------------------------------------------

    [Fact]
    public async Task OnlyStaffManageStays()
    {
        var (op, destinationId, stayId) = await SeedStay();
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();
        using var anonymous = _factory.CreateClient();

        await (await traveler.PostAsJsonAsync("/api/accommodations", Stay(destinationId))).ExpectErrorAsync(403);
        await (await traveler.PutAsJsonAsync($"/api/accommodations/{stayId}", new { destinationId, name = "x1", pricePerNight = 1, maxGuestsPerRoom = 1, isActive = true })).ExpectErrorAsync(403);
        await (await traveler.DeleteAsync($"/api/accommodations/{stayId}")).ExpectErrorAsync(403);
        await (await traveler.PutAsJsonAsync($"/api/accommodations/{stayId}/availability", new { from = Day(0), to = Day(1), totalRooms = 9 })).ExpectErrorAsync(403);
        await (await anonymous.PostAsJsonAsync("/api/accommodations", Stay(destinationId))).ExpectErrorAsync(401);
    }

    [Fact]
    public async Task OnlyTravelersBook_AndOnlyStaffListEverything()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();
        var tripId = await CreateTrip(traveler);

        await (await op.PostAsJsonAsync("/api/bookings", Booking(tripId, stayId))).ExpectErrorAsync(403);
        await (await op.GetAsync("/api/bookings/mine")).ExpectErrorAsync(403);
        await (await traveler.GetAsync("/api/bookings")).ExpectErrorAsync(403);
    }

    [Fact]
    public async Task ABookingBelongsToItsTraveler()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var sam = await _factory.TravelerAsync();
        using var kim = await _factory.TravelerAsync();
        var bookingId = await IdOf(await sam.PostAsJsonAsync("/api/bookings", Booking(await CreateTrip(sam), stayId)));

        await (await kim.GetAsync($"/api/bookings/{bookingId}")).ExpectErrorAsync(403);
        await (await kim.PostAsync($"/api/bookings/{bookingId}/cancel", null)).ExpectErrorAsync(403);
        Assert.Equal(HttpStatusCode.OK, (await op.GetAsync($"/api/bookings/{bookingId}")).StatusCode);
    }

    [Fact]
    public async Task ATravelerCannotBookForSomeoneElsesTrip()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var sam = await _factory.TravelerAsync();
        using var kim = await _factory.TravelerAsync();
        var kimsTrip = await CreateTrip(kim);

        await (await sam.PostAsJsonAsync("/api/bookings", Booking(kimsTrip, stayId))).ExpectErrorAsync(404, "trip not found");
    }

    // ---- Stay validation ---------------------------------------------------------------------

    [Fact]
    public async Task CreatingAStay_ChecksEveryField()
    {
        using var op = await _factory.OperatorAsync();
        var destinationId = await CreateDestination(op);

        var negative = await (await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, price: -5))).ExpectErrorAsync(400);
        var tooPricey = await (await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, price: 10_000_001))).ExpectErrorAsync(400);
        var noRooms = await (await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, guests: 0))).ExpectErrorAsync(400);
        var tooMany = await (await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, guests: 21))).ExpectErrorAsync(400);
        var tinyName = await (await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, name: "A"))).ExpectErrorAsync(400);
        var badType = await (await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, type: "Spaceship"))).ExpectErrorAsync(400, "invalid value");
        var numericType = await (await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, type: 42))).ExpectErrorAsync(400);

        Assert.NotEmpty(negative.FieldErrors("pricePerNight"));
        Assert.NotEmpty(tooPricey.FieldErrors("pricePerNight"));
        Assert.NotEmpty(noRooms.FieldErrors("maxGuestsPerRoom"));
        Assert.NotEmpty(tooMany.FieldErrors("maxGuestsPerRoom"));
        Assert.NotEmpty(tinyName.FieldErrors("name"));
        Assert.NotEmpty(badType.FieldErrors("type"));
        Assert.NotEmpty(numericType.FieldErrors("type"));
    }

    [Fact]
    public async Task AStayNeedsARealDestination_AndAUniqueNameThere()
    {
        using var op = await _factory.OperatorAsync();
        var destinationId = await CreateDestination(op);
        var name = Unique("Twin");
        await IdOf(await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, name: name)));

        await (await op.PostAsJsonAsync("/api/accommodations", Stay(Guid.NewGuid().ToString()))).ExpectErrorAsync(400, "destination");
        await (await op.PostAsJsonAsync("/api/accommodations", Stay(destinationId, name: name.ToUpperInvariant()))).ExpectErrorAsync(409, "already has");
    }

    [Fact]
    public async Task SettingRooms_IsValidated()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;

        await (await op.PutAsJsonAsync($"/api/accommodations/{stayId}/availability", new { from = Day(5), to = Day(1), totalRooms = 2 })).ExpectErrorAsync(400, "'To' cannot be before");
        await (await op.PutAsJsonAsync($"/api/accommodations/{stayId}/availability", new { from = Day(1), to = Day(2), totalRooms = 501 })).ExpectErrorAsync(400);
        await (await op.PutAsJsonAsync($"/api/accommodations/{stayId}/availability", new { from = Day(-3), to = Day(2), totalRooms = 2 })).ExpectErrorAsync(400, "today or later");
        await (await op.PutAsJsonAsync($"/api/accommodations/{stayId}/availability", new { from = "not-a-date", to = Day(2), totalRooms = 2 })).ExpectErrorAsync(400, "invalid value");
    }

    [Fact]
    public async Task OperatorsCannotCloseNightsThatAreAlreadyBooked()
    {
        var (op, _, stayId) = await SeedStay(rooms: 2);
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();
        await IdOf(await traveler.PostAsJsonAsync("/api/bookings", Booking(await CreateTrip(traveler), stayId, checkIn: 5, nights: 1, rooms: 2, guests: 2)));

        var response = await op.PutAsJsonAsync($"/api/accommodations/{stayId}/availability", new { from = Day(4), to = Day(6), totalRooms = 1 });

        await response.ExpectErrorAsync(409, "already booked");
    }

    // ---- Booking / quote validation ----------------------------------------------------------

    [Fact]
    public async Task ABookingIsChecked()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();
        var tripId = await CreateTrip(traveler);
        var item = new { accommodationId = stayId, checkIn = Day(5), checkOut = Day(7), rooms = 1, guests = 1 };

        await (await traveler.PostAsJsonAsync("/api/bookings", new { tripId, items = Array.Empty<object>() })).ExpectErrorAsync(400);
        await (await traveler.PostAsJsonAsync("/api/bookings", new { tripId, items = new[] { item with { rooms = 0 } } })).ExpectErrorAsync(400);
        await (await traveler.PostAsJsonAsync("/api/bookings", new { tripId, items = new[] { item with { rooms = 11 } } })).ExpectErrorAsync(400);
        await (await traveler.PostAsJsonAsync("/api/bookings", new { tripId, items = new[] { item with { checkIn = Day(7), checkOut = Day(5) } } })).ExpectErrorAsync(400, "check-out must be after");
        await (await traveler.PostAsJsonAsync("/api/bookings", new { tripId, items = new[] { item with { checkIn = Day(-5), checkOut = Day(-3) } } })).ExpectErrorAsync(400, "in the past");
        await (await traveler.PostAsJsonAsync("/api/bookings", new { tripId, items = new[] { item with { guests = 3 } } })).ExpectErrorAsync(400, "sleeps at most");
        await (await traveler.PostAsJsonAsync("/api/bookings", new { tripId, items = new[] { item }, notes = new string('n', 501) })).ExpectErrorAsync(400);
        await (await traveler.PostAsJsonAsync("/api/bookings", new { tripId, items = new[] { new { accommodationId = Guid.NewGuid(), checkIn = Day(5), checkOut = Day(7), rooms = 1, guests = 1 } } })).ExpectErrorAsync(404);
    }

    [Fact]
    public async Task AValidationErrorInsideAnItem_NamesTheItemAndField()
    {
        using var traveler = await _factory.TravelerAsync();
        var tripId = await CreateTrip(traveler);

        var error = await (await traveler.PostAsJsonAsync("/api/bookings", new
        {
            tripId,
            items = new[] { new { accommodationId = Guid.NewGuid(), checkIn = Day(5), checkOut = Day(7), rooms = 0, guests = 1 } }
        })).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("items[0].rooms"));
    }

    [Fact]
    public async Task AQuoteNeedsGoodDates_AndAKnownStay()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();

        await (await traveler.GetAsync($"/api/accommodations/{stayId}/quote?checkIn=nope&checkOut={Day(8)}")).ExpectErrorAsync(400, "invalid value");
        await (await traveler.GetAsync($"/api/accommodations/{stayId}/quote")).ExpectErrorAsync(400);
        await (await traveler.GetAsync($"/api/accommodations/{stayId}/quote?checkIn={Day(8)}&checkOut={Day(5)}")).ExpectErrorAsync(400, "check-out must be after");
        await (await traveler.GetAsync($"/api/accommodations/{Guid.NewGuid()}/quote?checkIn={Day(5)}&checkOut={Day(8)}")).ExpectErrorAsync(404);
    }

    // ---- Reading -----------------------------------------------------------------------------

    [Fact]
    public async Task AnUnknownStay_Is404_AndSoIsAnIdThatCannotBeAGuid()
    {
        using var traveler = await _factory.TravelerAsync();

        await (await traveler.GetAsync($"/api/accommodations/{Guid.NewGuid()}")).ExpectErrorAsync(404);
        // The route only matches GUIDs, so "abc" matches no route at all.
        await (await traveler.GetAsync("/api/accommodations/abc")).ExpectErrorAsync(404);
    }

    [Fact]
    public async Task TheStayList_RefusesAnUnknownType_AndHidesInactiveStaysFromTravelers()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();
        await traveler.GetAsync("/api/accommodations?type=Banana").ContinueWith(t => t.Result.ExpectErrorAsync(400)).Unwrap();

        await op.DeleteAsync($"/api/accommodations/{stayId}");

        // The traveler asking for inactive stays is ignored; the operator gets them.
        using var forTraveler = await (await traveler.GetAsync($"/api/accommodations?includeInactive=true&pageSize=50")).ReadJsonAsync();
        using var forOperator = await (await op.GetAsync($"/api/accommodations?includeInactive=true&pageSize=50")).ReadJsonAsync();
        Assert.DoesNotContain(forTraveler.RootElement.GetProperty("items").EnumerateArray(), s => s.GetProperty("id").GetString() == stayId);
        Assert.Contains(forOperator.RootElement.GetProperty("items").EnumerateArray(), s => s.GetProperty("id").GetString() == stayId);
        await (await traveler.GetAsync($"/api/accommodations/{stayId}")).ExpectErrorAsync(404);
    }

    // ---- Reviews -----------------------------------------------------------------------------

    [Fact]
    public async Task AReviewNeedsAFinishedStay_AndARealRating()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();
        await IdOf(await traveler.PostAsJsonAsync("/api/bookings", Booking(await CreateTrip(traveler), stayId)));

        await (await traveler.PostAsJsonAsync($"/api/accommodations/{stayId}/reviews", new { rating = 5, comment = "Lovely" })).ExpectErrorAsync(403, "after your stay");
        var bad = await (await traveler.PostAsJsonAsync($"/api/accommodations/{stayId}/reviews", new { rating = 6, comment = "x" })).ExpectErrorAsync(400);
        Assert.NotEmpty(bad.FieldErrors("rating"));
        await (await traveler.PostAsJsonAsync($"/api/accommodations/{stayId}/reviews", new { rating = 5, comment = new string('c', 1001) })).ExpectErrorAsync(400);
        await (await op.PostAsJsonAsync($"/api/accommodations/{stayId}/reviews", new { rating = 5, comment = "x" })).ExpectErrorAsync(403);
        await (await traveler.PostAsJsonAsync($"/api/accommodations/{Guid.NewGuid()}/reviews", new { rating = 5, comment = "x" })).ExpectErrorAsync(404);
    }

    [Fact]
    public async Task ReviewsCanBeListed_AndAnUnknownReviewIsA404()
    {
        var (op, _, stayId) = await SeedStay();
        using var _ = op;
        using var traveler = await _factory.TravelerAsync();

        using var page = await (await traveler.GetAsync($"/api/accommodations/{stayId}/reviews?page=1&pageSize=5")).ReadJsonAsync();
        Assert.Equal(0, page.RootElement.GetProperty("totalCount").GetInt32());
        await (await traveler.DeleteAsync($"/api/reviews/{Guid.NewGuid()}")).ExpectErrorAsync(404);
    }
}
