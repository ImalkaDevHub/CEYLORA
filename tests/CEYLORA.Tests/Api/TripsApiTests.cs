using System.Net;
using System.Net.Http.Json;

namespace CEYLORA.Tests.Api;

public class TripsApiTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public TripsApiTests(ApiFactory factory) => _factory = factory;

    private static string Day(int offsetFromTodayUtc) =>
        DateTime.UtcNow.Date.AddDays(offsetFromTodayUtc).ToString("yyyy-MM-dd");

    private static object Trip(string title = "South coast", int start = 10, int end = 14, object? budget = null) =>
        new { title, startDate = Day(start), endDate = Day(end), budget = budget ?? 150000 };

    private async Task<HttpResponseMessage> Create(HttpClient client, object body) =>
        await client.PostAsJsonAsync("/api/trips", body);

    // ---- Create: success ---------------------------------------------------------------------

    [Fact]
    public async Task Create_ReturnsTheNewDraftTrip_WithItsLocation()
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await Create(traveler, Trip());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
        using var body = await response.ReadJsonAsync();
        Assert.Equal("South coast", body.RootElement.GetProperty("title").GetString());
        Assert.Equal("Draft", body.RootElement.GetProperty("status").GetString());
        Assert.Equal(150000m, body.RootElement.GetProperty("budget").GetDecimal());
    }

    [Fact]
    public async Task Create_TrimsTheTitle()
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await Create(traveler, Trip(title: "   Hill country   "));

        using var body = await response.ReadJsonAsync();
        Assert.Equal("Hill country", body.RootElement.GetProperty("title").GetString());
    }

    [Theory]
    [InlineData(0, 0)]    // one day, starting today
    [InlineData(-1, 2)]   // yesterday in UTC: allowed, a traveler ahead of UTC is already on "today"
    [InlineData(10, 10)]  // one-day trip
    public async Task Create_AcceptsTheseDates(int start, int end)
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await Create(traveler, Trip(start: start, end: end));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task Create_AcceptsAFullYear_AndABudgetOfZeroOrTheMaximum()
    {
        using var traveler = await _factory.TravelerAsync();

        Assert.Equal(HttpStatusCode.Created, (await Create(traveler, Trip(start: 5, end: 5 + 364))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Create(traveler, Trip(budget: 0))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Create(traveler, Trip(budget: 1000000000))).StatusCode);
    }

    // ---- Create: validation ------------------------------------------------------------------

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("A")]
    public async Task Create_NeedsARealTitle(string title)
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, Trip(title: title))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("title"));
    }

    [Fact]
    public async Task Create_RefusesATitleOver120Characters()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, Trip(title: new string('x', 121)))).ExpectErrorAsync(400);

        Assert.Contains("2 to 120", error.FieldErrors("title")[0]);
    }

    [Fact]
    public async Task Create_NeedsBothDates()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, new { title = "No dates", budget = 1 })).ExpectErrorAsync(400);

        Assert.Contains("Start date is required.", error.FieldErrors("startDate"));
        Assert.Contains("End date is required.", error.FieldErrors("endDate"));
    }

    [Fact]
    public async Task Create_RefusesAnEndBeforeTheStart()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, Trip(start: 14, end: 10))).ExpectErrorAsync(400, "end date cannot be before");

        Assert.NotEmpty(error.FieldErrors("endDate"));
    }

    [Theory]
    [InlineData(-2)]
    [InlineData(-30)]
    public async Task Create_RefusesAStartInThePast(int start)
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, Trip(start: start, end: 5))).ExpectErrorAsync(400, "in the past");

        Assert.NotEmpty(error.FieldErrors("startDate"));
    }

    [Fact]
    public async Task Create_RefusesAStartMoreThanFiveYearsAway()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, new
        {
            title = "Far away",
            startDate = DateTime.UtcNow.Date.AddYears(5).AddDays(2).ToString("yyyy-MM-dd"),
            endDate = DateTime.UtcNow.Date.AddYears(5).AddDays(4).ToString("yyyy-MM-dd"),
            budget = 1
        })).ExpectErrorAsync(400, "too far ahead");

        Assert.NotEmpty(error.FieldErrors("startDate"));
    }

    [Fact]
    public async Task Create_RefusesATripLongerThanAYear()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, Trip(start: 5, end: 5 + 365))).ExpectErrorAsync(400, "at most 365 days");

        Assert.NotEmpty(error.FieldErrors("endDate"));
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(1000000001)]
    public async Task Create_RefusesABudgetOutOfRange(long budget)
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, Trip(budget: budget))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("budget"));
    }

    [Fact]
    public async Task Create_RefusesABudgetThatIsNotANumber()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, Trip(budget: "lots"))).ExpectErrorAsync(400, "invalid value");

        Assert.NotEmpty(error.FieldErrors("budget"));
    }

    [Fact]
    public async Task Create_RefusesADateThatIsNotADate()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await Create(traveler, new { title = "Bad", startDate = "next friday", endDate = Day(5), budget = 1 }))
            .ExpectErrorAsync(400, "invalid value");

        Assert.NotEmpty(error.FieldErrors("startDate"));
    }

    // ---- Access -------------------------------------------------------------------------------

    [Fact]
    public async Task Create_NeedsATraveler()
    {
        using var op = await _factory.OperatorAsync();
        using var anonymous = _factory.CreateClient();

        await (await Create(op, Trip())).ExpectErrorAsync(403);
        await (await Create(anonymous, Trip())).ExpectErrorAsync(401);
    }

    [Fact]
    public async Task Mine_ListsOnlyTheCallersTrips()
    {
        using var sam = await _factory.TravelerAsync();
        using var kim = await _factory.TravelerAsync();
        await Create(sam, Trip(title: "Sam's trip"));
        await Create(kim, Trip(title: "Kim's trip"));

        var response = await sam.GetAsync("/api/trips/mine");

        using var body = await response.ReadJsonAsync();
        var titles = body.RootElement.EnumerateArray().Select(t => t.GetProperty("title").GetString()).ToList();
        Assert.Equal(new[] { "Sam's trip" }, titles);
    }

    [Fact]
    public async Task Submit_MovesADraftToSubmitted_OnceOnly_AndOnlyForTheOwner()
    {
        using var sam = await _factory.TravelerAsync();
        using var kim = await _factory.TravelerAsync();
        using var created = await (await Create(sam, Trip())).ReadJsonAsync();
        var id = created.RootElement.GetProperty("id").GetString();

        await (await kim.PostAsync($"/api/trips/{id}/submit", null)).ExpectErrorAsync(400);

        var first = await sam.PostAsync($"/api/trips/{id}/submit", null);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        using var body = await first.ReadJsonAsync();
        Assert.Equal("Submitted", body.RootElement.GetProperty("status").GetString());

        await (await sam.PostAsync($"/api/trips/{id}/submit", null)).ExpectErrorAsync(400);
    }

    [Fact]
    public async Task AnIdThatIsNotAGuid_Is400WithAMessage()
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await traveler.GetAsync("/api/trips/abc");

        await response.ExpectErrorAsync(400, "invalid value");
    }
}
