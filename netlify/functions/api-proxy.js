/**
 * Netlify Serverless Function: API Proxy
 * Proxies API requests from frontend to backend service
 * Bypasses ISP/carrier blocking for mobile users
 */

exports.handler = async (event, context) => {
  try {
    console.log('=== API Proxy Request ===');
    console.log('Method:', event.httpMethod);
    console.log('Path:', event.path);
    console.log('Raw Query:', event.rawQuery);

    // Use environment variable or fallback to Railway
    const backendUrl = process.env.BACKEND_URL || 
                       'https://taskearn-production-production.up.railway.app';
    
    console.log('Backend URL:', backendUrl);

    // Extract the API path from the function invocation
    // Remove '/.netlify/functions/api-proxy' prefix
    let path = event.path.replace('/.netlify/functions/api-proxy', '') || '';
    
    // Ensure path starts with /
    if (!path.startsWith('/')) {
      path = '/' + path;
    }

    // Build query string
    const query = event.rawQuery ? `?${event.rawQuery}` : '';
    const targetUrl = `${backendUrl}${path}${query}`;

    console.log('Target URL:', targetUrl);

    try {
      // Prepare request headers
      const headers = {};
      
      // Copy relevant headers from request
      if (event.headers) {
        Object.keys(event.headers).forEach(key => {
          if (!['host', 'connection', 'content-length'].includes(key.toLowerCase())) {
            headers[key] = event.headers[key];
          }
        });
      }

      console.log('Request headers:', JSON.stringify(headers));

      // Prepare body
      let body = null;
      if (event.body && !['GET', 'HEAD'].includes(event.httpMethod)) {
        body = event.isBase64Encoded ? 
               Buffer.from(event.body, 'base64').toString() : 
               event.body;
        console.log('Request body:', body);
      }

      // Make the request
      const response = await fetch(targetUrl, {
        method: event.httpMethod || 'GET',
        headers: headers,
        body: body
      });

      console.log('Response status:', response.status);

      const contentType = response.headers.get('content-type');
      const responseBody = await response.text();

      console.log('Response body:', responseBody.substring(0, 200));

      return {
        statusCode: response.status,
        headers: {
          'Content-Type': contentType || 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, Accept',
          'Access-Control-Max-Age': '3600',
          'Cache-Control': 'no-cache, no-store, must-revalidate'
        },
        body: responseBody
      };
    } catch (fetchError) {
      console.error('Fetch Error:', fetchError.message);
      return {
        statusCode: 502,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({ 
          success: false,
          error: 'Backend API unreachable',
          message: fetchError.message,
          details: 'Failed to connect to Railway backend. Check if Railway service is running.'
        })
      };
    }
  } catch (error) {
    console.error('Proxy Error:', error);
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({ 
        success: false,
        error: 'Proxy server error',
        message: error.message
      })
    };
  }
};
