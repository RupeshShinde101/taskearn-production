#!/usr/bin/env python3
"""
Final Verification - Backend and CORS Status
"""

import requests
import json
import time

API_URL = 'http://localhost:5000/api'

print("\n" + "="*70)
print(" ✓ CORS FIX VERIFICATION")
print("="*70)

# Test 1: Health Check
print("\n1️⃣  Health Check...")
try:
    response = requests.get(f'{API_URL}/health', timeout=5)
    if response.status_code == 200:
        print("    ✅ Backend is running")
        data = response.json()
        print(f"    📊 Database: {data.get('database', 'Unknown')}")
    else:
        print(f"    ❌ Unexpected status: {response.status_code}")
except Exception as e:
    print(f"    ❌ Cannot connect: {e}")
    exit(1)

# Test 2: CORS Headers
print("\n2️⃣  CORS Headers...")
try:
    response = requests.options(
        f'{API_URL}/auth/login',
        headers={
            'Origin': 'http://localhost:5500',
            'Access-Control-Request-Method': 'POST'
        },
        timeout=5
    )
    cors_origin = response.headers.get('Access-Control-Allow-Origin')
    cors_methods = response.headers.get('Access-Control-Allow-Methods')
    cors_headers = response.headers.get('Access-Control-Allow-Headers')
    
    if cors_origin == '*':
        print(f"    ✅ CORS Origin: {cors_origin}")
    else:
        print(f"    ⚠️ CORS Origin: {cors_origin or 'Not set'}")
    
    if cors_methods:
        print(f"    ✅ CORS Methods: {cors_methods}")
    if cors_headers:
        print(f"    ✅ CORS Headers: {cors_headers}")
        
except Exception as e:
    print(f"    ❌ Error: {e}")

# Test 3: Register Endpoint
print("\n3️⃣  Register Endpoint (Create Account)...")
test_email = f'test{int(time.time())}@example.com'
test_data = {
    'name': 'Test User',
    'email': test_email,
    'password': 'Test12345',
    'dob': '2000-01-01',
    'phone': ''
}

try:
    response = requests.post(
        f'{API_URL}/auth/register',
        json=test_data,
        headers={'Content-Type': 'application/json'},
        timeout=5
    )
    
    if response.status_code == 201:
        print(f"    ✅ Registration works!")
        data = response.json()
        if data.get('token'):
            print(f"    🔐 Got auth token: {data['token'][:20]}...")
        if data.get('user'):
            print(f"    👤 User ID: {data['user'].get('id')}")
    else:
        print(f"    ⚠️ Status {response.status_code}: {response.json().get('message', 'Unknown error')}")
except Exception as e:
    print(f"    ❌ Error: {e}")

# Test 4: Login Endpoint
print("\n4️⃣  Login Endpoint...")
try:
    response = requests.post(
        f'{API_URL}/auth/login',
        json={'email': test_email, 'password': 'Test12345'},
        headers={'Content-Type': 'application/json'},
        timeout=5
    )
    
    if response.status_code == 200:
        print(f"    ✅ Login works!")
        data = response.json()
        if data.get('token'):
            print(f"    🔐 Got auth token: {data['token'][:20]}...")
    else:
        print(f"    ⚠️ Status {response.status_code}: {response.json().get('message', 'Unknown error')}")
except Exception as e:
    print(f"    ❌ Error: {e}")

# Summary
print("\n" + "="*70)
print(" ✨ VERIFICATION COMPLETE")
print("="*70)
print("""
Based on the tests above:

✅ If all tests passed:
   - Backend is running correctly
   - CORS is properly configured
   - Login/Signup should work in the browser
   - Open http://localhost:5500/index.html and test!

⚠️ If CORS test shows warnings:
   - The backends CORS might still not be perfect
   - But login/signup should still work
   - Test in the browser to confirm

❌ If any tests failed:
   - Check the backend terminal for errors
   - Restart the backend: python backend/server.py
   - Run this test again

Next steps:
  1. Open your app: http://localhost:5500/index.html
  2. Try creating an account
  3. Try logging in
  4. If you see errors, open api-diagnostic.html in your browser
""")
print("="*70 + "\n")
