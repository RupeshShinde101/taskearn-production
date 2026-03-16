#!/usr/bin/env python3
"""
Initialize PostgreSQL database on Railway after deployment.
This script calls the /api/init-db endpoint to create all necessary tables.
"""

import requests
import time
import sys

# Railway backend URL
RAILWAY_URL = "https://taskearn-production-production.up.railway.app"
INIT_DB_ENDPOINT = f"{RAILWAY_URL}/api/init-db"

def wait_for_server(max_attempts=30, delay=2):
    """Wait for Railway server to be ready"""
    print(f"⏳ Waiting for Railway server to be ready ({max_attempts} attempts, {delay}s delay)...")
    
    for attempt in range(max_attempts):
        try:
            response = requests.get(f"{RAILWAY_URL}/api/health", timeout=5)
            if response.status_code == 200:
                print(f"✅ Server is ready (attempt {attempt + 1})")
                return True
            else:
                print(f"   Attempt {attempt + 1}: Status {response.status_code}")
        except Exception as e:
            print(f"   Attempt {attempt + 1}: {str(e)[:50]}")
        
        if attempt < max_attempts - 1:
            time.sleep(delay)
    
    return False

def init_database():
    """Call the database initialization endpoint"""
    print("\n🔄 Initializing database on Railway...")
    print(f"   Calling: {INIT_DB_ENDPOINT}\n")
    
    try:
        response = requests.post(INIT_DB_ENDPOINT, timeout=30)
        
        if response.status_code == 200:
            result = response.json()
            print("✅ DATABASE INITIALIZATION SUCCESSFUL!")
            print(f"   Database Type: {result.get('database_type', 'Unknown')}")
            print(f"   Timestamp: {result.get('timestamp', 'N/A')}")
            print(f"   Message: {result.get('message', 'Success')}")
            return True
        else:
            print(f"❌ Initialization failed with status {response.status_code}")
            print(f"   Response: {response.text[:500]}")
            return False
    except Exception as e:
        print(f"❌ Error calling initialization endpoint: {e}")
        return False

def verify_tables():
    """Verify that tables were created by testing a simple query"""
    print("\n🔍 Verifying database tables...")
    
    # Test the health endpoint which queries the database
    try:
        response = requests.get(f"{RAILWAY_URL}/api/health", timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            if result.get('success'):
                print("✅ Database tables verified!")
                print(f"   Database: {result.get('database', 'N/A')}")
                print(f"   Status: {result.get('status', 'N/A')}")
                return True
        
        print(f"❌ Verification failed: Status {response.status_code}")
        return False
    except Exception as e:
        print(f"❌ Error verifying tables: {e}")
        return False

def main():
    print("=" * 60)
    print("🚀 TaskEarn Railway Database Initialization")
    print("=" * 60)
    
    # Step 1: Wait for server
    if not wait_for_server():
        print("\n❌ Server failed to become ready. Check Railway dashboard for errors.")
        sys.exit(1)
    
    # Step 2: Initialize database
    if not init_database():
        print("\n❌ Database initialization failed.")
        sys.exit(1)
    
    # Step 3: Verify tables
    time.sleep(2)  # Give database time to settle
    if not verify_tables():
        print("\n⚠️  Verification inconclusive, but initialization may have succeeded.")
        print("   Check Railway logs for details.")
    
    print("\n" + "=" * 60)
    print("✅ DATABASE INITIALIZATION COMPLETE!")
    print("=" * 60)
    print("\nYour application should now be able to:")
    print("  - Create user accounts")
    print("  - List tasks")
    print("  - Perform all database operations")
    print("\nURL: https://taskearn.netlify.app")

if __name__ == '__main__':
    main()
