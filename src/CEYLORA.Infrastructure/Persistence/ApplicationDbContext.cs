using CEYLORA.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace CEYLORA.Infrastructure.Persistence;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options) { }

    public DbSet<User> Users { get; set; }
    public DbSet<Role> Roles { get; set; }
    public DbSet<Trip> Trips => Set<Trip>();
    public DbSet<Destination> Destinations => Set<Destination>();
    public DbSet<Experience> Experiences => Set<Experience>();
    public DbSet<AIWorkflow> AIWorkflows => Set<AIWorkflow>();
    public DbSet<AIWorkflowStep> AIWorkflowSteps => Set<AIWorkflowStep>();
    public DbSet<Accommodation> Accommodations => Set<Accommodation>();
    public DbSet<Availability> Availabilities => Set<Availability>();
    public DbSet<Booking> Bookings => Set<Booking>();
    public DbSet<BookingItem> BookingItems => Set<BookingItem>();
    public DbSet<Review> Reviews => Set<Review>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Seed roles. IDs must stay static (not Guid.NewGuid()) so the model built at
        // runtime always matches what's baked into the InitialCreate migration/snapshot —
        // otherwise EF sees a "changed" model on every run and refuses to migrate.
        modelBuilder.Entity<Role>().HasData(
            new Role { Id = new Guid("c023fa33-20bf-4166-b56c-aeb11838c85c"), Name = "Traveler" },
            new Role { Id = new Guid("2886700a-03e0-46c0-90cd-a6ae1e51b09d"), Name = "Operator" },
            new Role { Id = new Guid("546b4d97-9957-4d52-9682-bfd998c63b80"), Name = "Admin" }
        );

        modelBuilder.Entity<Trip>()
            .HasOne(t => t.Traveler)
            .WithMany()
            .HasForeignKey(t => t.TravelerId);

        modelBuilder.Entity<Experience>()
            .HasOne(e => e.Destination)
            .WithMany(d => d.Experiences)
            .HasForeignKey(e => e.DestinationId)
            .OnDelete(DeleteBehavior.Cascade);

        ConfigureAiWorkflow(modelBuilder);
        ConfigureBookingOperations(modelBuilder);
    }

    private static void ConfigureBookingOperations(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Accommodation>(entity =>
        {
            entity.Property(a => a.Name).HasMaxLength(150);
            entity.Property(a => a.Description).HasMaxLength(2000);
            entity.Property(a => a.PricePerNight).HasPrecision(18, 2);
            entity.Property(a => a.Type).HasConversion<string>().HasMaxLength(32);

            // Destinations are only ever soft-deleted, so a stay must never cascade away with one.
            entity.HasOne(a => a.Destination)
                .WithMany()
                .HasForeignKey(a => a.DestinationId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(a => a.DestinationId);
            entity.HasIndex(a => new { a.IsActive, a.PricePerNight });

            // A destination does not list two stays with the same name.
            entity.HasIndex(a => new { a.DestinationId, a.Name }).IsUnique();

            entity.ToTable(t =>
            {
                t.HasCheckConstraint("CK_Accommodations_PricePerNight", "\"PricePerNight\" >= 0");
                t.HasCheckConstraint("CK_Accommodations_MaxGuestsPerRoom", "\"MaxGuestsPerRoom\" > 0");
            });
        });

        modelBuilder.Entity<Availability>(entity =>
        {
            entity.Ignore(a => a.AvailableRooms);

            // One inventory row per accommodation per night.
            entity.HasIndex(a => new { a.AccommodationId, a.Date }).IsUnique();

            // Optimistic concurrency, see Availability.Version.
            entity.Property(a => a.Version).IsConcurrencyToken();

            entity.HasOne(a => a.Accommodation)
                .WithMany(x => x.Availabilities)
                .HasForeignKey(a => a.AccommodationId)
                .OnDelete(DeleteBehavior.Cascade);

            // The database refuses overbooking even if application code ever gets it wrong.
            entity.ToTable(t =>
            {
                t.HasCheckConstraint("CK_Availabilities_Counts",
                    "\"BookedRooms\" >= 0 AND \"TotalRooms\" >= 0 AND \"BookedRooms\" <= \"TotalRooms\"");
            });
        });

        modelBuilder.Entity<Booking>(entity =>
        {
            entity.Property(b => b.Status).HasConversion<string>().HasMaxLength(32);
            entity.Property(b => b.TotalAmount).HasPrecision(18, 2);
            entity.Property(b => b.Notes).HasMaxLength(500);

            entity.HasOne(b => b.Traveler)
                .WithMany()
                .HasForeignKey(b => b.TravelerId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(b => b.Trip)
                .WithMany()
                .HasForeignKey(b => b.TripId)
                .OnDelete(DeleteBehavior.Restrict);

            // "My bookings" and the operator's filter-by-status screen read on these.
            entity.HasIndex(b => new { b.TravelerId, b.CreatedAt });
            entity.HasIndex(b => b.Status);
            entity.HasIndex(b => b.TripId);
        });

        modelBuilder.Entity<BookingItem>(entity =>
        {
            entity.Ignore(i => i.Nights);
            entity.Property(i => i.NightlyRate).HasPrecision(18, 2);
            entity.Property(i => i.Subtotal).HasPrecision(18, 2);

            entity.HasOne(i => i.Booking)
                .WithMany(b => b.Items)
                .HasForeignKey(i => i.BookingId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(i => i.Accommodation)
                .WithMany()
                .HasForeignKey(i => i.AccommodationId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(i => i.BookingId);
            entity.HasIndex(i => i.AccommodationId);

            entity.ToTable(t =>
            {
                t.HasCheckConstraint("CK_BookingItems_Dates", "\"CheckOut\" > \"CheckIn\"");
                t.HasCheckConstraint("CK_BookingItems_Counts", "\"Rooms\" > 0 AND \"Guests\" > 0");
            });
        });

        modelBuilder.Entity<Review>(entity =>
        {
            entity.Property(r => r.Comment).HasMaxLength(1000);

            entity.HasOne(r => r.Accommodation)
                .WithMany(a => a.Reviews)
                .HasForeignKey(r => r.AccommodationId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(r => r.Traveler)
                .WithMany()
                .HasForeignKey(r => r.TravelerId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(r => r.Booking)
                .WithMany()
                .HasForeignKey(r => r.BookingId)
                .OnDelete(DeleteBehavior.Restrict);

            // A traveler reviews each place once.
            entity.HasIndex(r => new { r.AccommodationId, r.TravelerId }).IsUnique();
            entity.HasIndex(r => new { r.AccommodationId, r.CreatedAt });

            entity.ToTable(t => t.HasCheckConstraint("CK_Reviews_Rating", "\"Rating\" BETWEEN 1 AND 5"));
        });
    }

    private static void ConfigureAiWorkflow(ModelBuilder modelBuilder)
    {
        // Interests is the only list-like scalar in the model, so it gets a value
        // converter rather than a separate table — a comma-separated column keeps
        // the migration simple and stays provider-agnostic.
        var interestsConverter = new ValueConverter<List<string>, string>(
            list => string.Join(',', list),
            text => string.IsNullOrWhiteSpace(text)
                ? new List<string>()
                : text.Split(',', StringSplitOptions.RemoveEmptyEntries).ToList());

        // Without a comparer EF compares List<string> by reference and misses edits.
        var interestsComparer = new ValueComparer<List<string>>(
            (a, b) => a != null && b != null && a.SequenceEqual(b),
            list => list.Aggregate(0, (hash, item) => HashCode.Combine(hash, item.GetHashCode())),
            list => list.ToList());

        modelBuilder.Entity<AIWorkflow>(entity =>
        {
            entity.Property(w => w.Interests)
                .HasConversion(interestsConverter)
                .Metadata.SetValueComparer(interestsComparer);

            // Store the enum by name so the column stays readable and reordering
            // the enum can't silently remap existing rows.
            entity.Property(w => w.ApprovalStatus)
                .HasConversion<string>()
                .HasMaxLength(32);

            entity.HasOne(w => w.Traveler)
                .WithMany()
                .HasForeignKey(w => w.TravelerId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(w => w.ApprovedByUser)
                .WithMany()
                .HasForeignKey(w => w.ApprovedByUserId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(w => w.Trip)
                .WithMany()
                .HasForeignKey(w => w.TripId)
                .OnDelete(DeleteBehavior.SetNull);

            // The operator queue reads on this column.
            entity.HasIndex(w => w.ApprovalStatus);
        });

        modelBuilder.Entity<AIWorkflowStep>()
            .HasOne(s => s.AIWorkflow)
            .WithMany(w => w.Steps)
            .HasForeignKey(s => s.AIWorkflowId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
