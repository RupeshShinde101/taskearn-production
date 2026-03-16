# 🚀 DEPLOYMENT CHECKLIST - Follow These Steps

## ✅ PRE-DEPLOYMENT CHECKLIST

Before you start, confirm:

- [ ] GitHub account created (https://github.com)
- [ ] Railway account created (https://railway.app)
- [ ] Netlify account created (https://netlify.com)
- [ ] Backend tested locally and working
- [ ] You have your Railway backend URL ready (or will get it during process)

---

## 🎯 DEPLOYMENT PROCESS (Choose One)

### OPTION A: Automated PowerShell Script (EASIEST - Windows)

Simply run this command in PowerShell:

```powershell
# Navigate to your project
cd c:\Users\therh\Desktop\ToDo

# Run the deployment script
.\Deploy-to-Production.ps1
```

The script will guide you through:
1. Creating GitHub repo
2. Deploying backend to Railway
3. Getting Railway URL
4. Updating frontend with Railway URL
5. Deploying frontend to Netlify

**Just follow the prompts!** ✅

### OPTION B: Manual Steps (If script has issues)

Follow the detailed guide:
- See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for step-by-step instructions

---

## 📋 WHAT YOU'LL NEED DURING DEPLOYMENT

Have these ready:

1. **GitHub Credentials**
   - Your GitHub username
   - GitHub personal access token (if needed)

2. **Secret Key**
   - Generate with: `python -c "import secrets; print(secrets.token_urlsafe(32))"`

3. **Railway URL**
   - You'll get this after deploying backend
   - Format: `https://taskearn-api-xyz.up.railway.app`

4. **Netlify URL**
   - You'll get this after deploying frontend
   - Format: `https://your-site.netlify.app`

---

## ⚡ QUICK START (For Experienced Users)

If you want to do it manually:

```bash
# 1. Push to GitHub
git init
git add .
git commit -m "Deployment"
git remote add origin https://github.com/YOUR_USERNAME/taskearn.git
git push -u origin main

# 2. Deploy backend to Railway
# - Create project
# - Connect GitHub
# - Set root directory to: backend
# - Set SECRET_KEY, FLASK_ENV=production, DEBUG=False
# - Copy your Railway URL

# 3. Update frontend
# - Replace localhost:5000 with your Railway URL in:
#   - index.html
#   - admin.html
#   - chat.html

# 4. Push updated code
git add .
git commit -m "Update backend URL"
git push

# 5. Deploy frontend to Netlify
# - Connect GitHub
# - Set publish directory to: .
# - Deploy site
```

---

## ✨ RECOMMENDED: Use the Automated Script

The PowerShell script handles everything automatically!

```powershell
.\Deploy-to-Production.ps1
```

Just follow the interactive prompts. 👉 **This is the easiest way!**

---

## 🔍 AFTER DEPLOYMENT

### Test Your App:
1. Visit your Netlify URL (you'll get this URL after deployment)
2. Open DevTools (F12)
3. Create an account
4. Create a task
5. Refresh page - data should persist ✅

### Monitor:
- Railway Dashboard: https://railway.app/dashboard
- Netlify Dashboard: https://app.netlify.com

### If Issues:
- Check browser console (F12)
- Check Railway logs
- See troubleshooting section in [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

---

## 🎯 YOU ARE HERE

```
✅ Local Backend Running
✅ Frontend Configured
👉 DEPLOYMENT STARTING
   └─ Step 1: Push to GitHub
   └─ Step 2: Deploy Backend to Railway
   └─ Step 3: Update Frontend URLs
   └─ Step 4: Deploy Frontend to Netlify
   └─ Step 5: Test Live App
✅ Live Production App
```

---

## 🚀 READY? LET'S GO!

### Windows (PowerShell):
```powershell
.\Deploy-to-Production.ps1
```

### Mac/Linux (Bash):
```bash
bash deploy-to-production.sh
```

**OR** follow [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) manually.

---

## 💡 Need Help?

- **Deployment script stuck?** Check [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for manual steps
- **Backend won't deploy?** Check Railway logs and verify SECRET_KEY is set
- **Frontend has errors?** Check browser console (F12) and verify API URL is correct
- **Data not saving?** Verify Railway backend is running

---

**Let's deploy! 🚀** You've got this! 💪
