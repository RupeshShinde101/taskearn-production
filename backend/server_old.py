"""
TaskEarn Backend Server
Flask + SQLite + bcrypt + JWT
Production-ready authentication
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
import sqlite3
import jwt
import datetime
import os
import secrets
import re

app = Flask(__name__)
CORS(app)  # Enable CORS for frontend communication

# Configuration
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['DATABASE'] = 'taskearn.db'
JWT_EXPIRATION_HOURS = 24

# ========================================
# DATABASE SETUP
# ========================================

def get_db():
    """Get database connection"""
    conn = sqlite3.connect(app.config['DATABASE'])
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    """Initialize database tables"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Users table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            phone TEXT,
            dob TEXT,
            rating REAL DEFAULT 5.0,
            tasks_posted INTEGER DEFAULT 0,
            tasks_completed INTEGER DEFAULT 0,
            total_earnings REAL DEFAULT 0,
            joined_at TEXT NOT NULL,
            last_login TEXT,
            session_token TEXT
        )
    ''')
    
    # Tasks table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            category TEXT,
            location_lat REAL,
            location_lng REAL,
            location_address TEXT,
            price REAL NOT NULL,
            posted_by TEXT NOT NULL,
            posted_at TEXT NOT NULL,
            expires_at TEXT,
            accepted_by TEXT,
            accepted_at TEXT,
            completed_at TEXT,
            status TEXT DEFAULT 'active',
            FOREIGN KEY (posted_by) REFERENCES users(id),
            FOREIGN KEY (accepted_by) REFERENCES users(id)
        )
    ''')
    
    # Password reset tokens table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS password_resets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            token TEXT NOT NULL,
            otp TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            used INTEGER DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    ''')
    
    conn.commit()
    conn.close()
    print("✅ Database initialized successfully")

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
        'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=JWT_EXPIRATION_HOURS),
        'iat': datetime.datetime.utcnow()
    }
    return jwt.encode(payload, app.config['SECRET_KEY'], algorithm='HS256')

def verify_jwt_token(token):
    """Verify JWT token and return payload"""
    try:
        payload = jwt.decode(token, app.config['SECRET_KEY'], algorithms=['HS256'])
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
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM users WHERE LOWER(email) = LOWER(?)', (email,))
    user = cursor.fetchone()
    conn.close()
    return dict(user) if user else None

def get_user_by_id(user_id):
    """Get user by ID"""
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM users WHERE id = ?', (user_id,))
    user = cursor.fetchone()
    conn.close()
    return dict(user) if user else None

def user_to_response(user):
    """Convert user dict to safe response (no password)"""
    if not user:
        return None
    return {
        'id': user['id'],
        'name': user['name'],
        'email': user['email'],
        'phone': user['phone'],
        'dob': user['dob'],
        'rating': user['rating'],
        'tasksPosted': user['tasks_posted'],
        'tasksCompleted': user['tasks_completed'],
        'totalEarnings': user['total_earnings'],
        'joinedAt': user['joined_at'],
        'lastLogin': user['last_login']
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
    joined_at = datetime.datetime.utcnow().isoformat()
    
    conn = get_db()
    cursor = conn.cursor()
    
    try:
        cursor.execute('''
            INSERT INTO users (id, name, email, password_hash, phone, dob, joined_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (user_id, name, email, password_hash, phone, dob, joined_at))
        conn.commit()
    except sqlite3.IntegrityError:
        conn.close()
        return jsonify({'success': False, 'message': 'Email already registered'}), 400
    
    conn.close()
    
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
    conn = get_db()
    cursor = conn.cursor()
    last_login = datetime.datetime.utcnow().isoformat()
    session_token = secrets.token_hex(32)
    cursor.execute('''
        UPDATE users SET last_login = ?, session_token = ? WHERE id = ?
    ''', (last_login, session_token, user['id']))
    conn.commit()
    conn.close()
    
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
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('UPDATE users SET session_token = NULL WHERE id = ?', (request.user_id,))
    conn.commit()
    conn.close()
    
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
    conn = get_db()
    cursor = conn.cursor()
    created_at = datetime.datetime.utcnow().isoformat()
    expires_at = (datetime.datetime.utcnow() + datetime.timedelta(minutes=10)).isoformat()
    
    cursor.execute('''
        INSERT INTO password_resets (user_id, token, otp, created_at, expires_at)
        VALUES (?, ?, ?, ?, ?)
    ''', (user['id'], reset_token, otp, created_at, expires_at))
    conn.commit()
    conn.close()
    
    # In production, send OTP via email
    # For development, we return it (remove in production!)
    print(f"🔐 OTP for {email}: {otp}")
    
    return jsonify({
        'success': True,
        'message': 'OTP sent to your email',
        'resetToken': reset_token,
        'maskedEmail': email[:3] + '***@' + email.split('@')[1],
        'userName': user['name'],
        # Remove 'otp' in production - only for testing!
        'otp': otp
    })

@app.route('/api/auth/verify-otp', methods=['POST'])
def verify_otp():
    """Verify OTP for password reset"""
    data = request.get_json()
    reset_token = data.get('resetToken', '')
    otp = data.get('otp', '')
    
    if not reset_token or not otp:
        return jsonify({'success': False, 'message': 'Reset token and OTP required'}), 400
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT * FROM password_resets 
        WHERE token = ? AND otp = ? AND used = 0 AND expires_at > ?
    ''', (reset_token, otp, datetime.datetime.utcnow().isoformat()))
    
    reset_record = cursor.fetchone()
    conn.close()
    
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
    
    conn = get_db()
    cursor = conn.cursor()
    
    # Get reset record
    cursor.execute('''
        SELECT * FROM password_resets 
        WHERE token = ? AND used = 0 AND expires_at > ?
    ''', (reset_token, datetime.datetime.utcnow().isoformat()))
    
    reset_record = cursor.fetchone()
    if not reset_record:
        conn.close()
        return jsonify({'success': False, 'message': 'Invalid or expired reset token'}), 400
    
    # Update password
    password_hash = generate_password_hash(new_password, method='pbkdf2:sha256')
    cursor.execute('UPDATE users SET password_hash = ? WHERE id = ?', 
                   (password_hash, reset_record['user_id']))
    
    # Mark token as used
    cursor.execute('UPDATE password_resets SET used = 1 WHERE token = ?', (reset_token,))
    
    conn.commit()
    conn.close()
    
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
    
    conn = get_db()
    cursor = conn.cursor()
    
    set_clause = ', '.join([f"{k} = ?" for k in updates.keys()])
    values = list(updates.values()) + [request.user_id]
    
    cursor.execute(f'UPDATE users SET {set_clause} WHERE id = ?', values)
    conn.commit()
    conn.close()
    
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
    conn = get_db()
    cursor = conn.cursor()
    password_hash = generate_password_hash(new_password, method='pbkdf2:sha256')
    cursor.execute('UPDATE users SET password_hash = ? WHERE id = ?', 
                   (password_hash, request.user_id))
    conn.commit()
    conn.close()
    
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
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT t.*, u.name as poster_name, u.rating as poster_rating, u.tasks_posted as poster_tasks
        FROM tasks t
        JOIN users u ON t.posted_by = u.id
        WHERE t.status = 'active'
        ORDER BY t.posted_at DESC
    ''')
    tasks = cursor.fetchall()
    conn.close()
    
    task_list = []
    for task in tasks:
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
            'price': task['price'],
            'postedBy': {
                'name': task['poster_name'],
                'rating': task['poster_rating'],
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
    
    conn = get_db()
    cursor = conn.cursor()
    
    posted_at = datetime.datetime.utcnow().isoformat()
    expires_at = (datetime.datetime.utcnow() + datetime.timedelta(hours=12)).isoformat()
    
    location = data.get('location', {})
    
    cursor.execute('''
        INSERT INTO tasks (title, description, category, location_lat, location_lng, 
                          location_address, price, posted_by, posted_at, expires_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')
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
    
    task_id = cursor.lastrowid
    
    # Update user's tasks_posted count
    cursor.execute('UPDATE users SET tasks_posted = tasks_posted + 1 WHERE id = ?', 
                   (request.user_id,))
    
    conn.commit()
    conn.close()
    
    return jsonify({
        'success': True,
        'message': 'Task created successfully',
        'taskId': task_id
    }), 201

@app.route('/api/tasks/<int:task_id>/accept', methods=['POST'])
@require_auth
def accept_task(task_id):
    """Accept a task"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Check if task exists and is active
    cursor.execute('SELECT * FROM tasks WHERE id = ? AND status = ?', (task_id, 'active'))
    task = cursor.fetchone()
    
    if not task:
        conn.close()
        return jsonify({'success': False, 'message': 'Task not found or already taken'}), 404
    
    # Can't accept own task
    if task['posted_by'] == request.user_id:
        conn.close()
        return jsonify({'success': False, 'message': 'Cannot accept your own task'}), 400
    
    # Accept task
    accepted_at = datetime.datetime.utcnow().isoformat()
    cursor.execute('''
        UPDATE tasks SET status = 'accepted', accepted_by = ?, accepted_at = ?
        WHERE id = ?
    ''', (request.user_id, accepted_at, task_id))
    
    conn.commit()
    conn.close()
    
    return jsonify({
        'success': True,
        'message': 'Task accepted successfully'
    })

@app.route('/api/tasks/<int:task_id>/complete', methods=['POST'])
@require_auth
def complete_task(task_id):
    """Mark task as completed"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Check if task exists and is accepted by current user
    cursor.execute('''
        SELECT * FROM tasks WHERE id = ? AND accepted_by = ? AND status = ?
    ''', (task_id, request.user_id, 'accepted'))
    task = cursor.fetchone()
    
    if not task:
        conn.close()
        return jsonify({'success': False, 'message': 'Task not found or not accepted by you'}), 404
    
    # Complete task
    completed_at = datetime.datetime.utcnow().isoformat()
    cursor.execute('''
        UPDATE tasks SET status = 'completed', completed_at = ?
        WHERE id = ?
    ''', (completed_at, task_id))
    
    # Update completer's stats
    cursor.execute('''
        UPDATE users SET tasks_completed = tasks_completed + 1, 
                        total_earnings = total_earnings + ?
        WHERE id = ?
    ''', (task['price'], request.user_id))
    
    conn.commit()
    conn.close()
    
    return jsonify({
        'success': True,
        'message': 'Task completed successfully'
    })

@app.route('/api/user/tasks', methods=['GET'])
@require_auth
def get_user_tasks():
    """Get current user's tasks"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Posted tasks
    cursor.execute('''
        SELECT * FROM tasks WHERE posted_by = ? ORDER BY posted_at DESC
    ''', (request.user_id,))
    posted = [dict(t) for t in cursor.fetchall()]
    
    # Accepted tasks
    cursor.execute('''
        SELECT * FROM tasks WHERE accepted_by = ? AND status = 'accepted' ORDER BY accepted_at DESC
    ''', (request.user_id,))
    accepted = [dict(t) for t in cursor.fetchall()]
    
    # Completed tasks
    cursor.execute('''
        SELECT * FROM tasks WHERE accepted_by = ? AND status = 'completed' ORDER BY completed_at DESC
    ''', (request.user_id,))
    completed = [dict(t) for t in cursor.fetchall()]
    
    conn.close()
    
    return jsonify({
        'success': True,
        'postedTasks': posted,
        'acceptedTasks': accepted,
        'completedTasks': completed
    })

# ========================================
# HEALTH CHECK
# ========================================

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'success': True,
        'status': 'healthy',
        'timestamp': datetime.datetime.now(datetime.UTC).isoformat()
    })

# ========================================
# RUN SERVER
# ========================================

if __name__ == '__main__':
    import sys
    
    # Initialize database
    init_db()
    
    # Check for development mode flag
    dev_mode = '--dev' in sys.argv or '-d' in sys.argv
    
    print("=" * 50)
    print("🚀 TaskEarn Backend Server")
    print("=" * 50)
    print(f"📍 Running on: http://localhost:5000")
    print(f"📚 API Docs: http://localhost:5000/api/health")
    
    if dev_mode:
        print("⚠️  Mode: DEVELOPMENT (Flask)")
        print("=" * 50)
        app.run(debug=True, port=5000)
    else:
        print("✅ Mode: PRODUCTION (Waitress WSGI)")
        print("=" * 50)
        from waitress import serve
        serve(app, host='0.0.0.0', port=5000, threads=4)
