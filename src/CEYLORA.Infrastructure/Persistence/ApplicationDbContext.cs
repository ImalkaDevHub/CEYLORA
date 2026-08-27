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

        // Seed roles
        modelBuilder.Entity<Role>().HasData(
            new Role { Id = Guid.NewGuid(), Name = "Traveler" },
            new Role { Id = Guid.NewGuid(), Name = "Operator" },
            new Role { Id = Guid.NewGuid(), Name = "Admin" }
        );
    }
}
