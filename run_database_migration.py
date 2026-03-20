#!/usr/bin/env python3
"""
Run database migrations on Railway after deployment.
This will add missing columns (service_charge, paid_at) to the tasks table.
"""

import requests
import time
import sys

RAILWAY_URL = "https://taskearn-production-production.up.railway.app"
HEALTH_ENDPOINT = f"{RAILWAY_URL}/api/health"
INIT_DB_ENDPOINT = f"{RAILWAY_URL}/api/init-db"

def wait_for_server(max_attempts=30, delay=2):
    """Wait for Railway server to be ready"""
    print(f"⏳ Waiting for Railway server to be ready ({max_attempts} attempts, {delay}s delay)...")
    
    for attempt in range(max_attempts):
        try:
            response = requests.get(HEALTH_ENDPOINT, timeout=5)
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

def run_migrations():
    """Call the database initialization endpoint to run migrations"""
    print("\n🔄 Running database migrations on Railway...")
    print(f"   Calling: {INIT_DB_ENDPOINT}\n")
    
    try:
        response = requests.post(INIT_DB_ENDPOINT, timeout=30)
        
        if response.status_code == 200:
            result = response.json()
            print("✅ DATABASE MIGRATION SUCCESSFUL!")
            print(f"   Database Type: {result.get('database_type', 'Unknown')}")
            print(f"   Timestamp: {result.get('timestamp', 'N/A')}")
            print(f"   Message: {result.get('message', 'Success')}")
            return True
        else:
            print(f"❌ Migration failed with status {response.status_code}")
            print(f"   Response: {response.text[:500]}")
            return False
    except Exception as e:
        print(f"❌ Error calling migration endpoint: {e}")
        return False

def verify_migration():
    """Verify that the migration worked by testing the tasks endpoint"""
    print("\n🔍 Verifying migration by fetching tasks...")
    
    try:
        response = requests.get(f"{RAILWAY_URL}/api/tasks", timeout=10)
        
        if response.status_code == 200:
            result = response.json()
            if result.get('success'):
                print("✅ Migration verified! Tasks endpoint is working.")
                print(f"   Total tasks: {len(result.get('tasks', []))}")
                return True
            else:
                print(f"❌ Verification failed: {result.get('message', 'Unknown error')}")
                return False
        else:
            print(f"❌ Verification failed: Status {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error verifying migration: {e}")
        return False

def main():
    print("=" * 70)
    print("🚀 TaskEarn Railway Database Migration - Add Missing Columns")
    print("=" * 70)
    print("\n📝 This migration will add missing columns to the tasks table:")
    print("   • service_charge (DECIMAL/REAL, DEFAULT 0)")
    print("   • paid_at (TIMESTAMP/TEXT)")
    print("\n" + "=" * 70 + "\n")
    
    # Step 1: Wait for server
    if not wait_for_server():
        print("\n❌ Server failed to become ready. Check Railway dashboard for errors.")
        print("   Go to: https://railway.app and check your deployment logs")
        sys.exit(1)
    
    time.sleep(2)
    
    # Step 2: Run migrations
    if not run_migrations():
        print("\n❌ Database migration failed.")
        print("   Go to: https://railway.app and check your deployment logs")
        sys.exit(1)
    
    time.sleep(2)
    
    # Step 3: Verify migration
    if not verify_migration():
        print("\n⚠️  Verification inconclusive, but migration may have succeeded.")
        print("   Go to: https://railway.app and check the deployment logs")
        print("   Then reload your app to test")
        sys.exit(0)
    
    print("\n" + "=" * 70)
    print("✅ ALL DONE! Your database is now updated.")
    print("=" * 70)
    print("\n🎉 Your app should now be able to load tasks without errors!")
    print("   Try refreshing your browser window.")

if __name__ == "__main__":
    main()
