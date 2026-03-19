#!/usr/bin/env python3
"""Debug script to check task visibility and database issues"""

import sqlite3
import datetime
import sys

def check_tasks_in_db():
    """Check all tasks in the database"""
    try:
        conn = sqlite3.connect('taskearn.db')
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        print("\n" + "="*80)
        print("📋 TASK DATABASE AUDIT")
        print("="*80)
        
        # Get all tasks
        cursor.execute('SELECT * FROM tasks ORDER BY posted_at DESC')
        all_tasks = cursor.fetchall()
        
        print(f"\n✅ Total tasks in database: {len(all_tasks)}")
        
        if all_tasks:
            print("\n📊 Task Breakdown:")
            print("-" * 80)
            print(f"{'ID':<5} {'Title':<25} {'Status':<12} {'Expires At':<25} {'Posted By':<15}")
            print("-" * 80)
            
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            
            for task in all_tasks:
                task_id = task['id']
                title = task['title'][:24] if task['title'] else 'N/A'
                status = task['status']
                expires = task['expires_at']
                posted_by = task['posted_by'][:14] if task['posted_by'] else 'N/A'
                
                # Check if expired
                is_expired = expires < now if expires else False
                expired_marker = "❌ EXPIRED" if is_expired else "✅ ACTIVE" if status == 'active' else f"⚠️  {status.upper()}"
                
                print(f"{task_id:<5} {title:<25} {status:<12} {expired_marker:<25} {posted_by:<15}")
        
        print("\n")
        print("="*80)
        print("🔍 FILTERING ANALYSIS")
        print("="*80)
        
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        # Count active, non-expired tasks (what the API returns)
        cursor.execute('''
            SELECT COUNT(*) as count FROM tasks 
            WHERE status = 'active' AND expires_at > ?
        ''', (now,))
        result = cursor.fetchone()
        active_count = result['count'] if result else 0
        
        print(f"\n✅ Active + Non-expired tasks (what API shows): {active_count}")
        
        # Count by status
        cursor.execute('SELECT status, COUNT(*) as count FROM tasks GROUP BY status')
        status_counts = cursor.fetchall()
        
        print("\n📊 Tasks by Status:")
        for row in status_counts:
            print(f"   {row['status']:<15}: {row['count']}")
        
        # Check for tasks that are expired
        cursor.execute('''
            SELECT COUNT(*) as count FROM tasks 
            WHERE expires_at < ?
        ''', (now,))
        expired_result = cursor.fetchone()
        expired_count = expired_result['count'] if expired_result else 0
        
        print(f"\n⏰ Expired tasks (not shown): {expired_count}")
        
        # Check for tasks with no expiration
        cursor.execute('SELECT COUNT(*) as count FROM tasks WHERE expires_at IS NULL')
        no_expire_result = cursor.fetchone()
        no_expire_count = no_expire_result['count'] if no_expire_result else 0
        
        print(f"❓ Tasks with no expiration date: {no_expire_count}")
        
        # Show details of recently created tasks
        print("\n" + "="*80)
        print("🆕 RECENTLY CREATED TASKS (Last 5)")
        print("="*80 + "\n")
        
        cursor.execute('''
            SELECT 
                id, title, posted_by, posted_at, expires_at, status,
                category, price
            FROM tasks
            ORDER BY posted_at DESC
            LIMIT 5
        ''')
        recent = cursor.fetchall()
        
        for task in recent:
            print(f"Task ID: {task['id']}")
            print(f"  Title: {task['title']}")
            print(f"  Posted by: {task['posted_by']}")
            print(f"  Posted at: {task['posted_at']}")
            print(f"  Expires at: {task['expires_at']}")
            print(f"  Status: {task['status']}")
            print(f"  Category: {task['category']}")
            print(f"  Price: ₹{task['price']}")
            print(f"  Will show to other users: {task['status'] == 'active' and (task['expires_at'] is None or task['expires_at'] > now)}")
            print()
        
        conn.close()
        
    except sqlite3.DatabaseError as e:
        print(f"❌ Database error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    check_tasks_in_db()
