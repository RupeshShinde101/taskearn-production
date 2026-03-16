# TaskEarn API Connection Test & Fix Script
# Run this in PowerShell to diagnose and fix API connection issues

Write-Host "$("`n" * 1)" -ForegroundColor Green
Write-Host "╔════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       TaskEarn API Connection - Diagnostic & Fix Tool (Windows)        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Function to test URL
function Test-ApiUrl {
    param(
        [string]$Url,
        [string]$Description
    )
    
    Write-Host "Testing: $Description" -ForegroundColor Yellow
    Write-Host "URL: $Url" -ForegroundColor Gray
    
    try {
        $response = Invoke-WebRequest -Uri "$Url/api/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ SUCCESS: Backend is reachable!" -ForegroundColor Green
            Write-Host "Response: $($response.Content)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠️ WARNING: Got status code $($response.StatusCode)" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "❌ FAILED: $($_.Exception.Message.Split([System.Environment]::NewLine)[0])" -ForegroundColor Red
        return $false
    }
}

# Menu
Write-Host "Choose what you want to do:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1) Test API Connectivity (Check if servers are responding)" -ForegroundColor White
Write-Host "2) Start Local Backend (For development testing)" -ForegroundColor White
Write-Host "3) Run Full Diagnostic (Test everything)" -ForegroundColor White
Write-Host "4) Generate Secret Key (For Railway deployment)" -ForegroundColor White
Write-Host "5) Open Diagnostic Page (For production testing)" -ForegroundColor White
Write-Host "0) Exit" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Enter your choice (0-5)"

switch ($choice) {
    "1" {
        # Test connectivity
        Write-Host "`n" -ForegroundColor Green
        Write-Host "🌐 API CONNECTIVITY TEST" -ForegroundColor Cyan
        Write-Host "═════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        
        $tests = @(
            @{ Url = "http://localhost:5000"; Description = "Local Backend (Development)" },
            @{ Url = "https://taskearn-production-production.up.railway.app"; Description = "Railway Production Backend" }
        )
        
        $passed = 0
        $failed = 0
        
        foreach ($test in $tests) {
            if (Test-ApiUrl -Url $test.Url -Description $test.Description) {
                $passed++
            } else {
                $failed++
            }
            Write-Host ""
        }
        
        Write-Host "═════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "Results: ✅ $passed passed, ❌ $failed failed" -ForegroundColor Cyan
        
        if ($failed -gt 0) {
            Write-Host ""
            Write-Host "Next Steps:" -ForegroundColor Yellow
            Write-Host "• If local backend failed: Run 'python backend/run.py' from project directory" -ForegroundColor Gray
            Write-Host "• If Railway failed: Check that you have deployed backend to Railway" -ForegroundColor Gray
            Write-Host "• Update BACKEND_URL in Netlify dashboard with your actual backend URL" -ForegroundColor Gray
        }
    }
    
    "2" {
        # Start backend
        Write-Host "`n" -ForegroundColor Green
        Write-Host "🚀 STARTING LOCAL BACKEND" -ForegroundColor Cyan
        Write-Host "═════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "This will start the backend server on http://localhost:5000" -ForegroundColor Gray
        Write-Host ""
        
        if (Test-Path "backend/run.py") {
            Write-Host "Starting backend..." -ForegroundColor Yellow
            Set-Location backend
            & python run.py
        } else {
            Write-Host "❌ ERROR: backend/run.py not found" -ForegroundColor Red
            Write-Host "Make sure you're in the project root directory" -ForegroundColor Red
        }
    }
    
    "3" {
        # Full diagnostic
        Write-Host "`n" -ForegroundColor Green
        Write-Host "🔍 FULL DIAGNOSTIC" -ForegroundColor Cyan
        Write-Host "═════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Checking Python installation..." -ForegroundColor Yellow
        try {
            $pyVersion = & python --version 2>&1
            Write-Host "✅ Python: $pyVersion" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Python not found. Install Python 3.11+" -ForegroundColor Red
        }
        
        Write-Host ""
        Write-Host "Checking project files..." -ForegroundColor Yellow
        $files = @(
            "index.html",
            "backend/server.py",
            "backend/run.py",
            "netlify.toml"
        )
        foreach ($file in $files) {
            if (Test-Path $file) {
                Write-Host "✅ $file" -ForegroundColor Green
            } else {
                Write-Host "❌ $file - NOT FOUND" -ForegroundColor Red
            }
        }
        
        Write-Host ""
        Write-Host "Running Python diagnostics..." -ForegroundColor Yellow
        if (Test-Path "api_diagnostic_tool.py") {
            & python api_diagnostic_tool.py
        } else {
            Write-Host "⚠️ Python diagnostic tool not found" -ForegroundColor Yellow
        }
    }
    
    "4" {
        # Generate secret key
        Write-Host "`n" -ForegroundColor Green
        Write-Host "🔐 GENERATE SECRET KEY FOR RAILWAY" -ForegroundColor Cyan
        Write-Host "═════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Generating a secure secret key..." -ForegroundColor Yellow
        Write-Host ""
        
        try {
            $secretKey = & python -c "import secrets; print(secrets.token_urlsafe(32))"
            Write-Host "Your SECRET_KEY (copy this to Netlify environment variables):" -ForegroundColor Green
            Write-Host "$secretKey" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Steps:" -ForegroundColor Yellow
            Write-Host "1. Copy the key above" -ForegroundColor Gray
            Write-Host "2. Go to https://app.netlify.com > Your Site > Settings" -ForegroundColor Gray
            Write-Host "3. Environment variables > Add new" -ForegroundColor Gray
            Write-Host "4. Name: SECRET_KEY" -ForegroundColor Gray
            Write-Host "5. Value: Paste your key" -ForegroundColor Gray
        }
        catch {
            Write-Host "❌ Failed to generate key. Make sure Python is installed." -ForegroundColor Red
        }
    }
    
    "5" {
        # Open diagnostic page
        Write-Host "`n" -ForegroundColor Green
        Write-Host "🌐 DIAGNOSTIC PAGE" -ForegroundColor Cyan
        Write-Host "═════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "The diagnostic page is available at:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Local: http://localhost:5500/api-diagnostic-page.html" -ForegroundColor Cyan
        Write-Host "Production: your-netlify-site.com/api-diagnostic-page.html" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Starting live server..." -ForegroundColor Gray
        Write-Host ""
        
        if (Get-Command "live-server" -ErrorAction SilentlyContinue) {
            & live-server --port=5500 --open=api-diagnostic-page.html
        } else {
            Write-Host "Live Server not installed. Install with: npm install -g live-server" -ForegroundColor Yellow
            Write-Host "For now, just open: api-diagnostic-page.html in your browser" -ForegroundColor Gray
        }
    }
    
    "0" {
        Write-Host ""
        Write-Host "Goodbye! 👋" -ForegroundColor Green
        exit
    }
    
    default {
        Write-Host "Invalid choice. Please try again." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "═════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
