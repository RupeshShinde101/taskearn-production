# TaskEarn - Netlify Deployment Guide

## ✨ Complete Frontend Deployment Setup

This guide covers deploying TaskEarn to Netlify. Your backend is handled separately on Railway.

---

## 🚀 Quick Start (5 Steps)

### Step 1: Get Your Railway Backend URL
1. Go to https://railway.app/dashboard
2. Select **TaskEarn** project
3. Click the service/domain
4. Copy the public URL (e.g., `https://taskearn-xyz.up.railway.app`)
5. **Save this URL** - you'll need it in Step 3

### Step 2: Prepare Your Repository
Run this PowerShell command:
```powershell
cd C:\Users\therh\Desktop\ToDo
.\deploy-netlify.ps1
```

This will:
- Stage all your files
- Create a commit
- Ask for a commit message
- Show you the next steps

### Step 3: Push to GitHub
If your repository doesn't exist yet:
```bash
git init
git remote add origin https://github.com/YOUR_USERNAME/taskearn.git
```

Push your code:
```bash
git push -u origin main
```

### Step 4: Connect to Netlify
1. Go to https://app.netlify.com/
2. **Sign up / Login** with GitHub
3. Click **"New site from Git"**
4. Choose your GitHub repository
5. **Build settings** (use these defaults):
   - Build command: *(leave empty)*
   - Publish directory: `.`
6. Click **"Deploy site"**

### Step 5: Configure Environment Variables
After initial deploy:
1. Go to **Site Settings** → **Build & Deploy** → **Environment**
2. Click **"Edit variables"**
3. Add this variable:
   ```
   RAILWAY_API_URL = https://your-railway-url
   ```
   (Replace with your actual Railway URL from Step 1)
4. Trigger a new deploy: **Deploys** → **Trigger deploy** → **Deploy site**

---

## 📋 What Gets Deployed to Netlify

**Frontend (Static Files):**
- ✅ index.html - Main app page
- ✅ admin.html - Admin dashboard
- ✅ chat.html - Messaging interface
- ✅ wallet.html - Wallet management
- ✅ styles.css - Application styling
- ✅ app.js - Main application logic
- ✅ api-client.js - API communication
- ✅ razorpay.js - Payment processing
- ✅ tracking.js - Location tracking
- ✅ All other static assets

**Backend (Runs on Railway):**
- ✅ Flask API server
- ✅ PostgreSQL database
- ✅ All API endpoints

---

## 🔗 How API Communication Works

1. **Frontend** (Netlify) makes requests to Railway backend
2. **Environment Variable** tells frontend where backend is located:
   ```
   RAILWAY_API_URL = https://your-railway-domain/api
   ```
3. **Netlify has Functions** to help proxy/manage API calls if needed

---

## 🛠️ File Structure

```
TaskEarn/
├── netlify.toml                 ← Netlify configuration
├── netlify/
│   └── functions/
│       ├── config.js            ← Get API configuration
│       └── api-proxy.js         ← Optional API proxy
├── index.html                   ← Main app
├── admin.html
├── app.js                       ← Uses RAILWAY_API_URL
├── .env                         ← Local development only
├── backend/                     ← NOT deployed to Netlify
│   ├── server.py
│   ├── requirements.txt
│   └── ...
└── deploy-netlify.ps1          ← Deployment helper script
```

---

## 🔍 Troubleshooting

### API calls returning 404
- Check `RAILWAY_API_URL` environment variable is set correctly
- Verify Railway backend is deployed and running
- Check browser console for the actual URL being called

### CORS errors
- netlify.toml has proper CORS headers configured
- Railway backend must allow Netlify domain
- Check backend logs for more details

### Netlify deploy failing
- Ensure no `node_modules` or `.venv` folders are included
- Check `.gitignore` is properly configured
- Review Netlify deploy logs for specific errors

### Pages showing 404
- Single Page App (SPA) routing is configured
- netlify.toml redirects all routes to `index.html`
- Clear browser cache if needed

---

## 📊 Deployment Checklist

- [ ] Railway backend URL obtained and saved
- [ ] Local code pushed to GitHub
- [ ] Netlify site created from GitHub repo
- [ ] `RAILWAY_API_URL` environment variable set in Netlify
- [ ] New deploy triggered after setting variables
- [ ] Frontend accessible at `https://your-site.netlify.app`
- [ ] API calls working (check browser console)
- [ ] Test login with valid credentials

---

## 🎯 Next Steps

1. **Test your deployment:**
   - Open your Netlify URL
   - Try logging in
   - Create a task
   - Check browser console for any errors

2. **Monitor your apps:**
   - **Frontend**: Netlify Dashboard
   - **Backend**: Railway Dashboard
   - Both should show green/operational status

3. **Set up custom domain** (optional):
   - In Netlify: Site settings → Domain management
   - Use your own domain instead of *.netlify.app

---

## 📞 Need Help?

- **Netlify Docs**: https://docs.netlify.com/
- **Railway Docs**: https://docs.railway.app/
- **Check logs**: 
  - Netlify: Deploys → Latest deploy → Deploy log
  - Railway: Select service → Logs → Deployment logs
