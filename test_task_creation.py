#!/usr/bin/env python3
"""
Test script to verify task creation works end-to-end
"""
import requests
import json
import time
from datetime import datetime, timedelta

BASE_URL = "http://localhost:5000/api"

def test_task_creation():
    print("=" * 70)
    print("TaskEarn Task Creation Test")
    print("=" * 70)
    
    # Step 1: Register a test user
    print("\n1️⃣ Registering test user...")
    timestamp = int(time.time() * 1000)
    test_user_id = f"test_user_{timestamp}"
    
    register_data = {
        "id": test_user_id,
        "name": "Test User",
        "email": f"test{timestamp}@taskearn.com",
        "password": "Test@123456",
        "phone": "9876543210",
        "dob": "2000-01-01"
    }
    
    try:
        resp = requests.post(f"{BASE_URL}/auth/register", json=register_data, timeout=5)
        print(f"   Status: {resp.status_code}")
        result = resp.json()
        print(f"   Response: {json.dumps(result, indent=2)}")
        
        if not result.get('success'):
            print(f"❌ Registration failed: {result.get('message')}")
            return
        
        token = result.get('token')
        if not token:
            print("❌ No token received from registration")
            return
        
        print(f"✅ Registration successful")
        print(f"   Token: {token[:20]}...")
    except Exception as e:
        print(f"❌ Registration error: {e}")
        return
    
    # Step 2: Create a task
    print("\n2️⃣ Creating a test task...")
    
    task_data = {
        "title": "Test Task - Clean House",
        "description": "Please help clean my house",
        "category": "household",
        "location": {
            "lat": 28.6139,
            "lng": 77.2090,
            "address": "New Delhi, India"
        },
        "price": 500
    }
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}"
    }
    
    try:
        resp = requests.post(f"{BASE_URL}/tasks", json=task_data, headers=headers, timeout=5)
        print(f"   Status: {resp.status_code}")
        result = resp.json()
        print(f"   Response: {json.dumps(result, indent=2)}")
        
        if not result.get('success'):
            print(f"❌ Task creation failed: {result.get('message')}")
            return
        
        task_id = result.get('taskId')
        if not task_id:
            print("❌ No taskId in response")
            return
        
        print(f"✅ Task created successfully")
        print(f"   Task ID: {task_id}")
    except Exception as e:
        print(f"❌ Task creation error: {e}")
        return
    
    # Step 3: Verify task exists in database
    print("\n3️⃣ Verifying task in database...")
    
    try:
        resp = requests.get(f"{BASE_URL}/tasks", headers=headers, timeout=5)
        print(f"   Status: {resp.status_code}")
        result = resp.json()
        
        if result.get('success') and result.get('tasks'):
            tasks = result['tasks']
            print(f"   Total tasks returned: {len(tasks)}")
            
            # Find our test task
            found = False
            for task in tasks:
                if task.get('id') == task_id:
                    found = True
                    print(f"\n✅ Task found in database!")
                    print(f"   Title: {task.get('title')}")
                    print(f"   Price: ₹{task.get('price')}")
                    print(f"   Status: {task.get('status')}")
                    print(f"   Category: {task.get('category')}")
                    break
            
            if not found:
                print(f"⚠️ Task {task_id} not found in returned list")
                print(f"   First task in list: {tasks[0].get('id') if tasks else 'None'}")
        else:
            print(f"⚠️ Could not fetch tasks: {result.get('message')}")
    except Exception as e:
        print(f"❌ Fetch tasks error: {e}")
        return
    
    print("\n" + "=" * 70)
    print("✅ TEST COMPLETED SUCCESSFULLY")
    print("=" * 70)

if __name__ == "__main__":
    test_task_creation()
