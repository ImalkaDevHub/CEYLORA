using System.ComponentModel.DataAnnotations;

namespace CEYLORA.Application.DTOs.Auth;

public class LoginRequestDto
{
    // No format or strength rules here: accounts made before those rules existed must still sign in.
    // The limits only keep absurd payloads out.
    [Required(ErrorMessage = "Email is required.")]
    [StringLength(254, ErrorMessage = "Email is too long.")]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "Password is required.")]
    [StringLength(128, ErrorMessage = "Password is too long.")]
    public string Password { get; set; } = string.Empty;
}
