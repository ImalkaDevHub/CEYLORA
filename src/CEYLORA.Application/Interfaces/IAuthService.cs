using CEYLORA.Application.DTOs.Auth;

namespace CEYLORA.Application.Interfaces;

public interface IAuthService
{
    Task<AuthResponseDto?> RegisterAsync(RegisterRequestDto request);
    Task<AuthResponseDto?> LoginAsync(LoginRequestDto request);
}
