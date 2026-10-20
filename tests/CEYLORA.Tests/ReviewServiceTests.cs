using CEYLORA.Application.Common;
using CEYLORA.Application.DTOs.Bookings;
using CEYLORA.Application.DTOs.Reviews;
using CEYLORA.Domain.Entities;
using CEYLORA.Tests.Support;

namespace CEYLORA.Tests;

public class ReviewServiceTests : IDisposable
{
    private readonly BookingFixture _f = new();
    private static readonly DateOnly Nov1 = BookingFixture.Nov1;

    public void Dispose() => _f.Dispose();

    private static CreateReviewDto Review(int rating = 5, string comment = "Lovely stay") =>
        new() { Rating = rating, Comment = comment };

    /// <summary>Sam books Sea View for 1-3 November (check-out on the 3rd).</summary>
    private async Task<BookingResponseDto> SamBooks(User? who = null)
    {
        var traveler = who ?? _f.Sam;
        var trip = traveler.Id == _f.Kim.Id ? _f.KimTrip : _f.SamTrip;
        var result = await _f.Bookings.CreateAsync(traveler.Id, new CreateBookingDto
        {
            TripId = trip.Id,
            Items = new()
            {
                new() { AccommodationId = _f.SeaView.Id, CheckIn = Nov1, CheckOut = Nov1.AddDays(2), Rooms = 1, Guests = 2 }
            }
        });
        Assert.True(result.Succeeded, result.Message);
        return result.Value!;
    }

    // ---- Eligibility -----------------------------------------------------------------------

    [Fact]
    public async Task CannotReviewWithoutEverBooking()
    {
        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review());

        Assert.Equal(ServiceError.Forbidden, result.Error);
    }

    [Fact]
    public async Task CannotReviewBeforeTheStayHasEnded()
    {
        await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(1)); // mid-stay

        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review());

        Assert.Equal(ServiceError.Forbidden, result.Error);
    }

    [Fact]
    public async Task CanReviewOnTheCheckoutDay()
    {
        await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(2)); // check-out day

        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review());

        Assert.True(result.Succeeded, result.Message);
    }

    [Fact]
    public async Task ACancelledBookingDoesNotQualify()
    {
        var booking = await SamBooks();
        await _f.Bookings.CancelAsync(booking.Id, _f.Sam.Id, isStaff: false);
        _f.MoveClockTo(Nov1.AddDays(10));

        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review());

        Assert.Equal(ServiceError.Forbidden, result.Error);
    }

    [Fact]
    public async Task AnotherTravelersStayDoesNotQualifyYou()
    {
        await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(10));

        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Kim.Id, Review());

        Assert.Equal(ServiceError.Forbidden, result.Error);
    }

    [Fact]
    public async Task AStayElsewhereDoesNotQualifyForThisPlace()
    {
        var inn = _f.AddAccommodation(_f.Ella, "Ella Inn", 9000m);
        _f.SetRooms(inn, Nov1, Nov1.AddDays(5), 1);
        await _f.Bookings.CreateAsync(_f.Sam.Id, new CreateBookingDto
        {
            TripId = _f.SamTrip.Id,
            Items = new() { new() { AccommodationId = inn.Id, CheckIn = Nov1, CheckOut = Nov1.AddDays(2), Rooms = 1, Guests = 1 } }
        });
        _f.MoveClockTo(Nov1.AddDays(10));

        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review());

        Assert.Equal(ServiceError.Forbidden, result.Error);
    }

    // ---- Creating ---------------------------------------------------------------------------

    [Fact]
    public async Task ReviewIsStoredWithTheAuthorAndProof()
    {
        var booking = await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(5));

        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review(4, "  Quiet and clean  "));

        var review = result.Value!;
        Assert.Equal(4, review.Rating);
        Assert.Equal("Quiet and clean", review.Comment);
        Assert.Equal("Sam Traveler", review.TravelerName);
        Assert.Equal(_f.SeaView.Id, review.AccommodationId);
        Assert.Equal(booking.Id, _f.Db.Reviews.Single().BookingId);
    }

    [Fact]
    public async Task AccommodationRatingUpdates()
    {
        await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(5));

        await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review(4));

        var stay = await _f.Accommodations.GetByIdAsync(_f.SeaView.Id);
        Assert.Equal(4.0, stay!.AverageRating);
        Assert.Equal(1, stay.ReviewCount);
    }

    [Fact]
    public async Task CannotReviewTheSamePlaceTwice()
    {
        await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(5));
        await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review(5));

        var second = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review(1));

        Assert.Equal(ServiceError.Conflict, second.Error);
        Assert.Single(_f.Db.Reviews);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(6)]
    [InlineData(-3)]
    public async Task RatingMustBeOneToFive(int rating)
    {
        await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(5));

        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review(rating));

        Assert.Equal(ServiceError.Invalid, result.Error);
        Assert.Empty(_f.Db.Reviews);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(5)]
    public async Task RatingBoundsAreAllowed(int rating)
    {
        await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(5));

        Assert.True((await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review(rating))).Succeeded);
    }

    [Fact]
    public async Task ReviewOfAnUnknownPlace_IsNotFound()
    {
        var result = await _f.Reviews.CreateAsync(Guid.NewGuid(), _f.Sam.Id, Review());

        Assert.Equal(ServiceError.NotFound, result.Error);
    }

    [Fact]
    public async Task CanStillReviewAPlaceThatWasLaterDeactivated()
    {
        await SamBooks();
        _f.MoveClockTo(Nov1.AddDays(5));
        await _f.Accommodations.DeactivateAsync(_f.SeaView.Id);

        var result = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review());

        Assert.True(result.Succeeded, result.Message);
    }

    // ---- Listing ----------------------------------------------------------------------------

    private async Task<List<ReviewResponseDto>> SeedTwoReviews()
    {
        await SamBooks();
        await SamBooks(_f.Kim);
        _f.MoveClockTo(Nov1.AddDays(5));
        var first = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review(5, "first"));
        _f.Clock.Set(_f.Clock.GetUtcNow().AddMinutes(5));
        var second = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Kim.Id, Review(3, "second"));
        return new() { first.Value!, second.Value! };
    }

    [Fact]
    public async Task List_IsNewestFirst_WithAuthorNames()
    {
        await SeedTwoReviews();

        var result = await _f.Reviews.GetForAccommodationAsync(_f.SeaView.Id, 1, 10);

        var page = result.Value!;
        Assert.Equal(2, page.TotalCount);
        Assert.Equal(new[] { "second", "first" }, page.Items.Select(r => r.Comment));
        Assert.Equal(new[] { "Kim Traveler", "Sam Traveler" }, page.Items.Select(r => r.TravelerName));
    }

    [Fact]
    public async Task List_Pages()
    {
        await SeedTwoReviews();

        var page2 = (await _f.Reviews.GetForAccommodationAsync(_f.SeaView.Id, 2, 1)).Value!;

        Assert.Equal(2, page2.TotalCount);
        Assert.Equal("first", Assert.Single(page2.Items).Comment);
    }

    [Fact]
    public async Task List_ClampsBadPaging()
    {
        var page = (await _f.Reviews.GetForAccommodationAsync(_f.SeaView.Id, -5, 100000)).Value!;

        Assert.Equal(1, page.Page);
        Assert.Equal(ReviewServiceLimits.MaxPage, page.PageSize);
    }

    [Fact]
    public async Task List_OfAnUnknownPlace_IsNotFound()
    {
        var result = await _f.Reviews.GetForAccommodationAsync(Guid.NewGuid(), 1, 10);

        Assert.Equal(ServiceError.NotFound, result.Error);
    }

    [Fact]
    public async Task List_WithNoReviews_IsEmpty()
    {
        var page = (await _f.Reviews.GetForAccommodationAsync(_f.SeaView.Id, 1, 10)).Value!;

        Assert.Empty(page.Items);
        Assert.Equal(0, page.TotalCount);
    }

    // ---- Deleting ---------------------------------------------------------------------------

    [Fact]
    public async Task AuthorCanDeleteTheirReview_AndRatingRecalculates()
    {
        var reviews = await SeedTwoReviews();

        var result = await _f.Reviews.DeleteAsync(reviews[0].Id, _f.Sam.Id, isAdmin: false);

        Assert.True(result.Succeeded);
        var stay = await _f.Accommodations.GetByIdAsync(_f.SeaView.Id);
        Assert.Equal(1, stay!.ReviewCount);
        Assert.Equal(3.0, stay.AverageRating);
    }

    [Fact]
    public async Task AnotherTravelerCannotDelete()
    {
        var reviews = await SeedTwoReviews();

        var result = await _f.Reviews.DeleteAsync(reviews[0].Id, _f.Kim.Id, isAdmin: false);

        Assert.Equal(ServiceError.Forbidden, result.Error);
        Assert.Equal(2, _f.Db.Reviews.Count());
    }

    [Fact]
    public async Task AdminCanDeleteAnyReview()
    {
        var reviews = await SeedTwoReviews();

        var result = await _f.Reviews.DeleteAsync(reviews[0].Id, _f.Olu.Id, isAdmin: true);

        Assert.True(result.Succeeded);
    }

    [Fact]
    public async Task DeletingAnUnknownReview_IsNotFound()
    {
        var result = await _f.Reviews.DeleteAsync(Guid.NewGuid(), _f.Sam.Id, isAdmin: true);

        Assert.Equal(ServiceError.NotFound, result.Error);
    }

    [Fact]
    public async Task AfterDeleting_TheTravelerMayReviewAgain()
    {
        var reviews = await SeedTwoReviews();
        await _f.Reviews.DeleteAsync(reviews[0].Id, _f.Sam.Id, isAdmin: false);

        var again = await _f.Reviews.CreateAsync(_f.SeaView.Id, _f.Sam.Id, Review(2, "changed my mind"));

        Assert.True(again.Succeeded, again.Message);
    }
}

internal static class ReviewServiceLimits
{
    public const int MaxPage = CEYLORA.Infrastructure.Services.ReviewService.MaxPageSize;
}
