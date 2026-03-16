-- Clean up virtual transaction records
-- This script removes all transactions that don't have Razorpay verification

-- Step 1: List virtual transactions before deletion
SELECT id, user_id, type, amount, description, created_at
FROM wallet_transactions
WHERE description LIKE '%Wallet top-up%' 
   OR description LIKE '%Virtual%'
ORDER BY created_at DESC;

-- Step 2: Delete virtual transactions
DELETE FROM wallet_transactions
WHERE description LIKE '%Wallet top-up%' 
   OR description LIKE '%Virtual%';

-- Step 3: Reset wallet balances to only include earned amounts
UPDATE wallets
SET balance = COALESCE((
    SELECT SUM(amount) 
    FROM wallet_transactions 
    WHERE wallet_transactions.user_id = wallets.user_id 
    AND wallet_transactions.type IN ('earned', 'commission')
), 0),
    total_added = 0
WHERE id IN (
    SELECT id FROM wallets
);

-- Verification: Show updated wallet balances
SELECT id, user_id, balance, total_added, total_earned, updated_at
FROM wallets
ORDER BY updated_at DESC;
