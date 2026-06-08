/**
 * Netlify Serverless Function — API Proxy for Mobile Devices
 * 
 * Mobile browsers on some carriers have DNS/CORS issues hitting Railway directly.
 * This proxy forwards /api/* requests to the Railway backend.
 */

const BACKEND_URL = process.env.BACKEND_URL || 'https://taskearn-production-production.up.railway.app';

const ALLOWED_ORIGINS = [
    'https://www.workmate4u.com',
    'https://workmate4u.com',
    'https://workmate4u.netlify.app'
];

function getCorsOrigin(requestOrigin) {
    if (!requestOrigin) return ALLOWED_ORIGINS[0];
    if (ALLOWED_ORIGINS.includes(requestOrigin)) return requestOrigin;
    // Allow Netlify deploy previews
    if (requestOrigin.endsWith('.netlify.app')) return requestOrigin;
    return ALLOWED_ORIGINS[0];
}

exports.handler = async (event) => {
    const origin = event.headers.origin || event.headers.Origin || '';
    const corsOrigin = getCorsOrigin(origin);

    const corsHeaders = {
        'Access-Control-Allow-Origin': corsOrigin,
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, Accept',
        'Access-Control-Allow-Credentials': 'true',
        'Access-Control-Max-Age': '3600'
    };

    // Handle preflight
    if (event.httpMethod === 'OPTIONS') {
        return { statusCode: 200, headers: corsHeaders, body: '' };
    }

    // Extract the API path: /.netlify/functions/api-proxy/api/auth/login → /api/auth/login
    const path = event.path.replace('/.netlify/functions/api-proxy', '') || '/';
    const method = (event.httpMethod || 'GET').toUpperCase();

    // Fast-path endpoints that do not need backend DB access.
    if (method === 'GET' && path === '/api/health') {
        return {
            statusCode: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            body: JSON.stringify({ success: true, status: 'proxy-ok', source: 'netlify-proxy' })
        };
    }

    if (method === 'GET' && path === '/api/config/google-client-id' && process.env.GOOGLE_CLIENT_ID) {
        return {
            statusCode: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            body: JSON.stringify({ success: true, clientId: process.env.GOOGLE_CLIENT_ID })
        };
    }
    // Forward query string parameters (event.path never includes them)
    const qs = event.rawQuery || Object.entries(event.queryStringParameters || {})
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
    const targetUrl = `${BACKEND_URL}${path}${qs ? '?' + qs : ''}`;

    // Dynamic import for node-fetch (Netlify functions use Node 18+)
    const fetchImpl = globalThis.fetch || (await import('node-fetch')).default;

    try {

        const headers = { ...event.headers };
        // Remove Netlify-specific headers
        delete headers.host;
        delete headers['x-forwarded-for'];
        delete headers['x-forwarded-proto'];
        delete headers['x-nf-request-id'];
        delete headers['x-nf-client-connection-ip'];
        delete headers.connection;

        const isGet = method === 'GET';
        const timeoutMs = isGet ? 15000 : 8000;

        const fetchOptions = {
            method,
            headers: {
                'Content-Type': headers['content-type'] || 'application/json',
                'Authorization': headers.authorization || '',
                'Accept': 'application/json'
            },
            // GETs are public and safe to wait a little longer for during a cold
            // start. Writes stay shorter so we don't risk hanging Netlify on posts.
            // If the backend is still cold after this window, the client retry
            // path will handle a second attempt.
            signal: AbortSignal.timeout(timeoutMs)
        };

        if (event.body && method !== 'GET' && method !== 'HEAD') {
            fetchOptions.body = event.body;
        }

        let response = await fetchImpl(targetUrl, fetchOptions);

        // Google login is user-facing and should tolerate a short backend blip.
        // Retry once on transient 5xx before returning failure.
        if (method === 'POST' && path === '/api/auth/google' && response.status >= 500) {
            await new Promise(r => setTimeout(r, 1200));
            response = await fetchImpl(targetUrl, fetchOptions);
        }

        const body = await response.text();

        // Graceful fallback for non-critical read-only endpoints when backend
        // returns 5xx. These should not block page rendering.
        if (isGet && response.status >= 500) {
            if (path === '/api/platform-stats') {
                return {
                    statusCode: 200,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    body: JSON.stringify({ success: true, users: 0, completedTasks: 0, totalEarned: 0, stale: true })
                };
            }
            if (path === '/api/trial/status') {
                return {
                    statusCode: 200,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    body: JSON.stringify({ trial: false, stale: true })
                };
            }
            if (path === '/api/config/google-client-id') {
                const fallbackClientId = process.env.GOOGLE_CLIENT_ID || '';
                if (fallbackClientId) {
                    return {
                        statusCode: 200,
                        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                        body: JSON.stringify({ success: true, clientId: fallbackClientId, stale: true })
                    };
                }
            }
        }

        // If Railway returned 504, fire a background wake-up ping so the
        // dyno starts warming for the user's next retry.
        if (response.status === 504) {
            fetchImpl(BACKEND_URL + '/api/health', { method: 'GET', signal: AbortSignal.timeout(25000) })
                .catch(() => {}); // intentionally background, ignore result
        }

        return {
            statusCode: response.status,
            headers: {
                ...corsHeaders,
                'Content-Type': response.headers.get('content-type') || 'application/json'
            },
            body
        };
    } catch (error) {
        console.error('Proxy error:', error.message);
        const isTimeout = error.name === 'TimeoutError' || error.name === 'AbortError';

        // One retry for Google auth on transient network/timeout.
        if (method === 'POST' && path === '/api/auth/google') {
            try {
                const retryResp = await fetchImpl(targetUrl, {
                    method,
                    headers: {
                        'Content-Type': event.headers['content-type'] || event.headers['Content-Type'] || 'application/json',
                        'Authorization': event.headers.authorization || event.headers.Authorization || '',
                        'Accept': 'application/json'
                    },
                    body: event.body,
                    signal: AbortSignal.timeout(8000)
                });
                const retryBody = await retryResp.text();
                return {
                    statusCode: retryResp.status,
                    headers: {
                        ...corsHeaders,
                        'Content-Type': retryResp.headers.get('content-type') || 'application/json'
                    },
                    body: retryBody
                };
            } catch (_) {
                // fall through to normal error handling
            }
        }
        // Fire a background wake-up ping so Railway starts warming up
        if (isTimeout) {
            fetchImpl(BACKEND_URL + '/api/health', { method: 'GET', signal: AbortSignal.timeout(25000) })
                .catch(() => {});
        }
        // Graceful fallback for non-critical read-only endpoints.
        if (isTimeout && method === 'GET') {
            if (path === '/api/platform-stats') {
                return {
                    statusCode: 200,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    body: JSON.stringify({ success: true, users: 0, completedTasks: 0, totalEarned: 0, stale: true })
                };
            }
            if (path === '/api/trial/status') {
                return {
                    statusCode: 200,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    body: JSON.stringify({ trial: false, stale: true })
                };
            }
            if (path === '/api/config/google-client-id' && process.env.GOOGLE_CLIENT_ID) {
                return {
                    statusCode: 200,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    body: JSON.stringify({ success: true, clientId: process.env.GOOGLE_CLIENT_ID, stale: true })
                };
            }
        }

        return {
            statusCode: isTimeout ? 504 : 502,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                success: false,
                message: isTimeout
                    ? 'Server is starting up — please wait a moment and try again.'
                    : 'Backend server unreachable. Please try again.'
            })
        };
    }
};
