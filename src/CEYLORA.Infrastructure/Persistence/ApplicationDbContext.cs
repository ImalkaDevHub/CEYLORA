using CEYLORA.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace CEYLORA.Infrastructure.Persistence;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options) { }

    public DbSet<User> Users { get; set; }
    public DbSet<Role> Roles { get; set; }

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
    }
}
