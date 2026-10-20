namespace CEYLORA.Domain.Entities;

/// <summary>
/// Room inventory for one accommodation on one night. A stay from check-in to check-out
/// uses the nights check-in .. check-out minus one day.
/// </summary>
public class Availability
{
    public Guid Id { get; set; }

    public Guid AccommodationId { get; set; }
    public Accommodation Accommodation { get; set; } = null!;

    /// <summary>The night (a calendar date, no time zone).</summary>
    public DateOnly Date { get; set; }

    public int TotalRooms { get; set; }
    public int BookedRooms { get; set; }

    /// <summary>
    /// Optimistic-concurrency token. Every change to the counts bumps it, so two travelers
    /// racing for the last room cannot both succeed: the second save fails and is retried
    /// against the fresh numbers.
    /// </summary>
    public int Version { get; set; }

    public int AvailableRooms => TotalRooms - BookedRooms;
}
