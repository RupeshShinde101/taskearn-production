#!/usr/bin/env python
"""
Auto-Deployment Script for TaskEarn to Railway
Handles Git setup, environment config, and deployment prep
"""

import os
import subprocess
import sys
import json
from pathlib import Path


def run_command(cmd, shell=False):
    """Run a shell command and return output"""
    try:
        result = subprocess.run(
            cmd if shell else cmd.split(),
            capture_output=True,
            text=True,
            shell=shell
        )
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)


def print_section(title):
    """Print a formatted section header"""
    print(f"\n{'='*70}")
    print(f"  {title}")
    print(f"{'='*70}\n")


def check_prerequisites():
    """Check if Git is installed"""
    print_section("Checking Prerequisites")
    
    code, _, _ = run_command("git --version")
    if code != 0:
        print("❌ Git is not installed!")
        print("Install from: https://git-scm.com/download/win")
        return False
    
    print("✅ Git is installed")
    return True


def setup_git_repo(repo_path):
    """Initialize Git repository if needed"""
    print_section("Setting Up Git Repository")
    
    os.chdir(repo_path)
    
    # Check if already a git repo
    if os.path.exists(".git"):
        print("✅ Git repository already initialized")
        return True
    
    print("Initializing Git repository...")
    code, _, err = run_command("git init")
    if code != 0:
        print(f"❌ Failed to initialize git: {err}")
        return False
    
    print("✅ Git initialized")
    return True


def configure_git_user():
    """Set Git user info"""
    print("Configuring Git user...")
    
    email = input("Enter your email: ").strip()
    name = input("Enter your name: ").strip()
    
    run_command(f'git config user.email "{email}"', shell=True)
    run_command(f'git config user.name "{name}"', shell=True)
    
    print(f"✅ Git configured as: {name} <{email}>")


def create_gitignore(repo_path):
    """Create .gitignore file"""
    print_section("Creating .gitignore")
    
    gitignore_content = """.env
.env.local
__pycache__/
*.pyc
*.db
*.sqlite
*.sqlite3
.vscode/
.idea/
venv/
ENV/
env/
*.egg-info/
dist/
build/
.DS_Store
Thumbs.db
*.log
logs/
.venv
node_modules/
"""
    
    gitignore_path = os.path.join(repo_path, ".gitignore")
    with open(gitignore_path, "w") as f:
        f.write(gitignore_content)
    
    print("✅ .gitignore created")


def create_railway_config(repo_path):
    """Create railway.json for Railway.app"""
    print_section("Creating Railway Configuration")
    
    railway_config = {
        "$schema": "https://railway.app/railway.schema.json",
        "build": {
            "builder": "dockerfile",
            "buildpacks": []
        },
        "deploy": {
            "numReplicas": 1,
            "startCommand": "gunicorn -w 4 -b 0.0.0.0:$PORT server:app",
            "restartPolicyType": "on_failure",
            "restartPolicyMaxRetries": 5
        }
    }
    
    railway_path = os.path.join(repo_path, "backend", "railway.json")
    with open(railway_path, "w") as f:
        json.dump(railway_config, f, indent=2)
    
    print(f"✅ railway.json created at {railway_path}")


def commit_changes(repo_path):
    """Commit all changes"""
    print_section("Committing Changes")
    
    os.chdir(repo_path)
    
    # Check if there are changes
    code, output, _ = run_command("git status --porcelain")
    if not output.strip():
        print("ℹ️  No changes to commit")
        return True
    
    print("Staging files...")
    run_command("git add .")
    
    print("Committing...")
    code, _, err = run_command('git commit -m "Prepare for Railway deployment"', shell=True)
    if code != 0:
        print(f"⚠️  Commit warning: {err}")
    else:
        print("✅ Changes committed")
    
    return True


def add_remote(repo_path, github_url):
    """Add GitHub remote if not exists"""
    print_section("Adding GitHub Remote")
    
    os.chdir(repo_path)
    
    code, output, _ = run_command("git remote -v")
    if "origin" in output:
        print("✅ GitHub remote already configured")
        return True
    
    print(f"Adding remote: {github_url}")
    code, _, err = run_command(f"git remote add origin {github_url}")
    if code != 0:
        print(f"❌ Failed to add remote: {err}")
        return False
    
    print("✅ GitHub remote added")
    return True


def push_to_github(repo_path):
    """Push code to GitHub"""
    print_section("Pushing to GitHub")
    
    os.chdir(repo_path)
    
    print("Checking current branch...")
    run_command("git branch -M main")
    
    print("Pushing to GitHub...")
    code, out, err = run_command("git push -u origin main")
    
    if code != 0 and "permission denied" in err.lower():
        print("⚠️  Authentication required")
        print("Setup GitHub CLI or use personal access token")
        print("Docs: https://docs.github.com/en/github/authenticating-to-github")
        return False
    elif code != 0:
        print(f"❌ Push failed: {err}")
        return False
    
    print("✅ Code pushed to GitHub")
    return True


def create_env_file(repo_path):
    """Create .env template"""
    print_section("Creating Environment Variables Template")
    
    env_content = """# Database
# Railway PostgreSQL plugin provides this automatically
# Leave empty for SQLite (local development only)
DATABASE_URL=

# JWT
# Generate: python -c "import secrets; print(secrets.token_urlsafe(32))"
SECRET_KEY=your-secret-key-here-min-32-chars

# Production Settings
FLASK_ENV=production
DEBUG=False
ENVIRONMENT=production

# Razorpay
# TEST KEYS (development)
RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxxxx
RAZORPAY_KEY_SECRET=xxxxxxxxxxxxxxxxxxxxxx

# LIVE KEYS (production - uncomment when ready)
# RAZORPAY_KEY_ID=rzp_live_xxxxxxxxxxxxxx
# RAZORPAY_KEY_SECRET=xxxxxxxxxxxxxxxxxxxxxx

# CORS Settings
# For Railway production, set to your domains:
CORS_ORIGINS=https://taskearn.netlify.app,https://taskearn-api.up.railway.app
"""
    
    env_path = os.path.join(repo_path, "backend", ".env.production")
    with open(env_path, "w", encoding="utf-8") as f:
        f.write(env_content)
    
    print(f"✅ .env.production template created")
    print(f"   Location: {env_path}")
    print("   ⚠️  DO NOT commit this file - add to .gitignore")


def print_next_steps(github_url, repo_name):
    """Print deployment instructions"""
    print_section("🎯 Next Steps")
    
    print("""
1. ✅ Local Git setup complete
2. ✅ Code pushed to GitHub

Now deploy to Railway:

   a) Go to: https://railway.app
   b) Sign in with GitHub
   c) Click "Deploy Now"
   d) Select your repository
   e) Railway auto-detects Flask
   f) Click "Deploy"
   
   g) Add PostgreSQL:
      - Click "New" → "Database" → PostgreSQL
      - Railway auto-links DATABASE_URL
      
   h) Set Environment Variables in Railway:
      - ENVIRONMENT=production
      - SECRET_KEY=(generate new one)
      - DEBUG=False
      - RAZORPAY_KEY_ID=(your live key)
      - RAZORPAY_KEY_SECRET=(your live key)
      
   i) Wait for deployment
   j) Get your API URL: https://taskearn-api.up.railway.app
   
3. Deploy Frontend to Netlify:
   
   a) Go to: https://netlify.com
   b) Sign in with GitHub or drag & drop
   c) Deploy your frontend files
   d) Update API URL in index.html
   e) Re-deploy
   
4. Test:
   
   a) Go to https://your-netlify-site.netlify.app
   b) Sign up and post a task
   c) Verify task saved to Railway database
   d) Test from different account

💡 Full guide: See RAILWAY_DEPLOYMENT_GUIDE.md

Questions? Check:
   - Railway Docs: https://docs.railway.app
   - Netlify Docs: https://docs.netlify.com
""")


def main():
    """Main deployment prep function"""
    print("\n" + "="*70)
    print("  ✨ TaskEarn - Railway Deployment Preparation")
    print("="*70)
    
    repo_path = r"c:\Users\therh\Desktop\ToDo"
    
    if not os.path.isdir(repo_path):
        print(f"❌ Repository path not found: {repo_path}")
        return False
    
    # Check prerequisites
    if not check_prerequisites():
        return False
    
    # Configure Git
    if not setup_git_repo(repo_path):
        return False
    
    # Ask for user config
    print("Git needs your information for commits...")
    configure_git_user()
    
    # Create configuration files
    create_gitignore(repo_path)
    create_railway_config(repo_path)
    create_env_file(repo_path)
    
    # Commit
    commit_changes(repo_path)
    
    # Get GitHub URL
    print_section("GitHub Repository")
    print("Create a new repo at: https://github.com/new")
    print("Name it: taskearn-production")
    github_url = input("Enter your GitHub repo URL (e.g., https://github.com/username/taskearn-production): ").strip()
    
    if github_url:
        add_remote(repo_path, github_url)
        push_to_github(repo_path)
    
    # Print next steps
    print_next_steps(github_url, "taskearn-production")
    
    print("\n✅ Deployment preparation complete!\n")
    return True


if __name__ == "__main__":
    try:
        success = main()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n❌ Cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)
