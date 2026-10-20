using CEYLORA.Application.Interfaces;
using CEYLORA.Infrastructure.Services;
using CEYLORA.Infrastructure.Services.Http;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// JsonStringEnumConverter: lets clients send/receive enums (TravelCategory, TripStatus, ...)
// as their string names (e.g. "Nature") instead of only the raw numeric value System.Text.Json
// defaults to — this is what request bodies like { "category": "Nature" } rely on.
builder.Services.AddControllers()
    .AddJsonOptions(options =>
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()));

// Add DbContext
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// Register the auth service for DI
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<ITripService, TripService>();
builder.Services.AddScoped<IDestinationService, DestinationService>();
builder.Services.AddScoped<IAiWorkflowService, AiWorkflowService>();
builder.Services.AddScoped<IAccommodationService, AccommodationService>();
builder.Services.AddScoped<IBookingService, BookingService>();
builder.Services.AddScoped<IReviewService, ReviewService>();

// "Today" for booking rules comes from here, so tests can pin the date.
builder.Services.AddSingleton(TimeProvider.System);

// Typed HttpClient for the external ceylora-ai-service (FastAPI/LangGraph).
// The client instance is DI-managed — AiPlanningClient never news up an HttpClient.
builder.Services.AddHttpClient<IAiPlanningClient, AiPlanningClient>(client =>
{
    client.BaseAddress = new Uri(builder.Configuration["AiService:BaseUrl"] ?? "http://localhost:8001");
    client.Timeout = TimeSpan.FromSeconds(30);
});

// Configure JWT authentication
var jwtKey = builder.Configuration["Jwt:Key"]!;
builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = builder.Configuration["Jwt:Issuer"],
        ValidAudience = builder.Configuration["Jwt:Audience"],
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey))
    };
});

builder.Services.AddAuthorization();

// Allow the React web app (different origin) to call this API from a browser
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowClients", policy =>
    {
        policy.WithOrigins(
                "http://localhost:3000",   // React dev server (adjust if you use Vite's 5173)
                "http://localhost:5173"
              )
            .AllowAnyHeader()
            .AllowAnyMethod();
        // Flutter mobile doesn't send a browser Origin header, so it isn't blocked by CORS —
        // this policy only matters for the React web app.
    });
});

// Using built-in OpenAPI for .NET instead of Swashbuckle
builder.Services.AddOpenApi();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

app.UseCors("AllowClients");

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

// Health endpoint for deployment evidence (spec Section 14)
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

// Opt-in sample catalogue (destinations, stays and room inventory) for demos:
//   dotnet user-secrets set "Seed:DemoData" "true" --project src/CEYLORA.Api
// It only ever fills an empty accommodation table and never changes existing rows.
if (app.Configuration.GetValue<bool>("Seed:DemoData"))
{
    using var scope = app.Services.CreateScope();
    var created = await DemoDataSeeder.SeedAsync(
        scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(),
        scope.ServiceProvider.GetRequiredService<TimeProvider>());
    app.Logger.LogInformation("Demo data seeder added {Count} accommodations.", created);
}

app.Run();
