# Wallet Amount Bug Fix - Deployment Guide

## Problem Summary

Users adding funds to their wallet were seeing incorrect amounts:
- When user added ₹10, wallet showed ₹0.10 (10 paise)
- When user added ₹100, wallet showed ₹1.00 (100 paise)
- **Root cause**: Paise/Rupees conversion inconsistency between frontend and backend

## Root Cause

### What Happened (Bug Timeline)
1. Frontend sent amount in **RUPEES** (10) to backend, NOT paise
2. Backend expected **PAISE** and divided by 100: 10 ÷ 100 = 0.1 rupees
3. Result: Wallet showed ₹0.10 instead of ₹10

### Example Flow (BUGGY)
```
User action: Add ₹10 to wallet
├─ Frontend: amount = 10 (rupees)
├─ Frontend sends: {amount: 10} to backend ❌ Should be 1000 (paise)
├─ Backend receives: 10
├─ Backend divides: 10 ÷ 100 = 0.1 rupees
└─ Result: ₹0.10 in wallet ❌
```

## Fixes Applied

### 1. Frontend Fix (wallet.html)
- **Line 1173**: Send `amount * 100` (paise) when creating order
- **Line 1222**: Send `amount * 100` (paise) when verifying payment
- **Current state**: ✅ CORRECT in code

### 2. Backend Defensive Fixes (server.py)

#### Order Creation Endpoint (create_wallet_topup_order)
- Added auto-detection: if amount < 1000 and >= 10, treat as rupees → multiply by 100
- Handles both old (buggy) and new (correct) code paths

#### Verification Endpoint (verify_wallet_topup)
- Added auto-detection: if amount < 1000 and >= 10, treat as rupees → multiply by 100
- Converted paise to rupees correctly: `credit_amount = amount / 100`
- Stores correction in database with full logging

### 3. Correction Tool (fix_wallet_amounts.py)
- Finds transactions with amounts < ₹10 (likely incorrect)
- Calculates the correct amount: `old_amount * 100`
- Applies correction and records adjustment transaction
- Interactive interface for user confirmation

## Deployment Checklist

### Step 1: Deploy Backend Changes
The following files have been updated:
- ✅ `backend/server.py` - Lines 3224-3232 and 3293-3305
  - Added defensive amount detection in both endpoints
  - Auto-corrects amounts that are in rupees instead of paise

### Step 2: Deploy Frontend Changes
- ✅ `wallet.html` - Lines 1173 and 1222
  - Already has correct `amount * 100` multiplication
  - Verify these lines are present on Railway

### Step 3: Deploy Correction Tool
- ✅ `fix_wallet_amounts.py` - Created
- Deploy to Railway for running corrections on individual user transactions

## How to Deploy to Railway

### Option A: Automatic Git Push
```bash
git add -A
git commit -m "Fix: Paise/Rupees conversion bug and add defensive code"
git push railway main
```

### Option B: Manual Upload
Upload these files to Railway:
1. `backend/server.py` (with defensive amount detection code)
2. `wallet.html` (ensure amount * 100 is present)
3. `fix_wallet_amounts.py` (for manual corrections)

## How to Correct User's Incorrect Transactions

### On Railway PostgreSQL:

1. **Connect to Railway PostgreSQL console**

2. **Run the correction script** (if deployed):
   ```bash
   python fix_wallet_amounts.py
   ```

3. **Manual correction** (if needed):
   ```sql
   -- Find incorrect transactions
   SELECT id, wallet_id, user_id, amount, created_at
   FROM wallet_transactions
   WHERE type = 'razorpay_topup' 
   AND amount > 0.1 AND amount < 10;
   
   -- Fix example: For Cbz Xp account (10 paise → 10 rupees)
   UPDATE wallet_transactions
   SET amount = 10
   WHERE id = <transaction_id>;
   
   UPDATE wallets
   SET balance = balance + 9.9,
       total_added = total_added + 9.9
   WHERE id = <wallet_id>;
   
   INSERT INTO wallet_transactions (
       wallet_id, user_id, type, amount, balance_after, description, created_at
   ) VALUES (
       <wallet_id>, '<user_id>', 'correction', 9.9, <new_balance>,
       'Correction for razorpay_topup bug', NOW()
   );
   ```

## Testing the Fix

### Test Case 1: Add ₹10 to Wallet
```
Expected: Wallet shows ₹10.00
Database: wallet_transactions shows amount = 10.0
With fix: Auto-detection converts if needed
```

### Test Case 2: Add ₹100 to Wallet
```
Expected: Wallet shows ₹100.00
Database: wallet_transactions shows amount = 100.0
With fix: Auto-detection converts if needed
```

### Test Case 3: Verify Razorpay Amount
```
Verification: Check in Railway logs
[WALLET] Amount (raw): <value>
[WALLET] Amount (after conversion): <corrected_value>
Should show paise value after auto-detection
```

## Monitoring

After deployment, monitor logs for:
- `⚠️ [WALLET] Amount appears to be in rupees, converting:` - Indicates defensive code is working
- `[WALLET] Amount (after conversion):` - Shows final amount being processed
- Transaction amounts should now be correct in database

## Rollback Plan

If issues occur:
1. Revert to previous server.py (removes defensive code but keeps working)
2. Revert wallet.html (removes amount * 100, goes back to buggy state)
3. Contact Razorpay support if payment amounts don't match

---

**Status**: ✅ All fixes applied locally  
**Next Step**: Deploy to Railway  
**Timeline**: Immediate (no data migration needed)  
**User Impact**: Fixes future deposits, corrects existing ones via script
