# Razorpay Webhook Configuration Guide

## 📋 Summary
This document provides step-by-step instructions for setting up Razorpay webhooks for your production payment system.

---

## 🚀 Quick Setup (5 minutes)

### Part 1: Razorpay Dashboard Configuration

1. **Open Razorpay Dashboard**
   - Go to https://dashboard.razorpay.com
   - Sign in with your account

2. **Navigate to Webhooks**
   - Click **Settings** (⚙️ gear icon)
   - Select **Webhooks** from left menu

3. **Create New Webhook**
   - Click **Add New Webhook**
   - Fill in the form:

   | Field | Value |
   |-------|-------|
   | **Webhook URL** | `https://taskearn-production-production.up.railway.app/api/payments/webhook` |
   | **Active** | ✅ Checked |
   | **Events** | See below |

4. **Select Events**
   - ✅ `payment.authorized`
   - ✅ `payment.failed`
   - ✅ `payment.captured`
   - ✅ `payment.disputes.created` (optional, for disputes)

5. **Create Webhook**
   - Click **Create Webhook** button
   - ✅ **IMPORTANT**: Copy the **Webhook Secret** (shown only once!)
   - Save it securely

---

### Part 2: Railway Environment Setup

1. **Open Railway Dashboard**
   - Go to https://railway.app
   - Select your project

2. **Add Environment Variable**
   - Go to **Deployments** tab
   - Click on your production deployment (taskearn-production)
   - Click **⚙️ Settings** → **Variables**

3. **Add Webhook Secret**
   - Click **New Variable**
   - **Key**: `RAZORPAY_WEBHOOK_SECRET`
   - **Value**: (Paste the webhook secret from Razorpay)
   - Click **Add**

4. **Auto-Redeploy**
   - Railway will automatically restart with the new environment variable
   - Check deployment logs: `🟢 Webhook signature verification enabled`

---

## ✅ Verification

### Check Webhook in Razorpay
1. Go back to Razorpay Dashboard → Settings → Webhooks
2. Find your webhook in the list
3. Click **View** to see event history
4. Make a test payment and check if webhook is triggered

### Check Backend Logs
1. Railway Dashboard → Your Deployment → Logs
2. Look for: `🟢 Webhook signature verified` (successful)
3. Or: `❌ Invalid webhook signature received` (signature mismatch)

### Test Webhook
**Option 1: Manual Test via Razorpay (Recommended)**
1. In Razorpay Webhooks list, click the **...** menu
2. Select **Redeliver** on a past event
3. Check Railway logs for webhook received

**Option 2: Test Payment Flow**
1. Create a test payment in your app
2. Complete payment with test card: `4111 1111 1111 1111`
3. Razorpay automatically sends webhook event
4. Check Railway logs for confirmation

---

## 🔐 Security Notes

### Signature Verification Enabled ✅
- Backend now verifies `X-Razorpay-Signature` header
- Uses HMAC-SHA256 algorithm
- Invalid signatures are rejected (401 Unauthorized)

### What the Backend Does:
1. Receives webhook from Razorpay
2. Verifies signature against webhook secret
3. Updates payment status in database
4. Updates task status to 'paid'
5. Logs transaction with ID
6. Responds with 200 OK

### Webhook Events Handled:
| Event | Action |
|-------|--------|
| `payment.captured` | ✅ Mark payment as captured, update task status |
| `payment.authorized` | ⏳ Payment authorized (waiting for capture) |
| `payment.failed` | ❌ Mark payment as failed, task remains pending |

---

## ⚠️ Common Issues & Solutions

### Issue: "Webhook Secret not configured"
**Solution**: 
- Go to Railway → Settings → Variables
- Add `RAZORPAY_WEBHOOK_SECRET` variable
- Wait for auto-redeploy (~1 minute)

### Issue: "Invalid webhook signature received"
**Solution**:
- Verify the webhook secret was copied correctly (no spaces)
- Make sure it matches exactly in Railway variables
- Delete and recreate webhook if needed

### Issue: Webhook not being called
**Solution**:
- Check if webhook URL is correct in Razorpay Dashboard
- Verify Railway deployment is running (check health endpoint)
- Make test payment and check Railway logs
- Razorpay has retry logic - wait up to 1 hour

### Issue: Payment status not updating in database
**Solution**:
- Check Railway logs for webhook received
- Verify database connection is working
- Restart deployment if needed
- Try re-delivering webhook from Razorpay Dashboard

---

## 📊 Webhook Event Flow Diagram

```
Customer makes payment
        ↓
Razorpay processes payment
        ↓
Razorpay sends webhook event
        ↓
Your backend receives POST to /api/payments/webhook
        ↓
Verify webhook signature (HMAC-SHA256)
        ↓
    ✅ Valid → Update database (payment status, task status)
    ❌ Invalid → Reject (401) and log error
        ↓
Respond 200 OK to Razorpay (webhook considered delivered)
```

---

## 📝 Testing Checklist

After setup, verify:
- [ ] Webhook URL is registered in Razorpay Dashboard
- [ ] Webhook Secret is stored in Railway environment variables
- [ ] Railway deployment shows green status
- [ ] Backend logs show "Webhook signature verified"
- [ ] Test payment completes without errors
- [ ] Payment status updates to 'paid' in database
- [ ] Task status updates to 'paid' in database
- [ ] No errors in Railway logs for webhook endpoint

---

## 🆘 Support

**If webhook isn't working:**
1. Check Railway logs for errors
2. Verify environment variable `RAZORPAY_WEBHOOK_SECRET` exists
3. Ensure Razorpay dashboard shows webhook as "Active"
4. Use Razorpay's "Redeliver" feature to test
5. Check database directly to verify payment record exists

**Backend Endpoint Code**: `backend/server.py` lines ~2719-2800
**Signature Verification**: Uses `hmac` + `sha256` algorithm
