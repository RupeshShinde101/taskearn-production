"""
API Diagnostic Tool - Check Netlify Frontend <-> Backend API Connectivity
Tests CORS, endpoints, and provides detailed remediation steps
"""

import requests
import json
from datetime import datetime

# Configuration
PRODUCTION_BACKEND = "https://taskearn-production-production.up.railway.app"
LOCAL_BACKEND = "http://localhost:5000"
ENDPOINTS_TO_TEST = [
    "/api/health",
    "/api/diagnostic",
    "/api/tasks"
]

def test_endpoint(base_url, endpoint, method="GET"):
    """Test if an endpoint is reachable and returns valid response"""
    url = f"{base_url}{endpoint}"
    try:
        print(f"\n  Testing: {url}")
        response = requests.get(url, timeout=10)
        print(f"    Status: {response.status_code}")
        print(f"    Headers: {dict(response.headers)}")
        if response.status_code == 200:
            try:
                data = response.json()
                print(f"    Response: {json.dumps(data, indent=2)}")
                return True
            except:
                print(f"    Response: {response.text[:200]}")
                return True
        else:
            print(f"    Error: {response.text[:200]}")
            return False
    except requests.exceptions.ConnectionError as e:
        print(f"    ❌ Connection Error: {str(e)[:100]}")
        return False
    except requests.exceptions.Timeout as e:
        print(f"    ❌ Timeout: Backend not responding (>10s)")
        return False
    except Exception as e:
        print(f"    ❌ Error: {str(e)[:100]}")
        return False

def test_cors_preflight(base_url):
    """Test CORS preflight request"""
    print(f"\n  Testing CORS preflight to: {base_url}/api/tasks")
    try:
        headers = {
            'Origin': 'https://taskearn.netlify.app',
            'Access-Control-Request-Method': 'POST',
            'Access-Control-Request-Headers': 'content-type'
        }
        response = requests.options(f"{base_url}/api/tasks", headers=headers, timeout=10)
        print(f"    Status: {response.status_code}")
        
        cors_headers = {
            'Access-Control-Allow-Origin': response.headers.get('Access-Control-Allow-Origin', 'NOT SET'),
            'Access-Control-Allow-Methods': response.headers.get('Access-Control-Allow-Methods', 'NOT SET'),
            'Access-Control-Allow-Headers': response.headers.get('Access-Control-Allow-Headers', 'NOT SET'),
        }
        print(f"    CORS Headers: {json.dumps(cors_headers, indent=2)}")
        
        if response.headers.get('Access-Control-Allow-Origin'):
            return True
        return False
    except Exception as e:
        print(f"    ❌ CORS Test Failed: {str(e)[:100]}")
        return False

def main():
    """Run all diagnostics"""
    print("\n" + "="*70)
    print("🔍 TaskEarn API Diagnostic Tool")
    print("="*70)
    print(f"Timestamp: {datetime.now().isoformat()}\n")
    
    results = {
        'production': {'reachable': False, 'health': False, 'cors': False},
        'local': {'reachable': False, 'health': False, 'cors': False}
    }
    
    # Test Production Backend
    print("\n📍 TESTING PRODUCTION BACKEND")
    print("-" * 70)
    print(f"URL: {PRODUCTION_BACKEND}")
    
    for endpoint in ENDPOINTS_TO_TEST:
        if test_endpoint(PRODUCTION_BACKEND, endpoint):
            if "health" in endpoint:
                results['production']['health'] = True
            if "diagnostic" in endpoint:
                results['production']['reachable'] = True
    
    test_cors_preflight(PRODUCTION_BACKEND)
    results['production']['cors'] = test_cors_preflight(PRODUCTION_BACKEND)
    
    # Test Local Backend
    print("\n\n📍 TESTING LOCAL BACKEND (Development)")
    print("-" * 70)
    print(f"URL: {LOCAL_BACKEND}")
    
    for endpoint in ENDPOINTS_TO_TEST:
        if test_endpoint(LOCAL_BACKEND, endpoint):
            if "health" in endpoint:
                results['local']['health'] = True
            if "diagnostic" in endpoint:
                results['local']['reachable'] = True
    
    results['local']['cors'] = test_cors_preflight(LOCAL_BACKEND)
    
    # Summary and Recommendations
    print("\n\n" + "="*70)
    print("📊 DIAGNOSTIC SUMMARY")
    print("="*70)
    
    print("\n✅ PRODUCTION Backend Status:")
    print(f"   Reachable: {'✓' if results['production']['reachable'] else '✗'}")
    print(f"   Health Check: {'✓' if results['production']['health'] else '✗'}")
    print(f"   CORS Enabled: {'✓' if results['production']['cors'] else '✗'}")
    
    print("\n✅ LOCAL Backend Status:")
    print(f"   Reachable: {'✓' if results['local']['reachable'] else '✗'}")
    print(f"   Health Check: {'✓' if results['local']['health'] else '✗'}")
    print(f"   CORS Enabled: {'✓' if results['local']['cors'] else '✗'}")
    
    print("\n" + "="*70)
    print("🔧 RECOMMENDED ACTIONS")
    print("="*70)
    
    if not results['production']['reachable']:
        print("\n⚠️  PRODUCTION BACKEND NOT RESPONDING")
        print("\nSOLUTION - Choose one:")
        print("\n1️⃣  OPTION A: Deploy backend to Railway")
        print("   • Push your backend code to GitHub")
        print("   • Connect Railway to your GitHub repo")
        print("   • Set environment variables on Railway:")
        print("     - SECRET_KEY=<generate new secret>")
        print("     - DATABASE_URL=<your PostgreSQL URL>")
        print("   • Deploy and note your Railway URL")
        print("   • Update index.html with the new URL")
        
        print("\n2️⃣  OPTION B: Use Netlify Functions as API Proxy")
        print("   • Use /netlify/functions/api-proxy.js")
        print("   • Configure to forward to your backend")
        print("   • Update frontend to call /api/* (Netlify will proxy)")
        
    if not results['local']['health']:
        print("\n⚠️  LOCAL BACKEND NOT RUNNING")
        print("\nSOLUTION:")
        print("   Run in backend directory: python run.py")
        print("   Frontend in development will connect to http://localhost:5000/api")
    
    if results['production']['reachable'] and not results['production']['cors']:
        print("\n⚠️  CORS NOT ENABLED ON PRODUCTION BACKEND")
        print("\nSOLUTION:")
        print("   • Check backend/server.py - CORS is configured but might be blocked")
        print("   • Ensure your backend allows requests from Netlify domain")
        print("   • Update CORS_ORIGINS in .env.production")
    
    print("\n" + "="*70)
    print("\n")

if __name__ == "__main__":
    main()
