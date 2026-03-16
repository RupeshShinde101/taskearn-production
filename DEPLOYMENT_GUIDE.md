# 🚀 TaskEarn Production Deployment Guide

## Complete Instructions: Backend to Railway + Frontend to Netlify

---

## 📋 Prerequisites

Before you start, make sure you have:

- ✅ GitHub account (free at https://github.com)
- ✅ Railway account (free at https://railway.app)
- ✅ Netlify account (free at https://netlify.com)
- ✅ Git installed on your computer
- ✅ Local backend tested and working

---

## 🚀 Deployment Steps

### Phase 1: Set Up GitHub Repository

#### Step 1.1: Create GitHub Repository

1. Go to https://github.com/new
2. **Repository name:** `taskearn`
3. **Description:** "TaskEarn - Complete your tasks and earn money"
4. **Private or Public?** Choose Public (required for free Netlify)
5. Click **"Create repository"**

#### Step 1.2: Push Your Code to GitHub

```bash
# From your project root directory (c:\Users\therh\Desktop\ToDo)
cd c:\Users\therh\Desktop\ToDo

# Initialize git (if not done)
git init

# Add all files
git add .

# First commit
git commit -m "Initial commit: TaskEarn production"

# Add GitHub remote (replace YOUR_USERNAME and REPOSITORY_NAME)
git remote add origin https://github.com/YOUR_USERNAME/taskearn.git

# Push to GitHub
git branch -M main
git push -u origin main
```

✅ Your code is now on GitHub!

---

### Phase 2: Deploy Backend to Railway

#### Step 2.1: Create Railway Project

1. Go to https://railway.app
2. Click **"Create Project"**
3. Select **"Deploy from GitHub"**
4. Click **"Connect GitHub"** and authorize Railway
5. Select your **"taskearn"** repository
6. Click **"Deploy now"**

Railway will start building your app. Wait for it to complete (1-2 minutes).

#### Step 2.2: Configure Root Directory

1. In Railway dashboard, click your project
2. Go to **Settings** → **Root Directory**
3. Enter: `backend`
4. Click **"Save"**

Railway will redeploy with the backend folder as root.

#### Step 2.3: Set Environment Variables

1. In Railway project, go to **Variables**
2. Click **"+ Add"** to create each variable:

**Variable 1: SECRET_KEY**
```
Name: SECRET_KEY
Value: (generate using command below)
```

To generate SECRET_KEY, run in PowerShell:
```powershell
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

Copy the output and paste it as the value.

**Variable 2: FLASK_ENV**
```
Name: FLASK_ENV
Value: production
```

**Variable 3: DEBUG**
```
Name: DEBUG
Value: False
```

3. Click **"Save"** after each variable

#### Step 2.4: Get Your Railway Backend URL

1. In Railway project, go to **Deployments**
2. Look for the deployed version with status "✓"
3. Click on it
4. Find the domain, it should look like:
   ```
   https://taskearn-api-xyz.up.railway.app
   ```
5. **Copy this URL** - you'll need it for the next step

#### Step 2.5: Test Your Backend

Open in browser:
```
https://your-railway-url/api/health
```

You should see:
```json
{
  "success": true,
  "status": "healthy",
  "database": "SQLite",
  "environment": "production"
}
```

✅ Backend is deployed!

---

### Phase 3: Update Frontend Configuration

#### Step 3.1: Update Frontend Files

Replace `localhost:5000` with your Railway URL in:

**File: index.html (line ~20)**
```javascript
// CHANGE FROM:
window.TASKEARN_API_URL = 'http://localhost:5000/api';

// TO:
window.TASKEARN_API_URL = 'https://your-railway-url/api';
```

**File: admin.html (line ~15)**
```javascript
// Same change
window.TASKEARN_API_URL = 'https://your-railway-url/api';
```

**File: chat.html (line ~15)**
```javascript
// Same change
window.TASKEARN_API_URL = 'https://your-railway-url/api';
```

**File: netlify.toml (line ~9)**
```toml
# CHANGE FROM:
BACKEND_URL = "https://taskearn-production-production.up.railway.app"

# TO:
[context.production.environment]
  BACKEND_URL = "https://your-railway-url"
```

#### Step 3.2: Push Updated Code to GitHub

```bash
git add .
git commit -m "Update backend URL to Railway deployment"
git push origin main
```

✅ Frontend is ready for deployment!

---

### Phase 4: Deploy Frontend to Netlify

#### Step 4.1: Connect Netlify to GitHub

1. Go to https://app.netlify.com
2. Click **"Add new site"** → **"Import an existing project"**
3. Select **"GitHub"**
4. **Authorize** Netlify with GitHub (one-time)
5. Select your **"taskearn"** repository

#### Step 4.2: Configure Deployment Settings

1. **Build settings:**
   - **Build command:** (leave empty - our app is static HTML)
   - **Publish directory:** `.` (dot, meaning current folder)

2. Click **"Deploy site"**

Netlify will now build and deploy your site!

#### Step 4.3: Get Your Netlify URL

1. Wait for deployment to complete (usually 1-2 minutes)
2. You'll see a screen with your site URL:
   ```
   https://your-site-name.netlify.app
   ```
3. Click the link to visit your live app!

✅ Frontend is deployed!

---

## ✅ Testing Your Production Deployment

### Test 1: Visit Your App

1. Go to your Netlify URL: `https://your-site-name.netlify.app`
2. Open **Developer Console** (Press F12)
3. Go to **Console** tab
4. You should see:
   ```
   🔗 API URL: https://your-railway-url/api
   🌍 Environment: DEVELOPMENT (Local Backend)
   ```

### Test 2: Create Account

1. Click **"Sign Up"**
2. Fill in form:
   - Email: test@example.com
   - Password: TestPassword123
   - Name: Test User
3. Click **"Register"**
4. Should see success message ✅
5. Login with same credentials

### Test 3: Create Task

1. Logged in, click **"Post a Task"**
2. Fill in task details:
   - Title: "Test Task"
   - Description: "Testing deployment"
   - Amount: 100
3. Click **"Post Task"**
4. Should see success ✅
5. Refresh page - task should still be there!

### Test 4: Monitor Backend

1. Go to https://railway.app/dashboard
2. Click your project
3. Go to **Logs**
4. You should see your API requests logged:
   ```
   POST /api/auth/register HTTP/1.1 - 201
   POST /api/tasks HTTP/1.1 - 201
   ```

✅ Everything is working!

---

## 🆘 Troubleshooting

### Problem: "Cannot connect to API server"

**Check 1: Backend URL is correct**
- Verify you updated index.html with your Railway URL
- Make sure it includes `/api` at the end
- Test URL in browser: https://your-railway-url/api/health

**Check 2: Railway backend is running**
- Go to https://railway.app/dashboard
- Check your project status
- Look at the Logs tab for errors

**Check 3: SECRET_KEY is set**
- Go to Railway project → Variables
- Verify SECRET_KEY is set
- If empty, redeploy after setting it

### Problem: "Page not found" on Netlify

**Check:**
- index.html exists in your repository
- You set Publish directory to `.` (dot)
- Netlify build completed successfully

### Problem: Data not saving

**Check 1: Database exists**
- Railway backend should create SQLite database automatically
- Check Railway logs for database errors

**Check 2: Check browser console**
- Open F12 → Console tab
- Look for red error messages
- Common: Missing API fields

---

## 📊 Quick Reference

### Important URLs

| Component | URL |
|-----------|-----|
| GitHub | https://github.com/YOUR_USERNAME/taskearn |
| Railway Dashboard | https://railway.app/dashboard |
| Railway Backend | https://taskearn-api-xyz.up.railway.app |
| Netlify Dashboard | https://app.netlify.com |
| Netlify Frontend | https://your-site.netlify.app |

### Useful Commands

```bash
# Push new changes to production:
git add .
git commit -m "Your message"
git push origin main

# Check git status:
git status

# View recent commits:
git log --oneline -5
```

---

## 🎯 Next Steps

### After Deployment is Successful

1. **Share your app!**
   - Send your Netlify URL to friends
   - Get feedback and test users

2. **Monitor your app**
   - Check Railway logs regularly
   - Monitor Netlify analytics
   - Fix any bugs that users report

3. **Add custom domain (Optional)**
   - Netlify: Settings → Domain management → Add custom domain
   - Railway: Configure in project settings

4. **Set up continuous deployment**
   - Both Railway and Netlify auto-deploy on `git push`
   - Just commit and push for automatic updates!

---

## 📚 Additional Resources

- Railway Docs: https://docs.railway.app
- Netlify Docs: https://docs.netlify.com
- Flask Deployment: https://flask.palletsprojects.com/en/latest/deploying/

---

## ✨ Congratulations! 🎉

Your TaskEarn app is now live on the internet!

**Frontend:** https://your-site.netlify.app  
**Backend:** https://your-railway-url/api

Share it with the world! 🌍
