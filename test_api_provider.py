#!/usr/bin/env python3
"""
Test API endpoint to verify provider phone is being returned
"""

import requests
import json

BASE_URL = "http://localhost:5000"

print("=" * 80)
print("TESTING API PROVIDER PHONE FIELD")
print("=" * 80)

try:
    response = requests.get(f"{BASE_URL}/api/tasks")
    
    if response.status_code == 200:
        data = response.json()
        tasks = data.get('tasks', [])
        
        print(f"\nFound {len(tasks)} tasks in API response\n")
        
        if tasks:
            # Check first task
            task = tasks[0]
            print(f"Task ID: {task.get('id')}")
            print(f"Task Title: {task.get('title')}")
            
            postedBy = task.get('postedBy', {})
            print(f"\nPosted By (Provider):")
            print(f"  Name: {postedBy.get('name', 'NOT FOUND')}")
            print(f"  Phone: {postedBy.get('phone', 'NOT FOUND')}")
            print(f"  Rating: {postedBy.get('rating', 'NOT FOUND')}")
            print(f"  Tasks Posted: {postedBy.get('tasksPosted', 'NOT FOUND')}")
            
            # Verify phone field exists
            if 'phone' in postedBy:
                print(f"\n✅ SUCCESS! Provider phone IS included in API response!")
                print(f"   Phone value: {postedBy['phone']}")
            else:
                print(f"\n❌ PROBLEM! Provider phone is NOT in API response")
                print(f"   Fields in postedBy: {list(postedBy.keys())}")
        else:
            print("No tasks returned")
    else:
        print(f"API Error: {response.status_code}")
        print(response.text)
        
except Exception as e:
    print(f"Connection error: {e}")
