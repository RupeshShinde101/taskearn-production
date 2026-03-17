#!/usr/bin/env python
"""Start the TaskEarn Flask backend on port 5000"""
import sys
import os
import socket

# Add backend to path
sys.path.insert(0, os.path.dirname(__file__))

from server import app
from database import init_sqlite_db

def get_local_ip():
    """Get local machine IP address"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

if __name__ == '__main__':
    print("\n" + "="*70)
    print("🚀 TaskEarn Backend API Server Starting")
    print("="*70)
    
    # Initialize database (create tables if needed)
    print("📦 Initializing database...")
    try:
        init_sqlite_db()
        print("✅ Database ready (SQLite: taskearn.db)")
    except Exception as e:
        print(f"⚠️ Database warning: {e}")
    
    # Get port from environment or default to 5000
    port = int(os.environ.get('PORT', 5000))
    local_ip = get_local_ip()
    
    print(f"\n🌐 Server Details:")
    print(f"   Local:        http://127.0.0.1:{port}")
    print(f"   Network:      http://{local_ip}:{port}")
    print(f"   API:          http://127.0.0.1:{port}/api")
    print(f"   Production:   https://taskearn-production-production.up.railway.app")
    
    print(f"\n📝 API Endpoints:")
    print(f"   /api/health              - Health check")
    print(f"   /api/auth/register       - User registration")
    print(f"   /api/tasks               - Task management")
    print(f"   /api/wallet              - Wallet operations")
    print(f"   /api/payments/verify     - Payment verification")
    print(f"   /api/chat/<task_id>      - Chat messages")
    
    print(f"\n⚙️  Environment:")
    print(f"   Debug Mode:  False")
    print(f"   WSGI Ready:  Yes (production-capable)")
    print(f"   Port:        {port}")
    print(f"   Host:        0.0.0.0\n")
    
    # Run Flask directly (gunicorn will handle it in production)
    try:
        print("="*70)
        print("✨ Server is running and ready for requests...")
        print("="*70 + "\n")
        app.run(host='0.0.0.0', port=port, debug=False, use_reloader=False, threaded=True)
    except KeyboardInterrupt:
        print("\n\n⛔ Server stopped by user")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Server error: {e}")
        sys.exit(1)

