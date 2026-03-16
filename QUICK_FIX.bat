@echo off
REM TaskEarn API Quick Fix Script
REM This script provides immediate solutions to get your app working

echo.
echo ======================================================================
echo  ^> TaskEarn API Connection - QUICK FIX
echo ======================================================================
echo.

echo What is your current situation?
echo.
echo 1. I want to test locally (quickest - 2 minutes)
echo 2. I want to fix the Netlify production site (5 minutes)
echo 3. I want to deploy backend properly to Railway (15 minutes)
echo.

set /p choice="Enter your choice (1, 2, or 3): "

if "%choice%"=="1" goto local_fix
if "%choice%"=="2" goto netlify_fix
if "%choice%"=="3" goto railway_fix
echo Invalid choice. Exiting.
exit /b

:local_fix
cls
echo ======================================================================
echo OPTION 1: Test Locally (Development)
echo ======================================================================
echo.
echo This will start your backend on http://localhost:5000
echo Then you can visit http://localhost:8080 (or use Live Server)
echo.
echo Starting backend...
echo.
cd backend
python run.py

:netlify_fix
cls
echo ======================================================================
echo OPTION 2: Fix Netlify Production Site
echo ======================================================================
echo.
echo Step 1: Go to https://app.netlify.com
echo Step 2: Select your site (taskearn)
echo Step 3: Settings ^> Environment variables
echo Step 4: Add or update this variable:
echo    Name: BACKEND_URL
echo    Value: https://YOUR-ACTUAL-BACKEND-URL
echo.
echo Example: https://taskearn-api.up.railway.app
echo          (Replace with your actual backend URL)
echo.
echo Step 5: Redeploy your site
echo Step 6: Visit your Netlify site and test login/task creation
echo.
pause
exit /b

:railway_fix
cls
echo ======================================================================
echo OPTION 3: Deploy to Railway (Production)
echo ======================================================================
echo.
echo This is the best long-term solution!
echo.
echo Prerequisites:
echo   - Git installed
echo   - GitHub account
echo.
echo Step 1: Create/Update GitHub Repository
pause
echo.
git init
git add .
git commit -m "TaskEarn deployment to Railway"
echo.
echo Step 2: Add remote (run this if not done):
echo   git remote add origin https://github.com/YOUR_USERNAME/taskearn.git
echo.
echo   Then: git push -u origin main
echo.
pause

echo.
echo Step 3: Deploy to Railway
echo   1. Go to https://railway.app
echo   2. Sign in or create account (free)
echo   3. Click "Create Project"
echo   4. Select "Deploy from GitHub"
echo   5. Choose your repository
echo   6. Set root directory to: backend
echo.
echo Step 4: Set Environment Variables on Railway
echo   After deployment, go to Railway Dashboard
echo   Add these variables:
echo     - SECRET_KEY (generate with: python -c "import secrets; print(secrets.token_urlsafe(32))")
echo     - DATABASE_URL (leave empty for SQLite or add PostgreSQL)
echo     - FLASK_ENV = production
echo     - DEBUG = False
echo.
pause

echo.
echo Step 5: Get Your Railway URL
echo   Look in Deployments - copy your URL
echo   Should look like: https://taskearn-api-xyz.up.railway.app
echo.
echo Step 6: Update Frontend Files
echo   - Update index.html (line ~24)
echo   - Update netlify.toml (line ~9)
echo   - Update admin.html (line ~16)
echo   - Update chat.html (line ~15)
echo.
echo   Replace: window.TASKEARN_API_URL = 'YOUR-RAILWAY-URL/api'
echo.
pause

echo.
echo Step 7: Deploy Frontend to Netlify
echo   git add .
echo   git commit -m "Update API URL to Railway backend"
echo   git push origin main
echo.
echo Done! Your app should now work on Netlify!
echo.
echo Check: Visit your Netlify site and try creating an account
echo.
pause

exit /b
