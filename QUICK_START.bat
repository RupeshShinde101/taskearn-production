@echo off
REM TaskEarn - Quick Start Script
REM Starts both backend and frontend servers

cls
echo.
echo ════════════════════════════════════════════════════════════
echo  TaskEarn - Quick Start
echo ════════════════════════════════════════════════════════════
echo.

REM Kill any existing Python processes
taskkill /F /IM python.exe >nul 2>&1

echo Starting backend server (port 5000)...
start "TaskEarn Backend" cmd /k "cd /d %~dp0backend && python server.py"
timeout /t 3 >nul

echo Starting frontend server (port 5500)...
start "TaskEarn Frontend" cmd /k "cd /d %~dp0 && python -m http.server 5500"
timeout /t 2 >nul

echo.
echo ════════════════════════════════════════════════════════════
echo  ✅ Servers Started!
echo ════════════════════════════════════════════════════════════
echo.
echo 📍 Frontend: http://localhost:5500/index.html
echo 📍 Backend:  http://localhost:5000/api
echo.
echo Opening app in browser...
timeout /t 2 >nul

REM Open in default browser
start http://localhost:5500/index.html

echo.
echo Servers will continue running in the background.
echo You can close this window when done.
echo.
pause
