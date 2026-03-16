# 💳 Razorpay Payment Integration - Complete Setup

## Overview

Implemented **end-to-end Razorpay payment integration** with automatic commission split:
- Task posters pay via Razorpay
- 90% goes to helper's wallet
- 10% goes to company account
- All payments tracked and verified

---

## Payment Flow

```
Task Poster Initiates Payment
        ↓
Opens Razorpay Payment Window
        ↓
Enters Card/UPI Details
        ↓
Payment Authorized
        ↓
Backend Verifies Signature
        ↓
Split Payment:
├─ Helper: 90% → Wallet
└─ Company: 10% → Account
        ↓
Task Marked as "Paid"
        ↓
Success Confirmation
```

---

## Backend Endpoints

### 1. Create Payment Order
```
POST /api/payments/create-order

Headers:
- Authorization: Bearer {token}
- Content-Type: application/json

Body:
{
    "taskId": 123,
    "amount": 50000,          // in paise (₹500)
    "helperId": 45,
    "description": "Payment for Website Redesign"
}

Response:
{
    "success": true,
    "orderId": "order_XXXXX",
    "amount": 50000,
    "currency": "INR",
    "key": "rzp_live_XXXXX"
}
```

### 2. Verify Payment
```
POST /api/payments/verify

Headers:
- Authorization: Bearer {token}
- Content-Type: application/json

Body:
{
    "razorpayPaymentId": "pay_XXXXX",
    "razorpayOrderId": "order_XXXXX",
    "razorpaySignature": "signature_XXXXX",
    "taskId": 123,
    "helperId": 45
}

Response:
{
    "success": true,
    "message": "Payment verified and completed successfully",
    "paymentId": "pay_XXXXX",
    "helperCredit": 450,        // ₹450 (90%)
    "platformCommission": 50    // ₹50 (10%)
    "taskId": 123
}
```

### 3. Get Payment Status
```
GET /api/payments/{paymentId}

Headers:
- Authorization: Bearer {token}

Response:
{
    "success": true,
    "payment": {
        "id": 1,
        "taskId": 123,
        "amount": 500,
        "platformFee": 50,
        "status": "paid",
        "createdAt": "2024-01-15T10:30:00Z",
        "verifiedAt": "2024-01-15T10:32:00Z",
        "razorpayPaymentId": "pay_XXXXX",
        "razorpayOrderId": "order_XXXXX"
    }
}
```

### 4. Payment History
```
GET /api/payments/history

Headers:
- Authorization: Bearer {token}

Response:
{
    "success": true,
    "made": [
        {
            "id": 1,
            "taskId": 123,
            "amount": 500,
            "status": "paid",
            "createdAt": "2024-01-15T10:30:00Z",
            "type": "made"
        }
    ],
    "received": [
        {
            "id": 2,
            "taskId": 456,
            "amount": 450,              // Helper receives 90%
            "platformFee": 50,
            "status": "paid",
            "createdAt": "2024-01-15T11:30:00Z",
            "type": "received"
        }
    ]
}
```

### 5. Webhook Handler
```
POST /api/payments/webhook

Handles Events:
- payment.authorized → Mark as captured
- payment.captured → Update status
- payment.failed → Mark as failed

Headers:
- Content-Type: application/json

Body (Razorpay sends):
{
    "event": "payment.captured",
    "payload": {
        "payment": {
            "entity": {
                "id": "pay_XXXXX",
                "order_id": "order_XXXXX",
                ...
            }
        }
    }
}
```

---

## Frontend Integration

### Payment Initiation
```javascript
// 1. Trigger from Posted Tasks
payForCompletedTask(taskId)

// 2. Initiates Razorpay
initiateRazorpayPayment(task)

// 3. Opens Payment Window
{
    key: "RAZORPAY_KEY_ID",
    amount: 55000,              // ₹550 (task + commission)
    order_id: "order_XXXXX",
    handler: paymentSuccessHandler
}

// 4. Verifies on Backend
paymentSuccessHandler()

// 5. Shows Success Modal
showPaymentSuccessModal()
```

### Frontend Functions

```javascript
// Initiate payment for a task
payForCompletedTask(taskId)

// Open Razorpay payment window
initiateRazorpayPayment(task)

// Handle payment success
paymentSuccessHandler(task, response)

// Show success confirmation
showPaymentSuccessModal(task, verifyData)
```

---

## Database Schema

### Payments Table
```
CREATE TABLE payments (
    id INTEGER PRIMARY KEY,
    task_id INTEGER,
    poster_id INTEGER,              // Who paid
    helper_id INTEGER,              // Who receives (90%)
    razorpay_order_id VARCHAR(255),
    razorpay_payment_id VARCHAR(255),
    razorpay_signature VARCHAR(255),
    amount DECIMAL(10,2),           // Full amount
    platform_fee DECIMAL(10,2),     // 10% commission
    currency VARCHAR(10),           // 'INR'
    status VARCHAR(20),             // 'pending', 'paid', 'failed'
    created_at TIMESTAMP,
    verified_at TIMESTAMP,
    paid_at TIMESTAMP
)
```

### Wallet Transactions (Updated)
```
Automatically created:

For Helper:
- Type: 'earned'
- Amount: platform_fee * 0.9
- Description: "Payment for task: {taskId}"

For Company:
- Type: 'commission'
- Amount: platform_fee * 0.1
- Description: "Platform commission from task {taskId}"

metadata: {
    taskId, helperId, amount, platformFee, razorpayPaymentId
}
```

---

## Commission Model

### For ₹500 Task
```
Task Amount:              ₹500
Platform Commission:      ₹50 (10%)
Total Task Poster Pays:   ₹550

Payment Split:
├─ Helper Receives:       ₹500 (90%) → To wallet
└─ Company Commission:    ₹50 (10%) → To account

Calculation:
commission = Math.ceil(amount * 0.10)
helper_amount = amount - commission
```

### Multiple Transactions
```
Task 1 (₹500):
├─ Helper: ₹500
└─ Company: ₹50

Task 2 (₹1000):
├─ Helper: ₹900
└─ Company: ₹100

Task 3 (₹750):
├─ Helper: ₹675
└─ Company: ₹75

TOTAL:
Helper Earned:          ₹2075
Company Commission:     ₹225
```

---

## Environment Variables Required

```
# Razorpay Keys (Get from https://dashboard.razorpay.com/)
RAZORPAY_KEY_ID=rzp_live_XXXXX
RAZORPAY_KEY_SECRET=XXXXX

# Essential for webhook verification
# Keep SECRET safe - never expose in frontend
```

---

## User Journey - Task Poster

### Step 1: Complete Task
- Task marked as complete by helper
- Status changes to "pending_payment"

### Step 2: See Payment Screen
```
Posted Tasks
├─ Task: "Website Redesign"
│  ├─ Status: ⏳ Awaiting Payment
│  ├─ Helper completed task!
│  ├─ Task Amount: ₹500
│  ├─ Platform Fee (10%): ₹50
│  ├─ Total Payable: ₹550
│  └─ [Pay ₹550 Now] button
```

### Step 3: Click "Pay Now"
- Confirmation dialog shows breakdown
- Razorpay payment window opens

### Step 4: Payment Window
- User enters card/UPI details
- Razorpay processes payment
- Success or failure notification

### Step 5: Success
- Task marked as "Paid"
- Confirmation shows:
  - ✓ Payment successful
  - ✓ ₹500 sent to helper
  - ✓ ₹50 commission deducted

---

## User Journey - Helper

### Automatically Happens After Payment:
1. Wallet credited with ₹500
2. Transaction logged with payment details
3. Task status shows "Paid"
4. Amount appears in wallet history

### Wallet Update
```
Before Payment:
Balance: ₹1000

After Payment:
Balance: ₹1500
Transaction: Earned ₹500 from Task #123
```

---

## Security Features

### Payment Verification
```javascript
// Signature verification
const message = `${orderId}|${paymentId}`;
const expectedSig = hmac.sha256(message, SECRET_KEY);
if (expectedSig !== receivedSig) {
    // Payment rejected - signature mismatch
}
```

### Data Integrity
- Razorpay signature verified server-side
- Payment amount verified against order
- Helper ID verified belongs to acceptor
- Poster ID verified belongs to current user

### Error Handling
```
Invalid Signature     → ❌ Payment Rejected
Amount Mismatch       → ❌ Order Failed
User Mismatch         → ❌ Unauthorized
Missing Fields        → ❌ Invalid Request
Database Error        → ❌ Processing Failed
```

---

## Testing Guide

### Test Credentials
```
Razorpay Test Key-Pair available on:
https://dashboard.razorpay.com/app/settings/api-keys

Store in .env:
RAZORPAY_KEY_ID=rzp_test_XXXXX
RAZORPAY_KEY_SECRET=XXXXX
```

### Test Payment Cards
```
Success: 4111 1111 1111 1111
Failure: 4000 0000 0000 0002
```

### Test Flow
1. Post a task with ₹500
2. Accept as different user
3. Mark as complete
4. Click "Pay Now"
5. Use test card 4111 1111 1111 1111
6. Enter any expiry/CVV
7. Verify success screen
8. Check wallet updated

---

## Production Deployment

### Step 1: Get Production Keys
```
1. Log in to Razorpay Dashboard
2. Settings → API Keys
3. Copy "Key ID" and "Secret"
4. Keep SECRET confidential
```

### Step 2: Update Environment
```
RAZORPAY_KEY_ID=rzp_live_XXXXX
RAZORPAY_KEY_SECRET=XXXXX
```

### Step 3: Configure Webhook
```
Razorpay Dashboard → Settings → Webhooks
URL: https://yourdomain.com/api/payments/webhook
Events:
  - payment.authorized
  - payment.captured
  - payment.failed

Verify Signature: MUST ENABLE
```

### Step 4: Test Live
```
1. Use production keys in staging
2. Process test transactions
3. Verify wallet updates
4. Confirm commission tracking
5. Deploy to production
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Razorpay window not opening | Missing RAZORPAY_KEY_ID | Check config and .env |
| Payment verified but wallet not updated | Database connection failed | Check database connectivity |
| Signature verification failed | Old/corrupted SECRET | Regenerate keys in dashboard |
| Commission not traced | Wallet table issue | Check wallet_transactions logs |
| Payment stuck as "pending" | Webhook not firing | Verify webhook configuration |

---

## API Status Check

```bash
# Check payment status
GET /api/payments/history

# Verify payment
POST /api/payments/verify
{
    "razorpayPaymentId": "pay_...",
    ...
}

# Get single payment
GET /api/payments/{paymentId}
```

---

## Summary

✅ **Complete Razorpay Integration**
- Payment initiation from task poster
- Automatic payment verification
- Payment split (90% helper, 10% company)
- Transaction logging
- Webhook handling
- Error recovery

✅ **Frontend Integration**
- Razorpay script loaded
- Payment modal with breakdown
- Success/failure handling
- Wallet updates automatic

✅ **Backend APIs**
- Create order endpoint
- Verify signature endpoint
- Payment history endpoint
- Webhook receiver
- Transaction logging

✅ **Security**
- HMAC signature verification
- User authorization checks
- Amount validation
- Error handling

**Ready for production deployment!** 🚀
