#!/bin/sh
# TaskEarn Backend Startup Script
# This script properly sets up the environment and starts the Flask API

cd /app/backend 2>/dev/null || cd /app || cd ./backend

# Export PORT if not already set
export PORT=${PORT:-5000}

# Start gunicorn with Flask app
exec gunicorn -w 4 -b 0.0.0.0:$PORT --timeout 120 --access-logfile - --error-logfile - server:app
