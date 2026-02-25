@echo off
REM Quick Production Deployment Setup Script
REM This script helps you configure your app for production

echo ============================================
echo  TaskEarn Production Setup
echo ============================================
echo.

REM Check if git is installed
git --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is not installed
    echo Please install Git from https://git-scm.com
    pause
    exit /b 1
)

REM Initialize git repo if not already done
if not exist .git (
    echo Initializing Git repository...
    git init
)

REM Configure git
echo.
echo Configuring Git...
git config user.email "you@example.com" 2>nul
git config user.name "TaskEarn Developer" 2>nul

REM Add all files
echo.
echo Staging files...
git add -A

REM Commit
git commit -m "TaskEarn production deployment - ready for Railway" --allow-empty

echo.
echo ============================================
echo Build files prepared for deployment!
echo ============================================
echo.
echo Next steps:
echo 1. Push to GitHub:
echo    git remote add origin https://github.com/YOUR-USERNAME/taskearn-production.git
echo    git branch -M main
echo    git push -u origin main
echo.
echo 2. Deploy to Railway:
echo    - Go to https://railway.app
echo    - Create new project from GitHub repo
echo    - Add PostgreSQL database
echo    - Set environment variables
echo    - Deploy!
echo.
echo 3. Deploy to Netlify:
echo    - Go to https://netlify.com
echo    - Create new site from GitHub repo
echo    - Update API URL in HTML files
echo    - Deploy!
echo.
echo See PRODUCTION_DEPLOYMENT.md for detailed instructions.
echo.
pause
