# Production Deployment Guide for TaskEarn

## 🚀 Deploy to Railway (Recommended)

This guide will help you deploy the TaskEarn platform to Railway production in 15 minutes.

---

## 📋 Prerequisites

- GitHub account (free at https://github.com)
- Railway account (free at https://railway.app)
- Netlify account for frontend (free at https://netlify.com)
- Your TaskEarn repository

---

## 🎯 Step 1: Prepare GitHub Repository

### 1.1 Initialize Git (if not already done)

```powershell
cd c:\Users\therh\Desktop\ToDo
git init
git config user.email "your-email@example.com"
git config user.name "Your Name"
```

### 1.2 Create .gitignore

File `c:\Users\therh\Desktop\ToDo\.gitignore`:
```
.env
__pycache__/
*.pyc
*.db
*.sqlite
.vscode/
.idea/
venv/
node_modules/
.DS_Store
```

### 1.3 Add and Commit

```powershell
git add .
git commit -m "Initial commit: TaskEarn with Flask backend and SQLite database"
```

### 1.4 Create GitHub Repository

1. Go to https://github.com/new
2. Create repository: `taskearn-production`
3. Don't initialize README (we have commits)
4. Click "Create repository"

### 1.5 Push to GitHub

```powershell
git remote add origin https://github.com/YOUR_USERNAME/taskearn-production.git
git branch -M main
git push -u origin main
```

---

## 🚂 Step 2: Deploy Backend to Railway

### 2.1 Create Railway Account

- Go to https://railway.app
- Sign in with GitHub
- Click "Deploy Now"

### 2.2 Select Your Repository

- Select `taskearn-production`
- Railway auto-detects Flask app
- Click "Deploy"

### 2.3 Add PostgreSQL Database

In Railway dashboard:
1. Click "New" → "Database" → "PostgreSQL"
2. Wait for creation (1-2 minutes)
3. Railway auto-links `DATABASE_URL` to your app

### 2.4 Configure Environment Variables

In Railway dashboard for your app:

**Click "+ New Variable" and add:**

```
ENVIRONMENT          production
FLASK_ENV            production
DEBUG                False
SECRET_KEY           (generate: python -c "import secrets; print(secrets.token_urlsafe(32))")
JWT_EXPIRATION_HOURS 24
RAZORPAY_KEY_ID      rzp_live_YOUR_LIVE_KEY
RAZORPAY_KEY_SECRET  YOUR_LIVE_SECRET
CORS_ORIGINS         https://taskearn.netlify.app,https://taskearn-api.up.railway.app
APP_NAME             TaskEarn
```

### 2.5 Deploy

- Railway deploys automatically from GitHub
- Watch the logs in dashboard
- Wait for "✓ Ready" status

### 2.6 Get Your API URL

In Railway dashboard:
- Click "Environment" tab
- Find URL: `https://taskearn-api.up.railway.app`
- Copy this URL (you'll need it for frontend)

---

## 💻 Step 3: Deploy Frontend to Netlify

### 3.1 Create Netlify Account

- Go to https://netlify.com
- Sign in with GitHub

### 3.2 Deploy Frontend

Option A: **Drag & Drop (Easiest)**
1. Zip your frontend files (all HTML, CSS, JS, images)
2. Go to https://app.netlify.com/drop
3. Drag and drop the zip
4. Wait for deployment
5. Your site lives at: `https://task-earn-XXXXX.netlify.app`

Option B: **Connect GitHub**
1. Click "Add new site" → "Import an existing project"
2. Select your GitHub repo
3. Set Build command: `(leave empty)`
4. Set Publish directory: `/` (or root)
5. Click "Deploy site"

### 3.3 Update Frontend API URL

Edit `c:\Users\therh\Desktop\ToDo\index.html`:

Find this code:
```javascript
(function() {
    const hostname = window.location.hostname;
    
    // Production: Use fixed backend URL
    if (hostname !== 'localhost' && hostname !== '127.0.0.1') {
        window.TASKEARN_API_URL = 'https://your-railway-url.up.railway.app/api';    } else {
        // Development: Use local backend
        window.TASKEARN_API_URL = 'http://localhost:5000/api';
    }
})();
```

Replace with:
```javascript
(function() {
    const hostname = window.location.hostname;
    
    // Production: Use Railway backend
    if (hostname !== 'localhost' && hostname !== '127.0.0.1') {
        window.TASKEARN_API_URL = 'https://taskearn-api.up.railway.app/api';
    } else {
        // Development: Use local backend
        window.TASKEARN_API_URL = 'http://localhost:5000/api';
    }
})();
```

### 3.4 Push Changes

```powershell
git add .
git commit -m "Update API URL to Railway production"
git push origin main
```

If using GitHub deployment on Netlify, automatic redeploy happens.
If using drag & drop, repeat deployment step.

---

## ✅ Verification

### Test Backend API

```powershell
curl https://taskearn-api.up.railway.app/api/health
```

Expected response:
```json
{"status": "ok"}
```

### Test Frontend

1. Go to `https://task-earn-XXXXX.netlify.app`
2. Sign up with test account
3. Post a task
4. ✅ Task should appear in database

### Monitor Railway

- Railway Dashboard → Your App
- Check logs for errors
- All requests logged

---

## 🔐 Security Setup

### 1. Update Razorpay Keys

- Go to https://dashboard.razorpay.com/app/keys
- Get **Live** keys (not test keys)
- Update in Railway environment variables
- DO NOT commit keys to GitHub

### 2. Set Custom Domain

In Railway dashboard:
1. Click "Environment" tab
2. Under "Domain":
   - Click "New Domain"
   - Enter: `taskearn-api.yourdomain.com`
   - Point DNS (CNAME) to Railway

### 3. Enable HTTPS

- Railway: Automatic ✅
- Netlify: Automatic ✅
- No additional setup needed

---

## 🎯 Post-Deployment Checks

- [ ] Backend API responds to requests
- [ ] Frontend loads without errors
- [ ] Can sign up and create account
- [ ] Can post task
- [ ] Task persists in database
- [ ] Task visible from another account
- [ ] Razorpay integration works
- [ ] Emails send (if configured)
- [ ] Logs show no errors

---

## 🔧 Troubleshooting

### "Cannot connect to API"
- Check Railway API URL in frontend code
- Verify `CORS_ORIGINS` includes your domain
- Check Railway logs for errors

### "Database errors"
- Railway PostgreSQL auto-initializes tables
- If schema missing: Re-deploy backend
- Check database connection string

### "Tasks not visible"
- Clear browser cache (Ctrl+Shift+Delete)
- Try incognito mode
- Check browser console (F12)

---

## 📊 Monitoring & Logs

### View Real-time Logs

Railway Dashboard → Your App → "Monitoring"

### Check for Errors

```bash
# SSH into Railway (advanced)
railway run bash
# Check server logs
tail -f /var/log/app.log
```

---

## 💰 Costs

| Service | Cost | Notes |
|---------|------|-------|
| Railway Backend | $5-10/mo | Pay as you go |
| Railway DB | $5/mo | PostgreSQL included |
| Netlify Frontend | Free | Unlimited sites |
| Domain (optional) | $10/year | From Namecheap |
| **Total** | **$20-25/mo** | With custom domain |

---

## 🎉 You're Live!

Your TaskEarn platform is now:
- ✅ Running on https://taskearn-api.up.railway.app
- ✅ Serving users at https://task-earn-XXXXX.netlify.app
- ✅ Storing data in Railway PostgreSQL
- ✅ Processing payments via Razorpay

---

## Next Steps

1. Monitor logs daily
2. Set up backups (Railway does this)
3. Configure email service
4. Add custom domain
5. Promote to users

---

## Support

- Railway Docs: https://docs.railway.app
- Netlify Docs: https://docs.netlify.com
- Flask Docs: https://flask.palletsprojects.com
- Email us: support@taskearn.com
