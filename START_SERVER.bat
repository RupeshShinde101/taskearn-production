@echo off
echo ===========================================
echo TaskEarn Backend Server Startup
echo ===========================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8+ from https://www.python.org
    echo Make sure to check "Add Python to PATH" during installation
    pause
    exit /b 1
)

echo Python version:
python --version
echo.

REM Navigate to backend directory
cd /d "%~dp0backend"
if errorlevel 1 (
    echo ERROR: Could not navigate to backend directory
    pause
    exit /b 1
)

echo Current directory: %cd%
echo.

REM Check if requirements.txt exists
if not exist requirements.txt (
    echo ERROR: requirements.txt not found in backend directory
    pause
    exit /b 1
)

echo Installing Python dependencies...
pip install --no-cache-dir -r requirements.txt
if errorlevel 1 (
    echo Retrying with no binary packages...
    pip install --no-binary :all: -r requirements.txt
)
if errorlevel 1 (
    echo ERROR: Failed to install dependencies
    pause
    exit /b 1
)

echo.
echo Starting TaskEarn Backend Server...
echo Server will run at http://localhost:5000
echo API endpoint: http://localhost:5000/api
echo.
echo Press Ctrl+C to stop the server
echo.

REM Run the Flask server
python server.py

if errorlevel 1 (
    echo.
    echo ERROR: Server failed to start
    echo Please check the error messages above
    pause
    exit /b 1
)

pause
