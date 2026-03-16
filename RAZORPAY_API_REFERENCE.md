# 🔌 RAZORPAY API REFERENCE - Complete Code Examples

## Table of Contents
1. [Create Order](#create-order)
2. [Verify Payment](#verify-payment)
3. [Get Payment Details](#get-payment-details)
4. [Payment History](#payment-history)
5. [Webhook Handler](#webhook-handler)
6. [Frontend Integration](#frontend-integration)
7. [Error Handling](#error-handling)
8. [Testing Scenarios](#testing-scenarios)

---

## Create Order

### Request
```http
POST /api/payments/create-order
Content-Type: application/json
Authorization: Bearer {token}

{
    "taskId": 123,
    "amount": 50000,
    "helperId": 45,
    "description": "Payment for Website Redesign"
}
```

### Response (Success - 200)
```json
{
    "success": true,
    "orderId": "order_HO2jIEqDnkXYXZ",
    "amount": 55000,
    "currency": "INR",
    "key": "rzp_test_1234567890abcd"
}
```

### Response (Error - 400)
```json
{
    "success": false,
    "error": "Invalid task ID or helper not found"
}
```

### Backend Code
```python
@app.route('/api/payments/create-order', methods=['POST'])
@login_required
def create_payment_order():
    """
    Creates a Razorpay order for a task payment
    
    Request Body:
    {
        "taskId": int,
        "amount": int (in paise),
        "helperId": int,
        "description": str
    }
    
    Returns:
    {
        "success": bool,
        "orderId": str,
        "amount": int,
        "currency": str,
        "key": str
    }
    """
    data = request.get_json()
    task_id = data.get('taskId')
    helper_id = data.get('helperId')
    amount = int(data.get('amount', 0))
    description = data.get('description', 'Payment via TaskEarn')
    
    # Validate inputs
    if amount < 10000:  # Minimum ₹100
        return {"success": False, "error": "Minimum amount is ₹100"}, 400
    
    # Get task
    task = Task.query.get(task_id)
    if not task or task.poster_id != current_user.id:
        return {"success": False, "error": "Task not found"}, 404
    
    # Create Razorpay client
    client = razorpay.Client(
        auth=(current_app.config['RAZORPAY_KEY_ID'], 
              current_app.config['RAZORPAY_KEY_SECRET'])
    )
    
    # Calculate platform fee (10%)
    platform_fee = int(amount * 0.10)
    
    # Create order
    order_data = {
        'amount': amount,
        'currency': 'INR',
        'receipt': f'task_{task_id}_{current_user.id}',
        'notes': {
            'taskId': str(task_id),
            'posterId': str(current_user.id),
            'helperId': str(helper_id),
            'platformFee': str(platform_fee)
        }
    }
    
    razorpay_order = client.order.create(data=order_data)
    
    # Store in database
    payment = Payment(
        task_id=task_id,
        poster_id=current_user.id,
        helper_id=helper_id,
        razorpay_order_id=razorpay_order['id'],
        amount=float(amount) / 100,
        platform_fee=float(platform_fee) / 100,
        status='pending'
    )
    db.session.add(payment)
    db.session.commit()
    
    return {
        "success": True,
        "orderId": razorpay_order['id'],
        "amount": amount,
        "currency": "INR",
        "key": current_app.config['RAZORPAY_KEY_ID']
    }, 200
```

### Frontend Usage
```javascript
async function initiateRazorpayPayment(task) {
    try {
        // Calculate amounts
        const taskAmount = task.price * 100;  // Convert to paise
        const commission = Math.ceil(task.price * 10);  // 10% in rupees
        const totalAmount = (task.price + commission / 100) * 100;  // In paise
        
        // Create order
        const response = await fetch('/api/payments/create-order', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${authToken}`
            },
            body: JSON.stringify({
                taskId: task.id,
                amount: totalAmount,
                helperId: task.acceptedBy,
                description: `Payment for Task: ${task.title}`
            })
        });
        
        const orderData = await response.json();
        
        if (!orderData.success) {
            showToast('Failed to create payment order', 'error');
            return;
        }
        
        // Razorpay options
        const options = {
            key: orderData.key,
            amount: orderData.amount,
            currency: 'INR',
            name: 'TaskEarn',
            description: task.title,
            order_id: orderData.orderId,
            prefill: {
                email: currentUser.email,
                contact: currentUser.phone
            },
            handler: async function(response) {
                await paymentSuccessHandler(task, response);
            },
            modal: {
                ondismiss: function() {
                    showToast('Payment cancelled', 'warning');
                }
            }
        };
        
        // Open checkout
        const rzp = new Razorpay(options);
        rzp.open();
        
    } catch (error) {
        console.error('Payment initiation failed:', error);
        showToast('Failed to initiate payment', 'error');
    }
}
```

---

## Verify Payment

### Request
```http
POST /api/payments/verify
Content-Type: application/json
Authorization: Bearer {token}

{
    "razorpayPaymentId": "pay_HO2jIEqDnkXYXZ",
    "razorpayOrderId": "order_HO2jIEqDnkXYXZ",
    "razorpaySignature": "9ef4dffbfd84f1318f6739a3ce19f9d85851857ae648f114332d8401e0949a3d",
    "taskId": 123,
    "helperId": 45
}
```

### Response (Success - 200)
```json
{
    "success": true,
    "message": "Payment verified and completed successfully",
    "paymentId": "pay_HO2jIEqDnkXYXZ",
    "helperCredit": 450.00,
    "platformCommission": 50.00,
    "taskId": 123
}
```

### Response (Signature Mismatch - 400)
```json
{
    "success": false,
    "error": "Payment signature verification failed"
}
```

### Backend Code
```python
@app.route('/api/payments/verify', methods=['POST'])
@login_required
def verify_payment():
    """
    Verifies Razorpay payment signature and completes payment split
    
    Request Body:
    {
        "razorpayPaymentId": str,
        "razorpayOrderId": str,
        "razorpaySignature": str,
        "taskId": int,
        "helperId": int
    }
    
    Returns:
    {
        "success": bool,
        "message": str,
        "helperCredit": float,
        "platformCommission": float,
        "taskId": int
    }
    """
    data = request.get_json()
    
    payment_id = data.get('razorpayPaymentId')
    order_id = data.get('razorpayOrderId')
    signature = data.get('razorpaySignature')
    task_id = data.get('taskId')
    helper_id = data.get('helperId')
    
    try:
        # Verify signature
        body = f"{order_id}|{payment_id}"
        expected_sig = hmac.new(
            current_app.config['RAZORPAY_KEY_SECRET'].encode(),
            body.encode(),
            hashlib.sha256
        ).hexdigest()
        
        if expected_sig != signature:
            return {
                "success": False,
                "error": "Payment signature verification failed"
            }, 400
        
        # Get payment record
        payment = Payment.query.filter_by(
            razorpay_order_id=order_id
        ).first()
        
        if not payment:
            return {
                "success": False,
                "error": "Payment record not found"
            }, 404
        
        # Calculate split (90% helper, 10% company)
        amount = float(payment.amount)
        platform_fee = amount * 0.10
        helper_amount = amount - platform_fee
        
        # Update payment
        payment.razorpay_payment_id = payment_id
        payment.razorpay_signature = signature
        payment.status = 'paid'
        payment.verified_at = datetime.datetime.now()
        payment.paid_at = datetime.datetime.now()
        
        # Update task
        task = Task.query.get(task_id)
        if task:
            task.status = 'paid'
        
        # Credit helper wallet
        helper = User.query.get(helper_id)
        if helper:
            helper.wallet_balance = float(helper.wallet_balance or 0) + helper_amount
            
            # Log transaction
            transaction = WalletTransaction(
                user_id=helper_id,
                amount=helper_amount,
                type='earned',
                description=f"Payment for task: {task.title if task else 'Unknown'}",
                created_at=datetime.datetime.now(),
                metadata={
                    'taskId': task_id,
                    'paymentId': payment_id,
                    'amount': amount,
                    'platformFee': platform_fee,
                    'type': 'earned'
                }
            )
            db.session.add(transaction)
        
        # Credit company wallet (user_id = 1)
        company = User.query.get(1)  # Company account
        if company:
            company.wallet_balance = float(company.wallet_balance or 0) + platform_fee
            
            # Log transaction
            commission_transaction = WalletTransaction(
                user_id=1,
                amount=platform_fee,
                type='commission',
                description=f"Platform commission from task {task_id}",
                created_at=datetime.datetime.now(),
                metadata={
                    'taskId': task_id,
                    'paymentId': payment_id,
                    'amount': amount,
                    'platformFee': platform_fee,
                    'type': 'commission'
                }
            )
            db.session.add(commission_transaction)
        
        db.session.commit()
        
        return {
            "success": True,
            "message": "Payment verified and completed successfully",
            "paymentId": payment_id,
            "helperCredit": round(helper_amount, 2),
            "platformCommission": round(platform_fee, 2),
            "taskId": task_id
        }, 200
        
    except Exception as e:
        db.session.rollback()
        print(f"Payment verification error: {str(e)}")
        return {
            "success": False,
            "error": f"Verification failed: {str(e)}"
        }, 500
```

### Frontend Usage
```javascript
async function paymentSuccessHandler(task, razorpayResponse) {
    try {
        showToast('Verifying payment...', 'info');
        
        const response = await fetch('/api/payments/verify', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${authToken}`
            },
            body: JSON.stringify({
                razorpayPaymentId: razorpayResponse.razorpay_payment_id,
                razorpayOrderId: razorpayResponse.razorpay_order_id,
                razorpaySignature: razorpayResponse.razorpay_signature,
                taskId: task.id,
                helperId: task.acceptedBy
            })
        });
        
        const verifyData = await response.json();
        
        if (!verifyData.success) {
            showToast('Payment verification failed: ' + verifyData.error, 'error');
            return;
        }
        
        // Update task locally
        task.status = 'paid';
        task.razorpayPaymentId = verifyData.paymentId;
        updateUserData();
        
        // Show success modal
        showPaymentSuccessModal(task, verifyData);
        
        showToast(
            `Payment successful! ₹${verifyData.helperCredit} sent to helper`,
            'success'
        );
        
    } catch (error) {
        console.error('Payment verification error:', error);
        showToast('Payment verification failed', 'error');
    }
}
```

---

## Get Payment Details

### Request
```http
GET /api/payments/pay_HO2jIEqDnkXYXZ
Authorization: Bearer {token}
```

### Response
```json
{
    "success": true,
    "payment": {
        "id": 1,
        "taskId": 123,
        "posterId": 10,
        "helperId": 45,
        "amount": 500.00,
        "platformFee": 50.00,
        "status": "paid",
        "razorpayPaymentId": "pay_HO2jIEqDnkXYXZ",
        "razorpayOrderId": "order_HO2jIEqDnkXYXZ",
        "createdAt": "2024-01-15T10:30:00Z",
        "verifiedAt": "2024-01-15T10:32:00Z",
        "paidAt": "2024-01-15T10:32:00Z"
    }
}
```

### Backend Code
```python
@app.route('/api/payments/<payment_id>', methods=['GET'])
@login_required
def get_payment_details(payment_id):
    """Get details of a specific payment"""
    
    try:
        payment = Payment.query.filter_by(
            razorpay_payment_id=payment_id
        ).first()
        
        if not payment:
            return {
                "success": False,
                "error": "Payment not found"
            }, 404
        
        # Verify user has access
        if (current_user.id != payment.poster_id and 
            current_user.id != payment.helper_id):
            return {
                "success": False,
                "error": "Unauthorized"
            }, 403
        
        return {
            "success": True,
            "payment": {
                "id": payment.id,
                "taskId": payment.task_id,
                "posterId": payment.poster_id,
                "helperId": payment.helper_id,
                "amount": float(payment.amount),
                "platformFee": float(payment.platform_fee or 0),
                "status": payment.status,
                "razorpayPaymentId": payment.razorpay_payment_id,
                "razorpayOrderId": payment.razorpay_order_id,
                "createdAt": payment.created_at.isoformat(),
                "verifiedAt": payment.verified_at.isoformat() if payment.verified_at else None,
                "paidAt": payment.paid_at.isoformat() if payment.paid_at else None
            }
        }, 200
        
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }, 500
```

---

## Payment History

### Request
```http
GET /api/payments/history
Authorization: Bearer {token}
```

### Response
```json
{
    "success": true,
    "made": [
        {
            "id": 1,
            "taskId": 123,
            "amount": 500.00,
            "commission": 50.00,
            "totalPaid": 550.00,
            "status": "paid",
            "createdAt": "2024-01-15T10:30:00Z",
            "type": "made"
        }
    ],
    "received": [
        {
            "id": 2,
            "taskId": 456,
            "amount": 450.00,
            "platformFee": 50.00,
            "status": "paid",
            "createdAt": "2024-01-15T11:30:00Z",
            "type": "received"
        }
    ]
}
```

### Backend Code
```python
@app.route('/api/payments/history', methods=['GET'])
@login_required
def get_payment_history():
    """Get payment history for current user"""
    
    try:
        # Payments made by user
        made_payments = Payment.query.filter_by(
            poster_id=current_user.id
        ).all()
        
        # Payments received by user
        received_payments = Payment.query.filter_by(
            helper_id=current_user.id
        ).all()
        
        made_list = [{
            "id": p.id,
            "taskId": p.task_id,
            "amount": float(p.amount),
            "commission": float(p.platform_fee or 0),
            "totalPaid": float(p.amount) + float(p.platform_fee or 0),
            "status": p.status,
            "createdAt": p.created_at.isoformat(),
            "type": "made"
        } for p in made_payments]
        
        received_list = [{
            "id": p.id,
            "taskId": p.task_id,
            "amount": float(p.amount) * 0.9,  # 90% helper gets
            "platformFee": float(p.platform_fee or 0),
            "status": p.status,
            "createdAt": p.created_at.isoformat(),
            "type": "received"
        } for p in received_payments]
        
        return {
            "success": True,
            "made": made_list,
            "received": received_list
        }, 200
        
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }, 500
```

---

## Webhook Handler

### Razorpay Webhook Configuration
```
Webhook URL: https://yourdomain.com/api/payments/webhook
Events: 
  - payment.authorized
  - payment.captured
  - payment.failed
```

### Webhook Request Format
```json
{
    "event": "payment.captured",
    "payload": {
        "payment": {
            "entity": {
                "id": "pay_HO2jIEqDnkXYXZ",
                "entity": "payment",
                "amount": 55000,
                "currency": "INR",
                "status": "captured",
                "description": "Payment for Website Redesign",
                "order_id": "order_HO2jIEqDnkXYXZ",
                "receipt": "task_123_10",
                ...
            }
        }
    }
}
```

### Backend Code
```python
@app.route('/api/payments/webhook', methods=['POST'])
def razorpay_webhook():
    """Handle Razorpay webhook events"""
    
    try:
        event_data = request.get_json()
        event = event_data.get('event')
        payload = event_data.get('payload', {})
        payment_data = payload.get('payment', {}).get('entity', {})
        
        payment_id = payment_data.get('id')
        order_id = payment_data.get('order_id')
        status = payment_data.get('status')
        
        # Find payment record
        payment = Payment.query.filter_by(
            razorpay_payment_id=payment_id
        ).first()
        
        if not payment:
            payment = Payment.query.filter_by(
                razorpay_order_id=order_id
            ).first()
        
        if not payment:
            print(f"Webhook: Payment not found for {payment_id}")
            return {"status": "ok"}, 200
        
        # Handle events
        if event == 'payment.authorized':
            payment.status = 'authorized'
            
        elif event == 'payment.captured':
            payment.status = 'captured'
            payment.paid_at = datetime.datetime.now()
            
        elif event == 'payment.failed':
            payment.status = 'failed'
            # Optionally refund wallet credits here
            
        db.session.commit()
        
        print(f"Webhook: Payment {payment_id} updated to {payment.status}")
        
        return {"status": "ok"}, 200
        
    except Exception as e:
        print(f"Webhook error: {str(e)}")
        return {"status": "error", "message": str(e)}, 500
```

---

## Frontend Integration

### Complete Flow Example
```javascript
// HTML Button
<button onclick="payForCompletedTask(123)">Pay ₹550 Now</button>

// Step 1: User clicks button
function payForCompletedTask(taskId) {
    const task = myPostedTasks.find(t => t.id === taskId);
    if (!task) return;
    
    const commission = Math.ceil(task.price * 0.10);
    const total = task.price + commission;
    
    if (confirm(`Pay ₹${total} for this task?`)) {
        initiateRazorpayPayment(task);
    }
}

// Step 2: Create order and open checkout
async function initiateRazorpayPayment(task) {
    const response = await fetch('/api/payments/create-order', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
            taskId: task.id,
            amount: (task.price + Math.ceil(task.price * 0.10)) * 100,
            helperId: task.acceptedBy,
            description: `Payment for: ${task.title}`
        })
    });
    
    const orderData = await response.json();
    
    const options = {
        key: orderData.key,
        amount: orderData.amount,
        currency: 'INR',
        name: 'TaskEarn',
        description: task.title,
        order_id: orderData.orderId,
        handler: async (response) => {
            await paymentSuccessHandler(task, response);
        }
    };
    
    new Razorpay(options).open();
}

// Step 3: Verify payment on backend
async function paymentSuccessHandler(task, response) {
    const verifyResponse = await fetch('/api/payments/verify', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
            razorpayPaymentId: response.razorpay_payment_id,
            razorpayOrderId: response.razorpay_order_id,
            razorpaySignature: response.razorpay_signature,
            taskId: task.id,
            helperId: task.acceptedBy
        })
    });
    
    const result = await verifyResponse.json();
    
    if (result.success) {
        showPaymentSuccessModal(task, result);
    } else {
        alert('Payment verification failed: ' + result.error);
    }
}

// Step 4: Show success
function showPaymentSuccessModal(task, verifyData) {
    document.getElementById('successModalContent').innerHTML = `
        <h2>✓ Payment Successful!</h2>
        <p>Task: ${task.title}</p>
        <p>Amount: ₹${task.price}</p>
        <p>Commission: ₹${Math.ceil(task.price * 0.10)}</p>
        <p style="color: green; font-weight: bold;">
            Helper receives: ₹${verifyData.helperCredit}
        </p>
        <button onclick="renderDashboard()">Continue to Dashboard</button>
    `;
    showModal('successModal');
}
```

---

## Error Handling

### Common Errors

#### 1. Signature Mismatch
```javascript
// Cause: Wrong secret key
// Fix: Verify RAZORPAY_KEY_SECRET in config

// Error Response:
{
    "success": false,
    "error": "Payment signature verification failed"
}
```

#### 2. Task Not Found
```javascript
// Cause: Invalid taskId or task doesn't belong to user
// Fix: Verify taskId and user ownership

// Error Response:
{
    "success": false,
    "error": "Task not found"
}
```

#### 3. Insufficient Amount
```javascript
// Cause: Amount less than ₹100
// Fix: Minimum payment is ₹100

// Error Response:
{
    "success": false,
    "error": "Minimum amount is ₹100"
}
```

---

## Testing Scenarios

### Scenario 1: Successful Payment
```
1. Task: ₹500 (ID: 123)
2. Helper: User B (ID: 45)
3. Poster: User A (ID: 10)

Call: POST /api/payments/create-order
↓
Response: orderId = order_ABC123

Razorpay Checkout Opens
↓
Enter Card: 4111 1111 1111 1111
↓
Call: POST /api/payments/verify
↓
Response: success = true

Database Updates:
✓ payments.status = 'paid'
✓ tasks.status = 'paid'
✓ User B wallet: +₹450
✓ User A (Company) wallet: +₹50
✓ 2 transactions logged

Expected Result:
✓ Task shows "Paid ✓"
✓ Helper sees ₹450 in wallet
✓ Payment in history for both users
```

### Scenario 2: Failed Signature
```
1. Same as above, but
2. Signature sent: xxxx123 (wrong)

Call: POST /api/payments/verify
↓
Compare:
- Expected: hmac(order|payment, SECRET)
- Received: xxxx123
↓
Result: Mismatch!

Error Response:
{
    "success": false,
    "error": "Payment signature verification failed"
}

Database NOT Updated:
✗ payment.status stays 'pending'
✗ task.status stays 'pending_payment'
✗ wallets not credited
```

---

**Last Updated**: 2024-01-15
**Status**: Ready for Testing
