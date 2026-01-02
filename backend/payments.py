"""
Razorpay Payment Integration for TaskEarn
"""

import razorpay
import datetime
from flask import Blueprint, request, jsonify
from config import get_config
from database import get_db, dict_from_row, get_placeholder

config = get_config()
PH = get_placeholder()

# Create Blueprint
payments_bp = Blueprint('payments', __name__)

# Initialize Razorpay client
razorpay_client = None
if config.RAZORPAY_KEY_ID and config.RAZORPAY_KEY_SECRET:
    razorpay_client = razorpay.Client(
        auth=(config.RAZORPAY_KEY_ID, config.RAZORPAY_KEY_SECRET)
    )
    print("✅ Razorpay initialized")
else:
    print("⚠️ Razorpay not configured - payment features disabled")


def require_razorpay(f):
    """Decorator to require Razorpay configuration"""
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        if not razorpay_client:
            return jsonify({
                'success': False, 
                'message': 'Payment system not configured'
            }), 503
        return f(*args, **kwargs)
    return decorated


# ========================================
# PAYMENT ROUTES
# ========================================

@payments_bp.route('/api/payments/create-order', methods=['POST'])
@require_razorpay
def create_order():
    """Create a Razorpay order for task payment"""
    from server import require_auth
    
    data = request.get_json()
    task_id = data.get('taskId')
    amount = data.get('amount')  # Amount in rupees
    
    if not task_id or not amount:
        return jsonify({'success': False, 'message': 'Task ID and amount required'}), 400
    
    # Verify task exists
    with get_db() as (cursor, conn):
        cursor.execute(f'SELECT * FROM tasks WHERE id = {PH}', (task_id,))
        task = cursor.fetchone()
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
    
    # Create Razorpay order (amount in paise)
    try:
        order_data = {
            'amount': int(float(amount) * 100),  # Convert to paise
            'currency': 'INR',
            'receipt': f'task_{task_id}_{datetime.datetime.now().timestamp()}',
            'notes': {
                'task_id': str(task_id),
                'app': 'TaskEarn'
            }
        }
        
        order = razorpay_client.order.create(data=order_data)
        
        return jsonify({
            'success': True,
            'orderId': order['id'],
            'amount': order['amount'],
            'currency': order['currency'],
            'keyId': config.RAZORPAY_KEY_ID
        })
        
    except Exception as e:
        print(f"Razorpay error: {e}")
        return jsonify({'success': False, 'message': 'Payment initialization failed'}), 500


@payments_bp.route('/api/payments/verify', methods=['POST'])
@require_razorpay
def verify_payment():
    """Verify Razorpay payment signature"""
    data = request.get_json()
    
    razorpay_order_id = data.get('razorpay_order_id')
    razorpay_payment_id = data.get('razorpay_payment_id')
    razorpay_signature = data.get('razorpay_signature')
    task_id = data.get('task_id')
    user_id = data.get('user_id')
    amount = data.get('amount')
    
    if not all([razorpay_order_id, razorpay_payment_id, razorpay_signature]):
        return jsonify({'success': False, 'message': 'Missing payment details'}), 400
    
    # Verify signature
    try:
        params = {
            'razorpay_order_id': razorpay_order_id,
            'razorpay_payment_id': razorpay_payment_id,
            'razorpay_signature': razorpay_signature
        }
        
        razorpay_client.utility.verify_payment_signature(params)
        
        # Payment verified - save to database
        with get_db() as (cursor, conn):
            created_at = datetime.datetime.now(datetime.UTC).isoformat()
            
            cursor.execute(f'''
                INSERT INTO payments 
                (task_id, user_id, razorpay_order_id, razorpay_payment_id, 
                 razorpay_signature, amount, status, created_at, completed_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, 'completed', {PH}, {PH})
            ''', (
                task_id, user_id, razorpay_order_id, razorpay_payment_id,
                razorpay_signature, amount, created_at, created_at
            ))
        
        return jsonify({
            'success': True,
            'message': 'Payment verified successfully',
            'paymentId': razorpay_payment_id
        })
        
    except razorpay.errors.SignatureVerificationError:
        return jsonify({'success': False, 'message': 'Payment verification failed'}), 400
    except Exception as e:
        print(f"Payment verification error: {e}")
        return jsonify({'success': False, 'message': 'Payment verification failed'}), 500


@payments_bp.route('/api/payments/history', methods=['GET'])
def get_payment_history():
    """Get payment history for a user"""
    from server import require_auth
    
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({'success': False, 'message': 'User ID required'}), 400
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT p.*, t.title as task_title 
            FROM payments p
            LEFT JOIN tasks t ON p.task_id = t.id
            WHERE p.user_id = {PH}
            ORDER BY p.created_at DESC
        ''', (user_id,))
        
        payments = [dict_from_row(p) for p in cursor.fetchall()]
    
    return jsonify({
        'success': True,
        'payments': payments
    })


@payments_bp.route('/api/payments/refund', methods=['POST'])
@require_razorpay
def refund_payment():
    """Initiate refund for a payment"""
    data = request.get_json()
    payment_id = data.get('paymentId')
    amount = data.get('amount')  # Optional - full refund if not specified
    
    if not payment_id:
        return jsonify({'success': False, 'message': 'Payment ID required'}), 400
    
    try:
        refund_data = {'payment_id': payment_id}
        if amount:
            refund_data['amount'] = int(float(amount) * 100)  # Convert to paise
        
        refund = razorpay_client.payment.refund(payment_id, refund_data)
        
        return jsonify({
            'success': True,
            'message': 'Refund initiated',
            'refundId': refund['id'],
            'status': refund['status']
        })
        
    except Exception as e:
        print(f"Refund error: {e}")
        return jsonify({'success': False, 'message': 'Refund failed'}), 500
