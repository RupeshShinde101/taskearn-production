#!/bin/bash
# TaskEarn Production Deployment Script
# Deploys backend to Railway and frontend to Netlify
# This script should be run from the project root directory

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║          TaskEarn - Production Deployment Script                      ║"
echo "║    Deploy Backend to Railway + Frontend to Netlify                    ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 1: Check if Git is initialized
echo -e "${BLUE}Step 1: Checking Git repository...${NC}"
if [ ! -d .git ]; then
    echo -e "${YELLOW}Git not initialized. Initializing now...${NC}"
    git init
    echo -e "${GREEN}✅ Git initialized${NC}"
else
    echo -e "${GREEN}✅ Git repository exists${NC}"
fi
echo ""

# Step 2: Add all files to Git
echo -e "${BLUE}Step 2: Staging files for deployment...${NC}"
git add .
git commit -m "Production deployment - Backend to Railway, Frontend to Netlify"
echo -e "${GREEN}✅ Files staged${NC}"
echo ""

# Step 3: Check for GitHub remote
echo -e "${BLUE}Step 3: Checking GitHub remote...${NC}"
if ! git config --get remote.origin.url > /dev/null; then
    echo -e "${YELLOW}GitHub remote not configured.${NC}"
    echo ""
    echo "You need to:"
    echo "1. Create a GitHub repository at https://github.com/new"
    echo "2. Copy the HTTPS URL"
    echo "3. Run:"
    echo "   git remote add origin https://github.com/YOUR_USERNAME/taskearn.git"
    echo "   git branch -M main"
    echo "   git push -u origin main"
    echo ""
    read -p "Press Enter once you've done this..."
else
    GITHUB_URL=$(git config --get remote.origin.url)
    echo -e "${GREEN}✅ GitHub remote: $GITHUB_URL${NC}"
    
    # Push to GitHub
    echo ""
    echo -e "${BLUE}Pushing to GitHub...${NC}"
    git push -u origin main
    echo -e "${GREEN}✅ Code pushed to GitHub${NC}"
fi
echo ""

# Step 4: Deploy Backend to Railway
echo -e "${BLUE}Step 4: Deploying Backend to Railway...${NC}"
echo ""
echo "Follow these steps:"
echo "1. Go to https://railway.app"
echo "2. Sign in or create account"
echo "3. Create new project"
echo "4. Select 'Deploy from GitHub'"
echo "5. Choose your 'taskearn' repository"
echo "6. Set root directory to: backend"
echo "7. Wait for deployment"
echo "8. Go to Settings → Variables and add:"
echo "   - SECRET_KEY = (generate with 'python -c \"import secrets; print(secrets.token_urlsafe(32))\"')"
echo "   - FLASK_ENV = production"
echo "   - DEBUG = False"
echo "9. Copy your deployed URL (e.g., https://taskearn-api-xyz.up.railway.app)"
echo ""
read -p "Enter your Railway backend URL (e.g., https://taskearn-api-xyz.up.railway.app): " RAILWAY_URL

# Step 5: Update frontend configuration
echo ""
echo -e "${BLUE}Step 5: Updating frontend configuration...${NC}"

# Update index.html
sed -i "s|http://localhost:5000/api|${RAILWAY_URL}/api|g" index.html

# Update admin.html
sed -i "s|http://localhost:5000/api|${RAILWAY_URL}/api|g" admin.html

# Update chat.html
sed -i "s|http://localhost:5000/api|${RAILWAY_URL}/api|g" chat.html

echo -e "${GREEN}✅ Frontend updated with Railway URL${NC}"
echo ""

# Step 6: Deploy Frontend to Netlify
echo -e "${BLUE}Step 6: Deploying Frontend to Netlify...${NC}"
echo ""
echo "Follow these steps:"
echo "1. Go to https://app.netlify.com"
echo "2. Click 'Add new site' > 'Import an existing project'"
echo "3. Connect your GitHub account"
echo "4. Select 'taskearn' repository"
echo "5. Settings:"
echo "   - Build command: (leave empty - static site)"
echo "   - Publish directory: . (current directory)"
echo "6. Click Deploy"
echo "7. Wait for deployment (usually 1-2 minutes)"
echo "8. Netlify gives you a URL like: https://your-site.netlify.app"
echo ""
read -p "Enter your Netlify URL once deployed (e.g., https://taskearn-app.netlify.app): " NETLIFY_URL

echo ""
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo -e "${BLUE}Your app is now live:${NC}"
echo "Frontend: ${NETLIFY_URL}"
echo "Backend: ${RAILWAY_URL}"
echo ""
echo "Next steps:"
echo "• Visit your Netlify URL and test the app"
echo "• Create an account and verify it works"
echo "• Check backend logs in Railway dashboard if issues"
echo ""
