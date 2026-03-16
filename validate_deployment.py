"""
Backend Deployment Validation Script
Checks if backend is properly configured for production deployment
"""

import os
import sys
from pathlib import Path

print("\n" + "="*70)
print("🔍 TaskEarn Backend Deployment Validation")
print("="*70 + "\n")

checks_passed = 0
checks_failed = 0

def check(name, condition, details=""):
    """Run a check and report status"""
    global checks_passed, checks_failed
    status = "✅" if condition else "❌"
    print(f"{status} {name}")
    if details:
        print(f"   → {details}")
    if condition:
        checks_passed += 1
    else:
        checks_failed += 1
    return condition

# Check 1: Backend directory structure
print("\n📁 DIRECTORY STRUCTURE")
print("-" * 70)
backend_dir = Path("backend")
check("Backend folder exists", backend_dir.exists())
check("requirements.txt exists", (backend_dir / "requirements.txt").exists())
check("server.py exists", (backend_dir / "server.py").exists())
check("config.py exists", (backend_dir / "config.py").exists())
check("database.py exists", (backend_dir / "database.py").exists())

# Check 2: Configuration files
print("\n⚙️ CONFIGURATION FILES")
print("-" * 70)
check(".env.production exists", (backend_dir / ".env.production").exists())

# Load and check .env.production
if (backend_dir / ".env.production").exists():
    with open(backend_dir / ".env.production") as f:
        env_content = f.read()
    check("SECRET_KEY configured", "SECRET_KEY=" in env_content and "your-secret-key" not in env_content)
    check("FLASK_ENV=production", "FLASK_ENV=production" in env_content)
    check("DEBUG=False", "DEBUG=False" in env_content)

# Check 3: Docker configuration
print("\n🐳 DEPLOYMENT CONFIGURATION")
print("-" * 70)
check("Dockerfile exists", (backend_dir / "Dockerfile").exists())
check("railway.json exists", (backend_dir / "railway.json").exists())
check("runtime.txt exists", (backend_dir / "runtime.txt").exists())

# Check 4: API routes
print("\n🔗 API ENDPOINTS")
print("-" * 70)
if (backend_dir / "server.py").exists():
    with open(backend_dir / "server.py") as f:
        server_content = f.read()
    
    check("/api/health endpoint", "@app.route('/api/health'" in server_content)
    check("/api/auth/register endpoint", "@app.route('/api/auth/register'" in server_content)
    check("/api/auth/login endpoint", "@app.route('/api/auth/login'" in server_content)
    check("/api/tasks endpoint", "@app.route('/api/tasks'" in server_content)
    check("CORS configured", "CORS(app" in server_content)

# Check 5: Database setup
print("\n💾 DATABASE")
print("-" * 70)
if (backend_dir / "database.py").exists():
    with open(backend_dir / "database.py") as f:
        db_content = f.read()
    
    check("init_db() function", "def init_db(" in db_content)
    check("PostgreSQL support", "psycopg2" in db_content or "PostgreSQL" in db_content)
    check("SQLite fallback", "sqlite3" in db_content or "SQLite" in db_content)

# Check 6: Required Python packages
print("\n📦 DEPENDENCIES")
print("-" * 70)
if (backend_dir / "requirements.txt").exists():
    with open(backend_dir / "requirements.txt") as f:
        requirements = f.read().lower()
    
    check("Flask required", "flask" in requirements)
    check("Flask-CORS required", "flask-cors" in requirements or "cors" in requirements)
    check("PyJWT required", "pyjwt" in requirements or "jwt" in requirements)
    check("Gunicorn included", "gunicorn" in requirements)
    check("python-dotenv included", "dotenv" in requirements)

# Check 7: Frontend configuration
print("\n🎨 FRONTEND CONFIGURATION")
print("-" * 70)
index_html = Path("index.html")
if index_html.exists():
    with open(index_html) as f:
        index_content = f.read()
    
    check("index.html has API URL config", "window.TASKEARN_API_URL" in index_content)
    check("index.html has environment detection", "window.location.hostname" in index_content)

netlify_toml = Path("netlify.toml")
if netlify_toml.exists():
    with open(netlify_toml) as f:
        toml_content = f.read()
    
    check("netlify.toml has BACKEND_URL env var", "BACKEND_URL" in toml_content)
    check("netlify.toml has functions config", "functions" in toml_content)

# Check 8: Netlify Functions
print("\n⚡ NETLIFY FUNCTIONS")
print("-" * 70)
proxy_func = Path("netlify/functions/api-proxy.js")
check("API proxy function exists", proxy_func.exists())
if proxy_func.exists():
    with open(proxy_func) as f:
        proxy_content = f.read()
    check("Proxy handles CORS", "Access-Control-Allow-Origin" in proxy_content)
    check("Proxy forwards requests", "fetch(targetUrl" in proxy_content)

# Summary
print("\n" + "="*70)
print("📊 VALIDATION SUMMARY")
print("="*70)
print(f"✅ Passed: {checks_passed}")
print(f"❌ Failed: {checks_failed}")
print(f"📈 Score: {checks_passed}/{checks_passed + checks_failed} ({int(100*checks_passed/(checks_passed+checks_failed)) if checks_passed+checks_failed > 0 else 0}%)")

if checks_failed == 0:
    print("\n🎉 ALL CHECKS PASSED! Your setup is ready for deployment.")
    print("\nNext steps:")
    print("1. Deploy to Railway or Render")
    print("2. Set environment variables on your hosting platform")
    print("3. Update BACKEND_URL in Netlify to your deployed URL")
    print("4. Deploy frontend to Netlify")
else:
    print(f"\n⚠️ {checks_failed} checks failed. Please fix the issues above.")
    print("\nCommon fixes:")
    print("• Set SECRET_KEY in .env.production")
    print("• Ensure all required files exist")
    print("• Update frontend API URL configuration")
    print("• Configure environment variables on hosting platform")

print("\n" + "="*70 + "\n")
