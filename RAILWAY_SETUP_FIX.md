# Railway Environment Variables Setup - DATABASE ERROR FIX

## Problem
Railway dashboard shows: "failed to fetch requirement variable" when trying to connect to PostgreSQL.

## Solution: Add Environment Variables to Railway

### Step 1: Access Railway Project Dashboard

1. Go to https://railway.app
2. Login to your account
3. Click on your "TaskEarn" project
4. Navigate to **Variables** tab on the left sidebar

### Step 2: Add Required Environment Variables

Add these environment variables in Railway:

#### Option A: Using PostgreSQL (Recommended)

If you have a PostgreSQL database on Railway:

```
DATABASE_URL=postgresql://postgres:[PASSWORD]@[HOST]:5432/[DATABASE]
```

Example format:
```
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@your-host.railway.internal:5432/railway
```

**To find your credentials:**
1. In Railway, go to **Plugins** or **Resources**
2. Click on your PostgreSQL database
3. Click **"Connect"**
4. Copy the **Database URL** or individual credentials

#### Option B: Using Individual PostgreSQL Variables

Add these separately in Railway:

```
PGHOST=your-postgres-host
PGPORT=5432
PGDATABASE=railway
PGUSER=postgres
PGPASSWORD=your-password
```

Then the backend will automatically construct the DATABASE_URL.

### Step 3: Add Other Required Variables

```
FLASK_ENV=production
SECRET_KEY=TaskEarn-Fixed-Secret-Key-2026-Do-Not-Change
DEBUG=False
CORS_ORIGINS=https://workmate4u.com,https://www.workmate4u.com
```

### Step 4: Verify Setup

1. After adding all variables, click **Deploy** or **Trigger Deploy** in Railway
2. Check the deployment logs to see if it starts successfully
3. Visit your app: https://taskearn-production-production.up.railway.app/api/health
4. You should see: `{"status":"healthy","database":"PostgreSQL",...}`

---

## Quick Checklist

- [ ] Are you signed into Railway?
- [ ] Are you in the correct project (TaskEarn)?
- [ ] Have you added the DATABASE_URL variable?
- [ ] Does the DATABASE_URL start with `postgresql://` or `postgres://`?
- [ ] Have you clicked "Deploy" after adding variables?
- [ ] Wait 2-3 minutes for the deployment to complete

---

## Troubleshooting

### If you see "OperationalError: could not connect to server"

1. Check if the DATABASE_URL is correct:
   - Should format: `postgresql://user:pass@host:port/database`
   - Should NOT have any spaces or special characters that need escaping

2. Verify the PostgreSQL plugin:
   - Is PostgreSQL enabled as a plugin in Railway?
   - Does it have at least 1 replica running?

### If dashboard still shows error

1. Go to **Logs** in Railway
2. Check the error message - it will tell you exactly what's wrong
3. Common issues:
   - Invalid PASSWORD in DATABASE_URL
   - Typo in HOST or DATABASE name
   - PostgreSQL service not running

### If taskearn.db appears in logs

That means SQLite is being used instead of PostgreSQL. This happens when:
- `DATABASE_URL` is NOT set on Railway
- Backend falls back to SQLite
- Solution: Add the `DATABASE_URL` variable!

---

## Production Deployment Verification

After setup, verify with:

```bash
# Check health endpoint
curl https://taskearn-production-production.up.railway.app/api/health

# Expected response:
# {"database":"PostgreSQL","environment":"production","status":"healthy",...}
```

