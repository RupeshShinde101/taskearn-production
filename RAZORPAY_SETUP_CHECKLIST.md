# 🚀 RAZORPAY SETUP CHECKLIST

## Pre-Deployment Checklist

### ✅ Code Implementation
- [x] Backend payment endpoints created
- [x] Frontend payment integration added
- [x] Database schema updated (PostgreSQL & SQLite)
- [x] Payment split logic implemented (90/10)
- [x] Wallet transaction logging added
- [x] Signature verification implemented
- [x] Webhook handler created
- [x] Error handling added

### ⏳ Configuration Required

#### 1. Razorpay Credentials Setup
- [ ] Create Razorpay account at https://razorpay.com
- [ ] Get API keys from Dashboard → Settings → API Keys
- [ ] Copy "Key ID" (rzp_live_XXXXX or rzp_test_XXXXX)
- [ ] Copy "Secret Key" (keep this safe!)

#### 2. Environment File (.env)
```bash
# Add to your .env file:
RAZORPAY_KEY_ID=your_key_id_here
RAZORPAY_KEY_SECRET=your_secret_here
```

#### 3. Verify config.py reads these
```python
# Should contain:
RAZORPAY_KEY_ID = os.getenv('RAZORPAY_KEY_ID')
RAZORPAY_KEY_SECRET = os.getenv('RAZORPAY_KEY_SECRET')
```

---

## Development Testing

### Test Setup
- [ ] Use Razorpay **Test Keys** (rzp_test_...)
- [ ] Get test keys from same dashboard
- [ ] Add to .env for development

### Test Payment Cards
```
✅ Successful Payment:   4111 1111 1111 1111
❌ Failed Payment:       4000 0000 0000 0002
💳 Expires:              Any future date
🔐 CVV:                  Any 3 digits
```

### Test Flow - Step by Step

**1. Start Application**
```bash
# Backend
cd backend
python run.py

# Frontend (separate terminal)
# Open index.html in browser
```

**2. Create Test Scenario**
```
a. Sign up/Login as User A (Task Poster)
b. Post a task: "Website Design" - ₹500
c. Note Task ID (e.g., 123)

d. Sign up/Login as User B (Helper)
e. Accept the task
f. Mark task as "Complete"

f. Switch back to User A
g. Go to "Posted Tasks" section
```

**3. Verify Payment UI**
```
Expected to see:
✓ Task card with "Completed ✓"
✓ Status: "Awaiting Payment"
✓ Amount shown: ₹500
✓ Commission shown: ₹50 (10%)
✓ Total: ₹550
✓ [Pay ₹550 Now] button visible
```

**4. Initiate Payment**
```
a. Click [Pay ₹550 Now] button
b. Verify confirmation dialog shows:
   - Task Amount: ₹500
   - Commission: ₹50
   - Total to Pay: ₹550
c. Click "Confirm Payment"
```

**5. Razorpay Checkout**
```
Should see Razorpay payment window with:
✓ TaskEarn branding
✓ Amount: ₹550
✓ Task description visible
✓ Email pre-filled
✓ Phone pre-filled
```

**6. Process Test Payment**
```
a. Enter Card Number: 4111 1111 1111 1111
b. Enter Expiry: Any future date (e.g., 12/25)
c. Enter CVV: Any 3 digits (e.g., 123)
d. Click "Pay" or complete OTP (if required)
```

**7. Verify Payment Success**
```
Expected response:
✓ Payment verified message
✓ Success modal showing:
  - Task title
  - Payment amount: ₹500
  - Commission: ₹50
  - Helper will receive: ₹500
✓ [Continue to Dashboard] button
```

**8. Check Backend Verification**
```
Backend logs should show:
✓ POST /api/payments/verify called
✓ Signature verification: SUCCESS
✓ Payment split completed
✓ Helper wallet updated: +₹500
✓ Company wallet updated: +₹50
✓ Task status: paid
```

**9. Verify Task Poster View**
```
Posted Tasks should now show:
✓ Task status: "Paid ✓"
✓ Amount paid: ₹500
✓ No pay button (grayed out or hidden)
```

**10. Verify Helper Wallet**
```
Switch to User B (Helper)
Go to Wallet:
✓ Balance increased by ₹500
✓ Transaction shows:
  - "Earned ₹500 from Task: Website Design"
  - Payment ID: pay_XXXXX
  - Status: Completed
```

**11. Verify Payment History**
```
Task Poster (User A):
✓ Payment History shows:
  - Task: "Website Design"
  - Amount: ₹500
  - Commission: ₹50
  - Total Paid: ₹550
  - Status: "Paid"

Helper (User B):
✓ Earnings shows:
  - Task: "Website Design"
  - Earned: ₹500
  - Status: "Completed"
```

---

## Production Deployment Checklist

### Before Going Live

**1. Switch to Production Keys**
- [ ] Generate new API keys on Razorpay Production
- [ ] Keys should start with `rzp_live_` (not `rzp_test_`)
- [ ] Update .env with production keys
- [ ] Verify authentication works

**2. Database Backup**
- [ ] Backup PostgreSQL database
- [ ] Backup user data and wallets
- [ ] Backup completed tasks

**3. Configure Webhook (CRITICAL)**
```
Razorpay Dashboard → Settings → Webhooks

URL: https://yourdomain.com/api/payments/webhook

Events to enable:
☐ payment.authorized
☐ payment.captured
☐ payment.failed
☐ payment.disputed

Secret: Will be provided by Razorpay
```

**4. SSL/HTTPS**
- [ ] Ensure domain has valid SSL certificate
- [ ] All payment pages use HTTPS
- [ ] Webhook receiver on HTTPS

**5. Error Handling**
- [ ] Test payment failures
- [ ] Test network timeouts
- [ ] Test invalid signatures
- [ ] Verify error messages are shown to users

**6. Monitoring**
- [ ] Set up logging for all payment transactions
- [ ] Monitor payment failure rates
- [ ] Alert if webhook delivery fails
- [ ] Track commission calculations

**7. Testing with Real Money**
- [ ] Test 1-2 transactions with small amounts
- [ ] Verify both wallets updated correctly
- [ ] Verify commission calculated correctly
- [ ] Verify transaction emails sent

### Production Safety Checks

```python
# Before first production payment, verify:

1. RAZORPAY_KEY_ID contains "rzp_live_"
2. RAZORPAY_KEY_SECRET is set and non-empty
3. Webhook URL is publicly accessible
4. Database connection is to production DB
5. Payment logging captures all transactions
6. Email notifications working
```

---

## Troubleshooting

### Issue: Razorpay Window Not Opening
```
Cause: Missing or invalid Key ID

Fix:
1. Check config.py has RAZORPAY_KEY_ID set
2. Verify .env file has the key
3. Restart backend server
4. Check browser console for errors
```

### Issue: Payment Verified but No Wallet Update
```
Cause: Database connection issue

Fix:
1. Check database is running
2. Verify connection string in config.py
3. Check payments table has correct schema
4. Review backend logs for SQL errors
```

### Issue: Signature Verification Failed
```
Cause: Mismatched keys or corrupted secret

Fix:
1. Verify RAZORPAY_KEY_SECRET matches original
2. Regenerate keys from Razorpay dashboard
3. Update .env with new keys
4. Restart backend
```

### Issue: Webhook Not Triggering
```
Cause: Network or configuration issue

Fix:
1. Verify webhook URL is accessible
2. Check HTTPS is working
3. Verify firewall allows incoming webhooks
4. Test webhook manually from Razorpay dashboard
```

### Issue: Wrong Commission Amount
```
Cause: Calculation error or old code

Fix:
Review calculation in /api/payments/verify:
- Commission should be: amount * 0.10
- Helper gets: amount - commission
- Company gets: commission
```

---

## Quick Test Commands

### Test Razorpay Configuration
```bash
# Backend Python
python -c "
import config
print('Key:', config.RAZORPAY_KEY_ID)
print('Secret:', 'SET' if config.RAZORPAY_KEY_SECRET else 'NOT SET')
"
```

### Test Payment History
```bash
# Check payment was recorded
# Use Admin interface:
# 1. Admin panel → Payments
# 2. Filter by date
# 3. Verify split amounts
```

### Test Webhook
```bash
# Razorpay Dashboard → Settings → Webhooks
# Click webhook URL
# Click "Send Test Event"
# Verify backend receives it
```

---

## Post-Payment Verification

### What Should Happen
1. **Task Status**: Shows "Paid ✓"
2. **Task Poster**: Sees payment in history
3. **Helper**: Sees 90% amount in wallet
4. **Company**: Sees 10% commission in account
5. **Database**: Payments table has record
6. **Transactions**: Both wallet transactions recorded

### What to Check
```
Tasks Table:
- SELECT * FROM tasks WHERE id = {taskId}
- status should be: 'paid'

Payments Table:
- SELECT * FROM payments WHERE task_id = {taskId}
- status should be: 'paid'
- platform_fee should be: amount * 0.10

Wallet_Transactions:
- SELECT * FROM wallet_transactions WHERE payment_id = {paymentId}
- Should have 2 rows: one for helper, one for company
```

---

## Rollback Plan

If something goes wrong in production:

### Immediate Actions
1. [ ] Contact Razorpay support
2. [ ] Disable payment button (maintenance mode)
3. [ ] Review payment logs for errors
4. [ ] Check database integrity

### Rollback Steps
```
1. Stop accepting new payments
2. Document all affected transactions
3. Manually refund if needed via Razorpay dashboard
4. Revert to previous code version if needed
5. Fix issue in development
6. Re-test thoroughly
7. Deploy fixed version
8. Resume payments
```

---

## Success Criteria

✅ **Payment System Live When:**
- [x] Code deployed to production
- [ ] Razorpay keys configured
- [ ] Webhook configured and tested
- [ ] First test payment succeeds
- [ ] Helper wallet updated correctly
- [ ] Company commission tracked
- [ ] Payment history shows for both users
- [ ] Error handling working
- [ ] Monitoring and alerts set up

---

## Support Resources

**Razorpay Documentation**
- API Docs: https://razorpay.com/docs/api/basics/
- Payment Gateway: https://razorpay.com/docs/payments/
- Testing: https://razorpay.com/docs/payments/test-cards/
- Webhooks: https://razorpay.com/docs/webhooks/

**Contact**
- Razorpay Support: https://razorpay.com/support
- Email: support@razorpay.com
- Live Chat: Available on dashboard

---

## Next Steps

1. **Get Razorpay Account**: https://razorpay.com
2. **Generate Test Keys**: Dashboard → Settings → API Keys
3. **Update .env File** with keys
4. **Run Development Test** following "Test Flow"
5. **Generate Production Keys** when ready
6. **Configure Webhook** for production
7. **Deploy to Production**
8. **Monitor First Transactions**

---

**Status**: ✅ Ready for testing with test keys

**Version**: 1.0 - Razorpay Integration Complete
