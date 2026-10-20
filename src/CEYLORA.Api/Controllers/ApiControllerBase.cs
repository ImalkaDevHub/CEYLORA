using System.Security.Claims;
using CEYLORA.Application.Common;
using Microsoft.AspNetCore.Mvc;

namespace CEYLORA.Api.Controllers;

/// <summary>Shared helpers for controllers that use <see cref="ServiceResult{T}"/>.</summary>
[ApiController]
public abstract class ApiControllerBase : ControllerBase
{
    protected Guid CurrentUserId =>
        Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    protected bool IsStaff => User.IsInRole("Operator") || User.IsInRole("Admin");

    protected bool IsAdmin => User.IsInRole("Admin");

    /// <summary>
    /// 200 with the value on success; otherwise the status that matches the error kind, with
    /// the same { "message": ... } body the rest of the API uses.
    /// </summary>
    protected IActionResult ToActionResult<T>(ServiceResult<T> result, Func<T, IActionResult>? onSuccess = null)
    {
        if (result.Succeeded)
            return onSuccess is null ? Ok(result.Value) : onSuccess(result.Value!);

        var body = new { message = result.Message };
        return result.Error switch
        {
            ServiceError.NotFound => NotFound(body),
            ServiceError.Forbidden => StatusCode(StatusCodes.Status403Forbidden, body),
            ServiceError.Conflict => Conflict(body),
            _ => BadRequest(body)
        };
    }
}
