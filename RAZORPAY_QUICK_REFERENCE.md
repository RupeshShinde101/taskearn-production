# 📱 RAZORPAY QUICK REFERENCE

## 🔑 Essential Configuration

### .env File
```bash
# Get these from https://dashboard.razorpay.com/app/settings/api-keys
RAZORPAY_KEY_ID=rzp_test_XXXXX        # Copy exact value
RAZORPAY_KEY_SECRET=XXXXX             # Keep this SECRET!
```

### Verify in Code
```python
# backend/config.py should have:
RAZORPAY_KEY_ID = os.getenv('RAZORPAY_KEY_ID')
RAZORPAY_KEY_SECRET = os.getenv('RAZORPAY_KEY_SECRET')
```

---

## 💰 Payment Amount Formula

```javascript
// Frontend Calculation
taskAmount = 500                       // ₹500
commission = Math.ceil(taskAmount * 0.10)  // ₹50
totalPayable = taskAmount + commission     // ₹550

// Razorpay Amount (in paise)
razorpayAmount = totalPayable * 100   // 55000 paise
```

---

## 🔄 Payment Flow Steps

```
1. TASK POSTER CLICKS "Pay Now"
   ↓
2. Frontend calls: POST /api/payments/create-order
   ↓
3. Backend returns: orderId, amount, key
   ↓
4. Frontend opens: Razorpay checkout window
   ↓
5. POSTER PAYS via Razorpay
   ↓
6. Frontend calls: POST /api/payments/verify
   ↓
7. Backend verifies signature
   ↓
8. Backend splits payment:
   - Helper: 90% → Wallet
   - Company: 10% → Account
   ↓
9. Task status updated to "paid"
   ↓
10. SUCCESS confirmed to poster
```

---

## 📊 Commission Split Example

### For ₹500 Task

```
┌─────── Poster Pays ─────────┐
│                              │
│ Task Amount:    ₹500        │
│ Commission:     ₹50  (10%)  │
│ ─────────────────────        │
│ Total:          ₹550        │
└──────────────────────────────┘
         ↓
    Payment Split
         ↓
┌──── Helper Receives ────┐  ┌─── Company Gets ───┐
│ Amount: ₹500 (90%)      │  │ Commission: ₹50   │
│ To: helper.wallet       │  │ To: company acc.   │
└─────────────────────────┘  └────────────────────┘
```

---

## 🎯 Key API Endpoints

### Create Order
```
POST /api/payments/create-order
Body: { taskId, amount, helperId, description }
Returns: { orderId, amount, currency, key }
```

### Verify Payment
```
POST /api/payments/verify
Body: { razorpayPaymentId, razorpayOrderId, razorpaySignature, taskId, helperId }
Returns: { success, helperCredit, platformCommission }
```

### Get History
```
GET /api/payments/history
Returns: { made[], received[] }
```

---

## 🧪 Test Payment Cards

| Type | Card Number | Expiry | CVV |
|------|-------------|--------|-----|
| ✅ Success | 4111 1111 1111 1111 | Any Future | Any 3 |
| ❌ Fail | 4000 0000 0000 0002 | Any Future | Any 3 |

---

## 📝 Frontend Function Calls

### Start Payment
```javascript
// Task poster clicks "Pay Now"
payForCompletedTask(taskId)
```

### Inside the Function
```javascript
// Finds task
const task = myPostedTasks.find(t => t.id === taskId)

// Shows confirmation
alert(`Pay ₹${task.price + Math.ceil(task.price * 0.10)}?`)

// Initiates payment
initiateRazorpayPayment(task)
```

### Razorpay Opens
```javascript
// Automatically happens in initiateRazorpayPayment()
new Razorpay(options).open()
```

### After Payment
```javascript
// Automatically called on success
paymentSuccessHandler(task, razorpayResponse)

// Which calls
POST /api/payments/verify
// Then shows
showPaymentSuccessModal(task, verifyData)
```

---

## 🗄️ Database Tables

### payments
```sql
- id: Payment record ID
- task_id: Which task
- poster_id: Who paid
- helper_id: Who receives
- razorpay_payment_id: Razorpay ID
- amount: Full amount
- platform_fee: 10% commission
- status: 'paid' or 'failed'
```

### wallet
```sql
- user_id: Wallet owner
- balance: Current amount
```

### wallet_transactions
```sql
- user_id: Who got money
- amount: How much
- type: 'earned' (for helper) or 'commission' (for company)
- payment_id: Links to payments table
- metadata: Contains task details
```

---

## ✅ Verification Checklist

### Before First Payment
- [ ] .env has RAZORPAY_KEY_ID
- [ ] .env has RAZORPAY_KEY_SECRET
- [ ] Backend restarted after .env change
- [ ] Test keys are used (rzp_test_)

### After Payment Completes
- [ ] Task shows status "Paid ✓"
- [ ] Helper wallet increased by 90%
- [ ] Company wallet increased by 10%
- [ ] Payment in history for both users
- [ ] Transaction in wallet_transactions table

---

## 🐛 Common Issues & Fixes

| Problem | Check | Fix |
|---------|-------|-----|
| Razorpay not opening | Is RAZORPAY_KEY_ID set? | Add to .env and restart |
| Wallet not updating | Is database connected? | Check DB connection string |
| Signature fails | Is SECRET correct? | Regenerate from Razorpay |
| Amount wrong | Is commission 10%? | Check calculation in verify |

---

## 📞 Backend Endpoints Summary

```
✓ POST   /api/payments/create-order   (Create Razorpay order)
✓ POST   /api/payments/verify         (Verify & split payment)
✓ GET    /api/payments/{id}           (Get payment status)
✓ GET    /api/payments/history        (Get payment history)
✓ POST   /api/payments/webhook        (Razorpay events)
```

---

## 🚀 Deployment Steps

```bash
1. Get production keys from Razorpay
2. Update .env with rzp_live_* keys
3. Configure webhook URL
4. Restart backend
5. Test payment
6. Monitor transactions
```

---

## 📋 What Happens at Each Stage

### Creation (create-order)
```
Backend generates:
├─ Razorpay Order
├─ Stores in DB
└─ Returns order ID to frontend

Frontend:
├─ Gets order ID
├─ Prepares Razorpay options
└─ Opens payment window
```

### Payment (user enters card)
```
Razorpay processes:
├─ Validates card
├─ Charges amount
└─ Returns payment ID
```

### Verification (verify endpoint)
```
Backend:
├─ Checks signature
├─ Splits payment (90/10)
├─ Updates both wallets
├─ Logs transactions
├─ Updates task status
└─ Returns success

Frontend:
├─ Shows success modal
├─ Updates UI
└─ Redirects to dashboard
```

---

## 💡 Pro Tips

**For Development:**
- Always use test keys (rzp_test_)
- Use test cards for payment
- Check backend logs for errors
- Use browser DevTools to inspect API calls

**For Production:**
- Use live keys (rzp_live_) only in production
- Enable HTTPS for webhook
- Set up monitoring and alerts
- Regular backup of payment database

---

## 🎓 Understanding the Split

```
Why 90/10?
- Helper does the work → Gets 90% (₹450)
- Company provides platform → Gets 10% (₹50)

Multiple Tasks Example:
Task 1: ₹500 → Helper: ₹450, Company: ₹50
Task 2: ₹1000 → Helper: ₹900, Company: ₹100
Task 3: ₹250 → Helper: ₹225, Company: ₹25

Monthly Example:
Total Earnings (Helpers): ₹4500
Total Commission (Company): ₹500
Total Payments: ₹5000
```

---

## 🔒 Security Reminders

```
DO:
✓ Keep RAZORPAY_KEY_SECRET in .env only
✓ Verify signatures on backend
✓ Use HTTPS for production
✓ Log all transactions
✓ Monitor for fraud

DON'T:
✗ Log SECRET in console
✗ Share API keys
✗ Expose SECRET in frontend
✗ Trust frontend amount (always verify)
✗ Skip signature verification
```

---

## 📞 Need Help?

**Documentation:**
- Full Guide: See RAZORPAY_INTEGRATION.md
- Setup: See RAZORPAY_SETUP_CHECKLIST.md

**Razorpay Support:**
- Website: https://razorpay.com/support
- Docs: https://razorpay.com/docs
- Email: support@razorpay.com

**In Code:**
```python
# File: backend/server.py - Lines 2140-2410
# API endpoints with full implementation
```

```javascript
// File: app.js - Lines 2470-2800
// Frontend payment functions
```

---

**Quick Status**: ✅ Ready to configure and test
