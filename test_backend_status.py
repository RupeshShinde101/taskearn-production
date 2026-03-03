#!/usr/bin/env python3
"""
TaskEarn Backend Diagnostic Tool
Tests local and production APIs to identify and fix deployment issues
"""

import requests
import json
import sys
from urllib.parse import urljoin

def test_endpoint(url, endpoint, name="", color=""):
    """Test an API endpoint and return formatted result"""
    try:
        full_url = urljoin(url.rstrip('/'), endpoint.lstrip('/'))
        response = requests.get(full_url, timeout=5)
        
        # Try to parse as JSON
        try:
            data = response.json()
            is_json = True
            content_preview = json.dumps(data)[:100]
        except:
            is_json = False
            content_preview = response.text[:100]
        
        # Check if it's HTML (bad sign)
        if response.text.startswith('<!DOCTYPE'):
            status = "❌ ERROR: HTML response (not JSON API)"
            return False, status, response.status_code
        
        status = f"✅ OK ({response.status_code}) - {('JSON' if is_json else 'TEXT')}"
        return True, status, response.status_code
        
    except Exception as e:
        return False, f"❌ FAILED: {str(e)}", 0

def main():
    print("\n" + "="*70)
    print("🔍 TaskEarn Backend Diagnostic Tool")
    print("="*70 + "\n")
    
    # Test local backend
    print("🔷 LOCAL BACKEND (Development)")
    print("-" * 70)
    local_url = "http://localhost:5000"
    
    local_health_ok, local_health_status, _ = test_endpoint(local_url, "/api/health", "Health Check")
    print(f"  /api/health:      {local_health_status}")
    
    local_diag_ok, local_diag_status, _ = test_endpoint(local_url, "/api/diagnostic", "Diagnostic")
    print(f"  /api/diagnostic:  {local_diag_status}")
    
    local_ok = local_health_ok and local_diag_ok
    local_status = "✅ WORKING" if local_ok else "❌ BROKEN"
    print(f"\n  LOCAL STATUS: {local_status}\n")
    
    # Test Railway backend
    print("🔷 RAILWAY BACKEND (Production)")
    print("-" * 70)
    railway_url = "https://taskearn-production-production.up.railway.app"
    
    railway_health_ok, railway_health_status, _ = test_endpoint(railway_url, "/api/health", "Health Check")
    print(f"  /api/health:      {railway_health_status}")
    
    railway_diag_ok, railway_diag_status, _ = test_endpoint(railway_url, "/api/diagnostic", "Diagnostic")
    print(f"  /api/diagnostic:  {railway_diag_status}")
    
    railway_ok = railway_health_ok and railway_diag_ok
    railway_status = "✅ WORKING" if railway_ok else "❌ BROKEN"
    print(f"\n  RAILWAY STATUS: {railway_status}\n")
    
    # Summary
    print("="*70)
    print("📊 DEPLOYMENT STATUS SUMMARY")
    print("="*70)
    print(f"  Local Backend:    {local_status}")
    print(f"  Railway Backend:  {railway_status}")
    print()
    
    if local_ok and railway_ok:
        print("✅ ALL SYSTEMS OPERATIONAL!")
        print("   Frontend should be able to connect to production API.")
        return 0
    elif local_ok and not railway_ok:
        print("⚠️  LOCAL WORKS, RAILWAY BROKEN")
        print()
        print("   ACTIONS NEEDED:")
        print("   1. Go to Railway Dashboard: https://railway.app/dashboard")
        print("   2. Find TaskEarn Backend service")
        print("   3. Go to Settings → Configure root (should be 'backend', not '.')")
        print("   4. Trigger Manual Redeploy")
        print("   5. Wait 2-3 minutes")
        print("   6. Run this test again")
        return 1
    else:
        print("❌ LOCAL BACKEND NOT RUNNING")
        print()
        print("   START LOCAL BACKEND:")
        print("   $ cd backend")
        print("   $ python server.py")
        return 2
    
    print()

if __name__ == "__main__":
    try:
        exit(main())
    except KeyboardInterrupt:
        print("\n\n⏹  Cancelled")
        exit(1)
