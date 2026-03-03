# 🔧 TaskEarn Network Error Fix Guide

## ❌ Problem
"Network error - failed to fetch" during login/signup

## ✅ Solution

### Step 1: Verify Backend is Running
The most common cause of "network error - failed to fetch" is that **the backend server is not running**.

**Check if backend is running:**
```powershell
netstat -ano | findstr :5000
```

If nothing appears, the server is NOT running.

**Start the backend:**
```powershell
cd c:\Users\therh\Desktop\ToDo\backend
python server.py
```

You should see:
```
==================================================
🚀 TaskEarn Backend Server
==================================================
📍 Running on: http://0.0.0.0:5000
💾 Database: SQLite (or PostgreSQL)
==================================================
```

### Step 2: Test API Endpoints

Open this file in your browser:
```
file:///c:/Users/therh/Desktop/ToDo/api-diagnostic.html
```

Click **"Run All Tests"** and check:
- ✅ Health Check
- ✅ Register Endpoint  
- ✅ Login Endpoint
- ✅ CORS Configuration

All should show green checkmarks.

### Step 3: Check Browser Console

While trying to signup/login:
1. Press **F12** to open Developer Tools
2. Go to **Console** tab
3. Look for error messages
4. Take a screenshot of any red errors

Common errors:
- `Failed to fetch` = Backend not running
- `CORS policy` = Backend CORS not configured
- `TypeError: Cannot read property` = Data format issue
- `401 Unauthorized` = Invalid credentials

### Step 4: Verify API URL

Check that your index.html has the correct API URL:
```javascript
// Should show when page loads:
🔗 API URL: http://localhost:5000/api
🌍 Environment: DEVELOPMENT
```

If it shows a different URL, open index.html and fix line 25:
```javascript
window.TASKEARN_API_URL = 'http://localhost:5000/api';
```

### Step 5: Check Backend Logs

While the backend is running, look at the terminal output for errors:
- Connection refused = Port 5000 in use
- Authentication failed = Database issue
- Internal Server Error (500) = Code error

### Step 6: Clear Browser Cache

1. Press **Ctrl + Shift + Delete**
2. Select "All time"
3. Check: Cookies, Cached images
4. Click "Clear data"
5. Reload the page

### Step 7: Test with Diagnostic Tool

Create a simple test:
```powershell
cd c:\Users\therh\Desktop\ToDo
python test_login_api.py
```

All tests should pass:
- ✅ 1️⃣ Health Check = 200
- ✅ 2️⃣ Register = 201  
- ✅ 3️⃣ Login = 401 (ok - invalid credentials)
- ✅ 4️⃣ CORS = Enabled

---

## 🔍 Detailed Diagnostic Checklist

### Is Backend Running?
```powershell
# Check if port 5000 is in use
netstat -ano | findstr :5000

# Expected output:
# TCP    127.0.0.1:5000         0.0.0.0:0        LISTENING       12345

# If NO output = Backend not running
```

### Is Database Connected?
Backend logs should show:
```
💾 Database: PostgreSQL  (or SQLite)
```

If it says SQLite but you want PostgreSQL:
- Add DATABASE_URL to .env file
- Set it to your Railway PostgreSQL URL
- Restart backend

### Is API Responding?
```powershell
# Quick test
Invoke-WebRequest -Uri http://localhost:5000/api/health
```

Expected: Returns JSON with "healthy" status

### Is CORS Working?
Browser console should NOT show:
```
Access to XMLHttpRequest at 'http://localhost:5000/api/auth/register'
from origin 'http://localhost:5500' has been blocked by CORS policy
```

### Port Already in Use?
If you see error about port 5000:
```powershell
# Kill process using port 5000
netstat -ano | findstr :5000
taskkill /PID <PID> /F

# Then restart backend
python server.py
```

---

## 📋 Complete Troubleshooting Steps

1. **Stop everything**
   ```powershell
   # Kill all Python processes
   taskkill /F /IM python.exe
   ```

2. **Clear cache**
   - Press Ctrl + Shift + Delete
   - Clear all cache and cookies

3. **Start fresh**
   ```powershell
   cd c:\Users\therh\Desktop\ToDo\backend
   python server.py
   ```
   
   Wait for:
   ```
   Running on: http://0.0.0.0:5000
   ```

4. **Test health**
   ```powershell
   # In another terminal
   Invoke-WebRequest -Uri http://localhost:5000/api/health
   ```

5. **Open app**
   - Open index.html in browser
   - Check console (F12)
   - Try signup with test credentials

6. **Check diagnostic**
   - Open api-diagnostic.html
   - Click "Run All Tests"
   - All should be green ✅

---

## 🆘 Still Getting Error?

If you've done all above steps and still getting "network error":

1. **Copy three pieces of information:**

**A) Browser Console Error**
   - Press F12
   - Go to Console tab
   - Copy the red error message

**B) Backend Terminal Output**
   - Copy the last few lines from backend terminal

**C) Diagnostic Test Results**
   - Open api-diagnostic.html
   - Click "Run All Tests"
   - Copy the results

2. **Create a bug report with:**
   - What error you see
   - What the backend logs show
   - What the diagnostic test shows

---

## 🚀 Quick Start (No Errors)

If everything is working:

**Terminal 1 - Start Backend:**
```powershell
cd c:\Users\therh\Desktop\ToDo\backend
python server.py
```

**Terminal 2 - (Optional) Start Frontend Server:**
```powershell
cd c:\Users\therh\Desktop\ToDo
python -m http.server 5500
```

**Browser - Open App:**
```
http://localhost:5500/index.html
```

Try signup/login - should work! ✅

---

## 📞 Need More Help?

Check these files:
- **Backend issues:** `backend/server.py`
- **Frontend issues:** `app.js` and `api-client.js`  
- **Config issues:** `.env` file
- **Database issues:** `backend/database.py`

Each file has comments explaining the code.

Good luck! 🍀
