# TaskEarn - Setup Guide for Task Server Sync

## Overview
Your TaskEarn website now has a Python backend server that allows tasks to be saved and visible to all users. Here's how to set it up and use it:

---

## Step 1: Install Python (if not already installed)

1. Download Python from https://www.python.org/downloads/
2. During installation, **CHECK** the box: "Add Python to PATH"
3. Click "Install Now"
4. Verify installation by opening Command Prompt and typing:
   ```
   python --version
   ```
   You should see Python 3.x.x

---

## Step 2: Start the Backend Server

**Windows:**
1. Go to `C:\Users\therh\Desktop\ToDo`
2. Double-click `START_SERVER.bat`
3. It will install dependencies and start the server
4. You should see: `Running on http://localhost:5000`

**Mac/Linux:**
```bash
cd ~/Desktop/ToDo/backend
pip install -r requirements.txt
python server.py
```

The server will run on `http://localhost:5000`

---

## Step 3: Open the Website

1. Open a web browser
2. Go to `file:///C:/Users/therh/Desktop/ToDo/index.html`
3. You'll see the TaskEarn website

---

## Step 4: Test Task Sharing

### Register a New User:
1. Click "Sign Up"
2. Fill in your details:
   - Name: Your name
   - Email: test@example.com
   - Password: test123 (must have letters + numbers)
   - Date of Birth: Any date 16+ years old
3. Click "Create Account"

### Post a Task:
1. Click "Post a Task"
2. Fill in task details:
   - Title: "Buy groceries"
   - Category: "Shopping & Errands"
   - Description: "Need groceries from nearby store"
   - Location: "Your address"
   - Budget: ₹100+
3. Click "Post Task"
4. You should see: "✅ Task posted successfully!"

### View All Tasks:
1. Click "Find Tasks"
2. You'll see a map and tasks list
3. All posted tasks are visible here to all users

### Register Another User (to test visibility):
1. Open a new browser tab/window
2. Go to `file:///C:/Users/therh/Desktop/ToDo/index.html`
3. Sign up with a different email: test2@example.com
4. Click "Find Tasks"
5. You should see the task posted by the first user!

---

## API Endpoints Available

The backend provides these endpoints:

### Authentication:
- `POST /api/auth/register` - Create new account
- `POST /api/auth/login` - Login with email/password
- `GET /api/auth/me` - Get current user

### Tasks:
- `GET /api/tasks` - Get all active tasks
- `POST /api/tasks` - Create new task
- `POST /api/tasks/{id}/accept` - Accept a task
- `POST /api/tasks/{id}/complete` - Complete a task

### Wallet:
- `GET /api/wallet` - Get wallet balance
- `POST /api/wallet/pay` - Pay for a task

---

## Database

Tasks are stored in SQLite database (`tasks.db`) in the backend folder.

To reset and start fresh:
1. Stop the server (Ctrl+C)
2. Delete `backend/tasks.db`
3. Start the server again (it will create a new database)

---

## Troubleshooting

### "Python not found"
- Make sure Python is installed and added to PATH
- Restart your computer after installing Python

### "pip: command not found"
- Windows: Try `python -m pip install -r requirements.txt`
- Make sure Python is in PATH

### "Port 5000 already in use"
- Another application is using port 5000
- Stop it or change the port in `backend/config.py`

### "Failed to connect to server"
- Make sure backend server is running (check terminal)
- Make sure you're on the same network (localhost:5000)

### Tasks not syncing
- Check browser console (F12 > Console tab) for errors
- Verify API token in localStorage (F12 > Application > Local Storage)
- Restart both server and browser

---

## Important Notes

1. **Always keep server running** when using the website
2. **Tasks expire after 12 hours** if not accepted
3. **Use HTTPS** when deploying to production
4. **Database is SQLite** - suitable for development/testing
5. **For production**, configure PostgreSQL in `backend/config.py`

---

## Next Steps

Once tasks are syncing:

1. **Add Payment Integration**: Razorpay is configured in backend
2. **Add Live Tracking**: Use Mapbox for real-time tracking
3. **Deploy to Production**: Use Railway, Render, or Heroku
4. **Enable HTTPS**: Use Let's Encrypt or Cloudflare

---

**Need Help?**
Check the backend logs in the terminal where you started `START_SERVER.bat`
All API requests are logged with details.

