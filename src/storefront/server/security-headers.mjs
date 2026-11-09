// Pages _headers applies to static assets. Functions must set these explicitly.
export const securityHeaders = Object.freeze({
 'Content-Security-Policy': "default-src 'self'; script-src 'self' https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' https://mknsaibrewksgomuslev.supabase.co https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; frame-ancestors 'none'; base-uri 'none'; form-action 'self'; object-src 'none'; upgrade-insecure-requests",
 'X-Content-Type-Options': 'nosniff',
 'Referrer-Policy': 'strict-origin-when-cross-origin',
 'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
 'X-Frame-Options': 'DENY',
 'Strict-Transport-Security': 'max-age=31536000'
});

export function secureResponse(response) {
 const headers = new Headers(response.headers);
 for (const [name, value] of Object.entries(securityHeaders)) headers.set(name, value);
 // The middleware covers HTML and APIs only; no stale shell or capability response.
 headers.set('Cache-Control', 'no-store');
 return new Response(response.body, {status: response.status, statusText: response.statusText, headers});
}
