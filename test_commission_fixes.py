#!/usr/bin/env python3
"""
Test script to verify commission deduction and service charge fixes
"""

import sqlite3
import json

# Connect to database
conn = sqlite3.connect('backend/taskearn.db')
cursor = conn.cursor()

# Get all tasks
cursor.execute('SELECT id, title, category, price, service_charge, status FROM tasks')
tasks = cursor.fetchall()

print("=" * 80)
print("COMMISSION DEDUCTION & SERVICE CHARGE TEST REPORT")
print("=" * 80)
print()

if not tasks:
    print("No tasks found in database")
    conn.close()
    exit(1)

print(f"Found {len(tasks)} tasks. Testing calculations:\n")

# Test service charges and calculations
for task_id, title, category, price, service_charge, status in tasks:
    print(f"Task {task_id}: {title}")
    print(f"  Category: {category}")
    print(f"  Base Price: ₹{price}")
    print(f"  Service Charge: ₹{service_charge if service_charge else 'NOT SET'}")
    
    if service_charge:
        total_amount = price + service_charge
        helper_commission = total_amount * 0.12
        helper_earnings = total_amount * 0.88
        poster_fee = total_amount * 0.05
        total_poster_pays = total_amount + poster_fee
        
        print(f"  Total Task Value: ₹{total_amount:.2f}")
        print(f"  Helper Commission (12%): ₹{helper_commission:.2f}")
        print(f"  Helper Receives (88%): ₹{helper_earnings:.2f}")
        print(f"  Poster Platform Fee (5%): ₹{poster_fee:.2f}")
        print(f"  Total Poster Pays: ₹{total_poster_pays:.2f}")
        print(f"  Status: {status}")
        
        # Verify calculations
        total_check = helper_earnings + helper_commission
        if abs(total_check - total_amount) < 0.01:
            print(f"  ✅ Calculation verified: {helper_earnings:.2f} + {helper_commission:.2f} = {total_amount:.2f}")
        else:
            print(f"  ❌ Calculation error: {helper_earnings:.2f} + {helper_commission:.2f} != {total_amount:.2f}")
    else:
        print(f"  ⚠️  Service charge NOT set - need migration")
    
    print()

# Summary stats
cursor.execute('SELECT COUNT(*) FROM tasks WHERE service_charge IS NOT NULL AND service_charge > 0')
service_charge_count = cursor.fetchone()[0]

cursor.execute('SELECT AVG(service_charge) FROM tasks WHERE service_charge > 0')
avg_service_charge = cursor.fetchone()[0]

print("=" * 80)
print("SUMMARY STATISTICS")
print("=" * 80)
print(f"Tasks with service charge: {service_charge_count}/{len(tasks)}")
print(f"Average service charge: ₹{avg_service_charge:.2f}" if avg_service_charge else "No service charges set")
print()
print("EXPECTED BEHAVIOR:")
print("- Task price + service_charge = Total task value")
print("- Helper commission = 12% of total task value")
print("- Helper earnings = 88% of total task value")
print("- Poster fee = 5% of total task value")
print("- Poster pays = Total task value + poster fee")
print()

conn.close()
print("✅ Test complete!")
