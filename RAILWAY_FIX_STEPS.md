# 🚨 CRITICAL: Railway Backend Configuration Fix

## Problem Identified
Railway is serving **frontend HTML files** instead of the **Flask API** on the backend URL.

**Symptom:** `https://taskearn-production-production.up.railway.app` returns `<!DOCTYPE html>...` (index.html) instead of JSON API responses.

## Root Cause
Railway deployment is likely configured to deploy from the **root directory** instead of the **backend folder only**. This causes the frontend (index.html, wallet.html, etc.) to be served instead of the Flask app.

## Solution

### Option 1: Reconfigure Railway to Deploy Backend Only (RECOMMENDED)

1. Go to [Railway Dashboard](https://railway.app) 
2. Find your TaskEarn Backend service
3. Go to **Settings** tab
4. Look for "Deploy Root" or "Service Root" setting
5. Change it from `.` (root) to `backend` (backend folder)
6. Save and **Trigger Redeploy**

### Option 2: Fix via Procfile and railway.json

Both files should point to `server:app`:

**Procfile:**
```
web: gunicorn -w 4 -b 0.0.0.0:$PORT server:app --timeout 120
```

**railway.json:**
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "dockerfile"
  },
  "deploy": {
    "startCommand": "gunicorn -w 4 -b 0.0.0.0:$PORT server:app --timeout 120"
  }
}
```

### Option 3: Add Root-Level Dockerfile (Alternative)

If Railway can't be configured to serve just backend, create a `Dockerfile` in root:

```dockerfile
# Use backend Dockerfile but from subdirectory
FROM python:3.11-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install -r requirements.txt
COPY backend /app
EXPOSE 5000
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:5000", "server:app"]
```

## Testing Steps

After reconfiguring Railway:

1. **Wait for redeploy to complete** (2-3 minutes)

2. **Test health endpoint:**
   ```powershell
   Invoke-WebRequest -Uri "https://taskearn-production-production.up.railway.app/api/health" -UseBasicParsing | Select-Object -ExpandProperty Content
   ```
   
   Expected response:
   ```json
   {
     "success": true,
     "status": "healthy",
     "database": "PostgreSQL",
     "timestamp": "2026-03-03T...",
     "environment": "production"
   }
   ```

3. **Test diagnostic endpoint:**
   ```powershell
   Invoke-WebRequest -Uri "https://taskearn-production-production.up.railway.app/api/diagnostic" -UseBasicParsing | Select-Object -ExpandProperty Content
   ```

   This will confirm Flask API is running and NOT frontend files.

4. **Test login endpoint:**
   ```powershell
   $headers = @{
     "Content-Type" = "application/json"
   }
   $body = @@{
     "email" = "test@example.com"
     "password" = "Test123"
   } | ConvertTo-Json
   Invoke-WebRequest -Uri "https://taskearn-production-production.up.railway.app/api/auth/login" -Method POST -Headers $headers -Body $body -UseBasicParsing
   ```

## Fallback: Deploy Backend Standalone

If Railway configuration doesn't work:

1. Create a **separate Railway service** for just the backend
2. Connect it only to the `backend/` folder  
3. Use the new URL for `RAILWAY_API_URL` in Netlify

## Status Update

- ✅ Diagnostic endpoint added to `server.py`
- ✅ Changes pushed to GitHub (commit: d888aea)
- ⏳ **WAITING:** Railway to redeploy with new commits
- ⏳ **ACTION NEEDED:** Reconfigure Railway settings to deploy from `backend` folder only

## Next Steps

1. **Go to Railway Dashboard NOW**
2. **Reconfigure service to use `backend` folder**
3. **Trigger manual redeploy**
4. **Wait 2-3 minutes**
5. **Test `/api/health` and `/api/diagnostic` endpoints**
6. **Report back when Railway is fixed**

Once Railway is correctly configured, the frontend should automatically connect to the working API!

---

**Quick Links:**
- 🚀 [Railway Dashboard](https://railway.app/dashboard)
- 📡 [Your Service URL](https://taskearn-production-production.up.railway.app)
- ✅ [Local API Test](http://localhost:5000/api/health)
