#!/usr/bin/env python3
"""
FIX PLAN: Wallet & Task Valuation Issues

ISSUE 1: Service Charge Not Included in Backend Calculations
==========================================================
Current State:
- Frontend displays task price + service_charge (e.g., ₹500 + ₹70 = ₹570)  
- Database stores only task.price (₹500)
- Backend calculates helper pay based on task.price only (₹500 * 0.88 = ₹440)
- Helper gets ₹440 instead of expected (₹570 * 0.88 = ₹501.60)

Root Cause: Service charge is calculated frontend-only, lost when persisted

Fix Strategy:
1. Add service_charge column to tasks table
2. Calculate and store service_charge when task is created
3. Include service_charge in all backend calculations
4. Return service_charge in task API responses


ISSUE 2: Wallet Topup Notification vs Balance Mismatch
======================================================
Current State:
- User sees topup notification with amount X
- Wallet balance shows amount Y (different from X)

Root Cause: Likely paise/rupee conversion error or notification using different logic

Fix Strategy:
1. Verify wallet.html and backend topup verification don't double-convert
2. Ensure notification shows exact amount credited
3. Add transaction logging to track topup amounts


ISSUE 3: Helper Payment Using Wrong Amount
==========================================
Current State:
- Task shows: ₹500 + ₹70 service charge = ₹570 display value
- Helper accepts and completes task
- Helper gets notified: "You will earn ₹440" (should be ₹501.60)
- Helper gets paid: ₹440 (should be ₹501.60)

Root Cause: Backend task completion response uses task.price, not effective total

Fix Strategy:
1. Include service_charge in task completion response
2. Calculate effective earning with serviceCharge included
3. Update UI to show correct earning amount
4. Update pay-helper calculation to use full amount

"""

import sqlite3
import os
import datetime

db_file = 'backend/taskearn.db'

if os.path.exists(db_file):
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    print("\n" + "="*80)
    print("🔍 PRE-FIX ANALYSIS")
    print("="*80)
    
    # Check tasks schema
    print("\n📋 Current Tasks Schema:")
    cursor.execute("PRAGMA table_info(tasks)")
    columns = cursor.fetchall()
    has_service_charge = False
    for col in columns:
        col_name = col[1]
        print(f"  {col_name}")
        if col_name == 'service_charge':
            has_service_charge = True
    
    if not has_service_charge:
        print("\n  ⚠️  service_charge column NOT FOUND")
        print("  Action: Will add service_charge column to tasks table")
    else:
        print("\n  ✅ service_charge column exists")
    
    # Get completed task for analysis
    print("\n\n📊 Current Task Data (Completed Task Only):")
    cursor.execute('''
        SELECT id, title, price, category, posted_by, accepted_by, status
        FROM tasks
        WHERE status = 'completed'
        LIMIT 1
    ''')
    
    task = cursor.fetchone()
    if task:
        task_id, title, price, category, posted_by, accepted_by, status = task
        print(f"  Task ID: {task_id}")
        print(f"  Title: {title}")
        print(f"  Price: ₹{price}")
        print(f"  Category: {category}")
        print(f"  Posted by: {posted_by}")
        print(f"  Accepted by: {accepted_by}")
        print(f"  Status: {status}")
        
        # Calculate service charge based on category
        service_charges = {
            'delivery': 30, 'pickup': 30, 'document': 30,
            'errand': 35, 'groceries': 40, 'laundry': 40,
            'shopping': 40, 'gardening': 50, 'cleaning': 50,
            'cooking': 50, 'repair': 60, 'assembly': 60,
            'tech-support': 60, 'event-help': 60, 'tailoring': 60,
            'beauty': 60, 'petcare': 60, 'tutoring': 70,
            'babysitting': 70, 'fitness': 70, 'photography': 70,
            'painting': 70, 'moving': 80, 'eldercare': 80,
            'carpentry': 90, 'electrician': 100, 'plumbing': 100,
            'vehicle': 40
        }
        
        service_charge = service_charges.get(category, 50)
        total_amount = float(price) + float(service_charge)
        
        print(f"\n  💰 Valuation Analysis:")
        print(f"    Base Price (DB): ₹{price}")
        print(f"    Service Charge ({category}): ₹{service_charge}")
        print(f"    Total Display Value: ₹{total_amount}")
        
        # Calculate helper earnings CURRENT vs CORRECT
        helper_commission_current = float(price) * 0.88
        helper_commission_correct = total_amount * 0.88
        
        print(f"\n  💸 Helper Earnings Comparison:")
        print(f"    Current Calculation (price only): ₹{helper_commission_current:.2f}")
        print(f"    Correct Calculation (price + service): ₹{helper_commission_correct:.2f}")
        print(f"    ⚠️  DIFFERENCE: ₹{(helper_commission_correct - helper_commission_current):.2f}")
    
    conn.close()
    
    print("\n" + "="*80)
    print("✅ ANALYSIS COMPLETE - Ready for fixes")
    print("="*80)
else:
    print(f"❌ Database not found: {db_file}")
