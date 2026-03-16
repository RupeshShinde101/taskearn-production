# TaskEarn API Connection Fix - Complete Setup Guide

## 🚨 Current Problem
Your Netlify frontend cannot connect to the backend API. When you try to:
- Create a new account
- Save data
- Post a task

You get error: "Cannot connect to API server at https://taskearn-production-production.up.railway.app"

---

## ✅ SOLUTION (3 Options - Choose ONE)

### **OPTION 1: Use Netlify Functions Proxy (RECOMMENDED FOR PRODUCTION)**

**What it does:** Netlify Functions act as a middleman between frontend and backend
**Pros:** Works on Netlify without external dependencies, no CORS issues
**Status:** ✅ ALREADY CONFIGURED

#### Step 1: Update Netlify Environment Variables
1. Go to [Netlify Dashboard](https://app.netlify.com)
2. Select your site (taskearn or similar)
3. Go to **Settings → Environment variables** (or Deploy settings)
4. Set or update this variable:
   ```
   BACKEND_URL = https://YOUR-ACTUAL-BACKEND-URL
   ```
   Replace with your actual backend server URL

#### Step 2: Deploy Updated Code
```bash
git add .
git commit -m "Fix API connectivity with Netlify proxy functions"
git push origin main
```

#### Step 3: Test
- Frontend will now call `/.netlify/functions/api-proxy` instead of direct API
- Netlify function proxies requests to your backend
- All CORS issues are handled automatically

---

### **OPTION 2: Deploy Backend to Production (BEST LONG-TERM)**

If you don't have a backend deployed yet, use Railway or Render:

#### **A) Deploy to Railway (Free tier available)**

1. **Create GitHub Repo (if not already done)**
   ```bash
   cd c:\Users\therh\Desktop\ToDo
   git init
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/YOUR_USERNAME/taskearn.git
   git push -u origin main
   ```

2. **Deploy to Railway**
   - Go to [Railway.app](https://railway.app)
   - Click "Create Project"
   - Select "Deploy from GitHub"
   - Choose your repository
   - Select `backend` folder as root directory
   - Wait for deployment

3. **Configure Environment Variables on Railway**
   - Railway Dashboard → Project → Variables
   - Add these:
     ```
     SECRET_KEY=<generate: python -c "import secrets; print(secrets.token_urlsafe(32))">
     DATABASE_URL=<Leave empty for SQLite or add PostgreSQL URL>
     FLASK_ENV=production
     DEBUG=False
     ```

4. **Get Your Railway URL**
   - Railway Dashboard → Deployments
   - Copy your deployed URL (e.g., `https://taskearn-api-xyz.up.railway.app`)

5. **Update Frontend (THREE locations)**
   - **A) Update `index.html` (line ~24)**
     ```javascript
     window.TASKEARN_API_URL = 'https://YOUR-RAILWAY-URL/api';
     ```

   - **B) Update `netlify.toml` (line ~9)**
     ```toml
     BACKEND_URL = "https://YOUR-RAILWAY-URL"
     ```

   - **C) Update `admin.html` (line ~16)**
     ```javascript
     window.TASKEARN_API_URL = 'https://YOUR-RAILWAY-URL/api';
     ```

   - **D) Update `chat.html` (line ~15)**
     ```javascript
     window.TASKEARN_API_URL = 'https://YOUR-RAILWAY-URL/api';
     ```

6. **Redeploy Netlify**
   ```bash
   git add .
   git commit -m "Update backend URL to Railway deployment"
   git push origin main
   ```

#### **B) Deploy to Render (Alternative)**
- Go to [Render.com](https://render.com)
- Create new Web Service
- Connect your GitHub repo
- Select `backend` folder
- Set environment variables
- Deploy
- Follow same update steps as Railway above

---

### **OPTION 3: Use Local Backend (DEVELOPMENT ONLY)**

**For testing on your machine:**

#### Step 1: Start Backend Server
```bash
cd backend
python run.py
```

Expected output:
```
🚀 TaskEarn Backend API Starting on http://localhost:5000
✅ Database ready (SQLite: taskearn.db)
📚 API Docs available at: http://localhost:5000
```

#### Step 2: Visit Frontend Locally
```
http://localhost:5500
```
(Use Live Server extension or similar)

#### Step 3: Test
- Create account → should work
- Post task → should work
- All data saves to `backend/taskearn.db`

---

## 🔍 VERIFICATION TESTS

### Test If Backend Is Reachable
```bash
# Windows PowerShell
curl https://taskearn-production-production.up.railway.app/api/health

# Expected: {"success": true, "status": "healthy", ...}
```

### Test Each Endpoint
1. **Health Check**
   ```
   GET /api/health
   ```

2. **Create Account**
   ```
   POST /api/auth/register
   Body: {"email": "test@example.com", "password": "password", "name": "Test"}
   ```

3. **Get Tasks**
   ```
   GET /api/tasks
   ```

---

## ⚠️ TROUBLESHOOTING

### "DNS resolution failed" Error
- Backend URL is wrong or not deployed yet
- Check your Railway/Render dashboard
- Verify URL is correct with `https://` not `http://`

### "Connection refused" Error (localhost:5000)
- Backend server not running
- Start it with: `python backend/run.py`

### CORS Errors
- Frontend and backend on different domains
- Solution 1: ✅ Already fixed with Netlify Functions proxy
- Solution 2: Ensure backend has CORS enabled (check `backend/server.py` line 26)
- Solution 3: Use Netlify Functions to handle CORS

### No Data Saved
- Backend running
- Check browser Console (F12) for errors
- Check backend logs for SQL errors
- Verify database file exists: `backend/taskearn.db`

---

## 📋 QUICK CHECKLIST

### Option 1 (Netlify Functions) - Quickest Fix
- [ ] Update `BACKEND_URL` in Netlify Dashboard
- [ ] Deploy code to Netlify with `git push`
- [ ] Test by creating account on your Netlify site
- [ ] Verify data saves

### Option 2 (Production Deployment) - Best Solution
- [ ] Deploy backend to Railway or Render
- [ ] Get deployed backend URL
- [ ] Update all 4 files with new URL (index.html, netlify.toml, admin.html, chat.html)
- [ ] Redeploy frontend to Netlify
- [ ] Test from Netlify site

### Option 3 (Local Testing) - Development Only
- [ ] Run `python backend/run.py` in backend folder
- [ ] Visit http://localhost:5500 or use Live Server
- [ ] Test features locally
- [ ] When ready, use Option 2 for production

---

## 🎯 RECOMMENDED STEPS (RIGHT NOW)

1. **First:** Try Option 1 (Netlify Functions proxy) - Takes 2 minutes
2. **If Option 1 fails:** Go to Option 2 (Deploy to Railway) - Takes 10-15 minutes
3. **For testing locally:** Use Option 3 anytime

---

## 📞 NEED HELP?

If you're still stuck:
1. Check Railway/Render dashboard for deployment errors
2. Run verification tests above
3. Check browser Console (F12 → Console) for error messages
4. Check backend logs for database or configuration errors

---

**Remember:** Your app NEEDS a working backend to save data. Choose one option above and implement it!
