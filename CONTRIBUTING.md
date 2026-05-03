# Contributing to Workmate4u

This document explains how to develop, test and ship changes safely as a team.

## TL;DR

```
local laptop  →  feature/<name> branch  →  PR into staging  →  PR into main
                                                  ↓                  ↓
                                       staging.workmate4u.com   workmate4u.com
```

**Never push directly to `main`.**

---

## 1. Repo & branches

| Branch | Purpose | Auto-deploys to |
|---|---|---|
| `main` | Production. Always green. | `workmate4u.com` (Netlify prod) + Railway prod |
| `staging` | Pre-production testing. | `staging--workmate4u.netlify.app` + Railway staging |
| `feature/*`, `fix/*` | Your work-in-progress | Netlify deploy preview per PR |

---

## 2. One-time local setup (Windows)

```powershell
# 1. Clone
git clone https://github.com/RupeshShinde101/taskearn-production.git
cd taskearn-production

# 2. Python env for backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend/requirements.txt

# 3. Local config — copy and fill in values
copy backend\.env.example backend\.env   # if exists, otherwise create
# Set DATABASE_URL (sqlite:///local.db works for quick dev)
# Set RAZORPAY_KEY_ID / SECRET to TEST keys (rzp_test_...)
# Set SENDGRID_API_KEY (optional locally)
```

---

## 3. Daily workflow

```powershell
# Always start fresh from main
git checkout main
git pull origin main

# Create a branch named after what you're doing
git checkout -b feature/wallet-redesign     # or fix/login-bug, chore/cleanup-css

# --- Code, test locally ---

# Run backend
cd backend
python server.py            # http://localhost:5000

# In another terminal: serve frontend
cd ..
python -m http.server 8080   # http://localhost:8080
# Open http://localhost:8080/index.html

# When happy:
git add -A
git commit -m "feat(wallet): redesign top-up flow"
git push -u origin feature/wallet-redesign
```

Then on GitHub:
1. Open a **Pull Request** → target branch: `staging`.
2. Netlify will post a **deploy preview URL** in the PR — share with team for review.
3. After approval, merge into `staging`.
4. Test on `staging.workmate4u.com`.
5. When staging passes QA, open a 2nd PR: `staging` → `main`.
6. Merge → live in ~30s.

---

## 4. Commit message style

Use prefixes so the changelog is readable:

- `feat:` new feature
- `fix:` bug fix
- `style:` CSS / visual only
- `refactor:` no behaviour change
- `chore:` tooling, deps, configs
- `docs:` documentation
- `content:` copy / wording / images

Examples:
- `feat(chat): add image attachment support`
- `fix(home): wallet balance not refreshing after top-up`
- `style(profile): tighter spacing on KYC card`

---

## 5. Environments

### Production (`main`)
- Frontend: https://workmate4u.com (Netlify)
- Backend: https://taskearn-production-production.up.railway.app
- DB: Railway production Postgres
- Razorpay: **LIVE** keys
- Email: SendGrid live

### Staging (`staging`)
- Frontend: https://staging--workmate4u.netlify.app (or `staging.workmate4u.com`)
- Backend: https://taskearn-production-staging.up.railway.app
- DB: Railway **separate** staging Postgres (safe to wipe)
- Razorpay: **TEST** keys (`rzp_test_...`)
- Email: SendGrid (use a `staging@` from-email so emails are tagged)

### Local
- Frontend: http://localhost:8080
- Backend: http://localhost:5000
- DB: sqlite or local Postgres
- Razorpay: TEST keys
- Email: optional

`api-client.js` automatically picks the right backend based on the hostname.

---

## 6. Pre-commit checklist

Before opening a PR:
- [ ] `python _fixmojibake.py` reports clean
- [ ] No console errors in browser
- [ ] Tested both light + dark mode
- [ ] Tested mobile width (<400px)
- [ ] Bumped cache token in HTML / sw.js if you changed JS or CSS that ships
- [ ] No real secrets committed (search for `rzp_live_`, `SG.`, etc.)

---

## 7. Branch protection (admin setup)

On GitHub: **Settings → Branches → Add rule** for `main`:
- ✅ Require pull request before merging
- ✅ Require approvals: 1
- ✅ Require linear history
- ✅ Do not allow bypassing
- ✅ Require status checks (once CI is added)

Same rule (lighter) for `staging`.

---

## 8. Hot-fix flow (production is broken)

```powershell
git checkout main
git pull
git checkout -b hotfix/payment-bug
# fix it
git commit -m "fix(payment): handle Razorpay timeout"
git push -u origin hotfix/payment-bug
# Open PR directly into main (skip staging only when truly urgent)
# After merge, ALSO merge main back into staging so they don't drift.
```

---

## 9. Useful commands

```powershell
# See what changed
git status
git diff

# Update your branch with latest main
git checkout my-branch
git fetch origin
git rebase origin/main

# Throw away local changes
git checkout -- path/to/file
git reset --hard origin/my-branch

# See branch history
git log --oneline --graph --all -20
```

---

## Questions?

Ping the team or open a GitHub Issue with the `question` label.
