# TaskEarn - Production Deployment Guide

## 🚀 Deploy to Railway (Recommended for Beginners)

Railway is the easiest way to deploy - it handles everything automatically.

---

## Step 1: Prepare Your Code

1. **Create a GitHub account** (if you don't have one): https://github.com/signup
2. **Initialize a Git repository** in your project folder:
   ```bash
   cd C:\Users\therh\Desktop\ToDo
   git init
   git add .
   git commit -m "Initial commit - TaskEarn production ready"
   ```
3. **Create a new GitHub repository**:
   - Go to https://github.com/new
   - Name it `taskearn-production`
   - Click "Create repository"
   - Follow the commands to push your local code to GitHub

---

## Step 2: Deploy Backend to Railway

1. **Go to Railway**: https://railway.app
2. **Sign up** with GitHub (easiest option)
3. **Create a new project**:
   - Click "New Project"
   - Select "Deploy from GitHub repo"
   - Select your `taskearn-production` repository
   - Click "Deploy Now"

4. **Configure environment variables**:
   - Go to your project → Variables
   - Add these variables:
     ```
     FLASK_ENV=production
     SECRET_KEY=<generate a random 32-char string here>
     CORS_ORIGINS=https://your-frontend-domain.com
     JWT_EXPIRATION_HOURS=24
     RAZORPAY_KEY_ID=<your key if using payments>
     RAZORPAY_KEY_SECRET=<your secret if using payments>
     ```

5. **Add PostgreSQL database**:
   - In your Railway project → Add Service
   - Select "PostgreSQL" → Provision
   - Railway automatically sets `DATABASE_URL` ✅

6. **Wait for deployment** - Railway will build and deploy your backend
   - You'll get a URL like: `https://taskearn.up.railway.app`
   - Copy this URL (you'll need it for the frontend)

---

## Step 3: Deploy Frontend to Netlify

1. **Go to Netlify**: https://netlify.com
2. **Sign up** with GitHub
3. **Create new site from Git**:
   - Click "Add new site" → "Import an existing project"
   - Select your `taskearn-production` GitHub repo
   - Build settings:
     - Build command: (leave empty)
     - Publish directory: `.` (root)
   - Click "Deploy site"

4. **Configure environment for API**:
   - Go to Site settings → Build & deploy → Environment
   - Add variable: `VITE_API_URL=https://taskearn.up.railway.app/api`
   
   **OR** manually update `index.html`:
   - Open `index.html` in your editor
   - Find this line (around line 17-18):
     ```html
     <script>
         window.TASKEARN_API_URL = 'http://localhost:5000/api';
     </script>
     ```
   - Change it to:
     ```html
     <script>
         window.TASKEARN_API_URL = 'https://taskearn.up.railway.app/api';
     </script>
     ```
   - Commit and push to GitHub
   - Netlify will auto-redeploy

5. **Wait for deployment** - Netlify will deploy your frontend
   - You'll get a URL like: `https://taskearn-production.netlify.app`

---

## Step 4: Connect Frontend to Backend

Update your frontend files with the correct backend URL:

**In `index.html`, `tracking.html`, `admin.html`, `wallet.html`, `chat.html`:**

```html
<script>
    // Production Backend URL
    window.TASKEARN_API_URL = 'https://taskearn.up.railway.app/api';
</script>
```

---

## Step 5: Test Everything

1. **Open your Netlify URL**: `https://your-site.netlify.app`
2. **Sign up** with an email
3. **Post a task** with your location
4. **In another browser/incognito window** sign up with different email
5. **View tasks** - you should see the task from the first user!

---

## 🎯 What You Now Have

✅ **Frontend**: Deployed on Netlify (always HTTPS)
✅ **Backend API**: Deployed on Railway (always HTTPS)  
✅ **Database**: PostgreSQL on Railway (automatic backups)
✅ **Email**: Tasks visible to all users worldwide
✅ **Ready for monetization**: Accept payments via Razorpay

---

## 💰 Monetization Setup

### Enable Razorpay Payments

1. **Create Razorpay account**: https://razorpay.com
2. **Get API keys** from Razorpay dashboard
3. **Update Railway environment variables**:
   ```
   RAZORPAY_KEY_ID=rzp_live_xxxxxx
   RAZORPAY_KEY_SECRET=xxxxx
   ```
4. **Uncomment Razorpay code** in `index.html` (already there but commented)

Now users can pay for tasks and you earn commission!

---

## 🔐 Security Checklist

- [ ] Change `SECRET_KEY` to a random 32+ character string
- [ ] Set `CORS_ORIGINS` to your actual domain (not `*`)
- [ ] Enable HTTPS everywhere (automatic on Railway/Netlify)
- [ ] Never commit `.env` file to GitHub (add to `.gitignore`)
- [ ] Use strong passwords for all accounts
- [ ] Enable 2FA on Railway, Netlify, GitHub, Razorpay

---

## 📊 Monitor Your Application

**Railway Dashboard**:
- View logs: Project → Logs
- Check database: Project → Postgres → Data
- Monitor performance: Project → Metrics

**Netlify Dashboard**:
- View deploy logs: Deploys
- Check analytics: Analytics
- Monitor errors: Functions

---

## 🚨 Troubleshooting

**"CORS Error" when posting tasks**
- Your frontend URL isn't in `CORS_ORIGINS`
- Update Railway env var to include your Netlify domain

**"Failed to connect to database"**
- PostgreSQL isn't provisioned on Railway
- Add PostgreSQL service in Railway project

**Tasks not saving**
- Check backend logs in Railway
- Verify `DATABASE_URL` is set in Railway

**Website loads but API calls fail**
- Browser console (F12) will show exact error
- Check `TASKEARN_API_URL` is correct in HTML

---

## 📈 Next Steps for Business

1. **Add more payment methods** (Stripe, PayPal)
2. **Implement email notifications** (SendGrid)
3. **Add user reviews/ratings** system
4. **Create admin dashboard** to manage platform
5. **Add commission/cut system** for platform revenue
6. **Implement referral program**
7. **Deploy mobile app** (React Native, Flutter)

---

## 💡 Cost Estimates (Monthly)

- **Railway Backend**: $5-20/month
- **Netlify Frontend**: Free - $19/month
- **PostgreSQL Database**: Included in Railway
- **Total**: ~$5-40/month

Free tier is available for both if you're just starting!

---

## 🤝 Support

- Railway Docs: https://railway.app/docs
- Netlify Docs: https://docs.netlify.com
- Flask Documentation: https://flask.palletsprojects.com
- Razorpay Integration: https://razorpay.com/docs

Your TaskEarn application is now production-ready! 🎉

