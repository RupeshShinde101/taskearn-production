/**
 * Netlify Function: Get API Configuration
 * Returns the correct API URL based on environment
 */

exports.handler = async (event, context) => {
  // Get the API URL from environment variable or use default
  const apiUrl = process.env.RAILWAY_API_URL || 
                 'https://taskearn-production-production.up.railway.app/api';

  return {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*"
    },
    body: JSON.stringify({
      API_URL: apiUrl,
      ENVIRONMENT: process.env.CONTEXT || 'production',
      VERSION: process.env.VERSION || '1.0.0'
    })
  };
};
