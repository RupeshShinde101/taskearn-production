#!/usr/bin/env python3
"""
Test to verify service_charge is being returned in API responses
"""

import requests
import json

BASE_URL = "http://localhost:5000"

# Get all tasks
print("Testing /api/tasks endpoint...")
response = requests.get(f"{BASE_URL}/api/tasks")

if response.status_code == 200:
    data = response.json()
    tasks = data.get('tasks', [])
    
    if tasks:
        print(f"\nFound {len(tasks)} tasks. Checking first task:")
        task = tasks[0]
        print(f"\nTask Details:")
        print(f"  ID: {task.get('id')}")
        print(f"  Title: {task.get('title')}")
        print(f"  Price: ₹{task.get('price')}")
        print(f"  Service Charge: ₹{task.get('service_charge')}")
        
        if 'service_charge' in task and task['service_charge'] > 0:
            total = task.get('price', 0) + task.get('service_charge', 0)
            print(f"  Total Value: ₹{total}")
            print("\n✅ Service charge IS being returned in API response!")
        else:
            print(f"\n❌ Service charge is missing or zero!")
    else:
        print("No tasks available for testing")
else:
    print(f"❌ Error: {response.status_code}")
    print(response.text)
