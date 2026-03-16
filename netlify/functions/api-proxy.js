/**
 * Netlify Redirect Function: API Proxy
 * Proxies API requests from frontend to backend service
 * Configure BACKEND_URL environment variable in Netlify dashboard
 */

exports.handler = async (event, context) => {
  // Use environment variable or fallback to Railway
  const backendUrl = process.env.BACKEND_URL || 
                     'https://taskearn-production-production.up.railway.app';
  
  // Extract the API path from the function invocation
  const path = event.path.replace('/.netlify/functions/api-proxy', '') || '';
  const query = event.rawQuery ? `?${event.rawQuery}` : '';
  const targetUrl = `${backendUrl}${path}${query}`;

  console.log(`Proxying ${event.httpMethod} ${path} to ${targetUrl}`);

  try {
    // Prepare request headers (remove host header to avoid conflicts)
    const headers = new Headers(event.headers);
    headers.delete('host');

    const response = await fetch(targetUrl, {
      method: event.httpMethod || 'GET',
      headers: headers,
      body: ['GET', 'HEAD'].includes(event.httpMethod) ? null : event.body
    });

    const contentType = response.headers.get('content-type');
    let body = await response.text();

    return {
      statusCode: response.status,
      headers: {
        "Content-Type": contentType || "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization"
      },
      body: body
    };
  } catch (error) {
    console.error('Proxy error:', error);
    return {
      statusCode: 502,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: JSON.stringify({ 
        success: false,
        error: "Backend API unreachable",
        message: error.message 
      })
    };
  }
};
