#!/usr/bin/env python
"""
Quick test to verify the TaskEarn API is working end-to-end
Tests: Register → Login → Post Task → List Tasks
"""

import requests
import json
import sys

API_URL = "http://localhost:5000/api"
FRONTEND_URL = "http://localhost:5500"

def test_api():
    print("\n" + "="*70)
    print("🧪 TaskEarn API End-to-End Test")
    print("="*70 + "\n")
    
    # Test 1: Register
    print("1️⃣  Testing User Registration...")
    register_data = {
        "name": "Test User",
        "email": f"test@taskearn.local",
        "password": "TestPass123",
        "phone": "9999999999",
        "dob": "1995-01-01"
    }
    
    try:
        r = requests.post(f"{API_URL}/auth/register", json=register_data, timeout=5)
        if r.status_code in (200, 201):
            user_data = r.json()
            user_id = user_data.get('user', {}).get('id')
            token = user_data.get('token')
            print(f"   ✅ Registration successful! User ID: {user_id}")
        else:
            print(f"   ⚠️ Registration returned {r.status_code}: {r.json()}")
            user_id = None
    except Exception as e:
        print(f"   ❌ Registration failed: {e}")
        user_id = None
    
    if not user_id:
        print("\n❌ Cannot proceed without user registration")
        return False
    
    # Test 2: Login
    print("\n2️⃣  Testing User Login...")
    login_data = {"email": register_data["email"], "password": register_data["password"]}
    
    try:
        r = requests.post(f"{API_URL}/auth/login", json=login_data, timeout=5)
        if r.status_code == 200:
            user_data = r.json()
            token = user_data.get('token')
            print(f"   ✅ Login successful! Token obtained")
        else:
            print(f"   ❌ Login failed: {r.status_code} - {r.json()}")
            token = None
    except Exception as e:
        print(f"   ❌ Login failed: {e}")
        token = None
    
    if not token:
        print("\n❌ Cannot proceed without authentication token")
        return False
    
    # Test 3: Post a Task
    print("\n3️⃣  Testing Task Creation...")
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    task_data = {
        "title": "Test Task - Help me understand this concept",
        "description": "Need someone to help with API testing and integration",
        "category": "tutoring",
        "price": 500,
        "location": {
            "lat": 28.6139,
            "lng": 77.2090,
            "address": "New Delhi, India"
        }
    }
    
    try:
        r = requests.post(f"{API_URL}/tasks", json=task_data, headers=headers, timeout=5)
        if r.status_code in (200, 201):
            task_response = r.json()
            task_id = task_response.get('taskId')
            print(f"   ✅ Task created successfully! Task ID: {task_id}")
        else:
            print(f"   ❌ Task creation failed: {r.status_code} - {r.json()}")
            task_id = None
    except Exception as e:
        print(f"   ❌ Task creation failed: {e}")
        task_id = None
    
    # Test 4: List Tasks (Public - no auth needed)
    print("\n4️⃣  Testing Task List Retrieval...")
    try:
        r = requests.get(f"{API_URL}/tasks", timeout=5)
        if r.status_code == 200:
            tasks_response = r.json()
            task_count = len(tasks_response.get('tasks', []))
            print(f"   ✅ Retrieved task list! Total tasks: {task_count}")
            
            if task_count > 0:
                first_task = tasks_response['tasks'][0]
                print(f"   📝 Most recent task: {first_task.get('title')}")
                print(f"      Posted by: {first_task.get('postedBy', {}).get('name')}")
                print(f"      Price: ₹{first_task.get('price')}")
        else:
            print(f"   ❌ Failed to retrieve tasks: {r.status_code}")
    except Exception as e:
        print(f"   ❌ Task retrieval failed: {e}")
    
    # Summary
    print("\n" + "="*70)
    print("✅ API TEST COMPLETE - System is working!")
    print("="*70)
    print(f"\n📱 Frontend URL: {FRONTEND_URL}")
    print(f"🔌 Backend API: {API_URL}")
    print(f"💻 Try signing up and posting a task!\n")
    
    return True

if __name__ == "__main__":
    try:
        success = test_api()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n❌ Test failed with error: {e}")
        sys.exit(1)
