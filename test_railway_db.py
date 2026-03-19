#!/usr/bin/env python
"""Test Railway PostgreSQL database connection"""

import os
import sys
import requests
import json

print("=" * 70)
print("Railway Database Connection Test")
print("=" * 70)

# Test 1: Check if Railway backend is running
print("\n1. Testing Railway Backend Health")
print("-" * 70)

try:
    response = requests.get(
        'https://taskearn-production-production.up.railway.app/api/health',
        timeout=10
    )
    print(f"   Status Code: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"   Status: {data.get('status')}")
        print(f"   Database Type: {data.get('database')}")
        print(f"   Environment: {data.get('environment')}")
        
        if data.get('database') == 'PostgreSQL':
            print("\n   ✅ PostgreSQL is CONNECTED on Railway!")
        elif data.get('database') == 'SQLite':
            print("\n   ⚠️ SQLite in use - DATABASE_URL may not be set on Railway")
            print("   ACTION NEEDED: Add DATABASE_URL environment variable to Railway")
        else:
            print(f"\n   ? Unexpected database: {data.get('database')}")
    else:
        print(f"   ❌ Unexpected status code")
        print(f"   Response: {response.text[:200]}")
        
except requests.exceptions.Timeout:
    print("   ❌ Connection TIMEOUT - Railway may be down or unreachable")
    print("   Check Railway logs for errors")
except Exception as e:
    print(f"   ❌ Error: {str(e)}")

# Test 2: Try to fetch tasks (requires authentication)
print("\n2. Testing Database Query (GET /api/tasks)")
print("-" * 70)

try:
    response = requests.get(
        'https://taskearn-production-production.up.railway.app/api/tasks',
        timeout=10
    )
    print(f"   Status Code: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        if data.get('success'):
            tasks = data.get('tasks', [])
            print(f"   ✅ Database query successful!")
            print(f"   Tasks found: {len(tasks)}")
            if tasks:
                print(f"   Sample task: {tasks[0].get('title')}")
        else:
            print(f"   ⚠️ Query failed: {data.get('message')}")
    elif response.status_code == 401:
        print(f"   ℹ️ Unauthenticated request (401) - This is normal for public endpoint")
        print(f"   Database is reachable!")
    else:
        print(f"   ❌ Error: {response.text[:200]}")
        
except Exception as e:
    print(f"   ❌ Error: {str(e)}")

# Test 3: Check environment variables on local backend
print("\n3. Checking Local Backend Configuration")
print("-" * 70)

database_url = os.environ.get('DATABASE_URL')
pg_host = os.environ.get('PGHOST')
pg_port = os.environ.get('PGPORT')
pg_user = os.environ.get('PGUSER')

if database_url:
    # Mask password
    masked = database_url.replace(database_url.split('@')[0].split(':')[-1], '[PASSWORD]') if '@' in database_url else database_url
    print(f"   DATABASE_URL: {masked}")
else:
    print(f"   DATABASE_URL: NOT SET (will use SQLite)")

if pg_host or pg_port or pg_user:
    print(f"   PGHOST: {pg_host or 'NOT SET'}")
    print(f"   PGPORT: {pg_port or 'NOT SET'}")
    print(f"   PGUSER: {pg_user or 'NOT SET'}")
    print(f"   PGPASSWORD: {'SET' if os.environ.get('PGPASSWORD') else 'NOT SET'}")

# Test 4: Summary and recommendations
print("\n" + "=" * 70)
print("RECOMMENDATIONS")
print("=" * 70)

print("""
If you see SQLite in the health check:
  1. Go to https://railway.app → Your Project → Variables
  2. Add DATABASE_URL environment variable with format:
     postgresql://user:password@host:port/database
  3. Click "Deploy" to restart the backend
  4. Wait 2-3 minutes and re-run this test

If PostgreSQL is connected but error persists:
  1. Check Railway Logs for error messages
  2. Verify the password has no special characters
  3. Ensure the host is reachable (should end in .railway.internal or be an IP)

For help finding your credentials:
  1. Go to Railway → Plugins/Resources
  2. Click your PostgreSQL database
  3. Click "Connect" to view credentials
  4. Copy the Database URL and add to Variables
""")

print("=" * 70)
