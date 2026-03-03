#!/usr/bin/env powershell
# Netlify Deployment Script for TaskEarn
# This script prepares your project for Netlify deployment

Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  TaskEarn - Netlify Deployment Setup      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan

# Step 1: Check Git status
Write-Host "`n📦 Step 1: Checking Git status..." -ForegroundColor Yellow
git status

# Step 2: Stage all changes
Write-Host "`n📝 Step 2: Staging files..." -ForegroundColor Yellow
git add .

# Step 3: Show what will be committed
Write-Host "`n✅ Files ready for commit:" -ForegroundColor Green
git status --short

# Step 4: Get commit message
Write-Host "`n💬 Enter commit message (default: 'Deploy to Netlify'):" -ForegroundColor Cyan
$commitMessage = Read-Host "Message"
if ([string]::IsNullOrWhiteSpace($commitMessage)) {
    $commitMessage = "Deploy to Netlify - Production ready"
}

# Step 5: Commit and push
Write-Host "`n🚀 Committing changes..." -ForegroundColor Yellow
git commit -m $commitMessage

Write-Host "`n📊 Git log (last 3 commits):" -ForegroundColor Cyan
git log --oneline -3

Write-Host @"
`n
╔════════════════════════════════════════════╗
║         NEXT STEPS - MANUAL ACTION         ║
╚════════════════════════════════════════════╝

1️⃣  PUSH TO GITHUB:
    git push origin main

2️⃣  SETUP NETLIFY:
    - Go to https://app.netlify.com/signup
    - Sign up / Login with GitHub
    - Click "New site from Git"
    - Select your repository
    - Build settings:
      • Build command: (leave empty)
      • Publish directory: .

3️⃣  GET YOUR RAILWAY BACKEND URL:
    - Go to https://railway.app/dashboard
    - Select your TaskEarn project
    - Copy the public domain/URL
    - Example: https://taskearn-xyz.up.railway.app

4️⃣  ADD ENVIRONMENT VARIABLES IN NETLIFY:
    Dashboard → Site Settings → Build & Deploy → Environment
    
    Add variable:
    • Key: RAILWAY_BACKEND_URL
    • Value: https://your-railway-domain.up.railway.app

5️⃣  UPDATE CONFIG IN NETLIFY:
    Create a functions/config.js or configure in netlify.toml

For detailed instructions, see: NETLIFY_DEPLOYMENT.md
"@ -ForegroundColor Magenta
