// ╔══════════════════════════════════════════════════════════════════╗
// ║         📧 EMAILJS CONFIGURATION FOR REAL OTP                    ║
// ║         FREE - 200 emails per month!                             ║
// ╚══════════════════════════════════════════════════════════════════╝

// ═══════════════════════════════════════════════════════════════════
// STEP 1: Create EmailJS Account
// ═══════════════════════════════════════════════════════════════════
// 1. Go to: https://www.emailjs.com/
// 2. Click "Sign Up Free"
// 3. Verify your email

// ═══════════════════════════════════════════════════════════════════
// STEP 2: Add Email Service
// ═══════════════════════════════════════════════════════════════════
// 1. Go to: Email Services → Add New Service
// 2. Select "Gmail" (easiest) or your preferred provider
// 3. Click "Connect Account" → Sign in with your Gmail
// 4. Name it: "TaskEarn Email Service"
// 5. Copy the SERVICE ID (e.g., "service_abc123")

// ═══════════════════════════════════════════════════════════════════
// STEP 3: Create Email Template
// ═══════════════════════════════════════════════════════════════════
// 1. Go to: Email Templates → Create New Template
// 2. Set Template Name: "OTP Template"
// 3. Set Subject: "🔐 TaskEarn Password Reset OTP: {{otp_code}}"
// 4. Set Content (copy this exactly):
/*
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   
   Hi {{to_name}},
   
   You requested to reset your password for your TaskEarn account.
   
   Your One-Time Password (OTP) is:
   
   ┌─────────────────────────────┐
   │     {{otp_code}}            │
   └─────────────────────────────┘
   
   This code is valid for {{validity}}.
   
   If you didn't request this, please ignore this email.
   
   Best regards,
   {{app_name}} Team
   
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
*/
// 5. Set "To Email": {{to_email}}
// 6. Save Template
// 7. Copy the TEMPLATE ID (e.g., "template_xyz789")

// ═══════════════════════════════════════════════════════════════════
// STEP 4: Get Your Public Key
// ═══════════════════════════════════════════════════════════════════
// 1. Go to: Account → API Keys
// 2. Copy your Public Key (e.g., "user_ABC123XYZ")

// ═══════════════════════════════════════════════════════════════════
// STEP 5: Update Configuration in app.js
// ═══════════════════════════════════════════════════════════════════
// Find the EMAILJS_CONFIG object in app.js and replace the values:

/*
const EMAILJS_CONFIG = {
    PUBLIC_KEY: 'your_public_key_here',    // From Step 4
    SERVICE_ID: 'service_abc123',           // From Step 2
    TEMPLATE_ID: 'template_xyz789'          // From Step 3
};
*/

// ═══════════════════════════════════════════════════════════════════
// THAT'S IT! Your Email OTP will now work!
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
// 📱 FOR SMS OTP (OPTIONAL - Requires Backend)
// ═══════════════════════════════════════════════════════════════════
// SMS requires a backend server for security. Options:
// 
// Option 1: Twilio (Most Popular)
//   - Sign up: https://www.twilio.com/
//   - Free trial includes $15 credit
//   - Requires Node.js/Python backend
//
// Option 2: MSG91 (India Focused)
//   - Sign up: https://msg91.com/
//   - Good for Indian phone numbers
//   - Requires backend integration
//
// Option 3: Firebase Phone Auth
//   - Sign up: https://firebase.google.com/
//   - Free tier available
//   - Can work from frontend with proper setup
//
// For backend implementation, create a simple API endpoint that:
// 1. Receives phone number and OTP
// 2. Calls Twilio/MSG91 API with your secret keys
// 3. Returns success/failure status

console.log('📧 EmailJS Config loaded. See emailjs-config.js for setup instructions.');
