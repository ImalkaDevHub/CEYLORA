using System.Net;
using System.Net.Http.Json;

namespace CEYLORA.Tests.Api;

public class AuthApiTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public AuthApiTests(ApiFactory factory) => _factory = factory;

    private static object Register(string? email = null, string password = ApiFactory.StrongPassword,
        string fullName = "Sam Traveler", string? role = null) => role is null
        ? new { email = email ?? ApiFactory.UniqueEmail(), password, fullName }
        : new { email = email ?? ApiFactory.UniqueEmail(), password, fullName, roleName = role };

    private async Task<HttpResponseMessage> PostRegister(object body)
    {
        using var client = _factory.CreateClient();
        return await client.PostAsJsonAsync("/api/auth/register", body);
    }

    private async Task<HttpResponseMessage> PostLogin(object body)
    {
        using var client = _factory.CreateClient();
        return await client.PostAsJsonAsync("/api/auth/login", body);
    }

    // ---- Register: success -----------------------------------------------------------------

    [Fact]
    public async Task Register_CreatesATraveler_ByDefault_AndReturnsAToken()
    {
        var response = await PostRegister(Register(email: "sam@example.com", fullName: "Sam Traveler"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await response.ReadJsonAsync();
        Assert.Equal("Traveler", body.RootElement.GetProperty("role").GetString());
        Assert.Equal("Sam Traveler", body.RootElement.GetProperty("fullName").GetString());
        Assert.False(string.IsNullOrWhiteSpace(body.RootElement.GetProperty("token").GetString()));
    }

    [Fact]
    public async Task Register_StoresTheEmailInLowerCase_AndTrimsTheName()
    {
        var email = ApiFactory.UniqueEmail("Mixed");
        var response = await PostRegister(Register(email: "  " + email.ToUpperInvariant() + "  ", fullName: "  Sam Traveler  "));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await response.ReadJsonAsync();
        Assert.Equal(email.ToLowerInvariant(), body.RootElement.GetProperty("email").GetString());
        Assert.Equal("Sam Traveler", body.RootElement.GetProperty("fullName").GetString());
    }

    [Theory]
    [InlineData("Traveler")]
    [InlineData("Operator")]
    public async Task Register_AcceptsTheKnownRoles(string role)
    {
        var response = await PostRegister(Register(role: role));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await response.ReadJsonAsync();
        Assert.Equal(role, body.RootElement.GetProperty("role").GetString());
    }

    [Fact]
    public async Task Register_AcceptsEightCharactersAndSeventyTwo()
    {
        Assert.Equal(HttpStatusCode.OK, (await PostRegister(Register(password: "abcdefg1"))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await PostRegister(Register(password: new string('a', 71) + "1"))).StatusCode);
    }

    // ---- Register: validation ----------------------------------------------------------------

    [Theory]
    [InlineData("not-an-email")]
    [InlineData("two@@example.com")]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Register_RefusesABadEmail(string email)
    {
        var response = await PostRegister(Register(email: email));

        var error = await response.ExpectErrorAsync(400);
        Assert.Contains("email", error.GetProperty("errors").EnumerateObject().Select(p => p.Name));
    }

    [Fact]
    public async Task Register_RefusesAnEmailThatIsTooLong()
    {
        var response = await PostRegister(Register(email: new string('a', 250) + "@x.com"));

        var error = await response.ExpectErrorAsync(400);
        Assert.Contains("too long", error.FieldErrors("email").First(), StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("short1", "8 to 72")]
    [InlineData("", "required")]
    [InlineData("allletters", "letter and one number")]
    [InlineData("12345678", "letter and one number")]
    public async Task Register_RefusesAWeakPassword(string password, string expected)
    {
        var response = await PostRegister(Register(password: password));

        var error = await response.ExpectErrorAsync(400);
        Assert.Contains(error.FieldErrors("password"), m => m.Contains(expected, StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Register_RefusesAPasswordLongerThanBcryptUses()
    {
        var response = await PostRegister(Register(password: new string('a', 72) + "1")); // 73

        var error = await response.ExpectErrorAsync(400);
        Assert.Contains(error.FieldErrors("password"), m => m.Contains("8 to 72"));
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("A")]
    public async Task Register_RefusesAMissingOrTinyName(string name)
    {
        var response = await PostRegister(Register(fullName: name));

        var error = await response.ExpectErrorAsync(400);
        Assert.NotEmpty(error.FieldErrors("fullName"));
    }

    [Theory]
    [InlineData("Superuser")]
    [InlineData("traveler")]
    [InlineData("")]
    public async Task Register_RefusesAnUnknownRole(string role)
    {
        var response = await PostRegister(Register(role: role));

        var error = await response.ExpectErrorAsync(400);
        Assert.NotEmpty(error.FieldErrors("roleName"));
    }

    [Fact]
    public async Task Register_ReportsEveryProblemAtOnce_WithTheFirstAsTheMessage()
    {
        var response = await PostRegister(new { email = "nope", password = "x", fullName = "" });

        var error = await response.ExpectErrorAsync(400);
        var fields = error.GetProperty("errors").EnumerateObject().Select(p => p.Name).ToHashSet();
        Assert.Superset(new HashSet<string> { "email", "password", "fullName" }, fields);
        Assert.False(string.IsNullOrWhiteSpace(error.GetProperty("message").GetString()));
    }

    [Fact]
    public async Task Register_RefusesAnEmptyBody()
    {
        using var client = _factory.CreateClient();
        var response = await client.PostAsync("/api/auth/register", new StringContent("", System.Text.Encoding.UTF8, "application/json"));

        await response.ExpectErrorAsync(400);
    }

    [Fact]
    public async Task Register_RefusesBrokenJson_WithoutLeakingParserDetails()
    {
        using var client = _factory.CreateClient();
        var response = await client.PostAsync("/api/auth/register", new StringContent("{ not json", System.Text.Encoding.UTF8, "application/json"));

        var error = await response.ExpectErrorAsync(400);
        Assert.Contains("not valid JSON", error.GetProperty("message").GetString());
    }

    [Fact]
    public async Task Register_RefusesTheWrongContentType()
    {
        using var client = _factory.CreateClient();
        var response = await client.PostAsync("/api/auth/register", new StringContent("email=a", System.Text.Encoding.UTF8, "text/plain"));

        await response.ExpectErrorAsync(415);
    }

    // ---- Register: duplicates ----------------------------------------------------------------

    [Fact]
    public async Task Register_RefusesAnEmailThatIsAlreadyTaken_IgnoringCaseAndSpaces()
    {
        var email = ApiFactory.UniqueEmail("dup");
        Assert.Equal(HttpStatusCode.OK, (await PostRegister(Register(email: email))).StatusCode);

        var again = await PostRegister(Register(email: "  " + email.ToUpperInvariant() + " "));

        await again.ExpectErrorAsync(409, "already registered");
    }

    // ---- Login --------------------------------------------------------------------------------

    [Fact]
    public async Task Login_WorksWhateverTheCaseOfTheEmail()
    {
        var email = ApiFactory.UniqueEmail("login");
        await PostRegister(Register(email: email));

        var response = await PostLogin(new { email = email.ToUpperInvariant(), password = ApiFactory.StrongPassword });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = await response.ReadJsonAsync();
        Assert.False(string.IsNullOrWhiteSpace(body.RootElement.GetProperty("token").GetString()));
    }

    [Fact]
    public async Task Login_GivesTheSameAnswerForAWrongPasswordAndAnUnknownEmail()
    {
        var email = ApiFactory.UniqueEmail("who");
        await PostRegister(Register(email: email));

        var wrongPassword = await PostLogin(new { email, password = "Wrong-pass1" });
        var unknownEmail = await PostLogin(new { email = ApiFactory.UniqueEmail("ghost"), password = "Wrong-pass1" });

        var a = await wrongPassword.ExpectErrorAsync(401);
        var b = await unknownEmail.ExpectErrorAsync(401);
        // Nothing reveals which emails have accounts.
        Assert.Equal(a.GetProperty("message").GetString(), b.GetProperty("message").GetString());
    }

    [Theory]
    [InlineData("", "Passw0rd1")]
    [InlineData("a@b.com", "")]
    public async Task Login_NeedsBothFields(string email, string password)
    {
        var response = await PostLogin(new { email, password });

        await response.ExpectErrorAsync(400);
    }

    [Fact]
    public async Task Login_DoesNotApplyThePasswordStrengthRule_SoOldAccountsStillWork()
    {
        // The strength rules are for new registrations only; a short password is simply "wrong" here.
        var response = await PostLogin(new { email = ApiFactory.UniqueEmail(), password = "abc" });

        await response.ExpectErrorAsync(401);
    }

    [Fact]
    public async Task Login_RefusesAbsurdlyLongInput()
    {
        var response = await PostLogin(new { email = new string('a', 300), password = "x" });

        await response.ExpectErrorAsync(400);
    }
}
