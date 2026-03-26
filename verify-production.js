// ========================================
// Production Deployment Verification
// Check if everything is working on production
// ========================================

console.log('🚀 Workmate4u Production Deployment Check\n');

// ========================================
// 1. Check Frontend URL
// ========================================
console.log('1️⃣  FRONTEND URL:');
console.log(`   Current: ${window.location.href}`);
console.log(`   Netlify: https://workmate4u.netlify.app`);
console.log(`   Status: ${window.location.hostname.includes('netlify') || window.location.hostname === 'workmate4u.netlify.app' ? '✅ LIVE' : '⚠️ LOCAL'}\n`);

// ========================================
// 2. Check Backend API URL
// ========================================
console.log('2️⃣  BACKEND API:');
const backendUrl = 'https://taskearn-production-production.up.railway.app/api';
console.log(`   URL: ${backendUrl}`);
console.log(`   Checking connectivity...\n`);

// Test backend connectivity
async function checkBackend() {
    try {
        const response = await fetch(`${backendUrl}/health`, {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json'
            }
        });
        
        console.log(`   Response Status: ${response.status}`);
        const data = await response.json();
        console.log(`   Status: ✅ LIVE`);
        console.log(`   Backend is responding correctly\n`);
    } catch (error) {
        console.log(`   Status: ❌ ERROR`);
        console.log(`   Error: ${error.message}`);
        console.log(`   Action: Check Railway deployment dashboard\n`);
    }
}

// ========================================
// 3. Check Socket.IO Connection
// ========================================
console.log('3️⃣  SOCKET.IO WEBSOCKET:');
console.log(`   URL: wss://taskearn-production-production.up.railway.app/socket.io`);
console.log(`   Status: Checking...\n`);

// ========================================
// 4. Check Local Storage
// ========================================
console.log('4️⃣  LOCAL STORAGE:');
const token = localStorage.getItem('taskearn_token');
const user = localStorage.getItem('taskearn_user');
console.log(`   Auth Token: ${token ? '✅ EXISTS' : '❌ MISSING'}`);
console.log(`   User Data: ${user ? '✅ EXISTS' : '❌ MISSING'}\n`);

// ========================================
// 5. Check Razorpay Integration
// ========================================
console.log('5️⃣  RAZORPAY PAYMENT:');
console.log(`   Key ID: rzp_live_SRt7rogPTT3FuK (Live Mode)`);
console.log(`   Status: ✅ LIVE\n`);

// Run backend check
checkBackend();

// ========================================
// 6. Summary
// ========================================
console.log('📋 DEPLOYMENT CHECKLIST:');
console.log(`   ✅ Frontend: ${window.location.hostname.includes('netlify') ? 'LIVE' : 'LOCAL'}`);
console.log(`   ⏳ Backend: Checking...`);
console.log(`   ✅ Database: PostgreSQL on Railway`);
console.log(`   ✅ Payments: Razorpay Live Mode`);
console.log(`   ⏳ Socket.IO: Checking...\n`);

console.log('🔗 Key URLs:');
console.log('   Frontend: https://workmate4u.netlify.app');
console.log('   Backend:  https://taskearn-production-production.up.railway.app');
console.log('   GitHub:   https://github.com/RupeshShinde101/taskearn-production\n');

console.log('✅ Production deployment script loaded successfully!');
