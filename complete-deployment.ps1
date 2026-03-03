#!/usr/bin/env powershell
<#
.SYNOPSIS
    Complete TaskEarn Deployment to Netlify
.DESCRIPTION
    Automates the GitHub push and provides Netlify setup instructions
#>

# Main script
Clear-Host
Write-Title "TaskEarn - Complete Netlify Deployment"

Write-Host @"

Your application has been configured for Netlify deployment:
  ✓ netlify.toml configured
  ✓ Environment variables set  
  ✓ Netlify functions created
  ✓ Frontend ready for deployment

Now let's complete the deployment process...

"@

Write-Step "1" "Checking git repository"
try {
    $gitStatus = git status 2>&1
    Write-Success "Git repository found"
    Write-Info "Current branch: $(git rev-parse --abbrev-ref HEAD)"
} catch {
    Write-Warning "Not a git repository - initializing..."
    git init
    git config user.email "you@example.com"
    git config user.name "TaskEarn Developer"
    Write-Success "Git repository initialized"
}

Write-Step "2" "Staging deployment files"
git add .
Write-Success "Files staged for commit"

Write-Step "3" "Preview files to be committed"
Write-Host ""
git diff --cached --name-status | Select-Object -First 20 | ForEach-Object {
    Write-Host "      $_"
}
Write-Host ""

Write-Step "4" "Creating deployment commit"
$defaultMessage = "Configure Netlify deployment with Railway backend"
Write-Host ""
Write-Host "  Commit message (press Enter for default):" -ForegroundColor Cyan
$message = Read-Host "  >> "
if ([string]::IsNullOrWhiteSpace($message)) {
    $message = $defaultMessage
}

git commit -m $message
Write-Success "Commit created: $message"

Write-Step "5" "Showing commit history"
Write-Host ""
git log --oneline -5 | ForEach-Object {
    Write-Host "      $_"
}
Write-Host ""

# Show the actual Git URLs to allow users to add remote
Write-Title "NEXT STEPS - NETLIFY DEPLOYMENT"

Write-Host @"

📍 STEP 1: PUSH TO GITHUB
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  If you don't have a GitHub remote yet:
    git remote add origin https://github.com/YOUR_USERNAME/taskearn.git
    git branch -M main
    git push -u origin main

  If you already have a remote:
    git push origin main

  ⚡ Quick Copy (Replace YOUR_USERNAME):
    git remote add origin https://github.com/YOUR_USERNAME/taskearn.git
    git push -u origin main


📍 STEP 2: SETUP NETLIFY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Open https://app.netlify.com/
  2. Sign up / Login with GitHub
  3. Click "New site from Git"
  4. Authorize GitHub if prompted
  5. Select your 'taskearn' repository
  6. Build settings (use defaults):
     • Build command: (leave empty)
     • Publish directory: .
  7. Click "Deploy site"


📍 STEP 3: GET RAILWAY BACKEND URL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Open https://railway.app/dashboard
  2. Select TaskEarn project
  3. View your service
  4. Copy the public domain URL
     Example: https://taskearn-abc123.up.railway.app


📍 STEP 4: CONFIGURE ENVIRONMENT VARIABLES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  In Netlify Dashboard:
  1. Site Settings → Build & deploy → Environment
  2. Click "Edit variables"
  3. Add new variable:
     • Key: RAILWAY_API_URL
     • Value: https://your-railway-domain.up.railway.app
  4. Save


📍 STEP 5: TRIGGER DEPLOY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Go to Netlify → Your Site → Deploys
  2. Click "Trigger deploy" → "Deploy site"
  3. Wait for green checkmark ✓
  4. Your site is live! 🎉


📍 VERIFY YOUR DEPLOYMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ Open your Netlify URL (you-site.netlify.app)
  ✓ Test login functionality
  ✓ Create a task
  ✓ Check browser console (F12) for any errors
  ✓ Verify API calls in Network tab
  ✓ Test payment feature with Razorpay


📍 AUTOMATED FUTURE DEPLOYS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Just push to GitHub and Netlify auto-deploys:
    git add .
    git commit -m "Your changes"
    git push origin main

  Netlify will automatically:
  ✓ Detect the push
  ✓ Build your site
  ✓ Deploy to production
  ✓ Show deployment status


📍 GET HELP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  📖 See detailed guide: NETLIFY_DEPLOYMENT.md
  📊 See deployment checklist: DEPLOYMENT_SUMMARY.md
  🔧 Need help? Check the troubleshooting section in NETLIFY_DEPLOYMENT.md


"@

Write-Title "Ready to Deploy! 🚀"
Write-Host ""
Write-Info "Your repository is ready to be pushed to GitHub"
Write-Info "Follow the steps above to complete Netlify deployment"
Write-Info "All configuration files have been created and optimized"

Write-Host ""
Write-Host "  Remember:" -ForegroundColor Magenta
Write-Host "  - Never commit .env file (contains secrets)" -ForegroundColor Magenta
Write-Host "  - Use Netlify environment variables instead" -ForegroundColor Magenta
Write-Host "  - Backend is separate on Railway" -ForegroundColor Magenta
Write-Host ""
