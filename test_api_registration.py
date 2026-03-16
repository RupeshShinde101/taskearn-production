#!/usr/bin/env python
"""Test user registration API endpoint"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

from server import app
import json
import secrets

print("🧪 Testing Registration API Endpoint...")
print()

# Create test client
client = app.test_client()

# Generate unique email
test_email = f"newuser_{secrets.token_hex(4)}@example.com"

print(f"1️⃣  Testing registration with email: {test_email}")
print()

# Test registration
response = client.post('/api/auth/register', 
    json={
        'name': 'John Doe',
        'email': test_email,
        'password': 'Test123!@',
        'phone': '9876543210',
        'dob': '2000-01-01'
    },
    content_type='application/json'
)

print(f"   Response Status: {response.status_code}")
print(f"   Response Body:")

data = response.get_json()
print(f"      Success: {data.get('success')}")
print(f"      Message: {data.get('message')}")

if response.status_code == 201 and data.get('success'):
    print(f"      Token: {data.get('token')[:20]}..." if data.get('token') else "      Token: None")
    user = data.get('user', {})
    print(f"      User ID: {user.get('id')}")
    print(f"      User Name: {user.get('name')}")
    print(f"      User Email: {user.get('email')}")
    print()
    print("✅ SUCCESS! User registration API is working!")
else:
    print(f"   Full Response: {json.dumps(data, indent=2)}")
    print()
    if response.status_code != 201:
        print(f"❌ FAILED! Got status {response.status_code}")
    else:
        print(f"❌ FAILED! Response indicated failure: {data.get('message')}")
    sys.exit(1)
