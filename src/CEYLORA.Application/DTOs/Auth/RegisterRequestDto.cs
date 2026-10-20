using System.ComponentModel.DataAnnotations;

namespace CEYLORA.Application.DTOs.Auth;

public class RegisterRequestDto
{
    public const int MinPasswordLength = 8;

    /// <summary>72 is the most characters BCrypt actually uses.</summary>
    public const int MaxPasswordLength = 72;

    [Required(ErrorMessage = "Email is required.")]
    [StringLength(254, ErrorMessage = "Email is too long.")]
    [EmailAddress(ErrorMessage = "Enter a valid email address.")]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "Password is required.")]
    [StringLength(MaxPasswordLength, MinimumLength = MinPasswordLength,
        ErrorMessage = "Password must be 8 to 72 characters.")]
    [RegularExpression(@"^(?=.*[A-Za-z])(?=.*\d).+$",
        ErrorMessage = "Password must include at least one letter and one number.")]
    public string Password { get; set; } = string.Empty;

    [Required(ErrorMessage = "Full name is required.")]
    [StringLength(100, MinimumLength = 2, ErrorMessage = "Full name must be 2 to 100 characters.")]
    public string FullName { get; set; } = string.Empty;

    [Required(ErrorMessage = "Role is required.")]
    [RegularExpression("^(Traveler|Operator|Admin)$",
        ErrorMessage = "Role must be Traveler, Operator or Admin.")]
    public string RoleName { get; set; } = "Traveler"; // default role for self-registration
}
