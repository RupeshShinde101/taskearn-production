#!/usr/bin/env python3
"""Debug API endpoint availability"""

import requests
import json

API_URL = 'http://localhost:5000/api'

# Test different variations
endpoints = [
    '/auth/register',
    '/auth/signup',
    '/auth/login',
    '/health'
]

print("Testing all API endpoints...\n")

for endpoint in endpoints:
    try:
        # OPTIONS request to check if endpoint exists
        response = requests.options(f'{API_URL}{endpoint}', timeout=2)
        status = f"✅ {response.status_code}"
    except:
        # GET request fallback
        try:
            response = requests.get(f'{API_URL}{endpoint}', timeout=2)
            status = f"⚠️ {response.status_code} (GET)"
        except Exception as e:
            status = f"❌ {str(e)}"
    
    print(f"{endpoint:<30} → {status}")

# Try POST to register
print("\n" + "=" * 60)
print("Detailed Register Endpoint Test")
print("=" * 60)

test_data = {
    'name': 'Debug User',
    'email': f'debug@example.com',
    'password': 'Test12345',
    'dob': '2000-01-01',
    'phone': ''
}

try:
    response = requests.post(
        f'{API_URL}/auth/register',
        json=test_data,
        timeout=5
    )
    print(f"\n✅ Endpoint Found!")
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
except Exception as e:
    print(f"\n❌ Error: {e}")
    print("\nTrying with URL prefix variation...")
    
    try:
        response = requests.post(
            f'http://localhost:5000/auth/register',
            json=test_data,
            timeout=5
        )
        print(f"Found at: http://localhost:5000/auth/register")
    except:
        print("Not found")
