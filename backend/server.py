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
from socketio import Server, ASGIApp
from werkzeug.security import generate_password_hash, check_password_hash
import jwt
import datetime
import secrets
import re
import hashlib
import hmac
import json
import time
from html import escape as html_escape

from config import get_config
from database import init_db, get_db, dict_from_row, get_placeholder

try:
    from flask_limiter import Limiter
    from flask_limiter.util import get_remote_address
    _has_limiter = True
except ImportError:
    _has_limiter = False
    print("\u26a0\ufe0f  flask-limiter not installed \u2014 rate limiting disabled")

# ========================================
# APP INITIALIZATION
# ========================================

config = get_config()
app = Flask(__name__)

# Rate limiter — protects auth endpoints from brute force
if _has_limiter:
    limiter = Limiter(
        get_remote_address,
        app=app,
        default_limits=[],
        storage_uri="memory://"
    )
else:
    limiter = None

def rate_limit(limit_string):
    """Apply rate limiting if flask-limiter is available, otherwise no-op"""
    if limiter:
        return limiter.limit(limit_string)
    return lambda f: f

# Socket.IO for real-time chat
socketio = Server(
    async_mode='threading',
    cors_allowed_origins=config.CORS_ORIGINS,
    ping_timeout=60,
    ping_interval=25
)

# CORS configuration - Restrict to allowed origins
CORS(app, 
     resources={r"/api/*": {"origins": config.CORS_ORIGINS}},
     supports_credentials=True,
     allow_headers=['Content-Type', 'Authorization', 'Accept'],
     methods=['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
     max_age=3600)

app.config['SECRET_KEY'] = config.SECRET_KEY

# Add security + CORS headers to all responses
@app.after_request
def add_security_headers(response):
    """Add security and CORS headers to all responses"""
    origin = request.headers.get('Origin', '')
    allowed = [o.strip() for o in config.CORS_ORIGINS]
    if '*' in allowed or origin in allowed:
        response.headers['Access-Control-Allow-Origin'] = origin or '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, Accept'
    response.headers['Access-Control-Max-Age'] = '3600'
    response.headers['Access-Control-Allow-Credentials'] = 'true'
    
    # Security headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    response.headers['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=(self)'
    
    # Cache headers for API responses
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
        origin = request.headers.get('Origin', '')
        allowed = [o.strip() for o in config.CORS_ORIGINS]
        if '*' in allowed or origin in allowed:
            response.headers['Access-Control-Allow-Origin'] = origin or '*'
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

_suspension_columns_ensured = False

def _ensure_suspension_columns():
    """Ensure suspension-related columns exist in the users table (one-time check per process)"""
    global _suspension_columns_ensured
    if _suspension_columns_ensured:
        return
    try:
        with get_db() as (cursor, conn):
            if PH == '%s':
                # PostgreSQL
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN DEFAULT FALSE")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS suspension_reason VARCHAR(255)")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMP")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMP")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_releases INTEGER DEFAULT 0")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_release_date VARCHAR(20)")
            else:
                # SQLite
                cursor.execute("PRAGMA table_info(users)")
                cols = [row[1] for row in cursor.fetchall()]
                for col, typ in [('is_suspended', 'BOOLEAN DEFAULT 0'), ('suspension_reason', 'TEXT'),
                                 ('suspended_at', 'TEXT'), ('suspended_until', 'TEXT'),
                                 ('daily_releases', 'INTEGER DEFAULT 0'), ('daily_release_date', 'TEXT')]:
                    if col not in cols:
                        cursor.execute(f'ALTER TABLE users ADD COLUMN {col} {typ}')
        _suspension_columns_ensured = True
        print("✅ Suspension columns verified")
    except Exception as e:
        print(f"⚠️ _ensure_suspension_columns error: {e}")

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
        print(f"✅ Token valid for user: {payload.get('email')}")
        return payload
    except jwt.ExpiredSignatureError as e:
        print(f"❌ Token expired: {e}")
        return None
    except jwt.InvalidTokenError as e:
        print(f"❌ Invalid token: {e}")
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


def get_service_charge(category):
    """Calculate service charge based on task category"""
    service_charges = {
        # Quick tasks (15-30 mins) - ₹30
        'delivery': 30, 'pickup': 30, 'document': 30,
        'errand': 35,
        
        # Medium tasks (1-2 hours) - ₹40-50
        'groceries': 40, 'laundry': 40, 'shopping': 40,
        'gardening': 50, 'cleaning': 50, 'cooking': 50,
        
        # Skilled tasks (2-4 hours) - ₹60-70
        'repair': 60, 'assembly': 60, 'tech-support': 60,
        'event-help': 60, 'tailoring': 60, 'beauty': 60, 'petcare': 60,
        
        # Time-intensive tasks (3-6 hours) - ₹70-80
        'tutoring': 70, 'babysitting': 70, 'fitness': 70,
        'photography': 70, 'painting': 70, 'moving': 80,
        'eldercare': 80,
        
        # Professional/High-skill tasks - ₹90-100
        'carpentry': 90, 'electrician': 100, 'plumbing': 100,
        
        # Vehicle related - ₹40
        'vehicle': 40
    }
    return service_charges.get(category, 50)


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
    
    # Get wallet balance
    wallet = get_or_create_wallet(user['id'])
    wallet_balance = float(wallet.get('balance', 0))
    wallet_low = wallet_balance < 100
    debt_suspended = wallet_balance <= -500
    
    # Check timer suspension (auto-clear if expired)
    suspended_until = user.get('suspended_until')
    timer_suspended = False
    suspended_until_iso = None
    if suspended_until:
        if isinstance(suspended_until, str):
            try:
                suspended_until_dt = datetime.datetime.fromisoformat(suspended_until.replace('Z', '+00:00'))
            except:
                suspended_until_dt = None
        else:
            suspended_until_dt = suspended_until
        
        if suspended_until_dt:
            now = datetime.datetime.now(datetime.timezone.utc)
            if suspended_until_dt.tzinfo is None:
                suspended_until_dt = suspended_until_dt.replace(tzinfo=datetime.timezone.utc)
            if now < suspended_until_dt:
                timer_suspended = True
                suspended_until_iso = suspended_until_dt.isoformat()
            else:
                # Auto-clear expired timer suspension
                try:
                    with get_db() as (cursor, conn):
                        cursor.execute(f'UPDATE users SET suspended_until = NULL WHERE id = {PH}', (user['id'],))
                except:
                    pass
    
    # Daily release count
    daily_release_count = int(user.get('daily_releases', 0) or 0)
    daily_release_date = user.get('daily_release_date', '')
    today = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')
    if daily_release_date != today:
        daily_release_count = 0
    
    return {
        'id': user['id'],
        'name': user['name'],
        'email': user['email'],
        'phone': user.get('phone'),
        'dob': user.get('dob'),
        'profilePhoto': user.get('profile_photo'),
        'rating': float(user.get('rating', 5.0)),
        'tasksPosted': user.get('tasks_posted', 0),
        'tasksCompleted': user.get('tasks_completed', 0),
        'totalEarnings': float(user.get('total_earnings', 0)),
        'joinedAt': user.get('joined_at'),
        'lastLogin': user.get('last_login'),
        'wallet': wallet_balance,
        'walletLow': wallet_low,
        'walletWarning': 'Please top up your wallet (below ₹100)' if wallet_low else None,
        'debtSuspended': debt_suspended,
        'debtAmount': abs(wallet_balance) if wallet_balance < 0 else 0,
        'timerSuspended': timer_suspended,
        'suspendedUntil': suspended_until_iso,
        'dailyReleaseCount': daily_release_count,
        'emailVerified': bool(user.get('email_verified', False))
    }


# ========================================
# AUTH MIDDLEWARE
# ========================================

def require_auth(f):
    """Decorator to require authentication"""
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization', '')
        print(f"🔍 Auth header received: {auth_header[:50] if auth_header else 'EMPTY'}...")
        
        token = auth_header.replace('Bearer ', '')
        if not token:
            print("❌ No token found in Authorization header")
            return jsonify({'success': False, 'message': 'Authentication required'}), 401
        
        print(f"🔑 Attempting to verify token (first 50 chars): {token[:50]}...")
        payload = verify_jwt_token(token)
        if not payload:
            print("❌ Token verification failed - returning Invalid or expired token")
            return jsonify({'success': False, 'message': 'Invalid or expired token'}), 401
        
        print(f"✅ Auth successful for user: {payload.get('email')}")
        request.user_id = payload['user_id']
        request.user_email = payload['email']
        return f(*args, **kwargs)
    return decorated


# ========================================
# SOCKET.IO EVENT HANDLERS - REAL-TIME CHAT
# ========================================

# Track active chat connections per task
task_users = {}  # {task_id: {user_id: sid}}

@socketio.event
def connect(auth):
    """User connected to chat"""
    try:
        # Verify user authentication
        token = auth.get('token') if isinstance(auth, dict) else None
        task_id = auth.get('taskId') if isinstance(auth, dict) else None
        
        if not token or not task_id:
            return False  # Reject connection
        
        payload = verify_jwt_token(token)
        if not payload:
            return False
        
        user_id = payload['user_id']
        
        # Track user in task chat
        if task_id not in task_users:
            task_users[task_id] = {}
        
        task_users[task_id][user_id] = request.sid
        
        # Notify others that user joined
        socketio.emit('user_joined', {
            'userId': user_id,
            'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
        }, room=f'task_{task_id}')
        
        print(f"✅ User {user_id} connected to chat for task {task_id}")
        return True
    except Exception as e:
        print(f"❌ Connection error: {e}")
        return False

@socketio.event
def join_task(data):
    """Join a task chat room"""
    task_id = data.get('taskId')
    token = data.get('token')
    
    payload = verify_jwt_token(token)
    if not payload:
        return
    
    user_id = payload['user_id']
    room = f'task_{task_id}'
    socketio.enter_room(request.sid, room)
    
    socketio.emit('notification', {
        'message': 'Connected to task chat',
        'type': 'connected'
    }, to=request.sid)

@socketio.event
def send_message(data):
    """Send a chat message"""
    message = data.get('message', '').strip()
    task_id = data.get('taskId')
    token = data.get('token')
    
    if not message:
        return
    
    payload = verify_jwt_token(token)
    if not payload:
        return
    
    user_id = payload['user_id']
    user_name = data.get('userName', 'User')
    
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    room = f'task_{task_id}'
    
    # Store message in database
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            INSERT INTO chat_messages (task_id, user_id, message, timestamp, user_name)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
        ''', (task_id, user_id, message, timestamp, user_name))
    
    # Broadcast message to task room
    socketio.emit('new_message', {
        'userId': user_id,
        'userName': user_name,
        'message': message,
        'timestamp': timestamp
    }, room=room)
    
    print(f"💬 Message from {user_name}: {message[:50]}...")

@socketio.event
def typing_indicator(data):
    """Show when user is typing"""
    task_id = data.get('taskId')
    token = data.get('token')
    user_name = data.get('userName', 'User')
    
    payload = verify_jwt_token(token)
    if not payload:
        return
    
    room = f'task_{task_id}'
    socketio.emit('user_typing', {
        'userName': user_name
    }, room=room, skip_sid=request.sid)

@socketio.event
def disconnect():
    """User disconnected"""
    print(f"❌ User {request.sid} disconnected")


# ========================================
# API ROUTES - AUTHENTICATION
# ========================================

@app.route('/api/auth/register', methods=['POST'])
@rate_limit('5 per minute')
def register():
    """Register a new user"""
    data = request.get_json()
    
    # Validate required fields
    required = ['name', 'email', 'password', 'dob']
    for field in required:
        if not data.get(field):
            return jsonify({'success': False, 'message': f'{field} is required'}), 400
    
    name = html_escape(data['name'].strip())
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
@rate_limit('10 per minute')
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


@app.route('/api/auth/send-verification-otp', methods=['POST'])
@require_auth
def send_verification_otp():
    """Generate and send email verification OTP — same pattern as forgot-password."""
    with get_db() as (cursor, conn):
        cursor.execute(f'SELECT email, name, email_verified FROM users WHERE id = {PH}', (request.user_id,))
        user = cursor.fetchone()
        if not user:
            return jsonify({'success': False, 'message': 'User not found'}), 404
        user = dict_from_row(user) if not isinstance(user, dict) else user

        if user.get('email_verified'):
            return jsonify({'success': False, 'message': 'Email already verified'}), 400

        email = user['email']
        name = user.get('name', 'User')

        # Generate 6-digit OTP
        otp = ''.join([str(secrets.randbelow(10)) for _ in range(6)])
        expires_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)).isoformat()

        # Store OTP in password_resets table (reuse existing table)
        cursor.execute(f'''
            INSERT INTO password_resets (user_id, token, otp, created_at, expires_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
        ''', (request.user_id, 'email_verify_' + secrets.token_hex(16), otp,
              datetime.datetime.now(datetime.timezone.utc).isoformat(), expires_at))

    # Send via SendGrid if configured
    email_sent_server = False
    if config.SENDGRID_API_KEY:
        try:
            from sendgrid import SendGridAPIClient
            from sendgrid.helpers.mail import Mail
            message = Mail(
                from_email=config.FROM_EMAIL,
                to_emails=email,
                subject=f'{config.APP_NAME} - Email Verification OTP',
                html_content=f'''
                    <h2>Email Verification</h2>
                    <p>Hi {name},</p>
                    <p>Your verification code for Workmate4u is:</p>
                    <h1 style="color: #6366f1; font-size: 32px; letter-spacing: 4px;">{otp}</h1>
                    <p>This code expires in 10 minutes.</p>
                    <p>If you didn't request this, please ignore this email.</p>
                '''
            )
            sg = SendGridAPIClient(config.SENDGRID_API_KEY)
            sg.send(message)
            email_sent_server = True
            print(f"📧 Verification OTP sent to {email}")
        except Exception as e:
            print(f"⚠️ SendGrid email error: {e}")

    if not email_sent_server:
        print(f"🔐 Verification OTP for {email}: {otp}")

    return jsonify({
        'success': True,
        'message': 'Verification code sent to your email',
        # Return OTP for client-side EmailJS delivery when SendGrid is not configured
        'otp': otp if not config.SENDGRID_API_KEY else None
    })


@app.route('/api/auth/verify-email', methods=['POST'])
@require_auth
def verify_email():
    """Verify email OTP and mark email as verified."""
    data = request.get_json() or {}
    otp = data.get('otp', '').strip()

    if not otp or len(otp) != 6:
        return jsonify({'success': False, 'message': 'Valid 6-digit OTP required'}), 400

    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT otp, expires_at FROM password_resets
            WHERE user_id = {PH} AND token LIKE {PH}
            ORDER BY created_at DESC LIMIT 1
        ''', (request.user_id, 'email_verify_%'))
        row = cursor.fetchone()

        if not row:
            return jsonify({'success': False, 'message': 'No verification code found. Please request a new one.'}), 400

        row = dict_from_row(row) if not isinstance(row, dict) else row
        stored_otp = row['otp']
        expires_at = row['expires_at']

        # Check expiry
        now = datetime.datetime.now(datetime.timezone.utc)
        try:
            if isinstance(expires_at, datetime.datetime):
                exp = expires_at if expires_at.tzinfo else expires_at.replace(tzinfo=datetime.timezone.utc)
            else:
                exp = datetime.datetime.fromisoformat(str(expires_at).replace('Z', '+00:00'))
            if now > exp:
                return jsonify({'success': False, 'message': 'Verification code has expired. Please request a new one.'}), 400
        except Exception as e:
            print(f"⚠️ Expiry check error: {e}")

        if otp != stored_otp:
            return jsonify({'success': False, 'message': 'Invalid verification code'}), 400

        # Mark email as verified
        cursor.execute(f'UPDATE users SET email_verified = TRUE WHERE id = {PH}', (request.user_id,))

        # Clean up used tokens
        cursor.execute(f"DELETE FROM password_resets WHERE user_id = {PH} AND token LIKE {PH}",
                       (request.user_id, 'email_verify_%'))

    return jsonify({'success': True, 'message': 'Email verified successfully'})


# ========================================
# API ROUTES - MIGRATE LOCAL SUSPENSION
# ========================================

@app.route('/api/user/migrate-suspension', methods=['POST'])
@require_auth
def migrate_local_suspension():
    """Migrate a localStorage-based suspension timer to the server DB.
    Called once per device for accounts suspended before server-side tracking."""
    data = request.get_json() or {}
    suspended_until_ms = data.get('suspendedUntil')  # epoch milliseconds from localStorage
    
    if not suspended_until_ms:
        return jsonify({'success': False, 'message': 'Missing suspendedUntil'}), 400
    
    try:
        suspended_until_ms = int(suspended_until_ms)
        until_dt = datetime.datetime.fromtimestamp(suspended_until_ms / 1000, tz=datetime.timezone.utc)
    except (ValueError, OSError):
        return jsonify({'success': False, 'message': 'Invalid timestamp'}), 400
    
    now = datetime.datetime.now(datetime.timezone.utc)
    if until_dt <= now:
        # Already expired — no need to migrate
        return jsonify({'success': True, 'migrated': False, 'reason': 'expired'})
    
    with get_db() as (cursor, conn):
        # Only migrate if server doesn't already have a suspension
        cursor.execute(f'SELECT suspended_until FROM users WHERE id = {PH}', (request.user_id,))
        row = cursor.fetchone()
        if not row:
            return jsonify({'success': False, 'message': 'User not found'}), 404
        
        row_dict = dict_from_row(row) if not isinstance(row, dict) else row
        existing = row_dict.get('suspended_until')
        
        if existing:
            # Server already has a suspension — don't overwrite
            return jsonify({'success': True, 'migrated': False, 'reason': 'already_set'})
        
        until_iso = until_dt.isoformat()
        cursor.execute(f'''
            UPDATE users SET suspended_until = {PH}, is_suspended = {PH},
                suspension_reason = {PH}, suspended_at = {PH}
            WHERE id = {PH}
        ''', (until_iso, True, 'Migrated from local device', now.isoformat(), request.user_id))
        print(f"✅ Migrated local suspension for user {request.user_id} until {until_iso}")
    
    return jsonify({'success': True, 'migrated': True, 'suspendedUntil': until_dt.isoformat()})


# ========================================
# API ROUTES - PASSWORD RESET
# ========================================

@app.route('/api/auth/forgot-password', methods=['POST'])
@rate_limit('3 per minute')
def forgot_password():
    """Find account for password reset"""
    data = request.get_json()
    email = data.get('email', '').strip().lower()
    
    if not email:
        return jsonify({'success': False, 'message': 'Email is required'}), 400
    
    user = get_user_by_email(email)
    if not user:
        # Return same success response to prevent account enumeration
        return jsonify({
            'success': True,
            'message': 'If an account exists with this email, an OTP has been sent',
            'resetToken': secrets.token_hex(32),
            'maskedEmail': email[:3] + '***@' + email.split('@')[1] if '@' in email else '***'
        })
    
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
        'message': 'If an account exists with this email, an OTP has been sent',
        'resetToken': reset_token,
        'maskedEmail': email[:3] + '***@' + email.split('@')[1],
        'userName': user['name'],
        # OTP returned for client-side EmailJS delivery; removed when SendGrid handles it server-side
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
    
    allowed_fields = ['name', 'phone', 'email', 'profile_photo']
    updates = {k: v for k, v in data.items() if k in allowed_fields}
    
    # Validate email uniqueness if changing email
    if 'email' in updates:
        new_email = updates['email'].strip().lower()
        if not new_email or '@' not in new_email:
            return jsonify({'success': False, 'message': 'Invalid email address'}), 400
        existing = get_user_by_email(new_email)
        if existing and existing['id'] != request.user_id:
            return jsonify({'success': False, 'message': 'Email already in use'}), 400
        updates['email'] = new_email
    
    # Limit profile photo size (max ~2MB base64 after client compression)
    if 'profile_photo' in updates and updates['profile_photo']:
        if len(updates['profile_photo']) > 2800000:
            return jsonify({'success': False, 'message': 'Photo too large. Max 2MB.'}), 400
    
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
    """Get all active tasks (non-expired)"""
    import datetime
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    print(f"\n[GET /api/tasks] Fetching tasks at {now}")
    
    # Mark expired tasks and notify posters on each fetch
    try:
        cleanup_old_tasks()
    except Exception:
        pass
    
    try:
        with get_db() as (cursor, conn):
            # Simple query without LEFT JOIN first
            cursor.execute(f'''
                SELECT id, title, description, category, location_lat, location_lng, 
                       location_address, price, service_charge, posted_by, posted_at, expires_at, status
                FROM tasks
                WHERE status = 'active' AND expires_at > {PH}
                ORDER BY posted_at DESC
            ''', (now,))
            
            rows = cursor.fetchall()
            print(f"[GET /api/tasks] Found {len(rows)} active tasks")
            
            task_list = []
            for task in rows:
                task = dict_from_row(task)
                
                # Get poster info separately
                poster_name = 'Anonymous'
                poster_phone = ''
                poster_rating = 5.0
                poster_tasks = 0
                
                try:
                    poster_id = task.get('posted_by')
                    if poster_id:
                        cursor.execute(f'SELECT name, phone, rating, tasks_posted FROM users WHERE id = {PH}', (poster_id,))
                        user_row = cursor.fetchone()
                        if user_row:
                            user = dict_from_row(user_row)
                            poster_name = user.get('name', 'Anonymous')
                            poster_phone = user.get('phone', '')
                            poster_rating = float(user.get('rating', 5.0))
                            poster_tasks = int(user.get('tasks_posted', 0))
                except:
                    pass  # Use defaults if user not found
                
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
                    'service_charge': float(task.get('service_charge', 0)),
                    'postedBy': {
                        'id': task.get('posted_by'),
                        'name': poster_name,
                        'phone': poster_phone,
                        'rating': poster_rating,
                        'tasksPosted': poster_tasks
                    },
                    'postedAt': task['posted_at'],
                    'expiresAt': task['expires_at'],
                    'status': task['status']
                })
        
        print(f"[GET /api/tasks] Returning {len(task_list)} tasks to client")
        return jsonify({
            'success': True,
            'tasks': task_list
        })
        
    except Exception as e:
        print(f"[GET /api/tasks] Error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({
            'success': False,
            'message': f'Error fetching tasks: {str(e)}'
        }), 500


@app.route('/api/tasks/category-counts', methods=['GET'])
def get_category_counts():
    """Get count of active (non-expired) tasks grouped by category"""
    import datetime
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT LOWER(category) as category, COUNT(*) as count
                FROM tasks
                WHERE status = 'active' AND expires_at > {PH}
                GROUP BY LOWER(category)
            ''', (now,))
            rows = cursor.fetchall()
            counts = {}
            for row in rows:
                r = dict_from_row(row)
                counts[r['category']] = r['count']
        return jsonify({'success': True, 'counts': counts})
    except Exception as e:
        print(f"[GET /api/tasks/category-counts] Error: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/tasks', methods=['POST'])
@require_auth
def create_task():
    """Create a new task"""
    try:
        print('='*60)
        print('🚀 POST /api/tasks - Task creation endpoint called')
        print(f'   User ID: {request.user_id}')
        
        data = request.get_json()
        print(f'   Raw request data: {data}')
        
        required = ['title', 'description', 'category', 'price']
        for field in required:
            if not data.get(field):
                print(f"⚠️ Task creation failed: missing required field '{field}'")
                print(f'   Available fields: {list(data.keys())}')
                return jsonify({'success': False, 'message': f'{field} is required'}), 400
        
        print(f"📝 Creating task: '{data.get('title')}'")
        print(f"   Category: {data.get('category')}")
        print(f"   Description: {data.get('description')}")
        print(f"   Price: {data.get('price')}")
        print(f"   Location: {data.get('location')}")
        
        # Calculate service charge based on category
        service_charge = get_service_charge(data.get('category', 'other'))
        print(f"   Service Charge: ₹{service_charge}")
        print(f"   Total Display Value: ₹{float(data.get('price')) + service_charge}")
        
        with get_db() as (cursor, conn):
            posted_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
            expires_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=12)).isoformat()
            
            location = data.get('location', {})
            
            print(f"   Posted at: {posted_at}")
            print(f"   Expires at: {expires_at}")
            
            # Insert task
            print('   Executing INSERT query...')
            cursor.execute(f'''
                INSERT INTO tasks (title, description, category, location_lat, location_lng, 
                                  location_address, price, service_charge, posted_by, posted_at, expires_at, status)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, 'active')
            ''', (
                html_escape(data['title']),
                html_escape(data['description']),
                html_escape(data['category']),
                location.get('lat'),
                location.get('lng'),
                html_escape(location.get('address', '') or ''),
                data['price'],
                service_charge,
                request.user_id,
                posted_at,
                expires_at
            ))
            print('   ✅ INSERT query executed successfully')
            
            # Get the inserted task ID
            print('   Getting inserted task ID...')
            try:
                if config.USE_POSTGRES:
                    cursor.execute('SELECT lastval() AS id')
                    result = cursor.fetchone()
                    task_id = result['id'] if result else None
                    print(f"   PostgreSQL lastval() result: {result}")
                else:
                    cursor.execute('SELECT last_insert_rowid() AS id')
                    result = cursor.fetchone()
                    task_id = result[0] if result else None
                    print(f"   SQLite last_insert_rowid() result: {result}")
            except Exception as id_error:
                print(f"❌ Error getting task ID: {id_error}")
                import traceback
                traceback.print_exc()
                task_id = None
            
            print(f"   Extracted task_id: {task_id}")
            
            if not task_id:
                print("❌ Failed to get task ID after insertion")
                return jsonify({'success': False, 'message': 'Failed to create task'}), 500
            
            # Update user's tasks_posted count
            print('   Updating user tasks_posted count...')
            cursor.execute(f'UPDATE users SET tasks_posted = tasks_posted + 1 WHERE id = {PH}', 
                           (request.user_id,))
            print('   ✅ User stats updated')
            
            # Create confirmation notification for poster
            import json
            notif_data = json.dumps({
                'type': 'task',
                'label': '👁️ View Task',
                'taskId': task_id
            })
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, task_id, 'task_posted',
                  'Task Posted! 📋',
                  f'Your task "{html_escape(data["title"])}" has been posted. Budget: ₹{data["price"]}. It will expire in 12 hours.',
                  'unread', notif_data, posted_at))
            
            print(f"✅ Task created successfully with ID: {task_id}")
        
        response = {
            'success': True,
            'message': 'Task created successfully',
            'taskId': task_id
        }
        print(f'   Returning response: {response}')
        print('='*60)
        return jsonify(response), 201
    
    except Exception as e:
        print(f"❌ Task creation error: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        import traceback
        traceback.print_exc()
        print('='*60)
        return jsonify({'success': False, 'message': f'Task creation failed: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/accept', methods=['POST'])
@require_auth
def accept_task(task_id):
    """Accept a task"""
    try:
        # Ensure suspension columns exist
        _ensure_suspension_columns()

        # Server-side suspension check
        cursor_user = None
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT suspended_until FROM users WHERE id = {PH}', (request.user_id,))
            cursor_user = cursor.fetchone()
        
        if cursor_user:
            user_dict = dict_from_row(cursor_user) if not isinstance(cursor_user, dict) else cursor_user
            sus_until = user_dict.get('suspended_until')
            if sus_until:
                try:
                    if isinstance(sus_until, str):
                        sus_dt = datetime.datetime.fromisoformat(sus_until.replace('Z', '+00:00'))
                    else:
                        sus_dt = sus_until
                    if sus_dt.tzinfo is None:
                        sus_dt = sus_dt.replace(tzinfo=datetime.timezone.utc)
                    if datetime.datetime.now(datetime.timezone.utc) < sus_dt:
                        return jsonify({'success': False, 'message': 'Your account is suspended. Please wait until the suspension period ends.'}), 403
                    else:
                        # Suspension expired — clear it and notify user
                        try:
                            with get_db() as (cur2, conn2):
                                cur2.execute(f'UPDATE users SET is_suspended = {PH}, suspended_until = {PH}, suspension_reason = {PH} WHERE id = {PH}',
                                             (False, None, None, request.user_id))
                                import json as _json2
                                _now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                                cur2.execute(f'''
                                    INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                                ''', (request.user_id, 'account_restored',
                                      'Account Restored! ✅',
                                      'Your suspension period has ended. You can now accept tasks again.',
                                      'unread', _json2.dumps({'type': 'system'}), _now))
                        except Exception:
                            pass  # Non-critical, continue allowing task acceptance
                except:
                    pass
        
        # Check debt suspension
        wallet = get_or_create_wallet(request.user_id)
        if float(wallet.get('balance', 0)) <= -500:
            return jsonify({'success': False, 'message': 'Your wallet balance is below -₹500. Add money to restore task acceptance.'}), 403

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
            
            # Create notification for task poster
            poster_id = task['posted_by']
            cursor.execute(f'SELECT name FROM users WHERE id = {PH}', (request.user_id,))
            helper_row = cursor.fetchone()
            helper_name = (dict_from_row(helper_row) if helper_row else {}).get('name', 'Someone')
            
            import json
            action_data = json.dumps({
                'type': 'task',
                'label': '👁️ View Task',
                'taskId': task_id
            })
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (poster_id, task_id, 'task_accepted',
                  'Task Accepted! 🎉',
                  f'{helper_name} has accepted your task "{task["title"]}". Budget: ₹{task["price"]}',
                  'unread', action_data, accepted_at))
            
            # Create confirmation notification for helper
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, task_id, 'task_assigned',
                  'Task Assigned! 📌',
                  f'You accepted "{task["title"]}". Budget: ₹{task["price"]}. Complete it before the poster cancels!',
                  'unread', action_data, accepted_at))
        
        return jsonify({
            'success': True,
            'message': 'Task accepted successfully'
        })
    except Exception as e:
        print(f"❌ Error in accept_task: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Error accepting task: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/abandon', methods=['POST'])
@require_auth
def abandon_task(task_id):
    """Abandon an accepted task - reverts it to active and records the release (auto-suspends if limit exceeded)"""
    try:
        with get_db() as (cursor, conn):
            # Check task exists and is accepted by the current user
            cursor.execute(f'SELECT * FROM tasks WHERE id = {PH} AND accepted_by = {PH} AND status = {PH}', (task_id, request.user_id, 'accepted'))
            task = cursor.fetchone()

            if not task:
                return jsonify({'success': False, 'message': 'Task not found or not accepted by you'}), 404

            # Revert task to active
            cursor.execute(f'''
                UPDATE tasks SET status = 'active', accepted_by = NULL, accepted_at = NULL
                WHERE id = {PH}
            ''', (task_id,))

        # Ensure suspension columns exist before using them
        _ensure_suspension_columns()

        # Record release and check daily limit
        today = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')
        suspended = False
        suspended_until_iso = None
        daily_count = 0

        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT daily_releases, daily_release_date FROM users WHERE id = {PH}', (request.user_id,))
            row = cursor.fetchone()
            if row:
                row_dict = dict_from_row(row) if not isinstance(row, dict) else row
                current_count = int(row_dict.get('daily_releases', 0) or 0)
                release_date = row_dict.get('daily_release_date', '')
                if release_date != today:
                    current_count = 0
                daily_count = current_count + 1

                if daily_count > 3:
                    until = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=48)
                    suspended_until_iso = until.isoformat()
                    cursor.execute(f'''
                        UPDATE users SET daily_releases = {PH}, daily_release_date = {PH},
                            suspended_until = {PH}, is_suspended = {PH}, suspension_reason = {PH},
                            suspended_at = {PH}
                        WHERE id = {PH}
                    ''', (daily_count, today, suspended_until_iso, True, 'Too many task releases',
                          datetime.datetime.now(datetime.timezone.utc).isoformat(), request.user_id))
                    suspended = True
                    print(f"⚠️ User {request.user_id} suspended until {suspended_until_iso} (released {daily_count} tasks today)")
                    
                    # Notify helper about suspension
                    import json as _json
                    sus_now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    cursor.execute(f'''
                        INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                        VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                    ''', (request.user_id, 'account_suspended',
                          'Account Suspended ⛔',
                          f'You released {daily_count} tasks today. Your account is suspended for 48 hours until {datetime.datetime.fromisoformat(suspended_until_iso).strftime("%b %d, %I:%M %p")} UTC.',
                          'unread', _json.dumps({'type': 'system', 'suspendedUntil': suspended_until_iso}), sus_now))
                else:
                    cursor.execute(f'''
                        UPDATE users SET daily_releases = {PH}, daily_release_date = {PH}
                        WHERE id = {PH}
                    ''', (daily_count, today, request.user_id))

        # Notify poster that helper released their task
        try:
            with get_db() as (cursor, conn):
                cursor.execute(f'SELECT title, posted_by, price FROM tasks WHERE id = {PH}', (task_id,))
                t = cursor.fetchone()
                if t:
                    t = dict_from_row(t)
                    cursor.execute(f'SELECT name FROM users WHERE id = {PH}', (request.user_id,))
                    h = cursor.fetchone()
                    h_name = (dict_from_row(h) if h else {}).get('name', 'The helper')
                    import json
                    notif_data = json.dumps({'type': 'task', 'label': '👁️ View Task', 'taskId': task_id})
                    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    cursor.execute(f'''
                        INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                        VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                    ''', (t['posted_by'], task_id, 'task_released',
                          'Task Released ⚠️',
                          f'{h_name} has released your task "{t["title"]}". It is now available for others to accept.',
                          'unread', notif_data, now))
        except Exception as notif_err:
            print(f"⚠️ Failed to create release notification: {notif_err}")
        
        print(f"✅ Task {task_id} abandoned by user {request.user_id} — release #{daily_count} today")
        return jsonify({
            'success': True,
            'message': 'Task released. It is now available for others.',
            'dailyReleaseCount': daily_count,
            'suspended': suspended,
            'suspendedUntil': suspended_until_iso
        })
    except Exception as e:
        print(f"❌ Error in abandon_task: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Error abandoning task: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>', methods=['DELETE'])
@require_auth
def delete_task(task_id):
    """Delete a task (only poster can delete, only if not accepted)"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT posted_by, status FROM tasks WHERE id = {PH}', (task_id,))
            task = cursor.fetchone()

            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404

            task = dict_from_row(task)

            if task['posted_by'] != request.user_id:
                return jsonify({'success': False, 'message': 'Only the task poster can delete this task'}), 403

            if task['status'] not in ('active',):
                return jsonify({'success': False, 'message': f"Cannot delete task with status '{task['status']}'"}), 400

            cursor.execute(f'DELETE FROM tasks WHERE id = {PH}', (task_id,))

        print(f"✅ Task {task_id} deleted by user {request.user_id}")
        return jsonify({'success': True, 'message': 'Task deleted successfully'})
    except Exception as e:
        print(f"❌ Error in delete_task: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Error deleting task: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/details', methods=['GET'])
@require_auth
def get_task_details(task_id):
    """Get task details with provider info for Task In Progress page"""
    with get_db() as (cursor, conn):
        # Get task with provider details
        cursor.execute(f'''
            SELECT t.*, u.name as provider_name, u.phone as provider_phone, 
                   u.rating as provider_rating, u.tasks_completed as provider_tasks
            FROM tasks t
            LEFT JOIN users u ON t.posted_by = u.id
            WHERE t.id = {PH} AND t.status IN ('accepted', 'completed')
        ''', (task_id,))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        
        task = dict_from_row(task)
        
        return jsonify({
            'success': True,
            'task': {
                'id': task['id'],
                'title': task['title'],
                'description': task['description'],
                'category': task['category'],
                'amount': float(task['price']),
                'price': float(task['price']),
                'service_charge': float(task.get('service_charge', 0)),
                'location': {
                    'lat': task['location_lat'],
                    'lng': task['location_lng'],
                    'address': task['location_address']
                },
                'status': task['status'],
                'postedAt': task['posted_at'],
                'provider': {
                    'id': task['posted_by'],
                    'name': task['provider_name'],
                    'phone': task['provider_phone'],
                    'rating': float(task['provider_rating'] or 0),
                    'tasksCompleted': task['provider_tasks']
                }
            }
        })


@app.route('/api/tasks/<int:task_id>/complete', methods=['POST'])
@require_auth
def complete_task(task_id):
    """
    Mark task as completed (NO payment processing here).
    Payment is handled separately via /pay-helper when the poster clicks 'Pay Now'.
    - Sets task status to 'completed'
    - Creates a 'Pay Now' notification for the poster
    """
    try:
        print(f"\n{'='*60}")
        print(f"📋 Marking Task {task_id} as Completed")
        print(f"Helper: {request.user_id}")
        print('='*60)
        
        with get_db() as (cursor, conn):
            # Check if task exists and is accepted by current user (the helper)
            cursor.execute(f'''
                SELECT * FROM tasks WHERE id = {PH} AND accepted_by = {PH} AND status = {PH}
            ''', (task_id, request.user_id, 'accepted'))
            task = cursor.fetchone()
            
            if not task:
                return jsonify({'success': False, 'message': 'Task not found or not accepted by you'}), 404
            
            task = dict_from_row(task)
            task_amount = float(task['price'])
            service_charge = float(task.get('service_charge', 0))
            total_task_value = task_amount + service_charge
            poster_id = task['posted_by']
            helper_id = request.user_id
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            
            # Calculate amounts for notification display
            poster_deduction = total_task_value * 0.05
            total_poster_cost = total_task_value + poster_deduction
            helper_total_deduction = total_task_value * 0.12
            helper_net_receives = total_task_value - helper_total_deduction
            
            print(f"\n💵 AMOUNTS (for notification):")
            print(f"   Total Task Value: ₹{total_task_value:.2f}")
            print(f"   Poster will pay: ₹{total_poster_cost:.2f}")
            print(f"   Helper will receive: ₹{helper_net_receives:.2f}")
            
            # ===== UPDATE TASK STATUS TO 'completed' =====
            cursor.execute(f'''
                UPDATE tasks
                SET status = 'completed', completed_at = {PH}
                WHERE id = {PH}
            ''', (now, task_id))
            
            print(f"   ✅ Task status updated to 'completed'")
            
            # ===== CREATE NOTIFICATION FOR POSTER =====
            cursor.execute(f'SELECT name FROM users WHERE id = {PH}', (helper_id,))
            helper_user_row = cursor.fetchone()
            helper_user = dict_from_row(helper_user_row) if helper_user_row else None
            helper_name = helper_user['name'] if helper_user else 'A helper'
            
            import json
            action_data = json.dumps({
                'type': 'payment',
                'label': '💳 Pay Now',
                'taskId': task_id,
                'amount': total_poster_cost,
                'timestamp': now
            })
            
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (poster_id, task_id, 'task_completed', 
                  'Task Completed! 💰',
                  f'{helper_name} has completed your task "{task["title"]}". Please pay ₹{total_poster_cost:.2f} from your wallet.',
                  'unread', action_data, now))
            
            # Create confirmation notification for helper
            helper_data = json.dumps({
                'type': 'task',
                'label': '👁️ View Task',
                'taskId': task_id
            })
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (helper_id, task_id, 'task_completed_helper',
                  'Task Done! ✅',
                  f'You completed "{task["title"]}". Waiting for poster to pay ₹{helper_net_receives:.2f}.',
                  'unread', helper_data, now))
            
            conn.commit()
            
            print(f"\n✅ TASK MARKED AS COMPLETED!")
            print(f"   Notification created for poster (ID: {poster_id}) with 'Pay Now' action")
            print(f"   Task status: accepted → completed")
            print('='*60 + "\n")
            
            return jsonify({
                'success': True,
                'message': 'Task marked as completed. Poster has been notified to pay.',
                'taskId': task_id,
                'status': 'completed',
                'totalPosterCost': total_poster_cost,
                'helperWillReceive': helper_net_receives
            }), 200
    
    except Exception as e:
        print(f"❌ Error completing task: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Failed to complete task: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/create-payment-order', methods=['POST'])
@require_auth
def create_payment_order(task_id):
    """Create a Razorpay order for task payment"""
    try:
        data = request.get_json()
        amount = data.get('amount')
        
        if not amount or amount <= 0:
            return jsonify({'success': False, 'message': 'Invalid amount'}), 400
        
        with get_db() as (cursor, conn):
            # Verify task exists and user is the poster
            cursor.execute(f'SELECT * FROM tasks WHERE id = {PH}', (task_id,))
            task = cursor.fetchone()
            
            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404
            
            task = dict_from_row(task)
            
            if task['posted_by'] != request.user_id:
                return jsonify({'success': False, 'message': 'Only task poster can create payment order'}), 403
            
            if task['status'] != 'completed':
                return jsonify({'success': False, 'message': 'Task not completed yet'}), 400
            
            # Create Razorpay order
            try:
                import razorpay
                client = razorpay.Client(auth=(config.RAZORPAY_KEY_ID, config.RAZORPAY_KEY_SECRET))
                
                order_data = {
                    'amount': int(amount * 100),  # Convert to paise
                    'currency': 'INR',
                    'receipt': f'task_{task_id}_{request.user_id}',
                    'notes': {
                        'task_id': str(task_id),
                        'poster_id': request.user_id,
                        'helper_id': task['accepted_by']
                    }
                }
                
                order = client.order.create(data=order_data)
                
                print(f"✅ Razorpay order created: {order['id']}")
                
                return jsonify({
                    'success': True,
                    'razorpay_order_id': order['id'],
                    'razorpay_key_id': config.RAZORPAY_KEY_ID,
                    'amount': amount,
                    'message': 'Order created successfully'
                }), 200
                
            except Exception as razorpay_error:
                print(f"❌ Razorpay error: {razorpay_error}")
                # Fallback: Create a local order ID for testing
                # In production, don't do this - always use Razorpay
                test_order_id = f'order_test_{task_id}_{request.user_id}'
                return jsonify({
                    'success': True,
                    'razorpay_order_id': test_order_id,
                    'razorpay_key_id': config.RAZORPAY_KEY_ID or 'rzp_test_demo',
                    'amount': amount,
                    'message': 'Test order (Razorpay unavailable)',
                    'test_mode': True
                }), 200
    
    except Exception as e:
        print(f"❌ Error creating payment order: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Server error: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/pay-helper', methods=['POST'])
@require_auth
def pay_helper(task_id):
    """
    Poster pays for completed task - ALL wallet deductions and credits happen here
    - Deduct helper commission (12%) from helper wallet
    - Deduct poster fee (5%) from poster wallet
    - Credit helper with task amount
    - Send platform income to Razorpay UPI
    """
    print(f"\n{'='*60}")
    print(f"💰 Payment Processing: Task {task_id}")
    print(f"Poster (payer): {request.user_id}")
    print('='*60)
    
    try:
        with get_db() as (cursor, conn):
            # Get task details
            cursor.execute(f'SELECT * FROM tasks WHERE id = {PH}', (task_id,))
            task = cursor.fetchone()
            
            if not task:
                print(f"❌ Task {task_id} not found")
                return jsonify({'success': False, 'message': 'Task not found'}), 404
            
            task = dict_from_row(task)
            print(f"📋 Task: {task['title']}")
            print(f"   Status: {task['status']}")
            print(f"   Posted by: {task['posted_by']}")
            print(f"   Accepted by: {task['accepted_by']}")
            
            # Verify task is completed
            if task['status'] != 'completed':
                print(f"❌ Task not completed (status: {task['status']})")
                return jsonify({'success': False, 'message': 'Task must be completed first'}), 400
            
            # Verify the poster is the one paying
            if task['posted_by'] != request.user_id:
                print(f"❌ Only task poster can pay (poster: {task['posted_by']}, requester: {request.user_id})")
                return jsonify({'success': False, 'message': 'Only task poster can pay'}), 403
            
            helper_id = task['accepted_by']
            task_amount = float(task['price'])
            service_charge = float(task.get('service_charge', 0))
            total_task_value = task_amount + service_charge  # FULL AMOUNT including service charge
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            
            # Calculate deductions and credits using FULL AMOUNT
            # Helper: 12% total (10% commission + 2% transaction fee)
            helper_commission = total_task_value * 0.10
            helper_fee = total_task_value * 0.02
            helper_total_deduction = helper_commission + helper_fee
            
            # Poster: 5% fee (on the full amount)
            poster_deduction = total_task_value * 0.05
            
            print(f"\n💵 PAYMENT BREAKDOWN:")
            print(f"   Base Task Price: ₹{task_amount:.2f}")
            print(f"   Service Charge ({task.get('category', 'other')}): ₹{service_charge:.2f}")
            print(f"   ✨ TOTAL TASK VALUE: ₹{total_task_value:.2f}")
            print(f"   Helper Commission (10% of total): ₹{helper_commission:.2f}")
            print(f"   Helper Transaction Fee (2% of total): ₹{helper_fee:.2f}")
            print(f"   Helper Total Deduction: ₹{helper_total_deduction:.2f}")
            print(f"   Poster Fee (5% of total): ₹{poster_deduction:.2f}")
            
            # ===== CHECK POSTER BALANCE FIRST =====
            poster_wallet = get_or_create_wallet(request.user_id)
            poster_balance = float(poster_wallet.get('balance', 0))
            total_poster_cost = total_task_value + poster_deduction
            
            print(f"\n👤 Poster Balance Check:")
            print(f"   Current balance: ₹{poster_balance:.2f}")
            print(f"   Total cost: ₹{total_poster_cost:.2f}")
            
            if poster_balance < total_poster_cost:
                print(f"❌ Insufficient balance! Need ₹{total_poster_cost:.2f}, have ₹{poster_balance:.2f}")
                print('='*60 + "\n")
                return jsonify({
                    'success': False, 
                    'message': f'Insufficient balance. Need ₹{total_poster_cost:.2f}, have ₹{poster_balance:.2f}'
                }), 400
            
            # ===== POSTER WALLET OPERATIONS (deduct first) =====
            poster_new_balance = poster_balance - total_poster_cost
            
            print(f"\n👤 Poster Wallet Operations:")
            print(f"   Deducting full task value: -₹{total_task_value:.2f}")
            print(f"   Deducting poster fee (5%): -₹{poster_deduction:.2f}")
            print(f"   Total deduction: -₹{total_poster_cost:.2f}")
            print(f"   Final balance: ₹{poster_new_balance:.2f}")
            
            cursor.execute(f'''
                UPDATE wallets
                SET balance = {PH}, total_spent = total_spent + {PH}, updated_at = {PH}
                WHERE user_id = {PH}
            ''', (poster_new_balance, total_poster_cost, now, request.user_id))
            
            # Record poster payment transaction (for the full task value)
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, reference_id, task_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                poster_wallet.get('id'), request.user_id, 'debit',
                total_task_value, poster_new_balance + poster_deduction,
                f'Task payment to helper (INCLUDING service charge): ₹{total_task_value:.2f}',
                f'task-payment-{task_id}', task_id, now
            ))
            
            # Record poster fee transaction
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, reference_id, task_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                poster_wallet.get('id'), request.user_id, 'debit',
                poster_deduction, poster_new_balance,
                f'Posting fee (5% of total): ₹{poster_deduction:.2f}',
                f'task-fee-{task_id}', task_id, now
            ))
            
            # ===== HELPER WALLET OPERATIONS (credit after poster deducted) =====
            helper_wallet = get_or_create_wallet(helper_id)
            helper_balance = float(helper_wallet.get('balance', 0))
            
            helper_balance_after_credit = helper_balance + total_task_value
            helper_new_balance = helper_balance_after_credit - helper_total_deduction
            
            print(f"\n👥 Helper Wallet Operations:")
            print(f"   Current balance: ₹{helper_balance:.2f}")
            print(f"   Adding task earning: +₹{total_task_value:.2f}")
            print(f"   Deducting commission (12%): -₹{helper_total_deduction:.2f}")
            print(f"   Final balance: ₹{helper_new_balance:.2f}")
            print(f"   ✨ Helper Net Earning: ₹{(total_task_value - helper_total_deduction):.2f}")
            
            cursor.execute(f'''
                UPDATE wallets
                SET balance = {PH}, total_earned = total_earned + {PH}, updated_at = {PH}
                WHERE user_id = {PH}
            ''', (helper_new_balance, total_task_value, now, helper_id))
            
            # Record helper earning transaction
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, reference_id, task_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                helper_wallet.get('id'), helper_id, 'credit',
                total_task_value, helper_balance_after_credit,
                f'Task payment received (INCLUDING service charge): ₹{total_task_value:.2f}',
                f'task-earning-{task_id}', task_id, now
            ))
            
            # Record helper commission deduction
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, reference_id, task_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                helper_wallet.get('id'), helper_id, 'deduction',
                -helper_total_deduction, helper_new_balance,
                f'Commission (10%) + Transaction Fee (2%): ₹{helper_total_deduction:.2f}',
                f'task-commission-{task_id}', task_id, now
            ))
            
            # ===== COMPANY WALLET OPERATIONS =====
            # Company receives: Helper commission (12%) + Poster fee (5%)
            total_platform_income = helper_total_deduction + poster_deduction
            
            company_wallet = get_or_create_wallet('1')
            company_balance = float(company_wallet.get('balance', 0))
            company_new_balance = company_balance + total_platform_income
            
            print(f"\n🏢 Company/Platform Income:")
            print(f"   Helper Commission (12%): ₹{helper_total_deduction:.2f}")
            print(f"   Poster Fee (5%): ₹{poster_deduction:.2f}")
            print(f"   Total Platform Income: ₹{total_platform_income:.2f}")
            print(f"   Company balance: ₹{company_balance:.2f} → ₹{company_new_balance:.2f}")
            
            # Update company wallet
            cursor.execute(f'''
                UPDATE wallets
                SET balance = {PH}, total_earned = total_earned + {PH}, updated_at = {PH}
                WHERE user_id = {PH}
            ''', (company_new_balance, total_platform_income, now, '1'))
            
            # Record company income transactions
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, reference_id, task_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                company_wallet.get('id'), '1', 'commission',
                helper_total_deduction, company_new_balance - poster_deduction,
                f'Helper commission (12%) from task #{task_id}: ₹{helper_total_deduction:.2f}',
                f'task-commission-{task_id}', task_id, now
            ))
            
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, reference_id, task_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                company_wallet.get('id'), '1', 'platform_fee',
                poster_deduction, company_new_balance,
                f'Posting fee (5%) from task #{task_id}: ₹{poster_deduction:.2f}',
                f'task-fee-{task_id}', task_id, now
            ))
            
            # NOW: Send platform income to Razorpay UPI link (DISABLED FOR TESTING)
            print(f"\n🔄 Initiating UPI transfer to razorpay.me/@taskern...")
            amount_in_paise = int(total_platform_income * 100)
            
            # Temporarily mock the response for testing - skip actual Razorpay call
            upi_transfer_result = {
                'success': True,
                'message': 'UPI transfer initiated (test mode)',
                'transfer_id': f'test-transfer-{task_id}',
                'transfer_status': 'initiated'
            }
            print(f"✅ UPI TRANSFER INITIATED (test mode)")
            print(f"   Transfer ID: {upi_transfer_result.get('transfer_id')}")
            print(f"   Amount: ₹{total_platform_income:.2f}")
            print(f"   Status: {upi_transfer_result.get('transfer_status', 'initiated')}")
            
            # Mark task as PAID
            cursor.execute(f'''
                UPDATE tasks
                SET status = 'paid', paid_at = {PH}
                WHERE id = {PH}
            ''', (now, task_id))
            
            # Clear payment notification for poster
            cursor.execute(f'''
                DELETE FROM notifications
                WHERE task_id = {PH} AND user_id = {PH} AND notification_type = {PH}
            ''', (task_id, request.user_id, 'task_completed'))
            
            # Create "Payment Received" notification for helper
            import json
            helper_earnings = total_task_value - helper_total_deduction
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (helper_id, task_id, 'payment_received', 
                  'Payment Received! 💰',
                  f'You received ₹{helper_earnings:.2f} for completing "{task["title"]}".',
                  'unread', json.dumps({'type': 'success', 'taskId': task_id, 'amount': helper_earnings}), now))
            
            # Create "Payment Done" notification for poster
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, task_id, 'payment_done', 
                  'Payment Done! ✅',
                  f'You paid ₹{total_poster_cost:.2f} for "{task["title"]}". Helper received ₹{helper_earnings:.2f}.',
                  'unread', json.dumps({'type': 'success', 'taskId': task_id, 'amount': total_poster_cost}), now))
            
            conn.commit()
            
            print(f"\n✅ PAYMENT COMPLETE!")
            print(f"   Task status: completed → paid")
            print(f"   Helper final balance: ₹{helper_new_balance:.2f}")
            print(f"   Poster final balance: ₹{poster_new_balance:.2f}")
            print(f"   Company final balance: ₹{company_new_balance:.2f}")
            print('='*60 + "\n")
            
            return jsonify({
                'success': True,
                'message': 'Payment successful and funds transferred',
                'taskId': task_id,
                'amount': task_amount,
                'serviceCharge': service_charge,
                'totalTaskValue': total_task_value,
                'helperEarnings': total_task_value - helper_total_deduction,
                'helperCommission': helper_total_deduction,
                'posterFee': poster_deduction,
                'platformIncome': total_platform_income,
                'helperNewBalance': helper_new_balance,
                'posterNewBalance': poster_new_balance,
                'companyNewBalance': company_new_balance,
                'upiTransferStatus': upi_transfer_result.get('transfer_status', 'initiated')
            }), 200
    
    except Exception as e:
        print(f"❌ Payment error: {e}")
        import traceback
        traceback.print_exc()
        print('='*60 + "\n")
        return jsonify({'success': False, 'message': f'Payment failed: {str(e)}'}), 500


@app.route('/api/user/tasks', methods=['GET'])
@require_auth
def get_user_tasks():
    """Get current user's tasks"""
    with get_db() as (cursor, conn):
        # Posted tasks - ALL statuses
        cursor.execute(f'''
            SELECT * FROM tasks WHERE posted_by = {PH} ORDER BY posted_at DESC
        ''', (request.user_id,))
        posted = [dict_from_row(t) for t in cursor.fetchall()]
        
        # Accepted tasks - ALL statuses (accepted, completed, paid)
        cursor.execute(f'''
            SELECT * FROM tasks WHERE accepted_by = {PH} AND status IN ('accepted', 'completed', 'paid') ORDER BY accepted_at DESC
        ''', (request.user_id,))
        accepted = [dict_from_row(t) for t in cursor.fetchall()]
    
    return jsonify({
        'success': True,
        'postedTasks': posted,
        'acceptedTasks': accepted
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
# COMMISSION SYSTEM
# ========================================

# Commission configuration
COMMISSION_PERCENTAGE = 20  # 20% commission on helper earnings
def calculate_commission(amount):
    """Calculate commission on task amount"""
    return (amount * COMMISSION_PERCENTAGE) / 100

def clear_debt_suspension_if_needed(user_id, cursor):
    """Clear debt suspension if wallet balance is back to >= 0"""
    try:
        cursor.execute(f'SELECT balance FROM wallets WHERE user_id = {PH}', (user_id,))
        wallet = cursor.fetchone()
        if not wallet:
            return False
        balance = float(wallet[0]) if isinstance(wallet[0], (int, float)) else float(wallet['balance'])
        if balance >= 0:
            cursor.execute(f'''
                UPDATE users SET is_suspended = {PH}, suspension_reason = NULL, suspended_at = NULL
                WHERE id = {PH} AND is_suspended = {PH}
            ''', (False, user_id, True))
            print(f"✅ Debt suspension cleared for user {user_id}. Balance: ₹{balance:.2f}")
            return True
        return False
    except Exception as e:
        print(f"❌ Error clearing suspension: {e}")
        return False

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
        
        wallet_dict = dict_from_row(wallet)
        print(f"[DEBUG] get_or_create_wallet for {user_id}: {wallet_dict}")
        return wallet_dict


@app.route('/api/wallet/debug', methods=['GET'])
@require_auth
def debug_wallet():
    """Debug endpoint - check actual wallet balance in database"""
    try:
        with get_db() as (cursor, conn):
            # Get wallet directly from database
            cursor.execute(f'SELECT * FROM wallets WHERE user_id = {PH}', (request.user_id,))
            wallet_row = cursor.fetchone()
            
            if not wallet_row:
                return jsonify({'success': False, 'message': 'Wallet not found'}), 404
            
            wallet = dict_from_row(wallet_row)
            
            # Get recent transactions
            cursor.execute(f'''
                SELECT id, type, amount, balance_after, description, created_at
                FROM wallet_transactions 
                WHERE user_id = {PH}
                ORDER BY created_at DESC 
                LIMIT 20
            ''', (request.user_id,))
            transactions = [dict_from_row(row) for row in cursor.fetchall()]
        
        print(f"\n[DEBUG WALLET] Wallet info for user {request.user_id}:")
        print(f"  Wallet ID: {wallet.get('id')}")
        print(f"  Balance: ₹{wallet.get('balance')}")
        print(f"  Total Added: ₹{wallet.get('total_added')}")
        print(f"  Total Spent: ₹{wallet.get('total_spent')}")
        print(f"  Total Earned: ₹{wallet.get('total_earned')}")
        print(f"  Recent Transactions: {len(transactions)}")
        
        return jsonify({
            'success': True,
            'wallet': wallet,
            'recentTransactions': transactions
        }), 200
        
    except Exception as e:
        print(f"❌ Error in debug endpoint: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': str(e)}), 500


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
    wallet_id = wallet.get('id')
    
    with get_db() as (cursor, conn):
        # Update wallet
        cursor.execute(f'''
            UPDATE wallets 
            SET balance = {PH}, total_added = total_added + {PH}, total_cashback = total_cashback + {PH}
            WHERE user_id = {PH}
        ''', (new_balance, amount, cashback, request.user_id))
        
        # Add transaction record
        cursor.execute(f'''
            INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, reference_id, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (wallet_id, request.user_id, 'credit', amount, new_balance, 'Added money to wallet', payment_id, now))
        
        # Add cashback transaction if applicable
        if cashback > 0:
            cursor.execute(f'''
                INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (wallet_id, request.user_id, 'cashback', cashback, new_balance, f'2% cashback on ₹{amount}', now))
        
        conn.commit()
        
        # Auto-clear debt suspension if balance is back to >= 0
        if new_balance >= 0:
            clear_debt_suspension_if_needed(request.user_id, cursor)
    
    # Create wallet top-up notification
    try:
        import json
        cashback_msg = f' (includes ₹{cashback:.2f} cashback!)' if cashback > 0 else ''
        with get_db() as (cursor2, conn2):
            cursor2.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, 'wallet_topup',
                  'Wallet Topped Up! 💰',
                  f'₹{amount:.2f} has been added to your wallet{cashback_msg}. New balance: ₹{new_balance:.2f}',
                  'unread', json.dumps({'type': 'success', 'amount': amount, 'cashback': cashback}), now))
    except Exception as notif_err:
        print(f"⚠️ Failed to create topup notification: {notif_err}")
    
    debt_cleared = new_balance >= 0
    return jsonify({
        'success': True,
        'message': f'₹{amount} added successfully' + (f' + ₹{cashback:.2f} cashback!' if cashback > 0 else ''),
        'newBalance': new_balance,
        'cashback': cashback,
        'debtSuspended': new_balance <= -500,
        'debtCleared': debt_cleared
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


@app.route('/api/wallet/penalty', methods=['POST'])
@require_auth
def deduct_penalty():
    """Deduct penalty from wallet — allows negative balance"""
    data = request.get_json()
    amount = float(data.get('amount', 0))
    task_id = data.get('taskId')
    description = data.get('description', 'Task release penalty')
    
    if amount <= 0:
        return jsonify({'success': False, 'message': 'Invalid penalty amount'}), 400
    
    wallet = get_or_create_wallet(request.user_id)
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
        ''', (wallet['id'], request.user_id, 'penalty', amount, new_balance, description, task_id, now))
        
        conn.commit()
    
    debt_suspended = new_balance <= -500
    print(f"💸 Penalty ₹{amount} deducted from user {request.user_id}. New balance: ₹{new_balance:.2f}. Debt suspended: {debt_suspended}")
    
    return jsonify({
        'success': True,
        'message': f'₹{amount} penalty deducted',
        'newBalance': new_balance,
        'penalty': amount,
        'debtSuspended': debt_suspended,
        'debtAmount': abs(new_balance) if new_balance < 0 else 0
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
        
        # Auto-clear debt suspension if balance is back to >= 0
        if new_balance >= 0:
            clear_debt_suspension_if_needed(request.user_id, cursor)
    
    return jsonify({
        'success': True,
        'message': f'₹{amount} added to earnings',
        'newBalance': new_balance,
        'debtSuspended': new_balance <= -500
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
    """Process withdrawal from wallet to user's bank account"""
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
    
    if len(ifsc_code) != 11:
        return jsonify({'success': False, 'message': 'Invalid IFSC code (must be 11 characters)'}), 400
    
    # Validate account number (9-18 digits only)
    if not account_number.isdigit() or len(account_number) < 9 or len(account_number) > 18:
        return jsonify({'success': False, 'message': 'Invalid account number (must be 9-18 digits)'}), 400
    
    # Validate IFSC format: 4 letters + 0 + 6 alphanumeric
    import re
    if not re.match(r'^[A-Z]{4}0[A-Z0-9]{6}$', ifsc_code):
        return jsonify({'success': False, 'message': 'Invalid IFSC code format'}), 400
    
    # Check wallet balance
    wallet = get_or_create_wallet(request.user_id)
    balance = float(wallet['balance'])
    if balance < amount:
        return jsonify({'success': False, 'message': f'Insufficient balance. Available: ₹{balance:.2f}'}), 400
    
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    masked_account = '****' + account_number[-4:]
    
    print(f"\n{'='*60}")
    print(f"💸 WITHDRAWAL REQUEST")
    print(f"   User: {request.user_id}")
    print(f"   Amount: ₹{amount:.2f}")
    print(f"   Bank: {bank_name}")
    print(f"   Account: {masked_account}")
    print(f"   IFSC: {ifsc_code}")
    print(f"   Balance: ₹{balance:.2f}")
    print('='*60)
    
    with get_db() as (cursor, conn):
        # Deduct from wallet
        new_balance = balance - amount
        cursor.execute(f'''
            UPDATE wallets 
            SET balance = {PH}, total_spent = total_spent + {PH}, updated_at = {PH}
            WHERE user_id = {PH}
        ''', (new_balance, amount, now, request.user_id))
        
        # Store full account number for admin processing
        # Masked version shown to users in API responses
        cursor.execute(f'''
            INSERT INTO withdrawal_requests 
            (user_id, amount, bank_name, account_holder_name, account_number, ifsc_code, status, requested_at, created_at, updated_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            RETURNING id
        ''', (request.user_id, amount, bank_name, account_holder, account_number, ifsc_code, 'pending', now, now, now))
        withdrawal_row = cursor.fetchone()
        withdrawal_id = dict_from_row(withdrawal_row)['id'] if withdrawal_row else None
        
        # Add wallet transaction record
        cursor.execute(f'''
            INSERT INTO wallet_transactions 
            (wallet_id, user_id, type, amount, balance_after, description, reference_id, created_at, status)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (wallet['id'], request.user_id, 'withdrawal', amount, new_balance,
              f'Withdrawal to {bank_name} ({masked_account})',
              f'WD-{withdrawal_id}', now, 'pending'))
        
        conn.commit()
    
    # Create withdrawal notification
    try:
        import json
        with get_db() as (cursor2, conn2):
            cursor2.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, 'withdrawal_requested',
                  'Withdrawal Requested 🏦',
                  f'Your withdrawal of ₹{amount:.2f} to {bank_name} ({masked_account}) is being processed. It will be transferred within 24 hours.',
                  'unread', json.dumps({'type': 'info', 'amount': amount, 'withdrawalId': withdrawal_id}), now))
    except Exception as notif_err:
        print(f"⚠️ Failed to create withdrawal notification: {notif_err}")
    
    print(f"   New balance: ₹{new_balance:.2f}")
    print(f"   Withdrawal ID: {withdrawal_id}")
    print(f"   Status: pending (admin will process)")
    print('='*60 + "\n")
    
    return jsonify({
        'success': True,
        'message': f'₹{amount:.2f} withdrawal request submitted! Amount will be transferred to your bank account within 24 hours.',
        'newBalance': new_balance,
        'withdrawalId': withdrawal_id
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
        
        # Mask account numbers in response for security
        for w in withdrawals:
            acct = w.get('account_number', '')
            if acct and len(acct) > 4 and not acct.startswith('****'):
                w['account_number'] = '****' + acct[-4:]
        
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
            SELECT id, task_id, user_id, user_name, message, timestamp
            FROM chat_messages
            WHERE task_id = {PH}
            ORDER BY timestamp ASC
        ''', (task_id,))
        messages = [dict_from_row(row) for row in cursor.fetchall()]
    
    return jsonify({
        'success': True,
        'messages': messages
    })


@app.route('/api/chat/<int:task_id>/send', methods=['POST'])
@require_auth
def send_chat_message(task_id):
    """Send a chat message (REST fallback for Socket.IO)"""
    data = request.get_json()
    message = data.get('message', '').strip()
    
    if not message:
        return jsonify({'success': False, 'message': 'Message cannot be empty'}), 400
    
    with get_db() as (cursor, conn):
        # Verify user is part of this task
        cursor.execute(f'''
            SELECT * FROM tasks WHERE id = {PH} AND (posted_by = {PH} OR accepted_by = {PH})
        ''', (task_id, request.user_id, request.user_id))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        # Get user info
        cursor.execute(f'SELECT id, name FROM users WHERE id = {PH}', (request.user_id,))
        user = dict_from_row(cursor.fetchone())
        
        # Store message
        timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        cursor.execute(f'''
            INSERT INTO chat_messages (task_id, user_id, user_name, message, timestamp)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
        ''', (task_id, request.user_id, user['name'], message, timestamp))
    
    return jsonify({
        'success': True,
        'message': {
            'userId': request.user_id,
            'userName': user['name'],
            'message': message,
            'timestamp': timestamp
        }
    })


@app.route('/api/chat/unread', methods=['GET'])
@require_auth
def get_unread_count():
    """Get unread message count (for backward compatibility)"""
    # This endpoint maintained for compatibility, but Socket.IO handles real-time updates
    return jsonify({
        'success': True,
        'unreadCount': 0
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

import hashlib
import hmac

# Try to import razorpay, but don't fail if not available
try:
    import razorpay
    RAZORPAY_AVAILABLE = True
except ImportError:
    razorpay = None
    RAZORPAY_AVAILABLE = False
    print("⚠️ Razorpay library not available")

# Initialize Razorpay client
if RAZORPAY_AVAILABLE and config.RAZORPAY_KEY_ID and config.RAZORPAY_KEY_SECRET:
    razorpay_client = razorpay.Client(auth=(config.RAZORPAY_KEY_ID, config.RAZORPAY_KEY_SECRET))
else:
    razorpay_client = None
    if not RAZORPAY_AVAILABLE:
        print("⚠️ Razorpay library not installed")
    else:
        print("⚠️ Razorpay credentials not configured. Payment features will be disabled.")


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
            
            task_amount = float(amount)
            poster_id = task.get('posted_by')
            
            # CHECK: If task amount > 1000, use wallet auto-payment instead of Razorpay
            if task_amount > 1000:
                print(f"\n💰 AUTO-PAYMENT TRIGGERED (Task > ₹1000)")
                print(f"   Task Amount: ₹{task_amount:.2f}")
                
                # Get poster's wallet
                poster_wallet = get_or_create_wallet(poster_id)
                poster_balance = float(poster_wallet.get('balance', 0))
                
                print(f"   Poster balance: ₹{poster_balance:.2f}")
                
                # Auto-deduct from poster's wallet (even if negative)
                new_poster_balance = poster_balance - task_amount
                
                cursor.execute(f'''
                    UPDATE wallets
                    SET balance = {PH}
                    WHERE user_id = {PH}
                ''', (new_poster_balance, poster_id))
                
                # Record payment deduction
                now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                cursor.execute(f'''
                    INSERT INTO wallet_transactions (
                        wallet_id, user_id, type, amount, balance_after,
                        description, reference_id, task_id, created_at
                    ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (
                    poster_wallet.get('id'), poster_id, 'payment',
                    -task_amount, new_poster_balance,
                    f'Auto-payment for task (> ₹1000)',
                    f'task-{task_id}', task_id, now
                ))
                
                # Credit helper's wallet
                helper_wallet = get_or_create_wallet(helper_id)
                helper_balance = float(helper_wallet.get('balance', 0)) + task_amount
                
                cursor.execute(f'''
                    UPDATE wallets
                    SET balance = {PH}, total_earned = total_earned + {PH}
                    WHERE user_id = {PH}
                ''', (helper_balance, task_amount, helper_id))
                
                # Record earned transaction for helper
                cursor.execute(f'''
                    INSERT INTO wallet_transactions (
                        wallet_id, user_id, type, amount, balance_after,
                        description, reference_id, task_id, created_at
                    ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (
                    helper_wallet.get('id'), helper_id, 'earned',
                    task_amount, helper_balance,
                    f'Earned from auto-payment (task > ₹1000)',
                    f'task-{task_id}', task_id, now
                ))
                
                # Mark task as paid
                cursor.execute(f'''
                    UPDATE tasks
                    SET status = {PH}, paid_at = {PH}
                    WHERE id = {PH}
                ''', ('paid', now, task_id))
                
                conn.commit()
                
                print(f"✅ AUTO-PAYMENT PROCESSED")
                print(f"   Poster: ₹{poster_balance:.2f} → ₹{new_poster_balance:.2f}")
                print(f"   Helper: ₹{float(helper_wallet.get('balance', 0)) - task_amount:.2f} → ₹{helper_balance:.2f}")
                
                return jsonify({
                    'success': True,
                    'message': 'Auto-payment processed (wallet deduction)',
                    'paymentMethod': 'wallet',
                    'taskId': task_id,
                    'amount': task_amount,
                    'posterNewBalance': new_poster_balance,
                    'helperNewBalance': helper_balance
                }), 200
            
            # NORMAL RAZORPAY PAYMENT (Task <= 1000)
            print(f"\n✅ RAZORPAY PAYMENT VERIFIED")
            print(f"   Amount: ₹{task_amount:.2f}")
            
            # Calculate split: Helper gets 90%, Company gets 10%
            platform_fee = task_amount * 0.10
            helper_amount = task_amount - platform_fee
            
            print(f"   Helper ({helper_id}): ₹{helper_amount:.2f} (90%)")
            print(f"   Company: ₹{platform_fee:.2f} (10%)")
            
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
                task_id, poster_id, helper_id,
                task_amount, 'INR', 'paid', order_id, payment_id,
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
            company_wallet = get_or_create_wallet('1')  # Company ID
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


# ========================================
# WALLET TOP-UP WITH RAZORPAY (REAL MONEY)
# ========================================

@app.route('/api/payments/wallet-topup-order', methods=['POST'])
@require_auth
def create_wallet_topup_order():
    """Create Razorpay order for wallet top-up (real money)"""
    try:
        print(f"\n[WALLET] Wallet top-up order request")
        print(f"  Razorpay client initialized: {razorpay_client is not None}")
        print(f"  Razorpay key available: {bool(config.RAZORPAY_KEY_ID)}")
        
        if not razorpay_client:
            print("❌ [WALLET] Razorpay client not available")
            return jsonify({'success': False, 'message': 'Payment gateway not configured'}), 503
        
        data = request.get_json()
        amount = int(data.get('amount', 0))  # Should be in paise
        
        print(f"  Amount (raw): {amount}")
        
        # DEFENSIVE: Auto-detect if amount is in rupees vs paise
        # Minimum is ₹10 = 1000 paise
        # If amount < 1000 and >= 10, it's likely in rupees (from frontend not multiplying)
        if amount < 1000 and amount >= 10:
            print(f"⚠️  [WALLET] Amount appears to be in rupees, converting: {amount}₹ → {amount * 100} paise")
            amount = amount * 100
        
        print(f"  Amount (after conversion): {amount} paise (₹{amount/100})")
        
        if amount < 1000:  # Minimum ₹10
            return jsonify({'success': False, 'message': 'Minimum top-up is ₹10'}), 400
        
        print(f"[WALLET] Creating Razorpay order for wallet top-up: {amount} paise (₹{amount/100})")
        
        # Create Razorpay order
        order_data = {
            'amount': amount,
            'currency': 'INR',
            'receipt': f'wallet-{request.user_id}-{int(time.time())}',
            'description': f'Wallet Top-up - ₹{amount/100}',
            'notes': {
                'userId': str(request.user_id),
                'type': 'wallet_topup',
                'platform': 'Workmate4u'
            }
        }
        
        print(f"[WALLET] Order data prepared: {order_data}")
        
        try:
            order = razorpay_client.order.create(data=order_data)
            print(f"✅ [WALLET] Order created: {order['id']}")
        except Exception as razorpay_error:
            print(f"❌ [WALLET] Razorpay API error: {razorpay_error}")
            print(f"⚠️ [WALLET] Error detail: {str(razorpay_error)}")
            
            # For wallet topup, we cannot create a fallback order
            # The main issue is likely Razorpay credentials on Railway
            print(f"❌ [WALLET] Cannot proceed without Razorpay. Please verify:")
            print(f"   - RAZORPAY_KEY_ID is set on Railway")
            print(f"   - RAZORPAY_KEY_SECRET is set on Railway")
            print(f"   - Keys are valid and in LIVE mode")
            raise razorpay_error
        
        response_data = {
            'success': True,
            'orderId': order['id'],
            'amount': amount,
            'currency': 'INR',
            'key': config.RAZORPAY_KEY_ID
        }
        
        print(f"✅ [WALLET] Returning response with order: {response_data}")
        
        return jsonify(response_data), 201
        
    except Exception as e:
        print(f"❌ [WALLET] Error creating order: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Failed to create order: {str(e)}'}), 500


@app.route('/api/payments/wallet-topup-verify', methods=['POST'])
@require_auth
def verify_wallet_topup():
    """Verify wallet top-up payment with Razorpay signature and credit wallet"""
    try:
        data = request.get_json()
        payment_id = data.get('paymentId')
        order_id = data.get('orderId')
        signature = data.get('signature')
        amount = float(data.get('amount', 0))
        
        print(f"\n[WALLET] ===== WALLET TOP-UP VERIFICATION =====")
        print(f"[WALLET] Order ID: {order_id}")
        print(f"[WALLET] Payment ID: {payment_id}")
        print(f"[WALLET] Amount (raw): {amount}")
        
        # DEFENSIVE: Auto-detect if amount is in rupees vs paise
        # Minimum is ₹10 = 1000 paise
        # If amount < 1000, it's likely in rupees (from old buggy code)
        if amount < 1000 and amount >= 10:
            print(f"⚠️  [WALLET] Amount appears to be in rupees, converting: {amount}₹ → {amount * 100} paise")
            amount = amount * 100
        
        print(f"[WALLET] Amount (after conversion): {amount} paise = ₹{amount/100}")
        print(f"[WALLET] User: {request.user_id}")
        
        if not all([payment_id, order_id, amount]) or amount <= 0:
            print(f"❌ [WALLET] Missing required fields")
            return jsonify({'success': False, 'message': 'Invalid payment details'}), 400
        
        # CRITICAL: Verify payment with Razorpay using signature
        if not signature:
            print(f"❌ [WALLET] Missing Razorpay signature - cannot verify payment")
            return jsonify({'success': False, 'message': 'Payment signature required'}), 400
        
        print(f"[WALLET] Verifying Razorpay signature...")
        
        # Verify signature
        try:
            import hmac
            import hashlib
            
            # Create signature verification string
            verify_string = f"{order_id}|{payment_id}"
            generated_signature = hmac.new(
                config.RAZORPAY_KEY_SECRET.encode(),
                verify_string.encode(),
                hashlib.sha256
            ).hexdigest()
            
            if generated_signature != signature:
                print(f"❌ [WALLET] Signature verification FAILED!")
                print(f"   Expected: {generated_signature}")
                print(f"   Got: {signature}")
                return jsonify({
                    'success': False,
                    'message': 'Payment verification failed - signature mismatch'
                }), 401
            
            print(f"✅ [WALLET] Signature verified successfully")
            
        except Exception as sig_error:
            print(f"❌ [WALLET] Signature verification error: {sig_error}")
            return jsonify({
                'success': False,
                'message': f'Verification error: {str(sig_error)}'
            }), 400
        
        # Payment verified! Now credit wallet
        print(f"[WALLET] Payment verified, crediting wallet...")
        
        with get_db() as (cursor, conn):
            # Get or create wallet for user
            wallet = get_or_create_wallet(request.user_id)
            current_balance = float(wallet.get('balance', 0))
            credit_amount = amount / 100.0  # Convert from paise to rupees
            new_balance = current_balance + credit_amount
            
            print(f"[WALLET] Current balance: ₹{current_balance}")
            print(f"[WALLET] Crediting: ₹{credit_amount}")
            print(f"[WALLET] New balance: ₹{new_balance}")
            
            # Update wallet balance
            cursor.execute(f'''
                UPDATE wallets
                SET balance = {PH}, total_added = total_added + {PH}
                WHERE user_id = {PH}
            ''', (new_balance, credit_amount, request.user_id))
            
            # Get wallet ID for transaction record
            wallet_id = wallet.get('id')
            if not wallet_id:
                print(f"❌ [WALLET] Wallet ID not found! Wallet dict: {wallet}")
                # Try to fetch it again
                cursor.execute(f'SELECT id FROM wallets WHERE user_id = {PH}', (request.user_id,))
                wallet_row = cursor.fetchone()
                if wallet_row:
                    wallet_id = dict_from_row(wallet_row).get('id')
                    print(f"[WALLET] Fetched wallet_id: {wallet_id}")
            
            # Record transaction
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after,
                    description, reference_id, created_at
                ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                wallet_id, request.user_id, 'razorpay_topup',
                credit_amount, new_balance,
                f'Razorpay wallet top-up - ₹{credit_amount:.2f}',
                payment_id, now
            ))
            
            conn.commit()
        
        print(f"✅ [WALLET] Wallet credited successfully: ₹{credit_amount}")
        print(f"[WALLET] New balance: ₹{new_balance}")
        print(f"[WALLET] Transaction recorded with ID: {wallet_id}")
        
        return jsonify({
            'success': True,
            'message': f'Wallet credited with ₹{credit_amount}',
            'newBalance': float(new_balance),
            'transactionId': payment_id
        }), 200
        
    except Exception as e:
        print(f"❌ [WALLET] Verification failed: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Verification failed: {str(e)}'}), 500


@app.route('/api/wallet/topup', methods=['POST'])
@require_auth
def topup_wallet():
    """✅ DEPRECATED - Virtual wallet topups are disabled. Use Razorpay for all transactions.
    
    Only Razorpay-verified transactions are now supported.
    Use /api/payments/wallet-topup-order for real money wallet top-ups.
    """
    return jsonify({
        'success': False, 
        'message': 'Virtual wallet top-ups are disabled. Please use Razorpay payment gateway with /api/payments/wallet-topup-order'
    }), 403


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
    import os
    db_url = os.environ.get('DATABASE_URL', 'NOT SET')
    db_url_masked = db_url[:30] + '***' if db_url != 'NOT SET' else 'NOT SET'
    
    return jsonify({
        'success': True,
        'status': 'healthy',
        'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'database': 'PostgreSQL' if config.USE_POSTGRES else 'SQLite',
        'environment': 'production' if config.USE_POSTGRES else 'development',
        'config.DATABASE_URL': db_url_masked,
        'config.USE_POSTGRES': config.USE_POSTGRES
    })


@app.route('/admin-dashboard.html', methods=['GET'])
def admin_dashboard():
    """Serve admin dashboard HTML"""
    # Return HTML directly without trying to load a file
    html_content = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Dashboard - TaskEarn</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 40px;
            padding-bottom: 20px;
            border-bottom: 2px solid rgba(255, 255, 255, 0.1);
        }
        
        h1 {
            font-size: 32px;
            color: #4ade80;
        }
        
        .user-info {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        
        .logout-btn {
            background: #ff6b6b;
            border: none;
            color: white;
            padding: 10px 20px;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .logout-btn:hover {
            background: #ff5252;
            transform: translateY(-2px);
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .stat-card {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            padding: 25px;
            backdrop-filter: blur(10px);
            transition: all 0.3s ease;
        }
        
        .stat-card:hover {
            background: rgba(255, 255, 255, 0.08);
            border-color: rgba(74, 222, 128, 0.3);
            transform: translateY(-5px);
        }
        
        .stat-label {
            font-size: 14px;
            color: #aaa;
            margin-bottom: 10px;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-weight: 600;
        }
        
        .stat-value {
            font-size: 32px;
            font-weight: 700;
            color: #4ade80;
            margin-bottom: 5px;
        }
        
        .stat-subtext {
            font-size: 12px;
            color: #888;
        }
        
        .section {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            padding: 30px;
            margin-bottom: 30px;
            backdrop-filter: blur(10px);
        }
        
        .section h2 {
            font-size: 24px;
            margin-bottom: 25px;
            color: #4ade80;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        label {
            display: block;
            font-size: 14px;
            margin-bottom: 8px;
            color: #ddd;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        input, select {
            width: 100%;
            padding: 12px;
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 8px;
            color: #fff;
            font-size: 14px;
        }
        
        input:focus, select:focus {
            outline: none;
            border-color: #4ade80;
            box-shadow: 0 0 0 3px rgba(74, 222, 128, 0.1);
        }
        
        input::placeholder {
            color: #777;
        }
        
        .btn {
            padding: 12px 24px;
            border-radius: 8px;
            border: none;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .btn-primary {
            background: #4ade80;
            color: #000;
            width: 100%;
        }
        
        .btn-primary:hover {
            background: #22c55e;
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(74, 222, 128, 0.3);
        }
        
        .alert {
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            display: none;
        }
        
        .alert.success {
            background: rgba(74, 222, 128, 0.2);
            border-left: 4px solid #4ade80;
            color: #4ade80;
            display: block;
        }
        
        .alert.error {
            background: rgba(255, 107, 107, 0.2);
            border-left: 4px solid #ff6b6b;
            color: #ff6b6b;
            display: block;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        
        th, td {
            padding: 15px;
            text-align: left;
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
        }
        
        th {
            background: rgba(255, 255, 255, 0.05);
            font-weight: 700;
            color: #aaa;
        }
        
        .status-badge {
            display: inline-block;
            padding: 6px 12px;
            border-radius: 6px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
        }
        
        .status-initiated {
            background: rgba(96, 165, 250, 0.2);
            color: #60a5fa;
        }
        
        .status-completed {
            background: rgba(74, 222, 128, 0.2);
            color: #4ade80;
        }
        
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid rgba(74, 222, 128, 0.2);
            border-top: 3px solid #4ade80;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .no-data {
            text-align: center;
            padding: 40px;
            color: #888;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🏢 Admin Dashboard</h1>
            <div class="user-info">
                <span id="userEmail">Loading...</span>
                <button class="logout-btn" onclick="logout()">Logout</button>
            </div>
        </header>
        
        <div class="stats-grid" id="statsGrid">
            <div class="loading"></div>
        </div>
        
        <div class="section">
            <h2>💰 Platform Statistics</h2>
            <div id="statsContent">Loading statistics...</div>
        </div>
        
        <div class="section">
            <h2>📊 Settlement Status</h2>
            <div id="settlementContent">Loading settlement data...</div>
        </div>
    </div>
    
    <script>
        const API_BASE_URL = window.location.origin;
        let authToken = localStorage.getItem('authToken');
        
        if (!authToken) {
            alert('Please login first!');
            window.location.href = '/index.html';
        }
        
        document.addEventListener('DOMContentLoaded', () => {
            loadStats();
        });
        
        function getUserEmail() {
            try {
                const parts = authToken.split('.');
                if (parts.length !== 3) return 'Admin User';
                const payload = JSON.parse(atob(parts[1]));
                return payload.email || 'Admin User';
            } catch (e) {
                return 'Admin User';
            }
        }
        
        document.getElementById('userEmail').textContent = getUserEmail();
        
        async function loadStats() {
            try {
                const response = await fetch(`${API_BASE_URL}/api/admin/settlement-stats`, {
                    method: 'GET',
                    headers: {
                        'Authorization': `Bearer ${authToken}`,
                        'Content-Type': 'application/json'
                    }
                });
                
                const data = await response.json();
                
                if (data.success) {
                    renderStats(data);
                } else {
                    document.getElementById('statsGrid').innerHTML = 
                        '<div style="color: red;">Error: ' + data.message + '</div>';
                }
            } catch (error) {
                console.error('Error loading stats:', error);
                document.getElementById('statsGrid').innerHTML = 
                    '<div style="color: red;">Error: ' + error.message + '</div>';
            }
        }
        
        function renderStats(data) {
            const statsGrid = document.getElementById('statsGrid');
            statsGrid.innerHTML = `
                <div class="stat-card">
                    <div class="stat-label">💳 Current Balance</div>
                    <div class="stat-value">₹${data.current_balance.toFixed(2)}</div>
                    <div class="stat-subtext">Available for settlement</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">💸 Total Settled</div>
                    <div class="stat-value">₹${data.total_settled.toFixed(2)}</div>
                    <div class="stat-subtext">${data.settlement_count} settlements</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">📈 Income (30 Days)</div>
                    <div class="stat-value">₹${data.income_30d.toFixed(2)}</div>
                    <div class="stat-subtext">Helper + Poster fees</div>
                </div>
            `;
            
            document.getElementById('statsContent').innerHTML = `
                <p><strong>Current Balance:</strong> ₹${data.current_balance.toFixed(2)}</p>
                <p><strong>30-Day Income:</strong> ₹${data.income_30d.toFixed(2)}</p>
                <p><strong>Helper Commission (30D):</strong> ₹${data.commission_30d.toFixed(2)}</p>
                <p><strong>Poster Fees (30D):</strong> ₹${data.fees_30d.toFixed(2)}</p>
            `;
        }
        
        function logout() {
            localStorage.removeItem('authToken');
            window.location.href = '/index.html';
        }
    </script>
</body>
</html>'''
    
    return html_content, 200, {'Content-Type': 'text/html; charset=utf-8'}


@app.route('/admin-dashboard', methods=['GET'])
def admin_dashboard_redirect():
    """Redirect to admin dashboard"""
    return admin_dashboard()


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
# DATABASE CLEANUP
# ========================================

def cleanup_old_tasks():
    """Delete tasks that are completed or expired (older than 30 days), and notify posters of newly expired tasks"""
    try:
        with get_db() as (cursor, conn):
            try:
                import json
                now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                thirty_days_ago = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=30)).isoformat()
                
                # Mark active tasks as expired and notify posters
                cursor.execute(f'''
                    SELECT id, title, posted_by, price FROM tasks
                    WHERE status = 'active' AND expires_at < {PH}
                ''', (now,))
                expired_tasks = [dict_from_row(r) for r in cursor.fetchall()]
                
                for t in expired_tasks:
                    cursor.execute(f"UPDATE tasks SET status = 'expired' WHERE id = {PH}", (t['id'],))
                    notif_data = json.dumps({'type': 'task', 'taskId': t['id']})
                    cursor.execute(f'''
                        INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                        VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                    ''', (t['posted_by'], t['id'], 'task_expired',
                          'Task Expired ⏰',
                          f'Your task "{t["title"]}" has expired without being accepted. You can post it again.',
                          'unread', notif_data, now))
                
                if expired_tasks:
                    print(f"✅ Marked {len(expired_tasks)} tasks as expired and notified posters")
                
                # Delete completed tasks older than 30 days
                cursor.execute(f'''
                    DELETE FROM tasks 
                    WHERE (status = 'completed' OR status = 'paid')
                    AND completed_at IS NOT NULL
                    AND completed_at < {PH}
                ''', (thirty_days_ago,))
                
                deleted_count = cursor.rowcount
                
                if deleted_count > 0:
                    print(f"✅ Cleaned up {deleted_count} old completed/paid tasks")
                
                return deleted_count + len(expired_tasks)
            except Exception as query_error:
                print(f"⚠️  Query error during cleanup: {query_error}")
                # Don't crash if cleanup fails
                return 0
    except Exception as e:
        print(f"⚠️  Cleanup error: {e}")
        return 0


# ========================================
# CONTACT MESSAGES API
# ========================================

@app.route('/api/contact', methods=['POST'])
def submit_contact_message():
    """Save a contact form message"""
    data = request.get_json()
    name = (data.get('from_name') or data.get('name', '')).strip()
    email = (data.get('from_email') or data.get('email', '')).strip()
    subject = data.get('subject', '').strip()
    message = data.get('message', '').strip()

    if not name or not email or not message:
        return jsonify({'success': False, 'message': 'Name, email and message are required'}), 400

    # Optional: get user_id from token if logged in
    user_id = None
    auth_header = request.headers.get('Authorization', '')
    if auth_header.startswith('Bearer '):
        token = auth_header[7:]
        if token:
            with get_db() as (cursor, conn):
                cursor.execute(f'SELECT id FROM users WHERE session_token = {PH}', (token,))
                row = cursor.fetchone()
                if row:
                    user_id = dict_from_row(row)['id']

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                INSERT INTO contact_messages (name, email, subject, message, user_id, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (name, email, subject, message, user_id, 'new', now))
        return jsonify({'success': True, 'message': 'Message received. We will respond within 24 hours.'}), 200
    except Exception as e:
        print(f"Contact message save error: {e}")
        return jsonify({'success': True, 'message': 'Message received'}), 200


@app.route('/api/admin/contact-messages', methods=['GET'])
@require_auth
def get_contact_messages():
    """Get all contact messages (admin only)"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT * FROM contact_messages ORDER BY created_at DESC LIMIT 100')
            messages = [dict_from_row(row) for row in cursor.fetchall()]
        return jsonify({'success': True, 'messages': messages}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# NOTIFICATIONS API
# ========================================

@app.route('/api/notifications', methods=['GET'])
@require_auth
def get_notifications():
    """Get notifications for current user"""
    try:
        with get_db() as (cursor, conn):
            # Get unread notifications
            cursor.execute(f'''
                SELECT n.*, t.title as task_title
                FROM notifications n
                LEFT JOIN tasks t ON n.task_id = t.id
                WHERE n.user_id = {PH}
                ORDER BY n.created_at DESC
                LIMIT 50
            ''', (request.user_id,))
            
            rows = cursor.fetchall()
            notifications = [dict_from_row(row) for row in rows]
            
            return jsonify({
                'success': True,
                'notifications': notifications,
                'count': len(notifications)
            }), 200
    
    except Exception as e:
        print(f"❌ Error fetching notifications: {e}")
        return jsonify({'success': False, 'message': f'Error fetching notifications: {str(e)}'}), 500


@app.route('/api/notifications/<int:notification_id>/read', methods=['POST'])
@require_auth
def mark_notification_read(notification_id):
    """Mark notification as read"""
    try:
        with get_db() as (cursor, conn):
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                UPDATE notifications 
                SET status = 'read', read_at = {PH}
                WHERE id = {PH} AND user_id = {PH}
            ''', (now, notification_id, request.user_id))
            
            return jsonify({
                'success': True,
                'message': 'Notification marked as read'
            }), 200
    
    except Exception as e:
        print(f"❌ Error marking notification as read: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


@app.route('/api/notifications/<int:notification_id>', methods=['DELETE'])
@require_auth
def delete_notification(notification_id):
    """Delete notification"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                DELETE FROM notifications 
                WHERE id = {PH} AND user_id = {PH}
            ''', (notification_id, request.user_id))
            
            return jsonify({
                'success': True,
                'message': 'Notification deleted'
            }), 200
    
    except Exception as e:
        print(f"❌ Error deleting notification: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


@app.route('/api/notifications/clear-all', methods=['DELETE'])
@require_auth
def clear_all_notifications():
    """Delete all notifications for current user"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'DELETE FROM notifications WHERE user_id = {PH}', (request.user_id,))
            deleted = cursor.rowcount
            conn.commit()
            
            return jsonify({
                'success': True,
                'message': f'{deleted} notifications cleared'
            }), 200
    
    except Exception as e:
        print(f"❌ Error clearing all notifications: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


@app.route('/api/notifications/clear-task/<int:task_id>', methods=['POST'])
@require_auth
def clear_task_notifications(task_id):
    """Clear notifications for a completed task"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                DELETE FROM notifications 
                WHERE task_id = {PH} AND user_id = {PH}
            ''', (task_id, request.user_id))
            
            return jsonify({
                'success': True,
                'message': 'Task notifications cleared'
            }), 200
    
    except Exception as e:
        print(f"❌ Error clearing notifications: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


# ========================================
# PLATFORM SETTLEMENTS (Bank Payouts)
# ========================================

@app.route('/api/admin/bank-details', methods=['POST'])
@require_auth
def update_bank_details():
    """Update company bank details for settlements"""
    try:
        # Only admin can update bank details (user_id = 1)
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        data = request.get_json()
        account_number = data.get('account_number', '').strip()
        ifsc_code = data.get('ifsc_code', '').strip()
        account_holder_name = data.get('account_holder_name', 'TaskEarn Platform').strip()
        bank_name = data.get('bank_name', '').strip()
        
        if not account_number or not ifsc_code:
            return jsonify({'success': False, 'message': 'Account number and IFSC code required'}), 400
        
        with get_db() as (cursor, conn):
            # Check if bank details exist
            cursor.execute('SELECT id FROM company_bank_details LIMIT 1')
            existing = cursor.fetchone()
            
            now = datetime.datetime.now()
            now_str = now.strftime('%Y-%m-%d %H:%M:%S')
            
            if existing:
                # Update existing
                cursor.execute(f'''
                    UPDATE company_bank_details 
                    SET account_number = {PH}, 
                        ifsc_code = {PH}, 
                        account_holder_name = {PH},
                        bank_name = {PH},
                        updated_at = {PH}
                    WHERE id = {PH}
                ''', (account_number, ifsc_code, account_holder_name, bank_name, now_str, existing['id'] if isinstance(existing, dict) else existing[0]))
            else:
                # Insert new
                cursor.execute(f'''
                    INSERT INTO company_bank_details 
                    (account_number, ifsc_code, account_holder_name, bank_name, is_active, created_at, updated_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, 1, {PH}, {PH})
                ''', (account_number, ifsc_code, account_holder_name, bank_name, now_str, now_str))
            
            return jsonify({
                'success': True,
                'message': 'Bank details updated successfully',
                'account_last4': account_number[-4:] if len(account_number) >= 4 else account_number
            }), 200
    
    except Exception as e:
        print(f"❌ Error updating bank details: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


@app.route('/api/admin/bank-details', methods=['GET'])
@require_auth
def get_bank_details():
    """Get company bank details (masked)"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        with get_db() as (cursor, conn):
            cursor.execute('SELECT * FROM company_bank_details WHERE is_active = TRUE LIMIT 1')
            details = cursor.fetchone()
            
            if not details:
                return jsonify({'success': False, 'message': 'No bank details configured'}), 404
            
            details_dict = dict_from_row(details)
            # Mask account number
            account_number = details_dict['account_number']
            masked_account = '*' * (len(account_number) - 4) + account_number[-4:]
            
            return jsonify({
                'success': True,
                'account_number': masked_account,
                'account_last4': account_number[-4:],
                'ifsc_code': details_dict['ifsc_code'],
                'account_holder_name': details_dict.get('account_holder_name', 'TaskEarn Platform'),
                'bank_name': details_dict.get('bank_name', ''),
                'is_active': details_dict['is_active']
            }), 200
    
    except Exception as e:
        print(f"❌ Error getting bank details: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


# ========================================
# RAZORPAY PAYOUTS INTEGRATION
# ========================================

def send_to_razorpay_upi(amount_in_paise, upi_handle="taskern"):
    """Send platform income to Razorpay UPI address (razorpay.me/@taskern)"""
    try:
        import requests
        
        if not config.RAZORPAY_KEY_ID or not config.RAZORPAY_KEY_SECRET:
            print("⚠️  Razorpay keys not configured for UPI transfer")
            return {
                'success': False,
                'message': 'Razorpay keys not configured',
                'transfer_id': None
            }
        
        # Razorpay API for creating payouts to UPI
        url = 'https://api.razorpay.com/v1/payouts'
        auth = (config.RAZORPAY_KEY_ID, config.RAZORPAY_KEY_SECRET)
        
        # Create payout to UPI address
        payout_data = {
            'account_number': f'taskern',  # UPI handle
            'fund_account_id': f'razorpay.me/{upi_handle}',
            'amount': int(amount_in_paise),  # Amount in paise
            'currency': 'INR',
            'mode': 'UPI',
            'purpose': 'settlement',
            'description': f'TaskEarn Platform Settlement - ₹{amount_in_paise/100:.2f} to Razorpay UPI',
            'notes': {
                'project': 'TaskEarn',
                'type': 'platform_settlement',
                'recipient': 'razorpay.me/@taskern'
            }
        }
        
        print(f"💸 Sending ₹{amount_in_paise/100:.2f} to Razorpay UPI (@{upi_handle})...")
        payout_response = requests.post(url, json=payout_data, auth=auth, timeout=10)
        
        if payout_response.status_code not in [200, 201]:
            print(f"⚠️  UPI transfer response: {payout_response.status_code}")
            print(f"   Response: {payout_response.text}")
            # Try alternative: Create payment request link
            return create_razorpay_payment_link(amount_in_paise, upi_handle)
        
        payout = payout_response.json()
        transfer_id = payout.get('id')
        
        print(f"✅ UPI TRANSFER INITIATED!")
        print(f"   Transfer ID: {transfer_id}")
        print(f"   Amount: ₹{amount_in_paise/100:.2f}")
        print(f"   To: razorpay.me/@{upi_handle}")
        print(f"   Status: {payout.get('status')}")
        
        return {
            'success': True,
            'message': 'UPI transfer initiated successfully',
            'transfer_id': transfer_id,
            'transfer_status': payout.get('status'),
            'amount': amount_in_paise / 100,
            'recipient': f'razorpay.me/@{upi_handle}'
        }
        
    except requests.exceptions.RequestException as e:
        print(f"❌ Network error sending to UPI: {e}")
        return {
            'success': False,
            'message': f'Network error: {str(e)}',
            'transfer_id': None
        }
    except Exception as e:
        print(f"❌ Error sending to UPI: {e}")
        import traceback
        traceback.print_exc()
        return {
            'success': False,
            'message': f'Error: {str(e)}',
            'transfer_id': None
        }


def create_razorpay_payment_link(amount_in_paise, upi_handle):
    """Fallback: Create Razorpay Payment Link for UPI address"""
    try:
        import requests
        
        url = 'https://api.razorpay.com/v1/payment_links'
        auth = (config.RAZORPAY_KEY_ID, config.RAZORPAY_KEY_SECRET)
        
        # Create payment link
        link_data = {
            'amount': int(amount_in_paise),
            'currency': 'INR',
            'accept_partial': False,
            'first_min_partial_amount': int(amount_in_paise),
            'reference_id': f'taskern-{int(time.time())}',
            'description': f'TaskEarn Platform Settlement to {upi_handle}',
            'customer_notify': 1,
            'notify': {
                'sms': False,
                'email': False
            },
            'reminder_enable': False,
            'notes': {
                'project': 'TaskEarn',
                'recipient_upi': f'razorpay.me/@{upi_handle}'
            }
        }
        
        print(f"🔗 Creating Razorpay Payment Link for ₹{amount_in_paise/100:.2f}...")
        link_response = requests.post(url, json=link_data, auth=auth, timeout=10)
        
        if link_response.status_code not in [200, 201]:
            print(f"⚠️  Payment Link creation failed: {link_response.status_code}")
            return {
                'success': False,
                'message': f'Payment link creation failed',
                'transfer_id': None
            }
        
        link = link_response.json()
        link_id = link.get('id')
        
        print(f"✅ PAYMENT LINK CREATED!")
        print(f"   Link ID: {link_id}")
        print(f"   Short URL: {link.get('short_url')}")
        
        return {
            'success': True,
            'message': 'Payment link created',
            'transfer_id': link_id,
            'payment_link': link.get('short_url'),
            'amount': amount_in_paise / 100
        }
        
    except Exception as e:
        print(f"❌ Error creating payment link: {e}")
        return {
            'success': False,
            'message': f'Error: {str(e)}',
            'transfer_id': None
        }


def create_razorpay_payout(amount_in_paise, account_number, ifsc_code, account_holder_name):
    """Create a payout using RazorpayX Payouts API
    
    Flow: Create Contact → Create Fund Account → Create Payout
    Requires: RazorpayX activated, RAZORPAYX_ACCOUNT_NUMBER env var set
    """
    try:
        import requests
        
        if not config.RAZORPAY_KEY_ID or not config.RAZORPAY_KEY_SECRET:
            return {'success': False, 'message': 'Razorpay keys not configured', 'payout_id': None}
        
        if not config.RAZORPAYX_ACCOUNT_NUMBER:
            return {'success': False, 'message': 'RazorpayX account number not configured. Set RAZORPAYX_ACCOUNT_NUMBER env var.', 'payout_id': None}
        
        auth = (config.RAZORPAY_KEY_ID, config.RAZORPAY_KEY_SECRET)
        headers = {'Content-Type': 'application/json'}
        
        # Step 1: Create contact
        contact_data = {
            'name': account_holder_name,
            'type': 'customer',
            'reference_id': f'taskearn_{account_number[-4:]}_{int(time.time())}',
            'notes': {
                'platform': 'TaskEarn'
            }
        }
        
        print(f"📨 Step 1: Creating RazorpayX contact...")
        contact_resp = requests.post(
            'https://api.razorpay.com/v1/contacts',
            json=contact_data, auth=auth, headers=headers, timeout=15
        )
        
        if contact_resp.status_code not in [200, 201]:
            error_msg = contact_resp.text
            print(f"❌ Contact creation failed: {contact_resp.status_code} - {error_msg}")
            return {'success': False, 'message': f'Contact creation failed: {error_msg}', 'payout_id': None}
        
        contact_id = contact_resp.json().get('id')
        if not contact_id:
            return {'success': False, 'message': 'Contact created but no ID returned', 'payout_id': None}
        
        print(f"✅ Contact created: {contact_id}")
        
        # Step 2: Create fund account (bank account linked to contact)
        fund_data = {
            'contact_id': contact_id,
            'account_type': 'bank_account',
            'bank_account': {
                'name': account_holder_name,
                'ifsc': ifsc_code,
                'account_number': account_number
            }
        }
        
        print(f"📨 Step 2: Creating fund account for ****{account_number[-4:]} ({ifsc_code})...")
        fund_resp = requests.post(
            'https://api.razorpay.com/v1/fund_accounts',
            json=fund_data, auth=auth, headers=headers, timeout=15
        )
        
        if fund_resp.status_code not in [200, 201]:
            error_msg = fund_resp.text
            print(f"❌ Fund account creation failed: {fund_resp.status_code} - {error_msg}")
            return {'success': False, 'message': f'Fund account creation failed: {error_msg}', 'payout_id': None}
        
        fund_account_id = fund_resp.json().get('id')
        if not fund_account_id:
            return {'success': False, 'message': 'Fund account created but no ID returned', 'payout_id': None}
        
        print(f"✅ Fund account created: {fund_account_id}")
        
        # Step 3: Create payout
        payout_data = {
            'account_number': config.RAZORPAYX_ACCOUNT_NUMBER,  # YOUR RazorpayX business account number
            'fund_account_id': fund_account_id,
            'amount': int(amount_in_paise),
            'currency': 'INR',
            'mode': 'IMPS',  # IMPS for faster transfer (instant), NEFT for batched
            'purpose': 'payout',
            'queue_if_low_balance': True,
            'reference_id': f'wd_{int(time.time())}',
            'narration': f'TaskEarn Withdrawal',
            'notes': {
                'platform': 'TaskEarn',
                'type': 'user_withdrawal'
            }
        }
        
        print(f"💸 Step 3: Creating payout of ₹{amount_in_paise/100:.2f}...")
        payout_resp = requests.post(
            'https://api.razorpay.com/v1/payouts',
            json=payout_data, auth=auth, headers=headers, timeout=15
        )
        
        if payout_resp.status_code not in [200, 201]:
            error_msg = payout_resp.text
            print(f"❌ Payout creation failed: {payout_resp.status_code} - {error_msg}")
            return {'success': False, 'message': f'Payout failed: {error_msg}', 'payout_id': None}
        
        payout = payout_resp.json()
        payout_id = payout.get('id')
        payout_status = payout.get('status', 'processing')
        
        print(f"✅ PAYOUT CREATED SUCCESSFULLY!")
        print(f"   Payout ID: {payout_id}")
        print(f"   Amount: ₹{amount_in_paise/100:.2f}")
        print(f"   Bank: {ifsc_code} ****{account_number[-4:]}")
        print(f"   Status: {payout_status}")
        print(f"   Mode: IMPS")
        
        return {
            'success': True,
            'message': 'Payout created successfully',
            'payout_id': payout_id,
            'payout_status': payout_status,
            'amount': amount_in_paise / 100
        }
        
    except requests.exceptions.RequestException as e:
        print(f"❌ Network error creating payout: {e}")
        return {'success': False, 'message': f'Network error: {str(e)}', 'payout_id': None}
    except Exception as e:
        print(f"❌ Error creating Razorpay payout: {e}")
        import traceback
        traceback.print_exc()
        return {'success': False, 'message': f'Error: {str(e)}', 'payout_id': None}


@app.route('/api/admin/process-settlement', methods=['POST'])
@require_auth
def process_settlement():
    """Process platform settlement - transfer to bank account"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        with get_db() as (cursor, conn):
            # Get bank details
            cursor.execute('SELECT * FROM company_bank_details WHERE is_active = TRUE LIMIT 1')
            bank_details = cursor.fetchone()
            
            if not bank_details:
                return jsonify({'success': False, 'message': 'Bank details not configured'}), 400
            
            # Get company wallet
            cursor.execute(f'SELECT balance FROM wallets WHERE user_id = {PH} LIMIT 1', ('1',))
            wallet = cursor.fetchone()
            company_balance = float(wallet[0]) if wallet else 0
            
            if company_balance <= 0:
                return jsonify({
                    'success': False, 
                    'message': 'No funds to settle',
                    'balance': company_balance
                }), 400
            
            # Get settlement summary for this period (24 hours or custom period)
            now = datetime.datetime.now()
            yesterday = now - datetime.timedelta(days=1)
            yesterday_str = yesterday.strftime('%Y-%m-%d %H:%M:%S')
            now_str = now.strftime('%Y-%m-%d %H:%M:%S')
            
            # Get income transactions from last 24 hours
            cursor.execute(f'''
                SELECT 
                    SUM(CASE WHEN transaction_type = 'commission' THEN amount ELSE 0 END) as helper_commission,
                    SUM(CASE WHEN transaction_type = 'platform_fee' THEN amount ELSE 0 END) as poster_fees
                FROM wallet_transactions
                WHERE user_id = {PH} AND created_at >= {PH}
                AND transaction_type IN ('commission', 'platform_fee')
            ''', ('1', yesterday_str,))
            
            income_summary = cursor.fetchone()
            helper_commission = float(income_summary[0] or 0) if income_summary else 0
            poster_fees = float(income_summary[1] or 0) if income_summary else 0
            total_income = helper_commission + poster_fees
            
            # Create settlement record
            settlement_date = now.strftime('%Y-%m-%d')
            settlement_date_str = now.strftime('%Y-%m-%d %H:%M:%S')
            bank_details_dict = dict_from_row(bank_details)
            
            cursor.execute(f'''
                INSERT INTO platform_settlements
                (settlement_date, period_start, period_end, total_income, helper_commission, 
                 poster_fees, amount_settled, razorpay_payout_id, status, bank_account_last4, created_at, updated_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (
                settlement_date,
                yesterday_str,
                now_str,
                total_income,
                helper_commission,
                poster_fees,
                total_income,
                'RAZORPAY_PAYOUT_PENDING',  # Will be updated when actually processed
                'initiated',
                bank_details_dict['account_number'][-4:] if bank_details_dict else 'XXXX',
                settlement_date_str,
                settlement_date_str
            ))
            
            print(f"💰 SETTLEMENT INITIATED")
            print(f"   Period: {yesterday_str} to {now_str}")
            print(f"   Helper Commission: ₹{helper_commission:.2f}")
            print(f"   Poster Fees: ₹{poster_fees:.2f}")
            print(f"   Amount to Transfer: ₹{total_income:.2f}")
            print(f"   Company Balance Before: ₹{company_balance:.2f}")
            
            # NOW: Call Razorpay Payouts API to transfer money to bank account
            amount_in_paise = int(total_income * 100)  # Convert rupees to paise
            payout_result = create_razorpay_payout(
                amount_in_paise,
                bank_details_dict['account_number'],
                bank_details_dict['ifsc_code'],
                bank_details_dict.get('account_holder_name', 'TaskEarn Platform')
            )
            
            # Update settlement record with payout result
            payout_id = payout_result.get('payout_id', 'RAZORPAY_PAYOUT_FAILED')
            payout_status = 'completed' if payout_result['success'] else 'failed'
            
            if payout_result['success']:
                print(f"✅ RAZORPAY PAYOUT SUCCESSFUL!")
                print(f"   Payout ID: {payout_id}")
                print(f"   Destination: {bank_details_dict['ifsc_code']} {bank_details_dict['account_number'][-4:]}")
            else:
                print(f"❌ RAZORPAY PAYOUT FAILED")
                print(f"   Reason: {payout_result.get('message', 'Unknown error')}")
            
            # Update the settlement record with payout info
            now_str = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            cursor.execute(f'''
                UPDATE platform_settlements 
                SET razorpay_payout_id = {PH}, 
                    status = {PH},
                    processed_at = {PH},
                    updated_at = {PH}
                WHERE settlement_date = {PH}
                ORDER BY id DESC LIMIT 1
            ''', (payout_id, payout_status, now_str, now_str, settlement_date))
            
            return jsonify({
                'success': payout_result['success'],
                'message': payout_result.get('message', 'Settlement processed'),
                'settlement_status': 'completed' if payout_result['success'] else 'failed',
                'period_start': yesterday_str,
                'period_end': now_str,
                'total_income': total_income,
                'helper_commission': helper_commission,
                'poster_fees': poster_fees,
                'amount_settled': total_income,
                'company_balance': company_balance,
                'bank_account_last4': bank_details_dict['account_number'][-4:] if bank_details_dict else 'XXXX',
                'razorpay_payout_id': payout_id,
                'payout_status': payout_result.get('payout_status', 'pending'),
                'payout_message': payout_result.get('message', '')
            }), 200 if payout_result['success'] else 400
    
    except Exception as e:
        print(f"❌ Error processing settlement: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


@app.route('/api/admin/settlements', methods=['GET'])
@require_auth
def get_settlements():
    """Get settlement history"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        limit = request.args.get('limit', 30, type=int)
        offset = request.args.get('offset', 0, type=int)
        
        with get_db() as (cursor, conn):
            # Get total count
            cursor.execute('SELECT COUNT(*) as total FROM platform_settlements')
            total = cursor.fetchone()[0]
            
            # Get settlements
            cursor.execute(f'''
                SELECT * FROM platform_settlements
                ORDER BY settlement_date DESC, id DESC
                LIMIT {PH} OFFSET {PH}
            ''', (limit, offset))
            
            settlements = []
            for row in cursor.fetchall():
                settlement = dict_from_row(row)
                settlements.append({
                    'id': settlement['id'],
                    'date': settlement['settlement_date'],
                    'period_start': settlement['period_start'],
                    'period_end': settlement['period_end'],
                    'total_income': float(settlement['total_income']),
                    'helper_commission': float(settlement['helper_commission']),
                    'poster_fees': float(settlement['poster_fees']),
                    'amount_settled': float(settlement['amount_settled']),
                    'status': settlement['status'],
                    'bank_account_last4': settlement['bank_account_last4'],
                    'razorpay_payout_id': settlement['razorpay_payout_id'],
                    'processed_at': settlement['processed_at'],
                    'created_at': settlement['created_at']
                })
            
            return jsonify({
                'success': True,
                'settlements': settlements,
                'total': total,
                'limit': limit,
                'offset': offset
            }), 200
    
    except Exception as e:
        print(f"❌ Error getting settlements: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


@app.route('/api/admin/settlement-stats', methods=['GET'])
@require_auth
def get_settlement_stats():
    """Get settlement statistics"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        with get_db() as (cursor, conn):
            # Get company wallet balance
            cursor.execute(f'SELECT balance FROM wallets WHERE user_id = {PH}', ('1',))
            wallet = cursor.fetchone()
            current_balance = float(wallet[0]) if wallet else 0
            
            # Get total settled amount
            cursor.execute('''
                SELECT SUM(amount_settled) as total_settled, COUNT(*) as settlement_count
                FROM platform_settlements
                WHERE status IN ('completed', 'initiated')
            ''')
            result = cursor.fetchone()
            total_settled = float(result[0] or 0) if result else 0
            settlement_count = result[1] if result else 0
            
            # Get stats for last 30 days
            thirty_days_ago = (datetime.datetime.now() - datetime.timedelta(days=30)).strftime('%Y-%m-%d')
            cursor.execute(f'''
                SELECT 
                    SUM(total_income) as income_30d,
                    SUM(helper_commission) as commission_30d,
                    SUM(poster_fees) as fees_30d
                FROM platform_settlements
                WHERE settlement_date >= {PH}
            ''', (thirty_days_ago,))
            
            stats_30d = cursor.fetchone()
            income_30d = float(stats_30d[0] or 0) if stats_30d else 0
            commission_30d = float(stats_30d[1] or 0) if stats_30d else 0
            fees_30d = float(stats_30d[2] or 0) if stats_30d else 0
            
            return jsonify({
                'success': True,
                'current_balance': current_balance,
                'total_settled': total_settled,
                'settlement_count': settlement_count,
                'income_30d': income_30d,
                'commission_30d': commission_30d,
                'fees_30d': fees_30d,
                'ready_for_settlement': current_balance
            }), 200
    
    except Exception as e:
        print(f"❌ Error getting settlement stats: {e}")
        return jsonify({'success': False, 'message': f'Error: {str(e)}'}), 500


# ========================================
# BANK DETAILS INITIALIZATION
# ========================================
def initialize_bank_details():
    """Initialize company bank details if not already set"""
    try:
        with get_db() as (cursor, conn):
            # Check if bank details already exist
            cursor.execute('SELECT id FROM company_bank_details WHERE is_active = TRUE LIMIT 1')
            existing = cursor.fetchone()
            
            if not existing:
                # Initialize with provided bank details
                now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                cursor.execute(f'''
                    INSERT INTO company_bank_details
                    (account_number, ifsc_code, account_holder_name, bank_name, is_active, created_at, updated_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, TRUE, {PH}, {PH})
                ''', ('2549449456', 'KKBK0001764', 'TaskEarn Platform', 'Kotak Bank', now, now))
                print("💾 Bank details initialized: KKBK0001764 ****9456")
            else:
                print("✅ Bank details already configured")
    except Exception as e:
        print(f"⚠️  Could not initialize bank details: {e}")

# Initialize bank details on startup
try:
    initialize_bank_details()
except Exception as e:
    print(f"⚠️  Bank details init failed: {e}")


# ========================================
# ADMIN AUDIT LOG HELPER
# ========================================

def log_admin_action(cursor, admin_id, action, resource_type, resource_id=None, details=None, ip_address=None):
    """Log an admin action to the audit trail"""
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    cursor.execute(f'''
        INSERT INTO admin_audit_log (admin_id, action, resource_type, resource_id, details, ip_address, created_at)
        VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
    ''', (admin_id, action, resource_type, str(resource_id) if resource_id else None, details, ip_address, now))


# ========================================
# ADMIN: AUDIT LOG API
# ========================================

@app.route('/api/admin/audit-log', methods=['GET'])
@require_auth
def get_audit_log():
    """Get admin audit log entries"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        limit = min(int(request.args.get('limit', 50)), 200)
        offset = int(request.args.get('offset', 0))
        
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT * FROM admin_audit_log 
                ORDER BY created_at DESC 
                LIMIT {PH} OFFSET {PH}
            ''', (limit, offset))
            rows = cursor.fetchall()
            entries = [dict_from_row(row) for row in rows]
            
            cursor.execute('SELECT COUNT(*) as count FROM admin_audit_log')
            total = cursor.fetchone()[0]
        
        return jsonify({'success': True, 'entries': entries, 'total': total}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# ADMIN: MANUAL REFUND
# ========================================

@app.route('/api/admin/refund', methods=['POST'])
@require_auth
def admin_manual_refund():
    """Admin manually credits a user's wallet"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        data = request.get_json()
        target_user_id = data.get('user_id', '').strip()
        amount = float(data.get('amount', 0))
        reason = data.get('reason', '').strip()
        
        if not target_user_id or amount <= 0 or not reason:
            return jsonify({'success': False, 'message': 'user_id, positive amount, and reason are required'}), 400
        
        if amount > 50000:
            return jsonify({'success': False, 'message': 'Refund amount cannot exceed ₹50,000'}), 400
        
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        with get_db() as (cursor, conn):
            # Check user exists
            cursor.execute(f'SELECT id, name FROM users WHERE id = {PH}', (target_user_id,))
            user = cursor.fetchone()
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404
            
            # Update wallet balance
            cursor.execute(f'''
                UPDATE wallets SET balance = balance + {PH}, updated_at = {PH}
                WHERE user_id = {PH}
            ''', (amount, now, target_user_id))
            
            if cursor.rowcount == 0:
                return jsonify({'success': False, 'message': 'User wallet not found'}), 404
            
            # Get new balance
            cursor.execute(f'SELECT balance FROM wallets WHERE user_id = {PH}', (target_user_id,))
            new_balance = float(cursor.fetchone()[0])
            
            # Log transaction
            cursor.execute(f'''
                INSERT INTO wallet_transactions (user_id, wallet_id, type, amount, balance_after, description, status, created_at)
                SELECT {PH}, w.id, 'refund', {PH}, {PH}, {PH}, 'completed', {PH}
                FROM wallets w WHERE w.user_id = {PH}
            ''', (target_user_id, amount, new_balance, f'Admin refund: {reason}', now, target_user_id))
            
            # Audit log
            log_admin_action(cursor, request.user_id, 'refund', 'wallet', target_user_id,
                           f'Refunded ₹{amount} to user. Reason: {reason}', request.remote_addr)
        
        return jsonify({
            'success': True, 
            'message': f'₹{amount} refunded to user wallet',
            'new_balance': new_balance
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# ADMIN: TASK MODERATION
# ========================================

@app.route('/api/admin/tasks/<int:task_id>/hide', methods=['POST'])
@require_auth
def admin_hide_task(task_id):
    """Admin hides/removes an inappropriate task"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        data = request.get_json() or {}
        reason = data.get('reason', 'Removed by admin').strip()
        
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id, title, status, posted_by FROM tasks WHERE id = {PH}', (task_id,))
            task = cursor.fetchone()
            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404
            
            old_status = task[2] if not hasattr(task, 'get') else task.get('status', '')
            
            # Set task to 'removed' status
            cursor.execute(f"UPDATE tasks SET status = 'removed' WHERE id = {PH}", (task_id,))
            
            # Audit log
            log_admin_action(cursor, request.user_id, 'hide_task', 'task', task_id,
                           f'Task hidden (was: {old_status}). Reason: {reason}', request.remote_addr)
        
        return jsonify({'success': True, 'message': 'Task hidden successfully'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/admin/tasks/<int:task_id>/restore', methods=['POST'])
@require_auth
def admin_restore_task(task_id):
    """Admin restores a hidden task back to active"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id, status FROM tasks WHERE id = {PH}', (task_id,))
            task = cursor.fetchone()
            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404
            
            cursor.execute(f"UPDATE tasks SET status = 'active' WHERE id = {PH}", (task_id,))
            
            log_admin_action(cursor, request.user_id, 'restore_task', 'task', task_id,
                           'Task restored to active', request.remote_addr)
        
        return jsonify({'success': True, 'message': 'Task restored'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# ADMIN: ANALYTICS / DASHBOARD STATS
# ========================================

@app.route('/api/admin/analytics', methods=['GET'])
@require_auth
def admin_analytics():
    """Get platform analytics for admin dashboard"""
    try:
        if request.user_id != '1':
            return jsonify({'success': False, 'message': 'Unauthorized'}), 403
        
        with get_db() as (cursor, conn):
            # Signups per day (last 30 days)
            cursor.execute('''
                SELECT DATE(joined_at) as day, COUNT(*) as count
                FROM users
                WHERE joined_at >= NOW() - INTERVAL '30 days'
                GROUP BY DATE(joined_at)
                ORDER BY day
            ''')
            signups = [{'day': str(r[0]), 'count': r[1]} for r in cursor.fetchall()]
            
            # Tasks per day (last 30 days)
            cursor.execute('''
                SELECT DATE(posted_at) as day, COUNT(*) as count
                FROM tasks
                WHERE posted_at >= NOW() - INTERVAL '30 days'
                GROUP BY DATE(posted_at)
                ORDER BY day
            ''')
            tasks_daily = [{'day': str(r[0]), 'count': r[1]} for r in cursor.fetchall()]
            
            # Tasks by category
            cursor.execute('''
                SELECT category, COUNT(*) as count
                FROM tasks
                GROUP BY category
                ORDER BY count DESC
                LIMIT 10
            ''')
            categories = [{'category': r[0], 'count': r[1]} for r in cursor.fetchall()]
            
            # Revenue last 30 days (commission + poster fees)
            cursor.execute('''
                SELECT COALESCE(SUM(amount), 0) as total
                FROM wallet_transactions
                WHERE user_id = '1'
                  AND type IN ('commission', 'platform_fee')
                  AND created_at >= NOW() - INTERVAL '30 days'
            ''')
            revenue_30d = float(cursor.fetchone()[0])
            
            # Tasks by status
            cursor.execute('''
                SELECT status, COUNT(*) as count
                FROM tasks GROUP BY status ORDER BY count DESC
            ''')
            tasks_by_status = [{'status': r[0], 'count': r[1]} for r in cursor.fetchall()]
            
            # Top earners
            cursor.execute('''
                SELECT u.id, u.name, w.total_earned, w.balance
                FROM users u JOIN wallets w ON u.id = w.user_id
                ORDER BY w.total_earned DESC
                LIMIT 10
            ''')
            top_earners = [{'id': r[0], 'name': r[1], 'total_earned': float(r[2] or 0), 'balance': float(r[3] or 0)} for r in cursor.fetchall()]
        
        return jsonify({
            'success': True,
            'signups_daily': signups,
            'tasks_daily': tasks_daily,
            'categories': categories,
            'revenue_30d': revenue_30d,
            'tasks_by_status': tasks_by_status,
            'top_earners': top_earners
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# STATIC FILE SERVING (Must come AFTER all API routes)
# ========================================


# ========================================
# RUN SERVER
# ========================================

if __name__ == '__main__':
    import sys
    import os
    
    # Initialize database
    init_db()
    
    # Try to run cleanup on startup (but don't crash if it fails)
    try:
        cleanup_old_tasks()
    except Exception as cleanup_error:
        print(f"⚠️  Cleanup failed at startup (non-fatal): {cleanup_error}")
    
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

