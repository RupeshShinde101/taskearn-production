# Railway Environment Variables Setup

## Required PostgreSQL Environment Variables

These variables are needed by Railway to connect to PostgreSQL properly.

### Option 1: Set Variables in Railway Dashboard (Recommended)

1. Go to [Railway Dashboard](https://railway.app)
2. Select your **taskearn-production** project
3. Click on the **PostgreSQL** service (NOT the backend)
4. Click **Variables** tab
5. Add these variables:

| Variable | Value |
|----------|-------|
| PGUSER | postgres |
| PGPASSWORD | EipPSaqvFSdRagwxVOWYpXUbtDaEiztw |
| PGHOST | crossover.proxy.rlwy.net |
| PGPORT | 17104 |
| PGDATABASE | railway |

---

### Option 2: Set in Backend Service Variables

1. Go to [Railway Dashboard](https://railway.app)
2. Select your **taskearn-production** project
3. Click on the **backend** service
4. Click **Variables** tab
5. Add these variables:

```
DATABASE_URL=postgresql://postgres:EipPSaqvFSdRagwxVOWYpXUbtDaEiztw@crossover.proxy.rlwy.net:17104/railway
PGUSER=postgres
PGPASSWORD=EipPSaqvFSdRagwxVOWYpXUbtDaEiztw
PGHOST=crossover.proxy.rlwy.net
PGPORT=17104
PGDATABASE=railway
SECRET_KEY=TaskEarn-Fixed-Secret-Key-2026-Do-Not-Change
```

---

### Option 3: Use Railway.json Config File

Create/Update `railway.json` in backend:

```json
{
  "build": {
    "builder": "nixpacks"
  },
  "deploy": {
    "startCommand": "python run.py"
  },
  "variables": {
    "DATABASE_URL": "postgresql://postgres:EipPSaqvFSdRagwxVOWYpXUbtDaEiztw@crossover.proxy.rlwy.net:17104/railway",
    "PGUSER": "postgres",
    "PGPASSWORD": "EipPSaqvFSdRagwxVOWYpXUbtDaEiztw",
    "PGHOST": "crossover.proxy.rlwy.net",
    "PGPORT": "17104",
    "PGDATABASE": "railway",
    "SECRET_KEY": "TaskEarn-Fixed-Secret-Key-2026-Do-Not-Change"
  }
}
```

---

## Testing PostgreSQL Connection

After adding environment variables, test with:

```bash
python -c "import os; print(f'PGUSER: {os.environ.get(\"PGUSER\")}'); print(f'PGDATABASE: {os.environ.get(\"PGDATABASE\")}')"
```

---

## Status

- ✅ Local .env files updated with PostgreSQL variables
- ✅ .env files automatically ignored (not committed to git for security)
- ⏳ **NEXT:** Add these variables to Railway dashboard

