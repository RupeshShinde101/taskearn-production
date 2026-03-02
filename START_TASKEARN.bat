@echo off
setlocal enabledelayedexpansion

title TaskEarn - Complete Platform Startup
color 0A

cls
echo.
echo ====================================================================
echo.
echo    ^╔════════════════════════════════════════════════════════════╗
echo    ^║        TASKEARN - Complete Platform Startup             ^║
echo    ^║                    (Powered by Flask + SQLite)             ^║
echo    ^╚════════════════════════════════════════════════════════════╝
echo.
echo ====================================================================
echo.

REM Check if Python is available
c:/python314/python.exe --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found! Ensure c:/python314/python.exe is installed.
    pause
    exit /b 1
)

echo [✓] Python is available
echo.

REM Start Backend API Server (Port 5000)
echo [1/2] Starting Backend API Server...
echo       Location: c:\Users\therh\Desktop\ToDo\backend\
echo       Running: run.py (Flask + SQLite)
echo       API URL: http://localhost:5000/api
echo.

start "TaskEarn-Backend" cmd /k "cd c:\Users\therh\Desktop\ToDo\backend && c:/python314/python.exe run.py"

REM Wait for backend to initialize
echo [⏳] Waiting for backend to start (5 seconds)...
timeout /t 5 /nobreak

REM Start Frontend HTTP Server (Port 5500)
echo.
echo [2/2] Starting Frontend Web Server...
echo       Location: c:\Users\therh\Desktop\ToDo\
echo       Running: Python HTTP Server on port 5500
echo       Frontend URL: http://localhost:5500
echo.

start "TaskEarn-Frontend" cmd /k "cd c:\Users\therh\Desktop\ToDo && c:/python314/python.exe -m http.server 5500"

timeout /t 2 /nobreak

cls
echo.
echo ====================================================================
echo            ^✅ TASKEARN PLATFORM IS NOW ONLINE ^✅
echo ====================================================================
echo.
echo 🌐 OPEN IN BROWSER:
echo    http://localhost:5500
echo.
echo 📊 API Documentation:
echo    http://localhost:5000/api/health
echo.
echo 💾 Database:
echo    c:\Users\therh\Desktop\ToDo\backend\taskearn.db
echo.
echo ⚙️  Backend Logs: TaskEarn-Backend window
echo ⚙️  Frontend Logs: TaskEarn-Frontend window
echo.
echo ====================================================================
echo.
echo 📝 QUICK START:
echo    1. Sign Up with email and password
echo    2. Post a Task (click "Post Task" button)
echo    3. Open another browser window
echo    4. Log in as different user
echo    5. See task immediately (no refresh needed!)
echo    6. Accept task and complete it
echo.
echo 🧪 To test API manually:
echo    cd c:\Users\therh\Desktop\ToDo\backend
echo    python test_api.py
echo.
echo ====================================================================
echo.
echo Press any key to continue...
pause

REM Keep this window open
:LOOP
timeout /t 60 /nobreak
goto LOOP
