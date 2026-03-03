#!/usr/bin/env python3
"""
Test TaskEarn Login/Signup Endpoints
"""

import requests
import json
import time

API_URL = 'http://localhost:5000/api'

print("=" * 60)
print("TaskEarn API Connection Test")
print("=" * 60)

# Test 1: Health Check
print("\n1️⃣ Testing Health Check...")
try:
    response = requests.get(f'{API_URL}/health', timeout=5)
    print(f"   Status: {response.status_code}")
    print(f"   Response: {response.json()}")
except Exception as e:
    print(f"   ❌ Error: {e}")

# Test 2: Signup
print("\n2️⃣ Testing Signup Endpoint...")
signup_data = {
    'name': 'Test User',
    'email': f'test-{int(time.time())}@example.com',
    'password': 'TestPassword123!',
    'confirm_password': 'TestPassword123!'
}

try:
    response = requests.post(
        f'{API_URL}/auth/signup',
        json=signup_data,
        headers={'Content-Type': 'application/json'},
        timeout=5
    )
    print(f"   Status: {response.status_code}")
    print(f"   Response: {json.dumps(response.json(), indent=2)}")
    
    if response.status_code == 201:
        print("   ✅ Signup successful!")
except Exception as e:
    print(f"   ❌ Error: {e}")

# Test 3: Login
print("\n3️⃣ Testing Login Endpoint...")
login_data = {
    'email': signup_data['email'],
    'password': 'TestPassword123!'
}

try:
    response = requests.post(
        f'{API_URL}/auth/login',
        json=login_data,
        headers={'Content-Type': 'application/json'},
        timeout=5
    )
    print(f"   Status: {response.status_code}")
    print(f"   Response: {json.dumps(response.json(), indent=2)}")
    
    if response.status_code == 200:
        print("   ✅ Login successful!")
        token = response.json().get('token')
        if token:
            print(f"   🔐 Token: {token[:20]}...")
except Exception as e:
    print(f"   ❌ Error: {e}")

# Test 4: CORS Check
print("\n4️⃣ Testing CORS Configuration...")
try:
    response = requests.options(
        f'{API_URL}/auth/login',
        headers={
            'Origin': 'http://localhost:5500',
            'Access-Control-Request-Method': 'POST'
        },
        timeout=5
    )
    cors_header = response.headers.get('Access-Control-Allow-Origin', 'NOT FOUND')
    print(f"   CORS Origin: {cors_header}")
    print(f"   ✅ CORS enabled!" if cors_header else "   ⚠️ CORS may be restricted")
except Exception as e:
    print(f"   ❌ Error: {e}")

print("\n" + "=" * 60)
print("If tests passed, the issue is in the frontend configuration.")
print("Check browser console for actual errors.")
print("=" * 60)
