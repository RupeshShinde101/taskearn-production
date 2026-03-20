#!/usr/bin/env python3
"""
Add service_charge column to tasks table
"""

import sqlite3
import os

db_file = 'backend/taskearn.db'

if os.path.exists(db_file):
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    print("🔧 Migrating database...")
    
    # Check if column already exists
    cursor.execute("PRAGMA table_info(tasks)")
    columns = [col[1] for col in cursor.fetchall()]
    
    if 'service_charge' not in columns:
        print("\n  Adding service_charge column...")
        
        # Add the column
        cursor.execute('''
            ALTER TABLE tasks
            ADD COLUMN service_charge REAL DEFAULT 0
        ''')
        
        # Calculate service charges based on category
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
        
        # Update existing tasks with calculated service charges
        cursor.execute("SELECT id, category FROM tasks")
        tasks = cursor.fetchall()
        
        for task_id, category in tasks:
            charge = service_charges.get(category, 50)
            cursor.execute('''
                UPDATE tasks
                SET service_charge = ?
                WHERE id = ?
            ''', (charge, task_id))
            print(f"    ✓ Task {task_id}: service_charge = ₹{charge}")
        
        conn.commit()
        print("\n  ✅ service_charge column added and populated")
        
    else:
        print("\n  ℹ️  service_charge column already exists")
    
    conn.close()
    print("\n✅ Migration complete")
else:
    print(f"❌ Database not found: {db_file}")
