// ========================================
// Razorpay Payment Integration for TaskEarn
// ========================================

const RAZORPAY_KEY_ID = 'rzp_live_Rz0lerO1zBlLgQ'; // Live Key ID

// ========================================
// PAYMENT FUNCTIONS
// ========================================

/**
 * Initialize Razorpay payment for a task
 * @param {Object} task - Task object
 * @param {Object} user - Current user
 * @param {Function} onSuccess - Callback on successful payment
 * @param {Function} onError - Callback on payment error
 */
async function initiatePayment(task, user, onSuccess, onError) {
    try {
        // Create order on backend
        const orderResponse = await fetch(`${API_BASE_URL}/payments/create-order`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
            },
            body: JSON.stringify({
                taskId: task.id,
                amount: task.price
            })
        });
        
        const orderData = await orderResponse.json();
        
        if (!orderData.success) {
            throw new Error(orderData.message || 'Failed to create order');
        }
        
        // Open Razorpay checkout
        const options = {
            key: orderData.keyId || RAZORPAY_KEY_ID,
            amount: orderData.amount,
            currency: orderData.currency || 'INR',
            name: 'TaskEarn',
            description: `Payment for: ${task.title}`,
            order_id: orderData.orderId,
            handler: async function(response) {
                // Verify payment on backend
                const verifyResponse = await verifyPayment(
                    response,
                    task.id,
                    user.id,
                    task.price
                );
                
                if (verifyResponse.success) {
                    if (onSuccess) onSuccess(verifyResponse);
                    showToast('✅ Payment successful!');
                } else {
                    if (onError) onError(verifyResponse);
                    showToast('❌ Payment verification failed');
                }
            },
            prefill: {
                name: user.name,
                email: user.email,
                contact: user.phone || ''
            },
            notes: {
                task_id: task.id,
                task_title: task.title
            },
            theme: {
                color: '#667eea'
            },
            modal: {
                ondismiss: function() {
                    showToast('Payment cancelled');
                }
            }
        };
        
        const razorpay = new Razorpay(options);
        razorpay.open();
        
    } catch (error) {
        console.error('Payment error:', error);
        if (onError) onError({ message: error.message });
        showToast('❌ ' + error.message);
    }
}


/**
 * Verify payment with backend
 */
async function verifyPayment(razorpayResponse, taskId, userId, amount) {
    try {
        const response = await fetch(`${API_BASE_URL}/payments/verify`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
            },
            body: JSON.stringify({
                razorpay_order_id: razorpayResponse.razorpay_order_id,
                razorpay_payment_id: razorpayResponse.razorpay_payment_id,
                razorpay_signature: razorpayResponse.razorpay_signature,
                task_id: taskId,
                user_id: userId,
                amount: amount
            })
        });
        
        return await response.json();
    } catch (error) {
        console.error('Verification error:', error);
        return { success: false, message: error.message };
    }
}


/**
 * Get payment history for current user
 */
async function getPaymentHistory(userId) {
    try {
        const response = await fetch(`${API_BASE_URL}/payments/history?user_id=${userId}`, {
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
            }
        });
        return await response.json();
    } catch (error) {
        console.error('Payment history error:', error);
        return { success: false, payments: [] };
    }
}


/**
 * Create payment button HTML
 */
function createPaymentButton(task, user) {
    return `
        <button class="btn btn-primary" onclick="initiatePayment(
            ${JSON.stringify(task).replace(/"/g, '&quot;')}, 
            ${JSON.stringify(user).replace(/"/g, '&quot;')},
            handlePaymentSuccess,
            handlePaymentError
        )">
            <i class="fas fa-credit-card"></i> Pay ₹${task.price}
        </button>
    `;
}


/**
 * Handle successful payment
 */
function handlePaymentSuccess(response) {
    console.log('Payment successful:', response);
    // Refresh tasks or update UI
    if (typeof renderDashboard === 'function') {
        renderDashboard();
    }
}


/**
 * Handle payment error
 */
function handlePaymentError(error) {
    console.error('Payment failed:', error);
}


/**
 * Add money to wallet using Razorpay
 * @param {number} amount - Amount in INR
 * @param {Function} onSuccess - Callback on successful payment
 * @param {Function} onError - Callback on payment error
 */
async function addMoneyToWallet(amount, onSuccess, onError) {
    // Get user info
    const userStr = localStorage.getItem('taskearn_user') || localStorage.getItem('taskearn_current_user');
    if (!userStr) {
        if (onError) onError({ message: 'Please login first' });
        return;
    }
    
    const user = JSON.parse(userStr);
    
    try {
        // Try to create order on backend first
        let orderId = null;
        let keyId = RAZORPAY_KEY_ID;
        
        try {
            const orderResponse = await fetch(`${window.TASKEARN_API_URL || 'http://localhost:5000/api'}/wallet/create-order`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
                },
                body: JSON.stringify({ amount: amount })
            });
            
            const orderData = await orderResponse.json();
            if (orderData.success) {
                orderId = orderData.orderId;
                keyId = orderData.keyId || RAZORPAY_KEY_ID;
            }
        } catch (e) {
            console.log('Backend not available, using client-side Razorpay');
        }
        
        // Check if Razorpay key is configured
        if (keyId === 'YOUR_RAZORPAY_KEY_ID') {
            // Demo mode - no real key configured
            if (onError) onError({ 
                message: 'Razorpay not configured. Using demo mode.',
                demo: true 
            });
            return;
        }
        
        // Open Razorpay checkout
        const options = {
            key: keyId,
            amount: amount * 100, // Razorpay expects amount in paise
            currency: 'INR',
            name: 'TaskEarn',
            description: `Add ₹${amount} to Wallet`,
            order_id: orderId, // null for client-side only
            handler: async function(response) {
                // Payment successful
                console.log('Razorpay response:', response);
                
                // Try to verify with backend
                try {
                    const verifyResponse = await fetch(`${window.TASKEARN_API_URL || 'http://localhost:5000/api'}/wallet/verify-payment`, {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
                        },
                        body: JSON.stringify({
                            razorpay_payment_id: response.razorpay_payment_id,
                            razorpay_order_id: response.razorpay_order_id,
                            razorpay_signature: response.razorpay_signature,
                            amount: amount
                        })
                    });
                    
                    const result = await verifyResponse.json();
                    if (result.success) {
                        if (onSuccess) onSuccess(result);
                        return;
                    }
                } catch (e) {
                    console.log('Backend verification not available');
                }
                
                // If backend not available, just confirm payment
                if (onSuccess) onSuccess({
                    success: true,
                    paymentId: response.razorpay_payment_id,
                    amount: amount
                });
            },
            prefill: {
                name: user.name || '',
                email: user.email || '',
                contact: user.phone || ''
            },
            notes: {
                type: 'wallet_recharge',
                user_id: user.id
            },
            theme: {
                color: '#4ade80'
            },
            modal: {
                ondismiss: function() {
                    if (onError) onError({ message: 'Payment cancelled', cancelled: true });
                }
            }
        };
        
        const razorpay = new Razorpay(options);
        razorpay.on('payment.failed', function(response) {
            if (onError) onError({
                message: response.error.description,
                code: response.error.code
            });
        });
        razorpay.open();
        
    } catch (error) {
        console.error('Wallet payment error:', error);
        if (onError) onError({ message: error.message });
    }
}


// Export for use
window.initiatePayment = initiatePayment;
window.verifyPayment = verifyPayment;
window.getPaymentHistory = getPaymentHistory;
window.createPaymentButton = createPaymentButton;
window.addMoneyToWallet = addMoneyToWallet;
