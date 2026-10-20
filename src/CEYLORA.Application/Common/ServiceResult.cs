namespace CEYLORA.Application.Common;

/// <summary>Why a service call did not succeed. The API maps each to an HTTP status.</summary>
public enum ServiceError
{
    None,
    NotFound,   // 404
    Forbidden,  // 403
    Invalid,    // 400: the request breaks a rule
    Conflict    // 409: the request is fine but clashes with current state (sold out, already reviewed)
}

/// <summary>
/// Outcome of a service call: a value, or an error kind with a message safe to show the caller.
/// Used where a plain "null means failure" would hide why it failed.
/// </summary>
public class ServiceResult<T>
{
    public T? Value { get; }
    public ServiceError Error { get; }
    public string? Message { get; }

    public bool Succeeded => Error == ServiceError.None;

    private ServiceResult(T? value, ServiceError error, string? message)
    {
        Value = value;
        Error = error;
        Message = message;
    }

    public static ServiceResult<T> Ok(T value) => new(value, ServiceError.None, null);

    public static ServiceResult<T> Fail(ServiceError error, string message) => new(default, error, message);

    public static ServiceResult<T> NotFound(string message) => Fail(ServiceError.NotFound, message);
    public static ServiceResult<T> Forbidden(string message) => Fail(ServiceError.Forbidden, message);
    public static ServiceResult<T> Invalid(string message) => Fail(ServiceError.Invalid, message);
    public static ServiceResult<T> Conflict(string message) => Fail(ServiceError.Conflict, message);
}
