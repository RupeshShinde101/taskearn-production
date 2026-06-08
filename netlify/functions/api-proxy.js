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
    // Forward query string parameters (event.path never includes them)
    const qs = event.rawQuery || Object.entries(event.queryStringParameters || {})
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
    const targetUrl = `${BACKEND_URL}${path}${qs ? '?' + qs : ''}`;

    try {
        // Dynamic import for node-fetch (Netlify functions use Node 18+)
        const fetch = globalThis.fetch || (await import('node-fetch')).default;

        const headers = { ...event.headers };
        // Remove Netlify-specific headers
        delete headers.host;
        delete headers['x-forwarded-for'];
        delete headers['x-forwarded-proto'];
        delete headers['x-nf-request-id'];
        delete headers['x-nf-client-connection-ip'];
        delete headers.connection;

        const fetchOptions = {
            method: event.httpMethod,
            headers: {
                'Content-Type': headers['content-type'] || 'application/json',
                'Authorization': headers.authorization || '',
                'Accept': 'application/json'
            },
            // Hard 8-second timeout so the function always returns a clean response
            // before Netlify's 10-second function limit kills it mid-transfer.
            // Without this, slow Railway responses cause ERR_CONNECTION_RESET + "200 (OK)"
            // in the browser — the function started sending 200 headers then got killed.
            signal: AbortSignal.timeout(8000)
        };

        if (event.body && event.httpMethod !== 'GET' && event.httpMethod !== 'HEAD') {
            fetchOptions.body = event.body;
        }

        const response = await fetch(targetUrl, fetchOptions);
        const body = await response.text();

        // If Railway returned 504, fire a background wake-up ping so the
        // dyno starts warming for the user's next retry.
        if (response.status === 504) {
            fetch(BACKEND_URL + '/api/health', { method: 'GET', signal: AbortSignal.timeout(25000) })
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
        // Fire a background wake-up ping so Railway starts warming up
        if (isTimeout) {
            fetch(BACKEND_URL + '/api/health', { method: 'GET', signal: AbortSignal.timeout(25000) })
                .catch(() => {});
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
