# 🎉 TaskEarn - Local Testing Guide (Working Now!)

## ✅ Status: BACKEND IS RUNNING

Your backend server is now running on **http://localhost:5000**

All frontend files are configured to use it:
- ✅ index.html
- ✅ admin.html  
- ✅ chat.html

---

## 🚀 How to Test Your App NOW

### Step 1: Open Your Frontend

**Choose ONE of these methods:**

**Option A: Using Live Server (Recommended)**
```
1. Install Live Server extension in VS Code
2. Right-click index.html
3. Select "Open with Live Server"
4. Should open at http://localhost:5500
```

**Option B: Using Python SimpleHTTPServer**
```bash
# In the project root directory:
python -m http.server 8080
# Then visit: http://localhost:8080
```

**Option C: Using Node.js**
```bash
npm install -g live-server
live-server --port=5500
```

### Step 2: Test Creating Account

1. **Open Browser DevTools** (F12)
2. Go to **Console tab**
3. You should see:
   ```
   🔗 API URL: http://localhost:5000/api
   🌍 Environment: DEVELOPMENT (Local Backend)
   ✅ Backend server is running at http://localhost:5000
   ```

4. **Create an Account:**
   - Click "Sign Up"
   - Enter email, password, name
   - Click Register
   - Look for success message

5. **Check Console for Errors:**
   - No red errors should appear
   - You should see API requests (Network tab)

### Step 3: Test Task Creation

1. **Login** with the account you just created
2. **Create a Task:**
   - Click "Post a Task"
   - Fill in details
   - Click Submit
3. **Should see success** and task appears in list
4. **Refresh page** - data should persist ✅

### Step 4: Test Wallet Features

1. **Go to Wallet page**
2. Should see your wallet balance (starts at $0)
3. Try to see if any tasks are available to earn money

---

## ✅ Expected Results

If everything works:

| Feature | Status |
|---------|--------|
| Create Account | ✅ Works |
| Login | ✅ Works |
| Create Task | ✅ Works |
| See Tasks | ✅ Works |
| Save Data | ✅ Persists |
| Refresh Page | ✅ Data Still There |

---

## ⚠️ If Something Goes Wrong

### "API Error" when creating account

**Check:**
1. Backend terminal - should show: `"POST /api/auth/register HTTP/1.1" 200`
2. Browser Console (F12) - check for error messages
3. Database file exists: `backend/taskearn.db`

**Fix:**
```bash
# Stop backend (Ctrl+C)
cd backend
python run.py
```

### "Cannot find TASKEARN_API_URL"

**Check:**
1. Open DevTools Console (F12)
2. Look for our startup messages about API URL
3. Try hard refresh: Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)

### Data not saving after refresh

**Check:**
1. Backend is still running (terminal shows requests)
2. Database file exists: `backend/taskearn.db`
3. Try logging out and back in
4. Check browser storage: Right-click → Inspect → Application → Storage

---

## 📊 Backend Server Details

Your backend is currently:
- **URL:** http://localhost:5000/api
- **Database:** SQLite (backend/taskearn.db)
- **Status:** ✅ Running and responding

**Available Endpoints:**
- POST /api/auth/register
- POST /api/auth/login
- GET /api/tasks
- POST /api/tasks
- GET /api/wallet
- ... and more

---

## 🌐 Next: Deploy to Production

Once you confirm everything works locally, follow these steps:

### Step 1: Deploy Backend to Railway
1. Go to https://railway.app
2. Create project and connect GitHub repo
3. Set backend as root directory
4. Set environment variables (SECRET_KEY, etc.)
5. Get your Railway URL: `https://my-api.railway.app`

### Step 2: Update Frontend URLs
Update these files with your Railway URL:
- **index.html** (line ~20)
- **admin.html** (line ~15)
- **chat.html** (line ~15)
- **netlify.toml** (set BACKEND_URL)

### Step 3: Deploy Frontend to Netlify
```bash
git add .
git commit -m "Update backend URL for production"
git push origin main
```

---

## 🎯 Commands Quick Reference

### Start Backend
```bash
cd backend && python run.py
```

### Start Frontend (Live Server)
```bash
live-server --port=5500
# Or use VS Code Live Server extension
```

### View Database
```bash
# SQLite has created: backend/taskearn.db
# To view tables:
sqlite3 backend/taskearn.db ".tables"
```

### Stop Backend
```
Press Ctrl+C in the backend terminal
```

---

## ✨ You're All Set!

Your TaskEarn app is now fully functional for local development!

**Start testing at:** http://localhost:5500

---

**Issues?** Check the browser console (F12) for error messages and let me know what you see!
