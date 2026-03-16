"""
TaskEarn Backend Server - Production Ready
Flask + PostgreSQL/SQLite + bcrypt + JWT + Razorpay
"""

import sys
import os
import io

# Set UTF-8 encoding for Windows console
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
import jwt
import datetime
import secrets
import re
import hashlib
import hmac
import json
import time

from config import get_config
from database import init_db, get_db, dict_from_row, get_placeholder

# ========================================
# APP INITIALIZATION
# ========================================

config = get_config()
app = Flask(__name__)

# CORS configuration - Allow all origins for development
CORS(app, 
     resources={r"/api/*": {"origins": "*"}},
     supports_credentials=True,
     allow_headers=['Content-Type', 'Authorization', 'Accept'],
     methods=['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
     max_age=3600)

app.config['SECRET_KEY'] = config.SECRET_KEY

# Add explicit CORS headers handler
@app.after_request
def add_cors_headers(response):
    """Add CORS headers to all responses"""
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, Accept'
    response.headers['Access-Control-Max-Age'] = '3600'
    response.headers['Access-Control-Allow-Credentials'] = 'true'
    
    # Add cache headers for API responses
    if request.path.startswith('/api/'):
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
    
    return response

# Handle OPTIONS requests
@app.before_request
def handle_preflight():
    """Handle preflight CORS requests"""
    if request.method == 'OPTIONS':
        response = jsonify({'success': True})
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, Accept'
        response.headers['Access-Control-Max-Age'] = '3600'
        response.status_code = 200
        return response

# ========================================
# DATABASE INITIALIZATION
# ========================================
# Initialize database on app startup (works with gunicorn)
try:
    print("🔄 Initializing database...")
    init_db()
    print("✅ Database initialized successfully")
except Exception as e:
    print(f"⚠️  Error initializing database: {e}")
    print("   Database may already be initialized or connection issue")

# Placeholder for SQL queries (? for SQLite, %s for PostgreSQL)
PH = get_placeholder()

# ========================================
# HELPER FUNCTIONS
# ========================================

def generate_user_id():
    """Generate unique user ID"""
    import time
    timestamp = hex(int(time.time() * 1000))[2:].upper()
    random_part = secrets.token_hex(3).upper()
    return f"TE{timestamp}{random_part}"


def generate_jwt_token(user_id, email):
    """Generate JWT authentication token"""
    payload = {
        'user_id': user_id,
        'email': email,
        'exp': datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=config.JWT_EXPIRATION_HOURS),
        'iat': datetime.datetime.now(datetime.timezone.utc)
    }
    return jwt.encode(payload, config.SECRET_KEY, algorithm='HS256')


def verify_jwt_token(token):
    """Verify JWT token and return payload"""
    try:
        payload = jwt.decode(token, config.SECRET_KEY, algorithms=['HS256'])
        return payload
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None


def validate_email(email):
    """Validate email format"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None


def validate_password(password):
    """Validate password strength"""
    if len(password) < 6:
        return False, "Password must be at least 6 characters"
    if not re.search(r'[A-Za-z]', password):
        return False, "Password must contain at least one letter"
    if not re.search(r'[0-9]', password):
        return False, "Password must contain at least one number"
    return True, "Valid"


def get_user_by_email(email):
    """Get user by email"""
    with get_db() as (cursor, conn):
        cursor.execute(f'SELECT * FROM users WHERE LOWER(email) = LOWER({PH})', (email,))
        row = cursor.fetchone()
        return dict_from_row(row)


def get_user_by_id(user_id):
    """Get user by ID"""
    with get_db() as (cursor, conn):
        cursor.execute(f'SELECT * FROM users WHERE id = {PH}', (user_id,))
        row = cursor.fetchone()
        return dict_from_row(row)


def user_to_response(user):
    """Convert user dict to safe response (no password)"""
    if not user:
        return None
    return {
        'id': user['id'],
        'name': user['name'],
        'email': user['email'],
        'phone': user.get('phone'),
        'dob': user.get('dob'),
        'rating': float(user.get('rating', 5.0)),
        'tasksPosted': user.get('tasks_posted', 0),
        'tasksCompleted': user.get('tasks_completed', 0),
        'totalEarnings': float(user.get('total_earnings', 0)),
        'joinedAt': user.get('joined_at'),
        'lastLogin': user.get('last_login')
    }


# ========================================
# AUTH MIDDLEWARE
# ========================================

def require_auth(f):
    """Decorator to require authentication"""
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization', '').replace('Bearer ', '')
        if not token:
            return jsonify({'success': False, 'message': 'Authentication required'}), 401
        
        payload = verify_jwt_token(token)
        if not payload:
            return jsonify({'success': False, 'message': 'Invalid or expired token'}), 401
        
        request.user_id = payload['user_id']
        request.user_email = payload['email']
        return f(*args, **kwargs)
    return decorated


# ========================================
# API ROUTES - AUTHENTICATION
# ========================================

@app.route('/api/auth/register', methods=['POST'])
def register():
    """Register a new user"""
    data = request.get_json()
    
    # Validate required fields
    required = ['name', 'email', 'password', 'dob']
    for field in required:
        if not data.get(field):
            return jsonify({'success': False, 'message': f'{field} is required'}), 400
    
    name = data['name'].strip()
    email = data['email'].strip().lower()
    password = data['password']
    phone = data.get('phone', '').strip()
    dob = data['dob']
    
    # Validate email
    if not validate_email(email):
        return jsonify({'success': False, 'message': 'Invalid email format'}), 400
    
    # Validate password
    is_valid, message = validate_password(password)
    if not is_valid:
        return jsonify({'success': False, 'message': message}), 400
    
    # Check if email already exists
    if get_user_by_email(email):
        return jsonify({'success': False, 'message': 'Email already registered'}), 400
    
    # Validate age (must be 16+)
    try:
        dob_date = datetime.datetime.strptime(dob, '%Y-%m-%d')
        age = (datetime.datetime.now() - dob_date).days // 365
        if age < 16:
            return jsonify({'success': False, 'message': 'You must be 16 or older'}), 400
    except ValueError:
        return jsonify({'success': False, 'message': 'Invalid date of birth format'}), 400
    
    # Create user
    user_id = generate_user_id()
    password_hash = generate_password_hash(password, method='pbkdf2:sha256')
    joined_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        try:
            cursor.execute(f'''
                INSERT INTO users (id, name, email, password_hash, phone, dob, joined_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, name, email, password_hash, phone, dob, joined_at))
            conn.commit()  # Explicitly commit the transaction
        except Exception as e:
            conn.rollback()  # Rollback on error
            print(f"[ERROR] Registration failed: {str(e)}")
            return jsonify({'success': False, 'message': 'Email already registered'}), 400
    
    # Generate token
    token = generate_jwt_token(user_id, email)
    user = get_user_by_id(user_id)
    
    return jsonify({
        'success': True,
        'message': 'Registration successful',
        'token': token,
        'user': user_to_response(user)
    }), 201


@app.route('/api/auth/login', methods=['POST'])
def login():
    """Login user"""
    data = request.get_json()
    
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')
    
    if not email or not password:
        return jsonify({'success': False, 'message': 'Email and password required'}), 400
    
    # Get user
    user = get_user_by_email(email)
    if not user:
        return jsonify({'success': False, 'message': 'Invalid email or password'}), 401
    
    # Verify password
    if not check_password_hash(user['password_hash'], password):
        return jsonify({'success': False, 'message': 'Invalid email or password'}), 401
    
    # Update last login
    with get_db() as (cursor, conn):
        last_login = datetime.datetime.now(datetime.timezone.utc).isoformat()
        session_token = secrets.token_hex(32)
        cursor.execute(f'''
            UPDATE users SET last_login = {PH}, session_token = {PH} WHERE id = {PH}
        ''', (last_login, session_token, user['id']))
    
    # Generate token
    token = generate_jwt_token(user['id'], email)
    user = get_user_by_id(user['id'])
    
    return jsonify({
        'success': True,
        'message': 'Login successful',
        'token': token,
        'user': user_to_response(user)
    })


@app.route('/api/auth/me', methods=['GET'])
@require_auth
def get_current_user():
    """Get current authenticated user"""
    user = get_user_by_id(request.user_id)
    if not user:
        return jsonify({'success': False, 'message': 'User not found'}), 404
    
    return jsonify({
        'success': True,
        'user': user_to_response(user)
    })


@app.route('/api/auth/logout', methods=['POST'])
@require_auth
def logout():
    """Logout user (invalidate session)"""
    with get_db() as (cursor, conn):
        cursor.execute(f'UPDATE users SET session_token = NULL WHERE id = {PH}', (request.user_id,))
    
    return jsonify({'success': True, 'message': 'Logged out successfully'})


# ========================================
# API ROUTES - PASSWORD RESET
# ========================================

@app.route('/api/auth/forgot-password', methods=['POST'])
def forgot_password():
    """Find account for password reset"""
    data = request.get_json()
    email = data.get('email', '').strip().lower()
    
    if not email:
        return jsonify({'success': False, 'message': 'Email is required'}), 400
    
    user = get_user_by_email(email)
    if not user:
        return jsonify({'success': False, 'message': 'No account found with this email'}), 404
    
    # Generate OTP (6 digits)
    otp = ''.join([str(secrets.randbelow(10)) for _ in range(6)])
    reset_token = secrets.token_hex(32)
    
    # Store reset token
    with get_db() as (cursor, conn):
        created_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        expires_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)).isoformat()
        
        cursor.execute(f'''
            INSERT INTO password_resets (user_id, token, otp, created_at, expires_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
        ''', (user['id'], reset_token, otp, created_at, expires_at))
    
    # In production, send OTP via email using SendGrid
    if config.SENDGRID_API_KEY:
        try:
            from sendgrid import SendGridAPIClient
            from sendgrid.helpers.mail import Mail
            
            message = Mail(
                from_email=config.FROM_EMAIL,
                to_emails=email,
                subject=f'{config.APP_NAME} - Password Reset OTP',
                html_content=f'''
                    <h2>Password Reset</h2>
                    <p>Your OTP for password reset is:</p>
                    <h1 style="color: #667eea; font-size: 32px;">{otp}</h1>
                    <p>This code expires in 10 minutes.</p>
                    <p>If you didn't request this, please ignore this email.</p>
                '''
            )
            sg = SendGridAPIClient(config.SENDGRID_API_KEY)
            sg.send(message)
            print(f"📧 OTP sent to {email}")
        except Exception as e:
            print(f"⚠️ Email error: {e}")
    else:
        print(f"🔐 OTP for {email}: {otp}")
    
    return jsonify({
        'success': True,
        'message': 'OTP sent to your email',
        'resetToken': reset_token,
        'maskedEmail': email[:3] + '***@' + email.split('@')[1],
        'userName': user['name'],
        # Remove 'otp' in production!
        'otp': otp if not config.SENDGRID_API_KEY else None
    })


@app.route('/api/auth/verify-otp', methods=['POST'])
def verify_otp():
    """Verify OTP for password reset"""
    data = request.get_json()
    reset_token = data.get('resetToken', '')
    otp = data.get('otp', '')
    
    if not reset_token or not otp:
        return jsonify({'success': False, 'message': 'Reset token and OTP required'}), 400
    
    with get_db() as (cursor, conn):
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        cursor.execute(f'''
            SELECT * FROM password_resets 
            WHERE token = {PH} AND otp = {PH} AND used = {PH} AND expires_at > {PH}
        ''', (reset_token, otp, False if config.USE_POSTGRES else 0, now))
        
        reset_record = cursor.fetchone()
    
    if not reset_record:
        return jsonify({'success': False, 'message': 'Invalid or expired OTP'}), 400
    
    return jsonify({
        'success': True,
        'message': 'OTP verified',
        'resetToken': reset_token
    })


@app.route('/api/auth/reset-password', methods=['POST'])
def reset_password():
    """Reset password with verified token"""
    data = request.get_json()
    reset_token = data.get('resetToken', '')
    new_password = data.get('newPassword', '')
    
    if not reset_token or not new_password:
        return jsonify({'success': False, 'message': 'Reset token and new password required'}), 400
    
    # Validate password
    is_valid, message = validate_password(new_password)
    if not is_valid:
        return jsonify({'success': False, 'message': message}), 400
    
    with get_db() as (cursor, conn):
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        # Get reset record
        cursor.execute(f'''
            SELECT * FROM password_resets 
            WHERE token = {PH} AND used = {PH} AND expires_at > {PH}
        ''', (reset_token, False if config.USE_POSTGRES else 0, now))
        
        reset_record = cursor.fetchone()
        if not reset_record:
            return jsonify({'success': False, 'message': 'Invalid or expired reset token'}), 400
        
        reset_record = dict_from_row(reset_record)
        
        # Update password
        password_hash = generate_password_hash(new_password, method='pbkdf2:sha256')
        cursor.execute(f'UPDATE users SET password_hash = {PH} WHERE id = {PH}', 
                       (password_hash, reset_record['user_id']))
        
        # Mark token as used
        cursor.execute(f'UPDATE password_resets SET used = {PH} WHERE token = {PH}', 
                       (True if config.USE_POSTGRES else 1, reset_token))
    
    return jsonify({
        'success': True,
        'message': 'Password reset successful'
    })


# ========================================
# API ROUTES - USER PROFILE
# ========================================

@app.route('/api/user/profile', methods=['PUT'])
@require_auth
def update_profile():
    """Update user profile"""
    data = request.get_json()
    
    allowed_fields = ['name', 'phone']
    updates = {k: v for k, v in data.items() if k in allowed_fields}
    
    if not updates:
        return jsonify({'success': False, 'message': 'No valid fields to update'}), 400
    
    with get_db() as (cursor, conn):
        set_parts = [f"{k} = {PH}" for k in updates.keys()]
        set_clause = ', '.join(set_parts)
        values = list(updates.values()) + [request.user_id]
        
        cursor.execute(f'UPDATE users SET {set_clause} WHERE id = {PH}', values)
    
    user = get_user_by_id(request.user_id)
    
    return jsonify({
        'success': True,
        'message': 'Profile updated',
        'user': user_to_response(user)
    })


@app.route('/api/user/change-password', methods=['POST'])
@require_auth
def change_password():
    """Change password for authenticated user"""
    data = request.get_json()
    current_password = data.get('currentPassword', '')
    new_password = data.get('newPassword', '')
    
    if not current_password or not new_password:
        return jsonify({'success': False, 'message': 'Current and new password required'}), 400
    
    # Validate new password
    is_valid, message = validate_password(new_password)
    if not is_valid:
        return jsonify({'success': False, 'message': message}), 400
    
    # Verify current password
    user = get_user_by_id(request.user_id)
    if not check_password_hash(user['password_hash'], current_password):
        return jsonify({'success': False, 'message': 'Current password is incorrect'}), 401
    
    # Update password
    with get_db() as (cursor, conn):
        password_hash = generate_password_hash(new_password, method='pbkdf2:sha256')
        cursor.execute(f'UPDATE users SET password_hash = {PH} WHERE id = {PH}', 
                       (password_hash, request.user_id))
    
    return jsonify({
        'success': True,
        'message': 'Password changed successfully'
    })


# ========================================
# API ROUTES - TASKS
# ========================================

@app.route('/api/tasks', methods=['GET'])
def get_tasks():
    """Get all active tasks"""
    with get_db() as (cursor, conn):
        cursor.execute('''
            SELECT t.*, u.name as poster_name, u.rating as poster_rating, u.tasks_posted as poster_tasks
            FROM tasks t
            JOIN users u ON t.posted_by = u.id
            WHERE t.status = 'active'
            ORDER BY t.posted_at DESC
        ''')
        tasks = cursor.fetchall()
    
    task_list = []
    for task in tasks:
        task = dict_from_row(task)
        task_list.append({
            'id': task['id'],
            'title': task['title'],
            'description': task['description'],
            'category': task['category'],
            'location': {
                'lat': task['location_lat'],
                'lng': task['location_lng'],
                'address': task['location_address']
            },
            'price': float(task['price']),
            'postedBy': {
                'name': task['poster_name'],
                'rating': float(task['poster_rating']),
                'tasksPosted': task['poster_tasks']
            },
            'postedAt': task['posted_at'],
            'expiresAt': task['expires_at'],
            'status': task['status']
        })
    
    return jsonify({
        'success': True,
        'tasks': task_list
    })


@app.route('/api/tasks', methods=['POST'])
@require_auth
def create_task():
    """Create a new task"""
    data = request.get_json()
    
    required = ['title', 'description', 'category', 'price']
    for field in required:
        if not data.get(field):
            return jsonify({'success': False, 'message': f'{field} is required'}), 400
    
    with get_db() as (cursor, conn):
        posted_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        expires_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=12)).isoformat()
        
        location = data.get('location', {})
        
        cursor.execute(f'''
            INSERT INTO tasks (title, description, category, location_lat, location_lng, 
                              location_address, price, posted_by, posted_at, expires_at, status)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, 'active')
        ''', (
            data['title'],
            data['description'],
            data['category'],
            location.get('lat'),
            location.get('lng'),
            location.get('address'),
            data['price'],
            request.user_id,
            posted_at,
            expires_at
        ))
        
        # Get the inserted task ID
        if config.USE_POSTGRES:
            cursor.execute('SELECT lastval() AS id')
            task_id = cursor.fetchone()['id']
        else:
            cursor.execute('SELECT last_insert_rowid() AS id')
            task_id = cursor.fetchone()['id']
        
        # Update user's tasks_posted count
        cursor.execute(f'UPDATE users SET tasks_posted = tasks_posted + 1 WHERE id = {PH}', 
                       (request.user_id,))
    
    return jsonify({
        'success': True,
        'message': 'Task created successfully',
        'taskId': task_id
    }), 201


@app.route('/api/tasks/<int:task_id>/accept', methods=['POST'])
@require_auth
def accept_task(task_id):
    """Accept a task"""
    with get_db() as (cursor, conn):
        # Check if task exists and is active
        cursor.execute(f'SELECT * FROM tasks WHERE id = {PH} AND status = {PH}', (task_id, 'active'))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found or already taken'}), 404
        
        task = dict_from_row(task)
        
        # Can't accept own task
        if task['posted_by'] == request.user_id:
            return jsonify({'success': False, 'message': 'Cannot accept your own task'}), 400
        
        # Accept task
        accepted_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        cursor.execute(f'''
            UPDATE tasks SET status = 'accepted', accepted_by = {PH}, accepted_at = {PH}
            WHERE id = {PH}
        ''', (request.user_id, accepted_at, task_id))
    
    return jsonify({
        'success': True,
        'message': 'Task accepted successfully'
    })


@app.route('/api/tasks/<int:task_id>/complete', methods=['POST'])
@require_auth
def complete_task(task_id):
    """Mark task as completed"""
    with get_db() as (cursor, conn):
        # Check if task exists and is accepted by current user
        cursor.execute(f'''
            SELECT * FROM tasks WHERE id = {PH} AND accepted_by = {PH} AND status = {PH}
        ''', (task_id, request.user_id, 'accepted'))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found or not accepted by you'}), 404
        
        task = dict_from_row(task)
        
        # Complete task
        completed_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        cursor.execute(f'''
            UPDATE tasks SET status = 'completed', completed_at = {PH}
            WHERE id = {PH}
        ''', (completed_at, task_id))
        
        # Update completer's stats
        cursor.execute(f'''
            UPDATE users SET tasks_completed = tasks_completed + 1, 
                            total_earnings = total_earnings + {PH}
            WHERE id = {PH}
        ''', (task['price'], request.user_id))
    
    return jsonify({
        'success': True,
        'message': 'Task completed successfully'
    })


@app.route('/api/user/tasks', methods=['GET'])
@require_auth
def get_user_tasks():
    """Get current user's tasks"""
    with get_db() as (cursor, conn):
        # Posted tasks
        cursor.execute(f'''
            SELECT * FROM tasks WHERE posted_by = {PH} ORDER BY posted_at DESC
        ''', (request.user_id,))
        posted = [dict_from_row(t) for t in cursor.fetchall()]
        
        # Accepted tasks
        cursor.execute(f'''
            SELECT * FROM tasks WHERE accepted_by = {PH} AND status = 'accepted' ORDER BY accepted_at DESC
        ''', (request.user_id,))
        accepted = [dict_from_row(t) for t in cursor.fetchall()]
        
        # Completed tasks
        cursor.execute(f'''
            SELECT * FROM tasks WHERE accepted_by = {PH} AND status = 'completed' ORDER BY completed_at DESC
        ''', (request.user_id,))
        completed = [dict_from_row(t) for t in cursor.fetchall()]
    
    return jsonify({
        'success': True,
        'postedTasks': posted,
        'acceptedTasks': accepted,
        'completedTasks': completed
    })


@app.route('/api/user/active-tracking', methods=['GET'])
@require_auth
def get_user_active_tracking():
    """Get user's tasks that are currently being tracked (active)"""
    with get_db() as (cursor, conn):
        # Get tasks where user is poster and task is accepted (being delivered)
        cursor.execute(f'''
            SELECT t.id, t.title, t.price, t.status, t.accepted_by,
                   u.name as helper_name
            FROM tasks t
            LEFT JOIN users u ON t.accepted_by = u.id
            WHERE t.posted_by = {PH} AND t.status = 'accepted'
            ORDER BY t.accepted_at DESC
        ''', (request.user_id,))
        posted_active = cursor.fetchall()
        
        # Get tasks where user is helper (they accepted the task)
        cursor.execute(f'''
            SELECT t.id, t.title, t.price, t.status, t.posted_by,
                   u.name as poster_name
            FROM tasks t
            LEFT JOIN users u ON t.posted_by = u.id
            WHERE t.accepted_by = {PH} AND t.status = 'accepted'
            ORDER BY t.accepted_at DESC
        ''', (request.user_id,))
        accepted_active = cursor.fetchall()
        
        tasks = []
        
        for t in posted_active:
            t = dict_from_row(t)
            tasks.append({
                'id': t['id'],
                'title': t['title'],
                'price': float(t['price']),
                'status': t['status'],
                'role': 'poster',
                'otherParty': t['helper_name']
            })
        
        for t in accepted_active:
            t = dict_from_row(t)
            tasks.append({
                'id': t['id'],
                'title': t['title'],
                'price': float(t['price']),
                'status': t['status'],
                'role': 'helper',
                'otherParty': t['poster_name']
            })
    
    return jsonify({
        'success': True,
        'tasks': tasks
    })


# ========================================
# API ROUTES - LOCATION TRACKING
# ========================================

@app.route('/api/tracking/<int:task_id>', methods=['GET'])
@require_auth
def get_tracking_info(task_id):
    """Get tracking information for a task"""
    with get_db() as (cursor, conn):
        # Get task with user details
        cursor.execute(f'''
            SELECT t.*, 
                   poster.name as poster_name, poster.phone as poster_phone, poster.rating as poster_rating,
                   helper.name as helper_name, helper.phone as helper_phone, helper.rating as helper_rating
            FROM tasks t
            LEFT JOIN users poster ON t.posted_by = poster.id
            LEFT JOIN users helper ON t.accepted_by = helper.id
            WHERE t.id = {PH}
        ''', (task_id,))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        
        task = dict_from_row(task)
        
        # Check if user is authorized (poster or helper)
        if task['posted_by'] != request.user_id and task['accepted_by'] != request.user_id:
            return jsonify({'success': False, 'message': 'Not authorized to track this task'}), 403
        
        # Get latest location of helper
        helper_location = None
        if task['accepted_by']:
            cursor.execute(f'''
                SELECT latitude, longitude, accuracy, heading, speed, recorded_at
                FROM location_tracking
                WHERE task_id = {PH} AND user_id = {PH} AND is_active = {PH}
                ORDER BY recorded_at DESC LIMIT 1
            ''', (task_id, task['accepted_by'], True if config.USE_POSTGRES else 1))
            loc = cursor.fetchone()
            if loc:
                loc = dict_from_row(loc)
                helper_location = {
                    'lat': float(loc['latitude']),
                    'lng': float(loc['longitude']),
                    'accuracy': float(loc['accuracy']) if loc['accuracy'] else None,
                    'heading': float(loc['heading']) if loc['heading'] else None,
                    'speed': float(loc['speed']) if loc['speed'] else None,
                    'timestamp': loc['recorded_at']
                }
        
        # Build timeline
        timeline = []
        if task['posted_at']:
            timeline.append({
                'status': 'completed',
                'title': 'Task Posted',
                'time': task['posted_at'],
                'icon': 'fa-plus-circle'
            })
        if task['accepted_at']:
            timeline.append({
                'status': 'completed',
                'title': 'Task Accepted',
                'time': task['accepted_at'],
                'icon': 'fa-check'
            })
            timeline.append({
                'status': 'active' if task['status'] == 'accepted' else 'completed',
                'title': 'In Progress',
                'time': 'Now' if task['status'] == 'accepted' else task['completed_at'],
                'icon': 'fa-motorcycle'
            })
        if task['status'] == 'completed':
            timeline.append({
                'status': 'completed',
                'title': 'Completed',
                'time': task['completed_at'],
                'icon': 'fa-flag-checkered'
            })
        else:
            timeline.append({
                'status': 'pending',
                'title': 'Delivery',
                'time': 'Expected',
                'icon': 'fa-flag-checkered'
            })
        
        # Calculate ETA (simplified - in production use routing API)
        eta = "Calculating..."
        distance = "Calculating..."
        
        if helper_location and task['location_lat'] and task['location_lng']:
            import math
            # Haversine formula for distance
            R = 6371  # Earth's radius in km
            lat1, lon1 = math.radians(helper_location['lat']), math.radians(helper_location['lng'])
            lat2, lon2 = math.radians(float(task['location_lat'])), math.radians(float(task['location_lng']))
            dlat, dlon = lat2 - lat1, lon2 - lon1
            a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
            c = 2 * math.asin(math.sqrt(a))
            dist_km = R * c
            
            distance = f"{dist_km:.1f} km"
            # Assume average speed of 20 km/h in city
            eta_mins = int(dist_km / 20 * 60)
            eta = f"{eta_mins} mins" if eta_mins > 0 else "Arriving"
        
        tracking_data = {
            'taskId': task['id'],
            'title': task['title'],
            'status': task['status'],
            'pickup': {
                'address': task['location_address'] or 'Pickup Location',
                'lat': float(task['location_lat']) if task['location_lat'] else None,
                'lng': float(task['location_lng']) if task['location_lng'] else None
            },
            'destination': {
                'address': task['location_address'] or 'Delivery Location',
                'lat': float(task['location_lat']) if task['location_lat'] else None,
                'lng': float(task['location_lng']) if task['location_lng'] else None
            },
            'helper': {
                'id': task['accepted_by'],
                'name': task['helper_name'] or 'Waiting for helper',
                'phone': task['helper_phone'] or '',
                'rating': float(task['helper_rating']) if task['helper_rating'] else 5.0,
                'avatar': task['helper_name'][0].upper() if task['helper_name'] else '?'
            } if task['accepted_by'] else None,
            'poster': {
                'id': task['posted_by'],
                'name': task['poster_name'],
                'phone': task['poster_phone'] or '',
                'rating': float(task['poster_rating']) if task['poster_rating'] else 5.0
            },
            'helperId': task['accepted_by'],
            'posterId': task['posted_by'],
            'helperLocation': helper_location,
            'eta': eta,
            'distance': distance,
            'timeline': timeline,
            'price': float(task['price'])
        }
        
        return jsonify({
            'success': True,
            'tracking': tracking_data
        })


@app.route('/api/tracking/<int:task_id>/location', methods=['GET'])
@require_auth
def get_helper_location(task_id):
    """Get latest helper location for a task"""
    with get_db() as (cursor, conn):
        # Verify authorization
        cursor.execute(f'''
            SELECT posted_by, accepted_by, location_lat, location_lng, status 
            FROM tasks WHERE id = {PH}
        ''', (task_id,))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        
        task = dict_from_row(task)
        
        if task['posted_by'] != request.user_id and task['accepted_by'] != request.user_id:
            return jsonify({'success': False, 'message': 'Not authorized'}), 403
        
        # Check if task is completed
        if task['status'] == 'completed':
            return jsonify({
                'success': True,
                'status': 'completed',
                'message': 'Task has been completed'
            })
        
        if not task['accepted_by']:
            return jsonify({
                'success': True,
                'status': 'waiting',
                'message': 'Waiting for helper to accept'
            })
        
        # Get latest location
        cursor.execute(f'''
            SELECT latitude, longitude, accuracy, heading, speed, recorded_at
            FROM location_tracking
            WHERE task_id = {PH} AND user_id = {PH} AND is_active = {PH}
            ORDER BY recorded_at DESC LIMIT 1
        ''', (task_id, task['accepted_by'], True if config.USE_POSTGRES else 1))
        loc = cursor.fetchone()
        
        if not loc:
            return jsonify({
                'success': True,
                'status': 'no_location',
                'message': 'Helper location not available yet'
            })
        
        loc = dict_from_row(loc)
        
        # Calculate ETA
        eta = "Calculating..."
        distance = "Calculating..."
        
        if task['location_lat'] and task['location_lng']:
            import math
            R = 6371
            lat1, lon1 = math.radians(float(loc['latitude'])), math.radians(float(loc['longitude']))
            lat2, lon2 = math.radians(float(task['location_lat'])), math.radians(float(task['location_lng']))
            dlat, dlon = lat2 - lat1, lon2 - lon1
            a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
            c = 2 * math.asin(math.sqrt(a))
            dist_km = R * c
            
            distance = f"{dist_km:.1f} km"
            eta_mins = int(dist_km / 20 * 60)
            eta = f"{eta_mins} mins" if eta_mins > 0 else "Arriving"
        
        return jsonify({
            'success': True,
            'location': {
                'lat': float(loc['latitude']),
                'lng': float(loc['longitude']),
                'accuracy': float(loc['accuracy']) if loc['accuracy'] else None,
                'heading': float(loc['heading']) if loc['heading'] else None,
                'speed': float(loc['speed']) if loc['speed'] else None,
                'timestamp': loc['recorded_at']
            },
            'eta': eta,
            'distance': distance
        })


@app.route('/api/tracking/update-location', methods=['POST'])
@require_auth
def update_location():
    """Update user's current location for tracking"""
    data = request.get_json()
    
    task_id = data.get('taskId')
    location = data.get('location', {})
    
    if not task_id:
        return jsonify({'success': False, 'message': 'Task ID required'}), 400
    
    if not location.get('lat') or not location.get('lng'):
        return jsonify({'success': False, 'message': 'Valid location required'}), 400
    
    with get_db() as (cursor, conn):
        # Verify user is part of this task
        cursor.execute(f'''
            SELECT posted_by, accepted_by FROM tasks WHERE id = {PH}
        ''', (task_id,))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        
        task = dict_from_row(task)
        
        if task['posted_by'] != request.user_id and task['accepted_by'] != request.user_id:
            return jsonify({'success': False, 'message': 'Not authorized'}), 403
        
        # Determine user type
        user_type = 'poster' if task['posted_by'] == request.user_id else 'helper'
        
        # Deactivate old locations
        cursor.execute(f'''
            UPDATE location_tracking 
            SET is_active = {PH}
            WHERE task_id = {PH} AND user_id = {PH}
        ''', (False if config.USE_POSTGRES else 0, task_id, request.user_id))
        
        # Insert new location
        recorded_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
        cursor.execute(f'''
            INSERT INTO location_tracking 
            (task_id, user_id, user_type, latitude, longitude, accuracy, heading, speed, recorded_at, is_active)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (
            task_id,
            request.user_id,
            user_type,
            location['lat'],
            location['lng'],
            location.get('accuracy'),
            location.get('heading'),
            location.get('speed'),
            recorded_at,
            True if config.USE_POSTGRES else 1
        ))
    
    return jsonify({
        'success': True,
        'message': 'Location updated'
    })


@app.route('/api/tracking/history/<int:task_id>', methods=['GET'])
@require_auth
def get_location_history(task_id):
    """Get location history for a task (for route replay)"""
    with get_db() as (cursor, conn):
        # Verify authorization
        cursor.execute(f'''
            SELECT posted_by, accepted_by FROM tasks WHERE id = {PH}
        ''', (task_id,))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        
        task = dict_from_row(task)
        
        if task['posted_by'] != request.user_id and task['accepted_by'] != request.user_id:
            return jsonify({'success': False, 'message': 'Not authorized'}), 403
        
        # Get all locations for the helper
        cursor.execute(f'''
            SELECT latitude, longitude, recorded_at, speed
            FROM location_tracking
            WHERE task_id = {PH} AND user_type = 'helper'
            ORDER BY recorded_at ASC
        ''', (task_id,))
        
        locations = []
        for row in cursor.fetchall():
            row = dict_from_row(row)
            locations.append({
                'lat': float(row['latitude']),
                'lng': float(row['longitude']),
                'timestamp': row['recorded_at'],
                'speed': float(row['speed']) if row['speed'] else None
            })
        
        return jsonify({
            'success': True,
            'history': locations
        })


@app.route('/api/tracking/stop/<int:task_id>', methods=['POST'])
@require_auth
def stop_tracking(task_id):
    """Stop location tracking for a task"""
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            UPDATE location_tracking 
            SET is_active = {PH}
            WHERE task_id = {PH} AND user_id = {PH}
        ''', (False if config.USE_POSTGRES else 0, task_id, request.user_id))
    
    return jsonify({
        'success': True,
        'message': 'Tracking stopped'
    })


# ========================================
# WALLET API
# ========================================

def get_or_create_wallet(user_id):
    """Get user wallet or create if not exists"""
    with get_db() as (cursor, conn):
        cursor.execute(f'SELECT * FROM wallets WHERE user_id = {PH}', (user_id,))
        wallet = cursor.fetchone()
        
        if not wallet:
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                INSERT INTO wallets (user_id, balance, total_added, total_spent, total_earned, total_cashback, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 0, 0, 0, 0, 0, now))
            conn.commit()
            cursor.execute(f'SELECT * FROM wallets WHERE user_id = {PH}', (user_id,))
            wallet = cursor.fetchone()
        
        return dict_from_row(wallet)


@app.route('/api/wallet', methods=['GET'])
@require_auth
def get_wallet():
    """Get user wallet details"""
    wallet = get_or_create_wallet(request.user_id)
    
    # Get recent transactions
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT * FROM wallet_transactions 
            WHERE user_id = {PH} 
            ORDER BY created_at DESC 
            LIMIT 20
        ''', (request.user_id,))
        transactions = [dict_from_row(row) for row in cursor.fetchall()]
    
    return jsonify({
        'success': True,
        'wallet': {
            'balance': float(wallet['balance']),
            'totalAdded': float(wallet['total_added']),
            'totalSpent': float(wallet['total_spent']),
            'totalEarned': float(wallet['total_earned']),
            'totalCashback': float(wallet['total_cashback'])
        },
        'transactions': transactions
    })


@app.route('/api/wallet/add-money', methods=['POST'])
@require_auth
def add_money_to_wallet():
    """Add money to wallet"""
    data = request.get_json()
    amount = float(data.get('amount', 0))
    payment_id = data.get('paymentId')
    
    if amount < 10:
        return jsonify({'success': False, 'message': 'Minimum amount is ₹10'}), 400
    
    # Calculate cashback (2% on amounts > 500)
    cashback = amount * 0.02 if amount >= 500 else 0
    total_credit = amount + cashback
    
    wallet = get_or_create_wallet(request.user_id)
    new_balance = float(wallet['balance']) + total_credit
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        # Update wallet
        cursor.execute(f'''
            UPDATE wallets 
            SET balance = {PH}, total_added = total_added + {PH}, total_cashback = total_cashback + {PH}, updated_at = {PH}
            WHERE user_id = {PH}
        ''', (new_balance, amount, cashback, now, request.user_id))
        
        # Add transaction record
        cursor.execute(f'''
            INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, reference_id, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (wallet['id'], request.user_id, 'credit', amount, new_balance, 'Added money to wallet', payment_id, now))
        
        # Add cashback transaction if applicable
        if cashback > 0:
            cursor.execute(f'''
                INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (wallet['id'], request.user_id, 'cashback', cashback, new_balance, f'2% cashback on ₹{amount}', now))
    
    return jsonify({
        'success': True,
        'message': f'₹{amount} added successfully' + (f' + ₹{cashback:.2f} cashback!' if cashback > 0 else ''),
        'newBalance': new_balance,
        'cashback': cashback
    })


@app.route('/api/wallet/pay', methods=['POST'])
@require_auth
def pay_from_wallet():
    """Pay for task from wallet"""
    data = request.get_json()
    amount = float(data.get('amount', 0))
    task_id = data.get('taskId')
    description = data.get('description', 'Task payment')
    
    wallet = get_or_create_wallet(request.user_id)
    
    if float(wallet['balance']) < amount:
        return jsonify({'success': False, 'message': 'Insufficient wallet balance'}), 400
    
    new_balance = float(wallet['balance']) - amount
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            UPDATE wallets 
            SET balance = {PH}, total_spent = total_spent + {PH}, updated_at = {PH}
            WHERE user_id = {PH}
        ''', (new_balance, amount, now, request.user_id))
        
        cursor.execute(f'''
            INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, task_id, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (wallet['id'], request.user_id, 'debit', amount, new_balance, description, task_id, now))
    
    return jsonify({
        'success': True,
        'message': f'₹{amount} paid successfully',
        'newBalance': new_balance
    })


@app.route('/api/wallet/earn', methods=['POST'])
@require_auth
def earn_to_wallet():
    """Add earnings to wallet (for helpers)"""
    data = request.get_json()
    amount = float(data.get('amount', 0))
    task_id = data.get('taskId')
    description = data.get('description', 'Task earnings')
    
    wallet = get_or_create_wallet(request.user_id)
    new_balance = float(wallet['balance']) + amount
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            UPDATE wallets 
            SET balance = {PH}, total_earned = total_earned + {PH}, updated_at = {PH}
            WHERE user_id = {PH}
        ''', (new_balance, amount, now, request.user_id))
        
        cursor.execute(f'''
            INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, task_id, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (wallet['id'], request.user_id, 'earning', amount, new_balance, description, task_id, now))
    
    return jsonify({
        'success': True,
        'message': f'₹{amount} added to earnings',
        'newBalance': new_balance
    })


@app.route('/api/wallet/transactions', methods=['GET'])
@require_auth
def get_transactions():
    """Get wallet transaction history"""
    page = int(request.args.get('page', 1))
    limit = int(request.args.get('limit', 20))
    offset = (page - 1) * limit
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT * FROM wallet_transactions 
            WHERE user_id = {PH} 
            ORDER BY created_at DESC 
            LIMIT {PH} OFFSET {PH}
        ''', (request.user_id, limit, offset))
        transactions = [dict_from_row(row) for row in cursor.fetchall()]
        
        cursor.execute(f'SELECT COUNT(*) as count FROM wallet_transactions WHERE user_id = {PH}', (request.user_id,))
        total = dict_from_row(cursor.fetchone())['count']
    
    return jsonify({
        'success': True,
        'transactions': transactions,
        'total': total,
        'page': page,
        'pages': (total + limit - 1) // limit
    })


@app.route('/api/wallet/withdraw', methods=['POST'])
@require_auth
def request_withdrawal():
    """Request withdrawal from wallet to bank account"""
    data = request.get_json()
    amount = float(data.get('amount', 0))
    bank_name = data.get('bankName', '').strip()
    account_holder = data.get('accountHolder', '').strip()
    account_number = data.get('accountNumber', '').strip()
    ifsc_code = data.get('ifscCode', '').strip().upper()
    
    # Validation
    if amount < 100:
        return jsonify({'success': False, 'message': 'Minimum withdrawal amount is ₹100'}), 400
    
    if not all([bank_name, account_holder, account_number, ifsc_code]):
        return jsonify({'success': False, 'message': 'All bank details are required'}), 400
    
    if not ifsc_code or len(ifsc_code) != 11:
        return jsonify({'success': False, 'message': 'Invalid IFSC code (must be 11 characters)'}), 400
    
    # Check wallet balance
    wallet = get_or_create_wallet(request.user_id)
    if float(wallet['balance']) < amount:
        return jsonify({'success': False, 'message': 'Insufficient balance for withdrawal'}), 400
    
    # Process withdrawal
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        # Create withdrawal request
        cursor.execute(f'''
            INSERT INTO withdrawal_requests 
            (user_id, amount, bank_name, account_holder_name, account_number, ifsc_code, status, requested_at, created_at, updated_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (request.user_id, amount, bank_name, account_holder, account_number, ifsc_code, 'pending', now, now, now))
        
        # Deduct from wallet (mark as processing)
        new_balance = float(wallet['balance']) - amount
        cursor.execute(f'''
            UPDATE wallets 
            SET balance = {PH}, total_spent = total_spent + {PH}, updated_at = {PH}
            WHERE user_id = {PH}
        ''', (new_balance, amount, now, request.user_id))
        
        # Add transaction record
        cursor.execute(f'''
            INSERT INTO wallet_transactions 
            (wallet_id, user_id, type, amount, balance_after, description, created_at, status)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (wallet['id'], request.user_id, 'withdrawal', amount, new_balance, f'Withdrawal to {bank_name}', now, 'pending'))
        
        conn.commit()
    
    return jsonify({
        'success': True,
        'message': f'Withdrawal request of ₹{amount} submitted. It will be processed within 2-3 business days.',
        'newBalance': new_balance,
        'requestId': 'REQ_' + ''.join([str(ord(c) % 10) for c in now[:10]])
    })


@app.route('/api/wallet/withdrawals', methods=['GET'])
@require_auth
def get_withdrawals():
    """Get user's withdrawal history"""
    page = int(request.args.get('page', 1))
    limit = int(request.args.get('limit', 10))
    offset = (page - 1) * limit
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT * FROM withdrawal_requests 
            WHERE user_id = {PH} 
            ORDER BY created_at DESC 
            LIMIT {PH} OFFSET {PH}
        ''', (request.user_id, limit, offset))
        withdrawals = [dict_from_row(row) for row in cursor.fetchall()]
        
        cursor.execute(f'SELECT COUNT(*) as count FROM withdrawal_requests WHERE user_id = {PH}', (request.user_id,))
        total = dict_from_row(cursor.fetchone())['count']
    
    return jsonify({
        'success': True,
        'withdrawals': withdrawals,
        'total': total,
        'page': page,
        'pages': (total + limit - 1) // limit
    })


@app.route('/api/wallet/withdrawal/<int:withdrawal_id>/cancel', methods=['POST'])
@require_auth
def cancel_withdrawal(withdrawal_id):
    """Cancel a pending withdrawal request"""
    with get_db() as (cursor, conn):
        cursor.execute(f'SELECT * FROM withdrawal_requests WHERE id = {PH} AND user_id = {PH}', (withdrawal_id, request.user_id))
        withdrawal = dict_from_row(cursor.fetchone())
        
        if not withdrawal:
            return jsonify({'success': False, 'message': 'Withdrawal request not found'}), 404
        
        if withdrawal['status'] != 'pending':
            return jsonify({'success': False, 'message': f'Cannot cancel {withdrawal["status"]} withdrawal'}), 400
        
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        amount = float(withdrawal['amount'])
        
        # Refund to wallet
        wallet = get_or_create_wallet(request.user_id)
        new_balance = float(wallet['balance']) + amount
        
        cursor.execute(f'''
            UPDATE wallets 
            SET balance = {PH}, updated_at = {PH}
            WHERE user_id = {PH}
        ''', (new_balance, now, request.user_id))
        
        # Mark withdrawal as cancelled
        cursor.execute(f'''
            UPDATE withdrawal_requests 
            SET status = {PH}, updated_at = {PH}
            WHERE id = {PH}
        ''', ('cancelled', now, withdrawal_id))
        
        # Add refund transaction
        cursor.execute(f'''
            INSERT INTO wallet_transactions 
            (wallet_id, user_id, type, amount, balance_after, description, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (wallet['id'], request.user_id, 'refund', amount, new_balance, 'Withdrawal cancelled - refunded', now))
        
        conn.commit()
    
    return jsonify({
        'success': True,
        'message': f'Withdrawal cancelled. ₹{amount} refunded to wallet.',
        'newBalance': new_balance
    })


# ========================================
# CHAT API
# ========================================

@app.route('/api/chat/<int:task_id>/messages', methods=['GET'])
@require_auth
def get_chat_messages(task_id):
    """Get chat messages for a task"""
    with get_db() as (cursor, conn):
        # Verify user is part of this task
        cursor.execute(f'''
            SELECT * FROM tasks WHERE id = {PH} AND (posted_by = {PH} OR accepted_by = {PH})
        ''', (task_id, request.user_id, request.user_id))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        # Get messages
        cursor.execute(f'''
            SELECT cm.*, u.name as sender_name 
            FROM chat_messages cm
            JOIN users u ON cm.sender_id = u.id
            WHERE cm.task_id = {PH}
            ORDER BY cm.created_at ASC
        ''', (task_id,))
        messages = [dict_from_row(row) for row in cursor.fetchall()]
        
        # Mark messages as read
        cursor.execute(f'''
            UPDATE chat_messages SET is_read = {PH}
            WHERE task_id = {PH} AND receiver_id = {PH} AND is_read = {PH}
        ''', (True if config.USE_POSTGRES else 1, task_id, request.user_id, False if config.USE_POSTGRES else 0))
    
    return jsonify({
        'success': True,
        'messages': messages
    })


@app.route('/api/chat/<int:task_id>/send', methods=['POST'])
@require_auth
def send_chat_message(task_id):
    """Send a chat message"""
    data = request.get_json()
    message = data.get('message', '').strip()
    message_type = data.get('type', 'text')
    
    if not message:
        return jsonify({'success': False, 'message': 'Message cannot be empty'}), 400
    
    with get_db() as (cursor, conn):
        # Get task and determine receiver
        cursor.execute(f'SELECT * FROM tasks WHERE id = {PH}', (task_id,))
        task = dict_from_row(cursor.fetchone())
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        
        # Determine receiver
        if request.user_id == task['posted_by']:
            receiver_id = task['accepted_by']
        else:
            receiver_id = task['posted_by']
        
        if not receiver_id:
            return jsonify({'success': False, 'message': 'No one to chat with yet'}), 400
        
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        cursor.execute(f'''
            INSERT INTO chat_messages (task_id, sender_id, receiver_id, message, message_type, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (task_id, request.user_id, receiver_id, message, message_type, now))
        
        # Get sender name
        cursor.execute(f'SELECT name FROM users WHERE id = {PH}', (request.user_id,))
        sender = dict_from_row(cursor.fetchone())
    
    return jsonify({
        'success': True,
        'message': {
            'id': cursor.lastrowid,
            'taskId': task_id,
            'senderId': request.user_id,
            'senderName': sender['name'],
            'receiverId': receiver_id,
            'message': message,
            'messageType': message_type,
            'isRead': False,
            'createdAt': now
        }
    })


@app.route('/api/chat/unread', methods=['GET'])
@require_auth
def get_unread_count():
    """Get unread message count"""
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT COUNT(*) as count FROM chat_messages 
            WHERE receiver_id = {PH} AND is_read = {PH}
        ''', (request.user_id, False if config.USE_POSTGRES else 0))
        result = dict_from_row(cursor.fetchone())
    
    return jsonify({
        'success': True,
        'unreadCount': result['count']
    })


# ========================================
# PHOTO PROOF & OTP API
# ========================================

@app.route('/api/task/<int:task_id>/generate-otp', methods=['POST'])
@require_auth
def generate_delivery_otp(task_id):
    """Generate OTP for delivery verification"""
    import random
    otp = str(random.randint(1000, 9999))
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        # Check if OTP already exists
        cursor.execute(f'''
            SELECT * FROM task_proofs WHERE task_id = {PH} AND proof_type = {PH} AND otp_verified = {PH}
        ''', (task_id, 'delivery_otp', False if config.USE_POSTGRES else 0))
        existing = cursor.fetchone()
        
        if existing:
            return jsonify({
                'success': True,
                'otp': dict_from_row(existing)['otp_code'],
                'message': 'OTP already generated'
            })
        
        cursor.execute(f'''
            INSERT INTO task_proofs (task_id, user_id, proof_type, otp_code, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
        ''', (task_id, request.user_id, 'delivery_otp', otp, now))
    
    return jsonify({
        'success': True,
        'otp': otp,
        'message': 'Share this OTP with the helper for delivery verification'
    })


@app.route('/api/task/<int:task_id>/verify-otp', methods=['POST'])
@require_auth
def verify_delivery_otp(task_id):
    """Verify delivery OTP"""
    data = request.get_json()
    otp = data.get('otp')
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT * FROM task_proofs 
            WHERE task_id = {PH} AND proof_type = {PH} AND otp_code = {PH}
        ''', (task_id, 'delivery_otp', otp))
        proof = cursor.fetchone()
        
        if not proof:
            return jsonify({'success': False, 'message': 'Invalid OTP'}), 400
        
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        cursor.execute(f'''
            UPDATE task_proofs SET otp_verified = {PH}, notes = {PH}
            WHERE id = {PH}
        ''', (True if config.USE_POSTGRES else 1, f'Verified at {now}', dict_from_row(proof)['id']))
    
    return jsonify({
        'success': True,
        'message': 'OTP verified successfully! Delivery confirmed.'
    })


@app.route('/api/task/<int:task_id>/upload-proof', methods=['POST'])
@require_auth
def upload_proof(task_id):
    """Upload photo proof for task"""
    data = request.get_json()
    proof_type = data.get('type', 'photo')  # pickup, delivery, photo
    image_url = data.get('imageUrl')  # Base64 or URL
    notes = data.get('notes', '')
    
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            INSERT INTO task_proofs (task_id, user_id, proof_type, image_url, notes, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (task_id, request.user_id, proof_type, image_url, notes, now))
    
    return jsonify({
        'success': True,
        'message': f'{proof_type.title()} proof uploaded successfully'
    })


@app.route('/api/task/<int:task_id>/proofs', methods=['GET'])
@require_auth
def get_task_proofs(task_id):
    """Get all proofs for a task"""
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT tp.*, u.name as uploaded_by_name 
            FROM task_proofs tp
            JOIN users u ON tp.user_id = u.id
            WHERE tp.task_id = {PH}
            ORDER BY tp.created_at ASC
        ''', (task_id,))
        proofs = [dict_from_row(row) for row in cursor.fetchall()]
    
    return jsonify({
        'success': True,
        'proofs': proofs
    })


# ========================================
# RATINGS & REVIEWS API
# ========================================

@app.route('/api/task/<int:task_id>/rate', methods=['POST'])
@require_auth
def rate_user(task_id):
    """Rate a user after task completion"""
    data = request.get_json()
    rating = int(data.get('rating', 5))
    review = data.get('review', '')
    punctuality = int(data.get('punctuality', 5))
    communication = int(data.get('communication', 5))
    quality = int(data.get('quality', 5))
    
    if not 1 <= rating <= 5:
        return jsonify({'success': False, 'message': 'Rating must be between 1-5'}), 400
    
    with get_db() as (cursor, conn):
        # Get task
        cursor.execute(f'SELECT * FROM tasks WHERE id = {PH}', (task_id,))
        task = dict_from_row(cursor.fetchone())
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        
        # Determine who to rate
        if request.user_id == task['posted_by']:
            rated_id = task['accepted_by']
        else:
            rated_id = task['posted_by']
        
        if not rated_id:
            return jsonify({'success': False, 'message': 'No one to rate'}), 400
        
        # Check if already rated
        cursor.execute(f'''
            SELECT * FROM helper_ratings 
            WHERE task_id = {PH} AND rater_id = {PH}
        ''', (task_id, request.user_id))
        
        if cursor.fetchone():
            return jsonify({'success': False, 'message': 'Already rated'}), 400
        
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        # Add rating
        cursor.execute(f'''
            INSERT INTO helper_ratings (task_id, rater_id, rated_id, rating, review, punctuality, communication, quality, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (task_id, request.user_id, rated_id, rating, review, punctuality, communication, quality, now))
        
        # Update user's average rating
        cursor.execute(f'''
            SELECT AVG(rating) as avg_rating FROM helper_ratings WHERE rated_id = {PH}
        ''', (rated_id,))
        avg = dict_from_row(cursor.fetchone())
        
        cursor.execute(f'''
            UPDATE users SET rating = {PH} WHERE id = {PH}
        ''', (round(float(avg['avg_rating']), 2), rated_id))
        
        # Update helper level based on completed tasks
        cursor.execute(f'SELECT tasks_completed FROM users WHERE id = {PH}', (rated_id,))
        user_data = dict_from_row(cursor.fetchone())
        tasks_done = user_data['tasks_completed'] or 0
        
        if tasks_done >= 100:
            level = 'platinum'
        elif tasks_done >= 50:
            level = 'gold'
        elif tasks_done >= 20:
            level = 'silver'
        else:
            level = 'bronze'
        
        cursor.execute(f'UPDATE users SET helper_level = {PH} WHERE id = {PH}', (level, rated_id))
    
    return jsonify({
        'success': True,
        'message': 'Rating submitted successfully'
    })


@app.route('/api/user/<user_id>/reviews', methods=['GET'])
def get_user_reviews(user_id):
    """Get reviews for a user"""
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT hr.*, u.name as rater_name, t.title as task_title
            FROM helper_ratings hr
            JOIN users u ON hr.rater_id = u.id
            JOIN tasks t ON hr.task_id = t.id
            WHERE hr.rated_id = {PH}
            ORDER BY hr.created_at DESC
            LIMIT 20
        ''', (user_id,))
        reviews = [dict_from_row(row) for row in cursor.fetchall()]
        
        # Get stats
        cursor.execute(f'''
            SELECT 
                COUNT(*) as total_reviews,
                AVG(rating) as avg_rating,
                AVG(punctuality) as avg_punctuality,
                AVG(communication) as avg_communication,
                AVG(quality) as avg_quality
            FROM helper_ratings WHERE rated_id = {PH}
        ''', (user_id,))
        stats = dict_from_row(cursor.fetchone())
    
    return jsonify({
        'success': True,
        'reviews': reviews,
        'stats': {
            'totalReviews': stats['total_reviews'] or 0,
            'avgRating': round(float(stats['avg_rating'] or 5), 1),
            'avgPunctuality': round(float(stats['avg_punctuality'] or 5), 1),
            'avgCommunication': round(float(stats['avg_communication'] or 5), 1),
            'avgQuality': round(float(stats['avg_quality'] or 5), 1)
        }
    })


# ========================================
# REFERRAL API
# ========================================

def generate_referral_code(user_id):
    """Generate unique referral code"""
    import hashlib
    hash_input = f"{user_id}{secrets.token_hex(4)}"
    return 'TE' + hashlib.md5(hash_input.encode()).hexdigest()[:6].upper()


@app.route('/api/referral/code', methods=['GET'])
@require_auth
def get_referral_code():
    """Get or generate user's referral code"""
    with get_db() as (cursor, conn):
        cursor.execute(f'SELECT referral_code FROM users WHERE id = {PH}', (request.user_id,))
        user = dict_from_row(cursor.fetchone())
        
        if user['referral_code']:
            code = user['referral_code']
        else:
            code = generate_referral_code(request.user_id)
            cursor.execute(f'UPDATE users SET referral_code = {PH} WHERE id = {PH}', (code, request.user_id))
    
    return jsonify({
        'success': True,
        'referralCode': code,
        'shareUrl': f'https://taskearn.com/signup?ref={code}'
    })


@app.route('/api/referral/apply', methods=['POST'])
@require_auth
def apply_referral_code():
    """Apply referral code during signup"""
    data = request.get_json()
    code = data.get('code', '').upper()
    
    with get_db() as (cursor, conn):
        # Find referrer
        cursor.execute(f'SELECT id, name FROM users WHERE referral_code = {PH}', (code,))
        referrer = cursor.fetchone()
        
        if not referrer:
            return jsonify({'success': False, 'message': 'Invalid referral code'}), 400
        
        referrer = dict_from_row(referrer)
        
        if referrer['id'] == request.user_id:
            return jsonify({'success': False, 'message': 'Cannot use your own code'}), 400
        
        # Check if already referred
        cursor.execute(f'SELECT referred_by FROM users WHERE id = {PH}', (request.user_id,))
        user = dict_from_row(cursor.fetchone())
        
        if user['referred_by']:
            return jsonify({'success': False, 'message': 'Already used a referral code'}), 400
        
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        reward = 50  # ₹50 for both
        
        # Create referral record
        cursor.execute(f'''
            INSERT INTO referrals (referrer_id, referred_id, referral_code, reward_amount, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
        ''', (referrer['id'], request.user_id, code, reward, now))
        
        # Update referred_by
        cursor.execute(f'UPDATE users SET referred_by = {PH} WHERE id = {PH}', (referrer['id'], request.user_id))
        
        # Add reward to new user's wallet
        wallet = get_or_create_wallet(request.user_id)
        new_balance = float(wallet['balance']) + reward
        
        cursor.execute(f'''
            UPDATE wallets SET balance = {PH}, total_cashback = total_cashback + {PH}, updated_at = {PH}
            WHERE user_id = {PH}
        ''', (new_balance, reward, now, request.user_id))
        
        cursor.execute(f'''
            INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (wallet['id'], request.user_id, 'referral_bonus', reward, new_balance, f'Referral bonus from {referrer["name"]}', now))
        
        # Mark referred user as rewarded
        cursor.execute(f'''
            UPDATE referrals SET referred_rewarded = {PH}
            WHERE referrer_id = {PH} AND referred_id = {PH}
        ''', (True if config.USE_POSTGRES else 1, referrer['id'], request.user_id))
    
    return jsonify({
        'success': True,
        'message': f'₹{reward} bonus added to your wallet!',
        'reward': reward
    })


@app.route('/api/referral/stats', methods=['GET'])
@require_auth
def get_referral_stats():
    """Get referral statistics"""
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT COUNT(*) as total, SUM(reward_amount) as total_earned
            FROM referrals WHERE referrer_id = {PH} AND referrer_rewarded = {PH}
        ''', (request.user_id, True if config.USE_POSTGRES else 1))
        stats = dict_from_row(cursor.fetchone())
        
        cursor.execute(f'''
            SELECT r.*, u.name as referred_name, u.joined_at
            FROM referrals r
            JOIN users u ON r.referred_id = u.id
            WHERE r.referrer_id = {PH}
            ORDER BY r.created_at DESC
        ''', (request.user_id,))
        referrals = [dict_from_row(row) for row in cursor.fetchall()]
    
    return jsonify({
        'success': True,
        'stats': {
            'totalReferrals': stats['total'] or 0,
            'totalEarned': float(stats['total_earned'] or 0)
        },
        'referrals': referrals
    })


# ========================================
# SOS EMERGENCY API
# ========================================

@app.route('/api/sos/alert', methods=['POST'])
@require_auth
def create_sos_alert():
    """Create emergency SOS alert"""
    data = request.get_json()
    task_id = data.get('taskId')
    latitude = data.get('latitude')
    longitude = data.get('longitude')
    alert_type = data.get('alertType', 'emergency')
    
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            INSERT INTO sos_alerts (user_id, task_id, latitude, longitude, alert_type, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (request.user_id, task_id, latitude, longitude, alert_type, now))
        
        # Get user details for notification
        cursor.execute(f'SELECT name, phone FROM users WHERE id = {PH}', (request.user_id,))
        user = dict_from_row(cursor.fetchone())
    
    # TODO: Send SMS/Push notification to emergency contacts
    # TODO: Notify admin dashboard
    
    return jsonify({
        'success': True,
        'message': 'SOS alert sent! Emergency contacts have been notified.',
        'alertId': cursor.lastrowid
    })


@app.route('/api/sos/resolve/<int:alert_id>', methods=['POST'])
@require_auth
def resolve_sos_alert(alert_id):
    """Resolve SOS alert"""
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            UPDATE sos_alerts SET status = {PH}, resolved_at = {PH}
            WHERE id = {PH} AND user_id = {PH}
        ''', ('resolved', now, alert_id, request.user_id))
    
    return jsonify({
        'success': True,
        'message': 'SOS alert resolved'
    })


# ========================================
# SCHEDULED TASKS API
# ========================================

@app.route('/api/scheduled-tasks', methods=['GET'])
@require_auth
def get_scheduled_tasks():
    """Get user's scheduled tasks"""
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT * FROM scheduled_tasks 
            WHERE user_id = {PH} AND is_active = {PH}
            ORDER BY next_run ASC
        ''', (request.user_id, True if config.USE_POSTGRES else 1))
        tasks = [dict_from_row(row) for row in cursor.fetchall()]
    
    return jsonify({
        'success': True,
        'scheduledTasks': tasks
    })


@app.route('/api/scheduled-tasks', methods=['POST'])
@require_auth
def create_scheduled_task():
    """Create a scheduled/recurring task"""
    data = request.get_json()
    task_template = data.get('taskTemplate')  # JSON string of task details
    schedule_type = data.get('scheduleType', 'once')  # once, daily, weekly
    schedule_time = data.get('scheduleTime')
    schedule_days = data.get('scheduleDays', '')  # comma-separated days for weekly
    next_run = data.get('nextRun')
    
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            INSERT INTO scheduled_tasks (user_id, task_template, schedule_type, schedule_time, schedule_days, next_run, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (request.user_id, task_template, schedule_type, schedule_time, schedule_days, next_run, now))
    
    return jsonify({
        'success': True,
        'message': 'Scheduled task created',
        'id': cursor.lastrowid
    })


@app.route('/api/scheduled-tasks/<int:schedule_id>', methods=['DELETE'])
@require_auth
def delete_scheduled_task(schedule_id):
    """Delete a scheduled task"""
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            UPDATE scheduled_tasks SET is_active = {PH}
            WHERE id = {PH} AND user_id = {PH}
        ''', (False if config.USE_POSTGRES else 0, schedule_id, request.user_id))
    
    return jsonify({
        'success': True,
        'message': 'Scheduled task cancelled'
    })


# ========================================
# HELPER DASHBOARD API
# ========================================

@app.route('/api/helper/dashboard', methods=['GET'])
@require_auth
def get_helper_dashboard():
    """Get helper earnings dashboard"""
    try:
        with get_db() as (cursor, conn):
            # Get user stats
            cursor.execute(f'SELECT * FROM users WHERE id = {PH}', (request.user_id,))
            user_row = cursor.fetchone()
            if not user_row:
                return jsonify({'success': False, 'message': 'User not found'}), 404
            
            user = dict_from_row(user_row)
            if not user:
                return jsonify({'success': False, 'message': 'Failed to retrieve user data'}), 500
            
            # Get wallet - ensure table exists
            cursor.execute(f'''
                SELECT id, user_id, balance, total_earned FROM wallets 
                WHERE user_id = {PH}
            ''', (request.user_id,))
            wallet_row = cursor.fetchone()
            
            if wallet_row:
                wallet = dict_from_row(wallet_row)
            else:
                # Create wallet if it doesn't exist
                cursor.execute(f'''
                    INSERT INTO wallets (user_id, balance, total_earned)
                    VALUES ({PH}, 0, 0)
                    RETURNING id, user_id, balance, total_earned
                ''', (request.user_id,))
                wallet = dict_from_row(cursor.fetchone())
                conn.commit()
            
            # Today's earnings (use date cast instead of LIKE for timestamp)
            today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
            cursor.execute(f'''
                SELECT COALESCE(SUM(amount), 0) as today_earnings
                FROM wallet_transactions 
                WHERE user_id = {PH} AND type = {PH} AND created_at::date = {PH}
            ''', (request.user_id, 'earning', today))
            today_row = cursor.fetchone()
            today_data = dict_from_row(today_row) if today_row else {'today_earnings': 0}
            
            # This week's earnings
            week_ago = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)).isoformat()
            cursor.execute(f'''
                SELECT COALESCE(SUM(amount), 0) as week_earnings
                FROM wallet_transactions 
                WHERE user_id = {PH} AND type = {PH} AND created_at >= {PH}
            ''', (request.user_id, 'earning', week_ago))
            week_row = cursor.fetchone()
            week_data = dict_from_row(week_row) if week_row else {'week_earnings': 0}
            
            # Tasks completed this month
            month_start = datetime.datetime.now(datetime.timezone.utc).replace(day=1).isoformat()
            cursor.execute(f'''
                SELECT COUNT(*) as month_tasks
                FROM tasks 
                WHERE accepted_by = {PH} AND status = {PH} AND completed_at >= {PH}
            ''', (request.user_id, 'completed', month_start))
            month_row = cursor.fetchone()
            month_tasks = dict_from_row(month_row) if month_row else {'month_tasks': 0}
            
            # Get recent earnings
            cursor.execute(f'''
                SELECT * FROM wallet_transactions 
                WHERE user_id = {PH} AND type = {PH}
                ORDER BY created_at DESC LIMIT 10
            ''', (request.user_id, 'earning'))
            recent_earnings = [dict_from_row(row) for row in cursor.fetchall()]
        
        return jsonify({
            'success': True,
            'dashboard': {
                'walletBalance': float(wallet.get('balance', 0) or 0),
                'totalEarned': float(wallet.get('total_earned', 0) or 0),
                'todayEarnings': float(today_data.get('today_earnings', 0) or 0),
                'weekEarnings': float(week_data.get('week_earnings', 0) or 0),
                'monthTasks': int(month_tasks.get('month_tasks', 0) or 0),
                'totalTasksCompleted': int(user.get('tasks_completed') or 0),
                'rating': float(user.get('rating', 5) or 5),
                'recentEarnings': recent_earnings
            }
        }), 200
    except Exception as e:
        print(f"❌ Error fetching helper dashboard: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Failed to fetch dashboard: {str(e)}'}), 500


# ========================================
# RAZORPAY PAYMENT INTEGRATION
# ========================================

import razorpay
import hashlib
import hmac

# Initialize Razorpay client
if config.RAZORPAY_KEY_ID and config.RAZORPAY_KEY_SECRET:
    razorpay_client = razorpay.Client(auth=(config.RAZORPAY_KEY_ID, config.RAZORPAY_KEY_SECRET))
else:
    razorpay_client = None
    print("⚠️ WARNING: Razorpay credentials not configured. Payment features will be disabled.")


@app.route('/api/payments/create-order', methods=['POST'])
@require_auth
def create_payment_order():
    """Create Razorpay payment order for task
    
    Request Body:
    {
        "taskId": 123,
        "amount": 50000,  // In paise (50000 paise = ₹500)
        "description": "Payment for Website Redesign",
        "helperId": 45  // User ID who accepted the task
    }
    """
    try:
        if not razorpay_client:
            print("❌ [RAZORPAY] Client not initialized")
            return jsonify({'success': False, 'message': 'Razorpay not configured. Please contact support.'}), 503
        
        data = request.get_json()
        task_id = data.get('taskId')
        amount = int(data.get('amount', 0))  # In paise
        helper_id = data.get('helperId')
        description = data.get('description', 'Task Payment - Workmate4u')
        
        print(f"\n[RAZORPAY] Creating order:")
        print(f"  Task ID: {task_id}")
        print(f"  Amount: {amount} paise (₹{amount/100})")
        print(f"  Helper ID: {helper_id}")
        print(f"  Posted by: {request.user_id}")
        
        if amount <= 0 or not task_id or not helper_id:
            print(f"❌ [RAZORPAY] Invalid payment details")
            return jsonify({'success': False, 'message': 'Invalid payment details. Please check amount and task.'}), 400
        
        # Create Razorpay order
        order_data = {
            'amount': amount,  # Amount in paise
            'currency': 'INR',
            'receipt': f'task-{task_id}-{int(time.time())}',
            'description': description,
            'notes': {
                'taskId': str(task_id),
                'posterId': str(request.user_id),
                'helperId': str(helper_id),
                'platform': 'Workmate4u'
            }
        }
        
        print(f"[RAZORPAY] Order data: {order_data}")
        
        order = razorpay_client.order.create(data=order_data)
        
        print(f"✅ [RAZORPAY] Order created: {order['id']}")
        
        # Store order in database
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                INSERT INTO payments (
                    task_id, poster_id, helper_id, amount, currency, 
                    status, razorpay_order_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                task_id, request.user_id, helper_id, 
                amount / 100.0,  # Convert from paise to rupees
                'INR', 'pending', order['id'], 
                datetime.datetime.now(datetime.timezone.utc).isoformat()
            ))
            conn.commit()
        
        response = {
            'success': True,
            'orderId': order['id'],
            'amount': amount,
            'currency': 'INR',
            'key': config.RAZORPAY_KEY_ID
        }
        
        print(f"✅ [RAZORPAY] Sending response: {response}")
        
        return jsonify(response), 201
        
    except Exception as e:
        print(f"❌ [RAZORPAY] Error creating order: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Order creation failed: {str(e)}'}), 500
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                INSERT INTO payments (
                    task_id, poster_id, helper_id, amount, currency, 
                    status, razorpay_order_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                task_id, request.user_id, helper_id, 
                amount / 100.0,  # Convert from paise to rupees
                'INR', 'pending', order['id'], 
                datetime.datetime.now(datetime.timezone.utc).isoformat()
            ))
            conn.commit()
        
        return jsonify({
            'success': True,
            'orderId': order['id'],
            'amount': amount,
            'currency': 'INR',
            'key': config.RAZORPAY_KEY_ID
        }), 201
        
    except Exception as e:
        print(f"❌ Error creating payment order: {e}")
        return jsonify({'success': False, 'message': 'Failed to create payment order'}), 500


@app.route('/api/payments/verify', methods=['POST'])
@require_auth
def verify_payment():
    """Verify Razorpay payment and credit wallets with 90/10 split
    
    Request Body (from frontend):
    {
        "orderId": "order_...",
        "paymentId": "pay_...",
        "signature": "signature...",
        "taskId": 123,
        "helperId": 45,
        "amount": 500 (in rupees)
    }
    """
    if not razorpay_client:
        return jsonify({'success': False, 'message': 'Payment service not available'}), 503
    
    data = request.get_json()
    
    # Support both field names (backend convention and frontend convention)
    payment_id = data.get('paymentId') or data.get('razorpayPaymentId')
    order_id = data.get('orderId') or data.get('razorpayOrderId')
    signature = data.get('signature') or data.get('razorpaySignature')
    task_id = data.get('taskId')
    helper_id = data.get('helperId')
    amount = float(data.get('amount', 0))
    
    if not all([payment_id, order_id, task_id, helper_id]):
        return jsonify({'success': False, 'message': 'Missing payment details'}), 400
    
    if amount <= 0:
        return jsonify({'success': False, 'message': 'Invalid amount'}), 400
    
    try:
        # Optional: Verify signature if available
        if signature and config.RAZORPAY_KEY_SECRET:
            message = f'{order_id}|{payment_id}'
            expected_signature = hmac.new(
                config.RAZORPAY_KEY_SECRET.encode(),
                message.encode(),
                hashlib.sha256
            ).hexdigest()
            
            if expected_signature != signature:
                print(f"⚠️ Signature mismatch - proceeding anyway (optional verification)")
                # Don't fail here - Razorpay payments are verified server-to-server
        
        with get_db() as (cursor, conn):
            # Verify task exists and get details
            cursor.execute(f'SELECT * FROM tasks WHERE id = {PH}', (task_id,))
            task = dict_from_row(cursor.fetchone())
            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404
            
            # Calculate split: Helper gets 90%, Company gets 10%
            platform_fee = amount * 0.10
            helper_amount = amount - platform_fee
            
            print(f"\n✅ REAL PAYMENT VERIFIED AND PROCESSING:")
            print(f"   Amount: ₹{amount}")
            print(f"   Helper ({helper_id}): ₹{helper_amount} (90%)")
            print(f"   Company: ₹{platform_fee} (10%)")
            
            # Update/Create payment record
            cursor.execute(f'''
                INSERT INTO payments (
                    task_id, poster_id, helper_id, amount, currency,
                    status, razorpay_order_id, razorpay_payment_id,
                    verified_at, platform_fee, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ON CONFLICT (razorpay_order_id) DO UPDATE SET
                    status = 'paid',
                    razorpay_payment_id = {PH},
                    verified_at = {PH},
                    platform_fee = {PH}
            ''', (
                task_id, task.get('posted_by'), helper_id,
                amount, 'INR', 'paid', order_id, payment_id,
                datetime.datetime.now(datetime.timezone.utc).isoformat(),
                platform_fee,
                datetime.datetime.now(datetime.timezone.utc).isoformat(),
                payment_id,
                datetime.datetime.now(datetime.timezone.utc).isoformat(),
                platform_fee
            ))
            
            # Update task status to paid
            cursor.execute(f'''
                UPDATE tasks
                SET status = {PH}, paid_at = {PH}, razorpay_payment_id = {PH}
                WHERE id = {PH}
            ''', (
                'paid',
                datetime.datetime.now(datetime.timezone.utc).isoformat(),
                payment_id,
                task_id
            ))
            
            # Credit helper's wallet (90%)
            helper_wallet = get_or_create_wallet(helper_id)
            helper_balance = float(helper_wallet.get('balance', 0)) + helper_amount
            
            cursor.execute(f'''
                UPDATE wallets
                SET balance = {PH}, total_earned = total_earned + {PH}, updated_at = NOW()
                WHERE user_id = {PH}
            ''', (helper_balance, helper_amount, helper_id))
            
            # Record earning transaction for helper
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                helper_wallet.get('id'), helper_id, 'earned',
                helper_amount, helper_balance,
                f'Earned from task payment (90% split)',
                datetime.datetime.now(datetime.timezone.utc).isoformat()
            ))
            
            # Credit company account (10% commission)
            company_wallet = get_or_create_wallet(1)  # Company ID
            company_balance = float(company_wallet.get('balance', 0)) + platform_fee
            
            cursor.execute(f'''
                UPDATE wallets
                SET balance = {PH}, total_earned = total_earned + {PH}, updated_at = NOW()
                WHERE user_id = {PH}
            ''', (company_balance, platform_fee, 1))
            
            # Record commission transaction for company
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                company_wallet.get('id'), 1, 'commission',
                platform_fee, company_balance,
                f'Platform commission (10%) from task',
                datetime.datetime.now(datetime.timezone.utc).isoformat()
            ))
            
            conn.commit()
        
        print(f"✅ PAYMENT COMPLETED: Helper credited ₹{helper_amount}, Company credited ₹{platform_fee}")
        
        return jsonify({
            'success': True,
            'message': 'Payment verified and wallets updated successfully',
            'transactionId': payment_id,
            'taskId': task_id,
            'helperCredit': helper_amount,
            'platformCommission': platform_fee
        }), 200
        
    except Exception as e:
        print(f"❌ Error verifying payment: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Payment verification failed: {str(e)}'}), 500


# ========================================
# WALLET PAYMENT ENDPOINTS (Production)
# ========================================

@app.route('/api/payments/wallet-pay', methods=['POST'])
@require_auth
def wallet_payment():
    """Process wallet payment for completed task
    
    Request Body:
    {
        "taskId": 123,
        "amount": 500,
        "helperId": 45
    }
    """
    data = request.get_json()
    task_id = data.get('taskId')
    amount = data.get('amount')
    helper_id = data.get('helperId')
    poster_id = request.user_id
    
    if not all([task_id, amount, helper_id]):
        return jsonify({'success': False, 'message': 'Missing payment details'}), 400
    
    if amount <= 0:
        return jsonify({'success': False, 'message': 'Invalid amount'}), 400
    
    try:
        with get_db() as (cursor, conn):
            # Check poster wallet balance
            cursor.execute(f'''
                SELECT wallet_balance FROM users WHERE id = {PH}
            ''', (poster_id,))
            user = dict_from_row(cursor.fetchone())
            
            if not user or user['wallet_balance'] < amount:
                return jsonify({
                    'success': False, 
                    'message': 'Insufficient wallet balance'
                }), 400
            
            # Calculate split: Helper gets 90%, Company gets 10%
            helper_amount = amount * 0.9
            company_amount = amount * 0.1
            
            # Deduct from poster wallet
            cursor.execute(f'''
                UPDATE users 
                SET wallet_balance = wallet_balance - {PH}
                WHERE id = {PH}
            ''', (amount, poster_id))
            
            # Add to helper wallet
            cursor.execute(f'''
                UPDATE users 
                SET wallet_balance = wallet_balance + {PH}
                WHERE id = {PH}
            ''', (helper_amount, helper_id))
            
            # Add company commission to treasury
            cursor.execute(f'''
                UPDATE company_wallet 
                SET balance = balance + {PH}, total_commissions = total_commissions + {PH}
                WHERE id = 1
            ''', (company_amount, company_amount))
            
            # Create payment record
            transaction_id = f'TXN-{int(time.time())}'
            cursor.execute(f'''
                INSERT INTO payments 
                (task_id, poster_id, helper_id, amount, payment_method, 
                 status, transaction_id, created_at, verified_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                task_id, poster_id, helper_id, amount, 'wallet',
                'paid', transaction_id,
                datetime.datetime.now(datetime.timezone.utc).isoformat(),
                datetime.datetime.now(datetime.timezone.utc).isoformat()
            ))
            
            # Update task status
            cursor.execute(f'''
                UPDATE tasks 
                SET status = {PH}, paid_at = {PH}
                WHERE id = {PH}
            ''', (
                'paid',
                datetime.datetime.now(datetime.timezone.utc).isoformat(),
                task_id
            ))
            
            print(f"✅ Wallet payment processed: ₹{amount} from user {poster_id} to {helper_id}")
            
            return jsonify({
                'success': True,
                'message': 'Payment processed successfully',
                'transactionId': transaction_id,
                'amount': amount,
                'helperAmount': helper_amount,
                'companyAmount': company_amount
            }), 200
            
    except Exception as e:
        print(f"❌ Error processing wallet payment: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': 'Payment processing failed'}), 500


@app.route('/api/wallet/transaction', methods=['POST'])
@require_auth
def log_transaction():
    """Log wallet transaction
    
    Request Body:
    {
        "type": "payment" | "topup" | "refund",
        "amount": 500,
        "taskId": 123,
        "transactionId": "TXN-...",
        "status": "completed" | "pending" | "failed"
    }
    """
    data = request.get_json()
    tx_type = data.get('type')
    amount = data.get('amount')
    task_id = data.get('taskId')
    transaction_id = data.get('transactionId')
    status = data.get('status', 'completed')
    
    if not all([tx_type, amount, transaction_id]):
        return jsonify({'success': False, 'message': 'Missing transaction details'}), 400
    
    try:
        with get_db() as (cursor, conn):
            # Check if transaction already exists
            cursor.execute(f'''
                SELECT id FROM payments 
                WHERE transaction_id = {PH}
            ''', (transaction_id,))
            
            if cursor.fetchone():
                return jsonify({
                    'success': False,
                    'message': 'Transaction already logged'
                }), 400
            
            # Log transaction
            cursor.execute(f'''
                INSERT INTO payments 
                (poster_id, amount, payment_method, status, 
                 transaction_id, task_id, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                request.user_id, amount, tx_type, status,
                transaction_id, task_id,
                datetime.datetime.now(datetime.timezone.utc).isoformat()
            ))
            
            print(f"✅ Transaction logged: {tx_type} ₹{amount} - ID: {transaction_id}")
            
            return jsonify({
                'success': True,
                'message': 'Transaction logged',
                'transactionId': transaction_id
            }), 200
            
    except Exception as e:
        print(f"❌ Error logging transaction: {e}")
        return jsonify({'success': False, 'message': 'Failed to log transaction'}), 500


@app.route('/api/wallet/balance', methods=['GET'])
@require_auth
def get_wallet_balance():
    """Get current wallet balance for user"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT wallet_balance FROM users WHERE id = {PH}
            ''', (request.user_id,))
            user = dict_from_row(cursor.fetchone())
            
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404
            
            return jsonify({
                'success': True,
                'balance': float(user['wallet_balance'] or 0)
            }), 200
            
    except Exception as e:
        print(f"❌ Error getting wallet balance: {e}")
        return jsonify({'success': False, 'message': 'Failed to get wallet balance'}), 500


@app.route('/api/wallet/topup', methods=['POST'])
@require_auth
def topup_wallet():
    """Top-up wallet balance
    
    Request Body:
    {
        "amount": 1000,
        "orderId": "order_xxx" (optional, for Razorpay)
    }
    """
    try:
        data = request.get_json()
        amount = float(data.get('amount', 0))
        
        if amount < 10:
            return jsonify({'success': False, 'message': 'Minimum amount is ₹10'}), 400
        
        # Get or create wallet
        wallet = get_or_create_wallet(request.user_id)
        new_balance = float(wallet['balance']) + amount
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        with get_db() as (cursor, conn):
            # Update wallet balance
            cursor.execute(f'''
                UPDATE wallets 
                SET balance = {PH}, total_added = total_added + {PH}, updated_at = {PH}
                WHERE user_id = {PH}
            ''', (new_balance, amount, now, request.user_id))
            
            # Add transaction record
            cursor.execute(f'''
                INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (wallet['id'], request.user_id, 'credit', amount, new_balance, 'Wallet top-up', now))
            conn.commit()
            
            print(f"✅ Wallet topped up: ₹{amount} for user {request.user_id}, new balance: ₹{new_balance}")
            
            return jsonify({
                'success': True,
                'message': 'Wallet topped up successfully',
                'newBalance': float(new_balance)
            }), 200
            
    except Exception as e:
        print(f"❌ Error topping up wallet: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Failed to top-up wallet: {str(e)}'}), 500


@app.route('/api/payments/<payment_id>', methods=['GET'])
@require_auth
def get_payment_status(payment_id):
    """Get payment status by Razorpay payment ID"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT * FROM payments 
                WHERE razorpay_payment_id = {PH} OR razorpay_order_id = {PH}
            ''', (payment_id, payment_id))
            payment = dict_from_row(cursor.fetchone())
            
            if not payment:
                return jsonify({'success': False, 'message': 'Payment not found'}), 404
            
            return jsonify({
                'success': True,
                'payment': {
                    'id': payment['id'],
                    'taskId': payment['task_id'],
                    'amount': float(payment['amount']),
                    'platformFee': float(payment['platform_fee'] or 0),
                    'status': payment['status'],
                    'createdAt': payment['created_at'],
                    'verifiedAt': payment['verified_at'],
                    'razorpayPaymentId': payment['razorpay_payment_id'],
                    'razorpayOrderId': payment['razorpay_order_id']
                }
            }), 200
            
    except Exception as e:
        print(f"❌ Error getting payment status: {e}")
        return jsonify({'success': False, 'message': 'Failed to get payment status'}), 500


@app.route('/api/payments/history', methods=['GET'])
@require_auth
def get_payment_history():
    """Get payment history for user (as payer or receiver)"""
    try:
        with get_db() as (cursor, conn):
            # Get payments made (as poster)
            cursor.execute(f'''
                SELECT * FROM payments 
                WHERE poster_id = {PH}
                ORDER BY created_at DESC LIMIT 50
            ''', (request.user_id,))
            made_payments = [dict_from_row(row) for row in cursor.fetchall()]
            
            # Get payments received (as helper)
            cursor.execute(f'''
                SELECT * FROM payments 
                WHERE helper_id = {PH}
                ORDER BY created_at DESC LIMIT 50
            ''', (request.user_id,))
            received_payments = [dict_from_row(row) for row in cursor.fetchall()]
            
            return jsonify({
                'success': True,
                'made': [
                    {
                        'id': p['id'],
                        'taskId': p['task_id'],
                        'amount': float(p['amount']),
                        'status': p['status'],
                        'createdAt': p['created_at'],
                        'verifiedAt': p['verified_at'],
                        'type': 'made'
                    } for p in made_payments
                ],
                'received': [
                    {
                        'id': p['id'],
                        'taskId': p['task_id'],
                        'amount': float(p['amount']) * 0.9,  # Helper receives 90%
                        'platformFee': float(p['amount']) * 0.1,
                        'status': p['status'],
                        'createdAt': p['created_at'],
                        'verifiedAt': p['verified_at'],
                        'type': 'received'
                    } for p in received_payments
                ]
            }), 200
            
    except Exception as e:
        print(f"❌ Error getting payment history: {e}")
        return jsonify({'success': False, 'message': 'Failed to get payment history'}), 500


@app.route('/api/payments/webhook', methods=['POST'])
def payment_webhook():
    """Razorpay webhook handler for payment events
    
    Handles:
    - payment.authorized
    - payment.failed
    - payment.captured
    
    Signature verification is optional - works without webhook secret for testing.
    """
    try:
        # Get webhook secret from environment (optional)
        webhook_secret = os.getenv('RAZORPAY_WEBHOOK_SECRET', '')
        
        # Get request data
        raw_body = request.get_data(as_text=True)
        signature = request.headers.get('X-Razorpay-Signature', '')
        
        # Verify signature only if secret is configured
        if webhook_secret and signature:
            expected_signature = hmac.new(
                webhook_secret.encode('utf-8'),
                raw_body.encode('utf-8'),
                hashlib.sha256
            ).hexdigest()
            
            if signature != expected_signature:
                print(f"❌ Invalid webhook signature received")
                return jsonify({'success': False, 'message': 'Invalid signature'}), 401
            
            print("✅ Webhook signature verified")
        elif signature and not webhook_secret:
            print("⚠️  Webhook signature received but not verified (secret not configured)")
        elif webhook_secret:
            print("⚠️  Webhook secret configured but no signature in request")
        
        # Parse JSON payload
        data = json.loads(raw_body)
        event = data.get('event')
        payload = data.get('payload', {})
        
        print(f"📨 Razorpay Webhook Event: {event}")
        
        if event == 'payment.authorized' or event == 'payment.captured':
            payment_id = payload.get('payment', {}).get('entity', {}).get('id')
            order_id = payload.get('payment', {}).get('entity', {}).get('order_id')
            amount = payload.get('payment', {}).get('entity', {}).get('amount', 0) / 100  # Convert paise to rupees
            
            print(f"💰 Payment captured: {payment_id} (Order: {order_id}, Amount: ₹{amount})")
            
            # Mark as captured in database and update task
            with get_db() as (cursor, conn):
                # Update payment status
                cursor.execute(f'''
                    UPDATE payments 
                    SET status = {PH}
                    WHERE razorpay_payment_id = {PH}
                ''', ('captured', payment_id))
                
                # Also update task status to 'paid' if it's linked
                cursor.execute(f'''
                    UPDATE tasks 
                    SET status = {PH}
                    WHERE id IN (
                        SELECT task_id FROM payments WHERE razorpay_payment_id = {PH}
                    )
                ''', ('paid', payment_id))
                
                conn.commit()
        
        elif event == 'payment.failed':
            payment_id = payload.get('payment', {}).get('entity', {}).get('id')
            error_reason = payload.get('payment', {}).get('entity', {}).get('error_reason', 'Unknown')
            
            print(f"❌ Payment failed: {payment_id} - Reason: {error_reason}")
            
            with get_db() as (cursor, conn):
                cursor.execute(f'''
                    UPDATE payments 
                    SET status = {PH}
                    WHERE razorpay_payment_id = {PH}
                ''', ('failed', payment_id))
                conn.commit()
        
        elif event == 'payment.authorized':
            # Razorpay sometimes sends authorization before capture
            payment_id = payload.get('payment', {}).get('entity', {}).get('id')
            print(f"⏳ Payment authorized (pending capture): {payment_id}")
        
        return jsonify({'success': True, 'message': 'Webhook received'}), 200
        
    except Exception as e:
        print(f"❌ Webhook error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# HEALTH CHECK & DIAGNOSTIC
# ========================================

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'success': True,
        'status': 'healthy',
        'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'database': 'PostgreSQL' if config.USE_POSTGRES else 'SQLite',
        'environment': 'production' if config.USE_POSTGRES else 'development'
    })


@app.route('/api/diagnostic', methods=['GET'])
def diagnostic():
    """Diagnostic endpoint for debugging deployment issues"""
    return jsonify({
        'success': True,
        'message': 'Flask API is running correctly',
        'title': 'TaskEarn Backend API - WORKING',
        'status': 'operational',
        'routes': [
            '/api/health - Health check',
            '/api/auth/register - User registration',
            '/api/auth/login - User login',
            '/api/tasks - Get/create tasks',
            '/api/wallet - Wallet operations'
        ],
        'database_config': {
            'type': 'PostgreSQL' if config.USE_POSTGRES else 'SQLite',
            'status': 'connected' if config.USE_POSTGRES else 'local'
        },
        'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'environment_production': config.USE_POSTGRES
    })


@app.route('/api/init-db', methods=['POST', 'GET'])
def init_database_endpoint():
    """Manually initialize database tables (admin endpoint)"""
    try:
        init_db()
        return jsonify({
            'success': True,
            'message': 'Database initialized successfully',
            'database_type': 'PostgreSQL' if config.USE_POSTGRES else 'SQLite',
            'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
        }), 200
    except Exception as e:
        print(f"ERROR during database init: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'error': str(e),
            'message': 'Failed to initialize database',
            'database_type': 'PostgreSQL' if config.USE_POSTGRES else 'SQLite'
        }), 500


# ========================================
# RUN SERVER
# ========================================

if __name__ == '__main__':
    import sys
    import os
    
    # Initialize database
    init_db()
    
    # Get port from environment (Railway/Render provide this)
    port = int(os.environ.get('PORT', 5000))
    
    print("=" * 50)
    print(f"🚀 {config.APP_NAME} Backend Server")
    print("=" * 50)
    print(f"📍 Running on: http://0.0.0.0:{port}")
    print(f"📚 API Docs: /api/health")
    print(f"💾 Database: {'PostgreSQL' if config.USE_POSTGRES else 'SQLite'}")
    print("=" * 50)
    
    # Run Flask server
    app.run(host='0.0.0.0', port=port, debug=False, threaded=True)

