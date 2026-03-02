#!/usr/bin/env python
"""Start the TaskEarn Flask backend on port 5000"""
import sys
import os

# Add backend to path
sys.path.insert(0, os.path.dirname(__file__))

from server import app
from database import init_sqlite_db

if __name__ == '__main__':
    print("\n" + "="*60)
    print("🚀 TaskEarn Backend API Starting on http://localhost:5000")
    print("="*60)
    
    # Initialize database (create tables if needed)
    print("📦 Initializing database...")
    try:
        init_sqlite_db()
        print("✅ Database ready (SQLite: taskearn.db)")
    except Exception as e:
        print(f"⚠️ Database warning: {e}")
    
    print("\n📚 API Docs available at: http://localhost:5000 (use Postman)")
    print("📝 Frontend connects at: http://localhost:5000/api/...\n")
    
    # Run Flask development server
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
