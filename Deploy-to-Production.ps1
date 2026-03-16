# TaskEarn Production Deployment Script (Windows)
# Deploy Backend to Railway + Frontend to Netlify

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          TaskEarn - Production Deployment (Windows)                   ║" -ForegroundColor Cyan
Write-Host "║    Backend → Railway  |  Frontend → Netlify                          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if Git is installed
Write-Host "Checking Git installation..." -ForegroundColor Yellow
try {
    git --version | Out-Null
    Write-Host "✅ Git is installed" -ForegroundColor Green
} catch {
    Write-Host "❌ Git not found. Install from https://git-scm.com" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 1: Initialize Git Repository
Write-Host "Step 1: Setting up Git repository..." -ForegroundColor Cyan
Write-Host "─" * 70 -ForegroundColor Gray

if (-not (Test-Path ".git")) {
    Write-Host "Initializing Git repository..." -ForegroundColor Yellow
    git init
    git add .
    git commit -m "Initial commit for production deployment"
    Write-Host "✅ Git repository initialized" -ForegroundColor Green
} else {
    Write-Host "✅ Git repository already exists" -ForegroundColor Green
}
Write-Host ""

# Step 2: Check GitHub Remote
Write-Host "Step 2: Checking GitHub remote..." -ForegroundColor Cyan
Write-Host "─" * 70 -ForegroundColor Gray

$gitRemote = git config --get remote.origin.url 2>$null
if (-not $gitRemote) {
    Write-Host ""
    Write-Host "⚠️  GitHub remote not configured!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please follow these steps:"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "1. Go to https://github.com/new" -ForegroundColor Green
    Write-Host "2. Create a new repository named 'taskearn'"
    Write-Host "3. Copy the HTTPS URL (e.g., https://github.com/username/taskearn.git)"
    Write-Host "4. Come back and follow the commands below"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    
    $githubUrl = Read-Host "Enter your GitHub repository URL (HTTPS)"
    
    git remote add origin $githubUrl
    git branch -M main
    Write-Host "✅ GitHub remote added: $githubUrl" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pushing code to GitHub..." -ForegroundColor Yellow
    git push -u origin main
    Write-Host "✅ Code pushed to GitHub!" -ForegroundColor Green
} else {
    Write-Host "✅ GitHub remote found: $gitRemote" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pushing latest changes..." -ForegroundColor Yellow
    git add .
    git commit -m "Production deployment update" 2>$null
    git push
    Write-Host "✅ Code pushed to GitHub!" -ForegroundColor Green
}
Write-Host ""

# Step 3: Backend Deployment to Railway
Write-Host "Step 3: Deploy Backend to Railway" -ForegroundColor Cyan
Write-Host "─" * 70 -ForegroundColor Gray
Write-Host ""
Write-Host "Follow these steps to deploy your backend to Railway:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Go to https://railway.app" -ForegroundColor Green
Write-Host "2. Sign in with GitHub or create account"
Write-Host "3. Click 'Create Project'"
Write-Host "4. Select 'Deploy from GitHub'"
Write-Host "5. Select your 'taskearn' repository"
Write-Host "6. Click on the project"
Write-Host "7. Configure environment:"
Write-Host "   - Root directory: backend"
Write-Host ""
Write-Host "8. IMPORTANT: Set Environment Variables"
Write-Host "   Go to Settings → Variables → Add"
Write-Host ""
Write-Host "   Name: SECRET_KEY" -ForegroundColor Yellow
Write-Host "   Value: " -NoNewline -ForegroundColor Yellow
Read-Host "Generate one and paste it"
Write-Host ""
Write-Host "   To generate SECRET_KEY, run:" -ForegroundColor Gray
Write-Host "   python -c \"import secrets; print(secrets.token_urlsafe(32))\"" -ForegroundColor Gray
Write-Host ""
Write-Host "9. Wait for deployment to complete"
Write-Host "10. Go to Deployments tab to see your URL"
Write-Host ""

$railwayUrl = Read-Host "Enter your Railway backend URL (e.g., https://taskearn-api-xyz.up.railway.app)"

if (-not $railwayUrl.StartsWith("https://")) {
    $railwayUrl = "https://" + $railwayUrl
}

Write-Host "✅ Railway URL saved: $railwayUrl" -ForegroundColor Green
Write-Host ""

# Step 4: Update Frontend Configuration
Write-Host "Step 4: Updating frontend configuration..." -ForegroundColor Cyan
Write-Host "─" * 70 -ForegroundColor Gray

Write-Host "Updating index.html..." -ForegroundColor Yellow
$indexPath = "index.html"
if (Test-Path $indexPath) {
    $content = Get-Content $indexPath -Raw
    $content = $content -replace "http://localhost:5000/api", "$railwayUrl/api"
    Set-Content $indexPath $content
    Write-Host "✅ index.html updated" -ForegroundColor Green
}

Write-Host "Updating admin.html..." -ForegroundColor Yellow
$adminPath = "admin.html"
if (Test-Path $adminPath) {
    $content = Get-Content $adminPath -Raw
    $content = $content -replace "http://localhost:5000/api", "$railwayUrl/api"
    Set-Content $adminPath $content
    Write-Host "✅ admin.html updated" -ForegroundColor Green
}

Write-Host "Updating chat.html..." -ForegroundColor Yellow
$chatPath = "chat.html"
if (Test-Path $chatPath) {
    $content = Get-Content $chatPath -Raw
    $content = $content -replace "http://localhost:5000/api", "$railwayUrl/api"
    Set-Content $chatPath $content
    Write-Host "✅ chat.html updated" -ForegroundColor Green
}

Write-Host "Updating netlify.toml..." -ForegroundColor Yellow
$netlifyPath = "netlify.toml"
if (Test-Path $netlifyPath) {
    $content = Get-Content $netlifyPath -Raw
    $content = $content -replace "BACKEND_URL = `"https://taskearn-production-production.up.railway.app`"", "BACKEND_URL = `"$railwayUrl`""
    Set-Content $netlifyPath $content
    Write-Host "✅ netlify.toml updated" -ForegroundColor Green
}

Write-Host ""

# Step 5: Push Updated Code
Write-Host "Step 5: Pushing updated code to GitHub..." -ForegroundColor Cyan
Write-Host "─" * 70 -ForegroundColor Gray

git add .
git commit -m "Update backend URL to Railway: $railwayUrl"
git push
Write-Host "✅ Code pushed to GitHub!" -ForegroundColor Green
Write-Host ""

# Step 6: Deploy Frontend to Netlify
Write-Host "Step 6: Deploy Frontend to Netlify" -ForegroundColor Cyan
Write-Host "─" * 70 -ForegroundColor Gray
Write-Host ""
Write-Host "Follow these steps to deploy your frontend to Netlify:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Go to https://app.netlify.com" -ForegroundColor Green
Write-Host "2. Click 'Add new site' > 'Import an existing project'"
Write-Host "3. Select GitHub"
Write-Host "4. Authorize Netlify with GitHub"
Write-Host "5. Select your 'taskearn' repository"
Write-Host "6. Settings:"
Write-Host "   - Build command: (leave empty)"
Write-Host "   - Publish directory: . (dot, meaning current directory)"
Write-Host "7. Click 'Deploy site'"
Write-Host ""
Write-Host "8. Wait for deployment (usually 1-2 minutes)"
Write-Host "9. Netlify will give you a URL like: https://your-site.netlify.app"
Write-Host ""

$netlifyUrl = Read-Host "Enter your Netlify frontend URL (e.g., https://taskearn-app.netlify.app)"

if (-not $netlifyUrl.StartsWith("https://")) {
    $netlifyUrl = "https://" + $netlifyUrl
}

Write-Host ""
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    ✅ DEPLOYMENT COMPLETE!                            ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "Your TaskEarn app is now live!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Frontend URL: $netlifyUrl" -ForegroundColor Green
Write-Host "Backend URL:  $railwayUrl" -ForegroundColor Green
Write-Host ""

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""
Write-Host "1. ✅ Visit your Netlify URL to test the app"
Write-Host "2. ✅ Create an account"
Write-Host "3. ✅ Try creating a task"
Write-Host "4. ✅ Check browser console for any errors (Press F12)"
Write-Host ""
Write-Host "If you see errors:" -ForegroundColor Yellow
Write-Host "• Check Railway dashboard for backend logs"
Write-Host "• Verify SECRET_KEY is set in Railway variables"
Write-Host "• Check Netlify deployment details"
Write-Host ""
Write-Host "Troubleshooting URLs:" -ForegroundColor Yellow
Write-Host "• Railway Dashboard: https://railway.app/dashboard"
Write-Host "• Netlify Dashboard: https://app.netlify.com"
Write-Host ""
