using System.Net;
using System.Net.Http.Json;

namespace CEYLORA.Tests.Api;

public class DestinationsApiTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public DestinationsApiTests(ApiFactory factory) => _factory = factory;

    private static object Destination(string name = "Ella", string region = "Uva Province", string description = "Tea hills",
        object? category = null, string? imageUrl = null) =>
        new { name, region, description, category = category ?? "Nature", imageUrl };

    private static string Unique(string name) => $"{name}-{Guid.NewGuid():N}"[..Math.Min(40, name.Length + 33)];

    // ---- Create ------------------------------------------------------------------------------

    [Fact]
    public async Task Create_ReturnsTheDestination()
    {
        using var op = await _factory.OperatorAsync();

        var response = await op.PostAsJsonAsync("/api/destinations", Destination(name: "Sigiriya", category: "Culture", imageUrl: "https://img.example/sigiriya.jpg"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        using var body = await response.ReadJsonAsync();
        Assert.Equal("Sigiriya", body.RootElement.GetProperty("name").GetString());
        Assert.Equal("Culture", body.RootElement.GetProperty("category").GetString());
        Assert.Equal("https://img.example/sigiriya.jpg", body.RootElement.GetProperty("imageUrl").GetString());
        Assert.True(body.RootElement.GetProperty("isActive").GetBoolean());
    }

    [Fact]
    public async Task Create_AllowsNoImageAndNoDescription()
    {
        using var op = await _factory.OperatorAsync();

        var response = await op.PostAsJsonAsync("/api/destinations", new { name = "Mirissa", region = "South", category = "Beach" });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task Create_AcceptsHttpAndHttpsImages()
    {
        using var op = await _factory.OperatorAsync();

        Assert.Equal(HttpStatusCode.Created, (await op.PostAsJsonAsync("/api/destinations", Destination(imageUrl: "http://img.example/a.png"))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await op.PostAsJsonAsync("/api/destinations", Destination(imageUrl: "  "))).StatusCode);
    }

    [Theory]
    [InlineData("", "name")]
    [InlineData("A", "name")]
    public async Task Create_NeedsARealName(string name, string field)
    {
        using var op = await _factory.OperatorAsync();

        var error = await (await op.PostAsJsonAsync("/api/destinations", Destination(name: name))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors(field));
    }

    [Fact]
    public async Task Create_RefusesTooLongText()
    {
        using var op = await _factory.OperatorAsync();

        var longName = await (await op.PostAsJsonAsync("/api/destinations", Destination(name: new string('n', 151)))).ExpectErrorAsync(400);
        var longRegion = await (await op.PostAsJsonAsync("/api/destinations", Destination(region: new string('r', 101)))).ExpectErrorAsync(400);
        var longDescription = await (await op.PostAsJsonAsync("/api/destinations", Destination(description: new string('d', 4001)))).ExpectErrorAsync(400);

        Assert.NotEmpty(longName.FieldErrors("name"));
        Assert.NotEmpty(longRegion.FieldErrors("region"));
        Assert.NotEmpty(longDescription.FieldErrors("description"));
    }

    [Fact]
    public async Task Create_NeedsARegion()
    {
        using var op = await _factory.OperatorAsync();

        var error = await (await op.PostAsJsonAsync("/api/destinations", Destination(region: ""))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("region"));
    }

    [Theory]
    [InlineData("javascript:alert(1)")]
    [InlineData("ftp://files.example/a.png")]
    [InlineData("file:///etc/passwd")]
    [InlineData("not a url")]
    [InlineData("//no-scheme.example/a.png")]
    public async Task Create_RefusesAnImageThatIsNotAnHttpLink(string url)
    {
        using var op = await _factory.OperatorAsync();

        var error = await (await op.PostAsJsonAsync("/api/destinations", Destination(imageUrl: url))).ExpectErrorAsync(400);

        Assert.Contains("http", error.FieldErrors("imageUrl")[0]);
    }

    [Fact]
    public async Task Create_RefusesAnImageLinkOver2048Characters()
    {
        using var op = await _factory.OperatorAsync();

        var error = await (await op.PostAsJsonAsync("/api/destinations",
            Destination(imageUrl: "https://img.example/" + new string('a', 2040)))).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("imageUrl"));
    }

    [Fact]
    public async Task Create_RefusesAnUnknownCategory_ByNameOrNumber()
    {
        using var op = await _factory.OperatorAsync();

        var byName = await (await op.PostAsJsonAsync("/api/destinations", Destination(category: "Banana"))).ExpectErrorAsync(400, "invalid value");
        var byNumber = await (await op.PostAsJsonAsync("/api/destinations", Destination(category: 99))).ExpectErrorAsync(400);

        Assert.NotEmpty(byName.FieldErrors("category"));
        Assert.NotEmpty(byNumber.FieldErrors("category"));
    }

    [Fact]
    public async Task Create_NeedsAnOperator()
    {
        using var traveler = await _factory.TravelerAsync();
        using var anonymous = _factory.CreateClient();

        await (await traveler.PostAsJsonAsync("/api/destinations", Destination())).ExpectErrorAsync(403);
        await (await anonymous.PostAsJsonAsync("/api/destinations", Destination())).ExpectErrorAsync(401);
    }

    // ---- Update / delete ---------------------------------------------------------------------

    [Fact]
    public async Task Update_AppliesTheSameRules()
    {
        using var op = await _factory.OperatorAsync();
        using var created = await (await op.PostAsJsonAsync("/api/destinations", Destination(name: Unique("Yala")))).ReadJsonAsync();
        var id = created.RootElement.GetProperty("id").GetString();

        var bad = await op.PutAsJsonAsync($"/api/destinations/{id}", new { name = "", region = "South", category = "Wildlife", isActive = true });
        var good = await op.PutAsJsonAsync($"/api/destinations/{id}", new { name = "Yala NP", region = "South", category = "Wildlife", isActive = true });

        await bad.ExpectErrorAsync(400);
        Assert.Equal(HttpStatusCode.OK, good.StatusCode);
    }

    [Fact]
    public async Task Update_OfAnUnknownDestination_Is404()
    {
        using var op = await _factory.OperatorAsync();

        var response = await op.PutAsJsonAsync($"/api/destinations/{Guid.NewGuid()}", new { name = "Nowhere", region = "Elsewhere", category = "Beach", isActive = true });

        await response.ExpectErrorAsync(404);
    }

    [Fact]
    public async Task Delete_NeedsAnOperator_AndUnknownIsA404()
    {
        using var op = await _factory.OperatorAsync();
        using var traveler = await _factory.TravelerAsync();

        await (await traveler.DeleteAsync($"/api/destinations/{Guid.NewGuid()}")).ExpectErrorAsync(403);
        await (await op.DeleteAsync($"/api/destinations/{Guid.NewGuid()}")).ExpectErrorAsync(404);
    }

    // ---- Reading: paging, sorting, filtering -------------------------------------------------

    [Theory]
    [InlineData("page=0", "page")]
    [InlineData("page=-3", "page")]
    [InlineData("pageSize=0", "pageSize")]
    [InlineData("pageSize=101", "pageSize")]
    [InlineData("pageSize=-1", "pageSize")]
    [InlineData("sortBy=Banana", "sortBy")]
    [InlineData("category=Banana", "category")]
    [InlineData("category=99", "category")]
    public async Task List_RefusesBadQueryValues(string query, string field)
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await traveler.GetAsync($"/api/destinations?{query}")).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors(field));
    }

    [Fact]
    public async Task List_RefusesLongSearchText()
    {
        using var traveler = await _factory.TravelerAsync();

        var error = await (await traveler.GetAsync($"/api/destinations?search={new string('a', 101)}")).ExpectErrorAsync(400);

        Assert.NotEmpty(error.FieldErrors("search"));
    }

    [Theory]
    [InlineData("page=1&pageSize=100")]
    [InlineData("sortBy=region")]
    [InlineData("sortBy=NAME&sortDescending=true")]
    [InlineData("category=Beach")]
    [InlineData("")]
    public async Task List_AcceptsGoodQueries(string query)
    {
        using var traveler = await _factory.TravelerAsync();

        var response = await traveler.GetAsync($"/api/destinations?{query}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await response.ReadJsonAsync();
        Assert.True(body.RootElement.TryGetProperty("items", out _));
        Assert.True(body.RootElement.TryGetProperty("totalCount", out _));
    }

    [Fact]
    public async Task List_FiltersAndSearches()
    {
        using var op = await _factory.OperatorAsync();
        var token = Guid.NewGuid().ToString("N")[..8];
        await op.PostAsJsonAsync("/api/destinations", Destination(name: $"Beachy {token}", category: "Beach"));
        await op.PostAsJsonAsync("/api/destinations", Destination(name: $"Hilly {token}", category: "Nature"));

        var both = await (await op.GetAsync($"/api/destinations?search={token}")).ReadJsonAsync();
        var beach = await (await op.GetAsync($"/api/destinations?search={token}&category=Beach")).ReadJsonAsync();

        Assert.Equal(2, both.RootElement.GetProperty("totalCount").GetInt32());
        Assert.Equal(1, beach.RootElement.GetProperty("totalCount").GetInt32());
    }

    [Fact]
    public async Task Get_AnUnknownDestination_Is404_AndAMalformedIdIs400()
    {
        using var traveler = await _factory.TravelerAsync();

        await (await traveler.GetAsync($"/api/destinations/{Guid.NewGuid()}")).ExpectErrorAsync(404);
        await (await traveler.GetAsync("/api/destinations/abc")).ExpectErrorAsync(400);
    }
}
