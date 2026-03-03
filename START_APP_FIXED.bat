@echo off
REM TaskEarn - Automated Startup Script
REM Starts backend and frontend servers

echo.
echo ════════════════════════════════════════════════════════════
echo  TaskEarn - Complete Startup
echo ════════════════════════════════════════════════════════════
echo.

REM Kill any existing Python/Node processes
echo Cleaning up old processes...
taskkill /F /IM python.exe >nul 2>&1
timeout /t 1 >nul

REM Check if backend is already running
echo.
echo Checking if backend is already running on port 5000...
netstat -ano | findstr :5000 >nul 2>&1
if %errorlevel% equ 0 (
    echo ✓ Backend already running on port 5000
) else (
    echo Starting backend server...
    start "TaskEarn Backend" cmd /k "cd backend && python server.py"
    timeout /t 3 >nul
    echo.
    echo ✓ Backend started on http://localhost:5000
)

REM Test backend
echo.
echo Testing backend connection...
powershell -Command "try { $r = Invoke-WebRequest -Uri http://localhost:5000/api/health -ErrorAction SilentlyContinue; if ($r.StatusCode -eq 200) { Write-Host '✓ Backend responding' } else { Write-Host 'X Backend not responding' } } catch { Write-Host 'X Cannot connect to backend' }"

REM Open app in browser
echo.
echo ════════════════════════════════════════════════════════════
echo  Starting Application
echo ════════════════════════════════════════════════════════════
echo.
echo Opening TaskEarn in your browser...
echo.
echo 🔗 Frontend: http://localhost:5500/index.html
echo 🔗 Backend:  http://localhost:5000/api
echo 🔗 Diagnostic: file:///c:/Users/therh/Desktop/ToDo/api-diagnostic.html
echo.

REM Open in default browser
start http://localhost:5500/index.html

echo.
echo ════════════════════════════════════════════════════════════
echo  ✓ TaskEarn is ready!
echo ════════════════════════════════════════════════════════════
echo.
echo Try these next:
echo  1. Sign up with test account
echo  2. Login with your credentials  
echo  3. Create a task
echo.
echo If you see errors:
echo  1. Check browser console (F12)
echo  2. Open api-diagnostic.html to test
echo  3. Check FIX_NETWORK_ERROR.md for help
echo.
pause
