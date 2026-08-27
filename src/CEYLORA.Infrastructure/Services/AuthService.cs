using CEYLORA.Application.DTOs.Auth;
using CEYLORA.Application.Interfaces;
using CEYLORA.Domain.Entities;
using CEYLORA.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;

namespace CEYLORA.Infrastructure.Services;

public class AuthService : IAuthService
{
    private readonly ApplicationDbContext _db;
    private readonly IConfiguration _config;

    public AuthService(ApplicationDbContext db, IConfiguration config)
    {
        _db = db;
        _config = config;
    }

    public async Task<AuthResponseDto?> RegisterAsync(RegisterRequestDto request)
    {
        if (await _db.Users.AnyAsync(u => u.Email == request.Email))
            return null; // caller returns 409 Conflict

        var role = await _db.Roles.FirstOrDefaultAsync(r => r.Name == request.RoleName);
        if (role is null) return null; // invalid role name

        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = request.Email,
            FullName = request.FullName,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            RoleId = role.Id,
            Role = role
        };

        _db.Users.Add(user);
        await _db.SaveChangesAsync();

        return GenerateToken(user, role.Name);
    }

    public async Task<AuthResponseDto?> LoginAsync(LoginRequestDto request)
    {
        var user = await _db.Users
            .Include(u => u.Role)
            .FirstOrDefaultAsync(u => u.Email == request.Email);

        if (user is null || !BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            return null; // caller returns 401 Unauthorized

        return GenerateToken(user, user.Role.Name);
    }

    private AuthResponseDto GenerateToken(User user, string roleName)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_config["Jwt:Key"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var expires = DateTime.UtcNow.AddHours(8);

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Email, user.Email),
            new Claim(ClaimTypes.Role, roleName)
        };

        var token = new JwtSecurityToken(
            issuer: _config["Jwt:Issuer"],
            audience: _config["Jwt:Audience"],
            claims: claims,
            expires: expires,
            signingCredentials: creds
        );

        return new AuthResponseDto
        {
            Token = new JwtSecurityTokenHandler().WriteToken(token),
            Email = user.Email,
            FullName = user.FullName,
            Role = roleName,
            ExpiresAt = expires
        };
    }
}
