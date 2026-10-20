// Turns a failed axios request into a message that is safe to show an operator.
// The API answers { message } for business-rule errors and ASP.NET problem details
// ({ errors: { Field: [..] }, title }) for request validation.
export function apiErrorMessage(err, fallback = 'Something went wrong.') {
  const response = err?.response;

  if (!response) return 'Cannot reach the server. Check your connection and try again.';

  const data = response.data;
  if (data?.message) return data.message;

  if (data?.errors && typeof data.errors === 'object') {
    const first = Object.values(data.errors).flat()[0];
    if (first) return String(first);
  }

  if (response.status === 401) return 'Your session has expired. Please sign in again.';
  if (response.status === 403) return "You don't have permission to do that.";
  if (response.status >= 500) return 'Something went wrong on the server.';
  if (data?.title) return data.title;

  return fallback;
}
