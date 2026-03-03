# TaskEarn - Complete Setup Guide

## ✅ Current Status

Your TaskEarn application is now **fully configured and running**!

### Servers Running
- ✅ **Backend API Server** (Flask) - http://localhost:5000
- ✅ **Frontend Web Server** (HTTP) - http://localhost:5500  
- ✅ **Database** (SQLite locally, PostgreSQL on Railway)
- ✅ **CORS** (Properly configured)

### What Works
- ✅ User Registration (Sign Up)
- ✅ User Authentication (Login)
- ✅ Task Management
- ✅ Payment Processing (Razorpay ready)
- ✅ Wallet System
- ✅ Location Tracking
- ✅ Admin Dashboard

---

## 🚀 Quick Start (Next Time)

### Option 1: Automated (Easiest)
```batch
QUICK_START.bat
```
This will:
1. Kill old processes
2. Start backend server
3. Start frontend server
4. Open app in browser

### Option 2: Manual
**Terminal 1 - Start Backend:**
```powershell
cd c:\Users\therh\Desktop\ToDo\backend
python server.py
```

**Terminal 2 - Start Frontend:**
```powershell
cd c:\Users\therh\Desktop\ToDo
python -m http.server 5500
```

**Browser:**
```
http://localhost:5500/index.html
```

---

## 🧪 Testing Your App

### 1. Sign Up (Create New Account)
- Click **Sign Up** button
- Enter: Name, Email, Password, Date of Birth, Phone (optional)
- Click **Create Account**
- You'll be logged in automatically

### 2. Login (If You Already Have Account)
- Click **Login** button
- Enter email and password
- Click **Sign In**

### 3. Create a Task
- Click **Post Task** tab
- Fill in task details (title, description, location, price, deadline)
- Click **Post Task**
- Task appears in "Find Tasks" for other users

### 4. Complete a Task
- View tasks in **Find Tasks** section
- Click **Accept Task** to start working
- Complete the work
- Upload proof of completion
- Request payment

### 5. Earn Money
- Complete tasks to earn money
- Check your **Wallet** for balance
- Withdraw money to your bank account

---

## ⚙️ Configuration Files

### Key Files
| File | Purpose |
|------|---------|
| `.env` | Environment variables (database URL, secret key) |
| `backend/server.py` | Flask API server (2000+ lines) |
| `backend/database.py` | Database connection and queries |
| `backend/config.py` | Configuration settings |
| `app.js` | Frontend business logic (4000+ lines) |
| `api-client.js` | API communication functions |
| `index.html` | Main app page (1170 lines) |
| `styles.css` | Application styling |

### Current Database
- **Local Development**: SQLite (`taskearn.db`)
- **Production**: PostgreSQL on Railway
- **Connection**: Auto-detected in config

---

## 🔗 API Endpoints

### Authentication
```
POST   /api/auth/register          - Sign up new user
POST   /api/auth/login             - Login user
POST   /api/auth/logout            - Logout
GET    /api/auth/me                - Get current user
POST   /api/auth/forgot-password   - Request password reset
```

### Tasks
```
GET    /api/tasks                  - List all tasks
POST   /api/tasks                  - Create new task
POST   /api/tasks/<id>/accept      - Accept a task
POST   /api/tasks/<id>/complete    - Complete task
GET    /api/user/tasks             - Get user's tasks
```

### Wallet
```
GET    /api/wallet                 - Get wallet balance
POST   /api/wallet/add-money       - Add funds (Razorpay)
POST   /api/wallet/pay             - Pay for service
POST   /api/wallet/withdraw        - Withdraw to bank
GET    /api/wallet/transactions    - Transaction history
```

### Tracking
```
POST   /api/tracking/update-location - Update user location
GET    /api/tracking/<id>/location   - Get task location
GET    /api/tracking/history/<id>    - Location history
```

### Other
```
GET    /api/health                 - Health check
GET    /api/user/profile           - Get user profile
PUT    /api/user/profile           - Update profile
GET    /api/chat/<id>/messages     - Get task messages
POST   /api/chat/<id>/send         - Send message
```

---

## 🔑 Environment Variables

Currently set in `.env`:
```
DATABASE_URL = postgresql://...    # Railway PostgreSQL
SECRET_KEY = your-secret-key       # JWT secret
DEBUG = False                      # Always false in production
```

Available (but optional):
```
RAZORPAY_KEY_ID = ...              # Razorpay merchant ID
RAZORPAY_KEY_SECRET = ...          # Razorpay secret
SENDGRID_API_KEY = ...             # Email service
FROM_EMAIL = noreply@taskearn.com  # Email sender
CORS_ORIGINS = *                   # Allowed origins
```

---

## 🐛 Debugging

### Browser Console (F12)
- Shows all API calls and responses
- Shows authentication tokens
- Shows error messages
- Shows console.logs from app.js

### Backend Logs
- Shows in terminal running `python server.py`
- Shows all HTTP requests
- Shows database queries
- Shows error stack traces

### Diagnostic Tool
Open in browser:
```
file:///c:/Users/therh/Desktop/ToDo/api-diagnostic.html
```

Runs tests:
- Health check
- Registration
- Login
- CORS configuration

---

## 📦 Database Schema

### Tables
- `users` - User accounts (email, password, profile)
- `tasks` - Tasks posted by users  
- `task_assignments` - User-task relationships
- `wallets` - User wallet balances
- `transactions` - Payment/earning history
- `messages` - Task chat messages
- `tracking` - Location tracking data
- `ratings` - Task ratings and reviews
- Others (referrals, SOS alerts, scheduled tasks, etc.)

### Sample Data
- 2 test users (created for testing)
- 2 sample tasks
- All table structures initialized

---

## 🚀 Deployment

### Current Setup
- **Frontend**: Ready for Netlify
- **Backend**: Deployed to Railway  
- **Database**: Railway PostgreSQL
- **Git**: All committed and ready to push

### Deploy to Production
1. Frontend → Netlify (see NETLIFY_DEPLOYMENT.md)
2. Backend → Railway (already configured)
3. Database → Railway PostgreSQL (already set up)

---

## 🆘 Common Issues & Fixes

### "Cannot reach http://localhost:5500"
→ Frontend server not running
→ Run: `python -m http.server 5500`

### "Network error - failed to fetch"
→ Backend not running
→ Run: `cd backend && python server.py`
→ Or: Use QUICK_START.bat

### CORS Policy Errors
→ Already fixed! CORS is properly configured
→ If still seeing errors, run verify_cors_fix.py

### Login/Signup Not Working
→ Check browser console (F12) for exact error
→ Run api-diagnostic.html to test API
→ Check backend terminal for errors

### Database Connection Error
→ If using PostgreSQL, check DATABASE_URL in .env
→ Ensure Railway PostgreSQL is running
→ Falls back to SQLite if PostgreSQL unavailable

---

## 📚 Additional Resources

### Guides
- `FIX_NETWORK_ERROR.md` - Network error troubleshooting
- `NETLIFY_DEPLOYMENT.md` - Frontend deployment guide
- `RAILWAY_DEPLOYMENT_GUIDE.md` - Backend deployment
- `PRODUCTION_CHECKLIST.md` - Pre-launch checklist

### Tools
- `api-diagnostic.html` - Test all endpoints
- `test_login_api.py` - Python API test script
- `verify_cors_fix.py` - Verify CORS configuration
- `test_api.html` - Browser-based API tester

### Files to Review
- `backend/server.py` - Backend API (2137 lines)
- `app.js` - Frontend logic (4024 lines)
- `index.html` - Main page (1170 lines)
- `api-client.js` - API client library (506 lines)

---

## ✨ Features Implemented

### User Management
- ✅ Sign up with validation
- ✅ Login/logout
- ✅ Password reset via OTP
- ✅ User profiles with editing
- ✅ Age verification (16+)

### Tasks
- ✅ Create/post tasks
- ✅ Browse available tasks
- ✅ Accept tasks
- ✅ Track progress
- ✅ Complete and submit proof
- ✅ Rating system

### Payments
- ✅ Razorpay integration
- ✅ Wallet system
- ✅ Add funds to wallet
- ✅ Pay for services
- ✅ Earn from completed tasks
- ✅ Withdraw to bank account

### Real-time Features
- ✅ Location tracking (Leaflet.js)
- ✅ Live task status updates
- ✅ Chat messaging system
- ✅ Notifications
- ✅ OTP verification

### Admin Features
- ✅ Admin dashboard
- ✅ User management
- ✅ Task moderation
- ✅ Payment monitoring
- ✅ Dispute resolution

### Security
- ✅ JWT authentication
- ✅ Bcrypt password hashing
- ✅ CORS configuration
- ✅ Rate limiting ready
- ✅ Input validation
- ✅ SQL injection protection

---

## 🎯 Next Steps

1. **Start servers**
   ```
   QUICK_START.bat
   ```

2. **Create account**
   - Sign up with test data
   - Verify email (in development, auto-verified)

3. **Test all features**
   - Create a task
   - Accept someone else's task
   - Use wallet features
   - Test chat and tracking

4. **Review code**
   - Check `backend/server.py` for business logic
   - Review `app.js` for frontend handling
   - Understand the data flow

5. **Deploy to production** (when ready)
   - Frontend → Netlify
   - Backend → Railway (already configured)
   - Follow NETLIFY_DEPLOYMENT.md

---

## 📞 Support

If you encounter issues:

1. **Check the relevant guide**
   - Network error? → FIX_NETWORK_ERROR.md
   - Deployment? → NETLIFY_DEPLOYMENT.md
   - Backend? → RAILWAY_DEPLOYMENT_GUIDE.md

2. **Use diagnostic tools**
   - Open api-diagnostic.html
   - Run verify_cors_fix.py
   - Check browser console (F12)

3. **Review logs**
   - Backend terminal output
   - Browser network tab
   - Browser console errors

4. **Restart servers**
   - Use QUICK_START.bat
   - Or manually restart both processes

---

**🎉 You're all set! Enjoy using TaskEarn!**

For questions, check the markdown guides in your project folder.
