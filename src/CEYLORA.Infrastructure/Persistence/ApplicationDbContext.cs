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
