/**
 * Netlify Redirect Function: API Proxy
 * This allows the frontend to call /api/* which redirects to the railway backend
 */

exports.handler = async (event, context) => {
  const railwayUrl = process.env.RAILWAY_API_URL || 
                     'https://taskearn-production-production.up.railway.app';
  
  const path = event.path.replace('/.netlify/functions/api-proxy', '');
  const targetUrl = `${railwayUrl}${path}`;

  try {
    const response = await fetch(targetUrl, {
      method: event.httpMethod,
      headers: event.headers,
      body: event.body
    });

    const contentType = response.headers.get('content-type');
    let body = await response.text();

    return {
      statusCode: response.status,
      headers: {
        "Content-Type": contentType || "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: body
    };
  } catch (error) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message })
    };
  }
};
