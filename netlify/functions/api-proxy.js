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
    const targetUrl = `${BACKEND_URL}${path}`;

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
            }
        };

        if (event.body && event.httpMethod !== 'GET' && event.httpMethod !== 'HEAD') {
            fetchOptions.body = event.body;
        }

        const response = await fetch(targetUrl, fetchOptions);
        const body = await response.text();

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
        return {
            statusCode: 502,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            body: JSON.stringify({
                success: false,
                message: 'Backend server unreachable. Please try again.'
            })
        };
    }
};
