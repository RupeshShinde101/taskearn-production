@echo off
REM TaskEarn - Complete Netlify Deployment Script
REM Automates GitHub preparation for Netlify deployment

setlocal enabledelayedexpansion

cls
echo.
echo ========================================================================
echo  TaskEarn - Complete Netlify Deployment
echo ========================================================================
echo.

REM Check git status
echo Step 1: Checking git repository...
git status >nul 2>&1
if errorlevel 1 (
    echo   - Initializing git repository...
    git init
    git config user.email "dev@taskearn.local"
    git config user.name "TaskEarn Developer"
) else (
    echo   OK - Git repository found
)
echo.

REM Stage files
echo Step 2: Staging deployment files...
git add .
echo   OK - Files staged
echo.

REM Show what will be committed
echo Step 3: Files to be committed:
echo.
git diff --cached --name-status | findstr /r "^M" | for /l %%A in (1,1,10) do (
    if defined LINE echo     %%~A
    set "LINE=%%~A"
)
echo.

REM Create commit
echo Step 4: Creating deployment commit...
set /p MESSAGE="Enter commit message (default: Configure Netlify deployment): "
if "!MESSAGE!"=="" set "MESSAGE=Configure Netlify deployment with Railway backend"
git commit -m "!MESSAGE!"
echo   OK - Commit created
echo.

REM Show log
echo Step 5: Git history (last 3 commits):
echo.
git log --oneline -3
echo.

REM Display next steps
echo ========================================================================
echo  NEXT STEPS - NETLIFY DEPLOYMENT
echo ========================================================================
echo.
echo STEP 1: PUSH TO GITHUB
echo -------------------------------------------------------
echo.
echo If new repository:
echo   git remote add origin https://github.com/YOUR_USERNAME/taskearn.git
echo   git branch -M main
echo   git push -u origin main
echo.
echo Or if existing:
echo   git push origin main
echo.
echo.
echo STEP 2: SETUP NETLIFY
echo -------------------------------------------------------
echo.
echo 1. Open https://app.netlify.com/
echo 2. Sign up/login with GitHub
echo 3. Click "New site from Git"
echo 4. Select taskearn repository
echo 5. Build settings:
echo    - Build command: (leave empty)
echo    - Publish directory: .
echo 6. Click "Deploy"
echo.
echo.
echo STEP 3: GET RAILWAY BACKEND URL
echo -------------------------------------------------------
echo.
echo 1. Open https://railway.app/dashboard
echo 2. Select TaskEarn project
echo 3. Copy the public domain URL
echo 4. Save it (you'll need it next)
echo.
echo.
echo STEP 4: CONFIGURE ENVIRONMENT VARIABLES
echo -------------------------------------------------------
echo.
echo In Netlify Dashboard:
echo 1. Site Settings ^> Build ^& deploy ^> Environment
echo 2. Click "Edit variables"
echo 3. Add variable:
echo    Key: RAILWAY_API_URL
echo    Value: (paste your Railway domain)
echo 4. Save
echo.
echo.
echo STEP 5: DEPLOY
echo -------------------------------------------------------
echo.
echo 1. Go to Netlify ^> Your Site ^> Deploys
echo 2. Click "Trigger deploy" ^> "Deploy site"
echo 3. Wait for green checkmark
echo 4. Your site is live! 
echo.
echo.
echo HELPFUL RESOURCES
echo -------------------------------------------------------
echo.
echo - Full Guide: NETLIFY_DEPLOYMENT.md
echo - Checklist: DEPLOYMENT_SUMMARY.md
echo - Netlify Docs: https://docs.netlify.com/
echo.
echo ========================================================================
echo  Ready to Deploy! Your code is committed and ready for GitHub.
echo ========================================================================
echo.
pause
