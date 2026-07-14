"""
TaskEarn Backend Server - Production Ready
Flask + PostgreSQL + bcrypt + JWT + Razorpay
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
from urllib.parse import urlparse

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

# ── JSON provider: emit ISO-8601 for datetime objects ────────────────────────
# Flask 3.0's default provider serialises datetime as RFC-1123 HTTP-date
# (e.g. "Thu, 12 Jul 2026 10:30:00 GMT") which Dart's DateTime.tryParse
# cannot read, causing every task timestamp to fall back to DateTime.now().
# Overriding here ensures every jsonify() call returns proper ISO strings.
from flask.json.provider import DefaultJSONProvider as _DefaultJSONProvider

class _IsoDateJSONProvider(_DefaultJSONProvider):
    def default(self, o):
        if isinstance(o, (datetime.datetime, datetime.date)):
            return o.isoformat()
        return super().default(o)

app.json_provider_class = _IsoDateJSONProvider
app.json = _IsoDateJSONProvider(app)
# ────────────────────────────────────────────────────────────────────────────

# Rate limiter — protects auth endpoints from brute force
if _has_limiter:
    limiter = Limiter(
        get_remote_address,
        app=app,
        default_limits=[],
        storage_uri=os.environ.get('RATELIMIT_STORAGE_URL', 'memory://')
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
app.config['MAX_CONTENT_LENGTH'] = 20 * 1024 * 1024  # 20 MB — enough for two compressed KYC images

# ========================================
# ERROR HANDLERS — prevent raw tracebacks in production
# ========================================

@app.errorhandler(404)
def not_found(error):
    return jsonify({'success': False, 'message': 'Resource not found'}), 404

@app.errorhandler(405)
def method_not_allowed(error):
    return jsonify({'success': False, 'message': 'Method not allowed'}), 405

@app.errorhandler(500)
def server_error(error):
    return jsonify({'success': False, 'message': 'Internal server error'}), 500

@app.errorhandler(413)
def request_too_large(error):
    return jsonify({'success': False, 'message': 'Upload too large. Please use smaller images.'}), 413

# Add security + CORS headers to all responses
@app.after_request
def add_security_headers(response):
    """Add security and CORS headers to all responses"""
    origin = request.headers.get('Origin', '')
    allowed = [o.strip() for o in config.CORS_ORIGINS]
    if origin and origin in allowed:
        response.headers['Access-Control-Allow-Origin'] = origin
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
    response.headers['Content-Security-Policy'] = "default-src 'none'"
    
    # Cache headers for API responses
    if request.path.startswith('/api/'):
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
    
    return response

# Handle OPTIONS requests and CSRF origin validation
@app.before_request
def handle_preflight_and_csrf():
    """Handle preflight CORS requests and validate origin for state-changing requests"""
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

    # CSRF: Validate Origin/Referer for state-changing requests
    if request.method in ('POST', 'PUT', 'DELETE', 'PATCH'):
        # Exempt server-to-server callbacks (no browser Origin)
        csrf_exempt_paths = ('/api/payments/webhook',)
        if request.path in csrf_exempt_paths:
            return None

        allowed = [o.strip() for o in config.CORS_ORIGINS]
        if '*' in allowed:
            return None

        # Check Origin header first, fall back to Referer
        origin = request.headers.get('Origin', '')
        if not origin:
            referer = request.headers.get('Referer', '')
            if referer:
                parsed = urlparse(referer)
                origin = f"{parsed.scheme}://{parsed.netloc}"

        # Same-origin requests from non-browser clients may lack Origin
        # Only reject when Origin IS present but doesn't match
        if origin and origin not in allowed:
            return jsonify({'success': False, 'message': 'Request blocked'}), 403

# ========================================
# DATABASE INITIALIZATION
# ========================================
# Run init_db() in a background thread so the server starts accepting
# requests (and passes Railway's health checks) immediately, even if the
# database is slow to accept connections on cold start.
import threading as _threading

def _bg_init_db():
    try:
        print("🔄 Initializing database (background)...")
        init_db()
        print("✅ Database initialized successfully")
    except Exception as e:
        print(f"⚠️  Error initializing database: {e}")
        print("   Database may already be initialized or connection issue")

_threading.Thread(target=_bg_init_db, daemon=True, name="db-init").start()

def ensure_platform_account():
    """Create the platform system account (user_id='1') if it doesn't exist.
    This account holds company revenue (commission, platform_fee, penalty income).
    """
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f"SELECT id FROM users WHERE id = {PH}", ('1',))
            if not cursor.fetchone():
                now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                cursor.execute(f"""
                    INSERT INTO users (id, name, email, password_hash, joined_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
                """, ('1', 'Platform Account', 'platform@internal.taskern', 'PLATFORM_NO_AUTH', now))
                print("✅ Platform user account created (id='1')")
            cursor.execute(f"SELECT id FROM wallets WHERE user_id = {PH}", ('1',))
            if not cursor.fetchone():
                now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                cursor.execute(f"""
                    INSERT INTO wallets (user_id, balance, total_added, total_spent, total_earned, total_cashback, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                """, ('1', 0, 0, 0, 0, 0, now))
                print("✅ Platform wallet created (user_id='1')")
    except Exception as e:
        print(f"⚠️  Could not ensure platform account: {e}")

try:
    ensure_platform_account()
except Exception as e:
    print(f"⚠️  Platform account setup failed: {e}")

# Placeholder for SQL queries (%s for PostgreSQL)
PH = get_placeholder()

# ========================================
# VAPID / PUSH NOTIFICATION CONFIG
# ========================================

VAPID_PUBLIC_KEY  = os.environ.get('VAPID_PUBLIC_KEY', '')
VAPID_PRIVATE_KEY = os.environ.get('VAPID_PRIVATE_KEY', '')
VAPID_CLAIMS_EMAIL = os.environ.get('VAPID_CLAIMS_EMAIL', 'admin@workmate4u.com')


def send_push_to_user(user_id, title, body, url='/notifications.html'):
    """Send a web push notification to all subscriptions for a user.
    Silently skips if pywebpush is not installed or VAPID keys are missing."""
    if not _has_webpush or not VAPID_PRIVATE_KEY or not VAPID_PUBLIC_KEY:
        return
    try:
        with get_db() as (cursor, conn):
            cursor.execute(
                f'SELECT subscription_json FROM push_subscriptions WHERE user_id = {PH}',
                (str(user_id),)
            )
            rows = cursor.fetchall()
        stale_users = []
        for row in rows:
            sub_json = dict_from_row(row).get('subscription_json') if hasattr(row, 'keys') else row[0]
            try:
                sub = json.loads(sub_json)
                webpush(
                    subscription_info=sub,
                    data=json.dumps({'title': title, 'body': body, 'url': url}),
                    vapid_private_key=VAPID_PRIVATE_KEY,
                    vapid_claims={'sub': f'mailto:{VAPID_CLAIMS_EMAIL}'}
                )
            except WebPushException as exc:
                resp = exc.response
                if resp is not None and resp.status_code in (404, 410):
                    stale_users.append(str(user_id))
            except Exception:
                pass
        if stale_users:
            with get_db() as (cursor2, conn2):
                cursor2.execute(
                    f'DELETE FROM push_subscriptions WHERE user_id = {PH}',
                    (str(user_id),)
                )
    except Exception as e:
        print(f'[push] Error sending to user {user_id}: {e}')


# ========================================
# FCM (FIREBASE CLOUD MESSAGING) — Android/iOS push
# ========================================

_has_fcm = False
try:
    import firebase_admin
    from firebase_admin import credentials as fb_credentials
    from firebase_admin import messaging as fb_messaging

    _firebase_sa_json = os.environ.get('FIREBASE_SERVICE_ACCOUNT_JSON', '')
    if _firebase_sa_json:
        import json as _json_fcm
        _cred = fb_credentials.Certificate(_json_fcm.loads(_firebase_sa_json))
        if not firebase_admin._apps:
            firebase_admin.initialize_app(_cred)
        _has_fcm = True
        print('[FCM] Firebase Admin SDK initialized ✅')
    else:
        print('[FCM] FIREBASE_SERVICE_ACCOUNT_JSON not set — FCM push disabled')
except ImportError:
    print('[FCM] firebase-admin not installed — FCM push disabled')
except Exception as _fcm_init_err:
    print(f'[FCM] Init error: {_fcm_init_err}')

_fcm_columns_ensured = False
_bio_skills_columns_ensured = False
_user_location_columns_ensured = False
_google_auth_schema_ensured = False
_gender_column_ensured = False

def _ensure_user_location_columns():
    """Add last_lat / last_lng columns to users table (one-time per process)."""
    global _user_location_columns_ensured
    if _user_location_columns_ensured:
        return
    try:
        with get_db() as (cursor, conn):
            if PH == '%s':  # PostgreSQL
                cursor.execute('ALTER TABLE users ADD COLUMN IF NOT EXISTS last_lat FLOAT')
                cursor.execute('ALTER TABLE users ADD COLUMN IF NOT EXISTS last_lng FLOAT')
            else:           # SQLite
                cursor.execute('PRAGMA table_info(users)')
                cols = [row[1] for row in cursor.fetchall()]
                if 'last_lat' not in cols:
                    cursor.execute('ALTER TABLE users ADD COLUMN last_lat FLOAT')
                if 'last_lng' not in cols:
                    cursor.execute('ALTER TABLE users ADD COLUMN last_lng FLOAT')
            conn.commit()
        _user_location_columns_ensured = True
    except Exception as e:
        print(f'\u26a0\ufe0f _ensure_user_location_columns error: {e}')

def _ensure_gender_column():
    """Add gender column to users table if it does not exist (one-time per process)."""
    global _gender_column_ensured
    if _gender_column_ensured:
        return
    try:
        with get_db() as (cursor, conn):
            if PH == '%s':
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS gender VARCHAR(10)")
            else:
                cursor.execute("PRAGMA table_info(users)")
                cols = [row[1] for row in cursor.fetchall()]
                if 'gender' not in cols:
                    cursor.execute("ALTER TABLE users ADD COLUMN gender VARCHAR(10)")
            conn.commit()
        _gender_column_ensured = True
    except Exception as e:
        print(f'⚠️ _ensure_gender_column error: {e}')

def _ensure_bio_skills_columns():
    """Add bio and skills columns to users table if they do not exist (one-time per process)."""
    global _bio_skills_columns_ensured
    if _bio_skills_columns_ensured:
        return
    try:
        with get_db() as (cursor, conn):
            if PH == '%s':
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS skills TEXT")
            else:
                cursor.execute("PRAGMA table_info(users)")
                cols = [row[1] for row in cursor.fetchall()]
                if 'bio' not in cols:
                    cursor.execute("ALTER TABLE users ADD COLUMN bio TEXT")
                if 'skills' not in cols:
                    cursor.execute("ALTER TABLE users ADD COLUMN skills TEXT")
            conn.commit()
        _bio_skills_columns_ensured = True
    except Exception as e:
        print(f'⚠️ _ensure_bio_skills_columns error: {e}')

def _ensure_fcm_token_column():
    """Add fcm_token column to users table if it does not exist (one-time per process)."""
    global _fcm_columns_ensured
    if _fcm_columns_ensured:
        return
    try:
        with get_db() as (cursor, conn):
            if PH == '%s':
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT")
            else:
                cursor.execute("PRAGMA table_info(users)")
                cols = [row[1] for row in cursor.fetchall()]
                if 'fcm_token' not in cols:
                    cursor.execute("ALTER TABLE users ADD COLUMN fcm_token TEXT")
            conn.commit()
        _fcm_columns_ensured = True
    except Exception as e:
        print(f'⚠️ _ensure_fcm_token_column error: {e}')


def send_fcm_to_user(user_id, title, body, data=None, channel='workmate4u_main'):
    """Send an FCM push notification to the user's registered device.
    Falls back silently if firebase-admin is not configured.

    channel values:
      workmate4u_main    — general task updates (high importance)
      workmate4u_matched — nearby task matches  (max importance)
      workmate4u_payment — payment events       (max importance)
    """
    if not _has_fcm:
        return
    _ensure_fcm_token_column()
    try:
        with get_db() as (cursor, _):
            cursor.execute(f'SELECT fcm_token FROM users WHERE id = {PH}', (str(user_id),))
            row = cursor.fetchone()
        if not row:
            print(f'[FCM] ⚠️ No user row for user_id={user_id} — skipping push')
            return
        token = dict_from_row(row).get('fcm_token') if hasattr(row, 'keys') else row[0]
        if not token:
            print(f'[FCM] ⚠️ No FCM token registered for user_id={user_id} — skipping push')
            return

        # All data values must be strings for FCM data messages
        payload = {'type': data.get('type', 'general') if data else 'general',
                   'title': title, 'body': body}
        if data:
            for k, v in data.items():
                payload[str(k)] = str(v)

        # Data-only message — no 'notification' key so the FCM SDK always
        # routes it to the Flutter background handler (_bgMessageHandler) even
        # when the app is killed.  The handler itself creates the local
        # notification on the correct channel with the right importance.
        message = fb_messaging.Message(
            data=payload,
            android=fb_messaging.AndroidConfig(
                priority='high',   # FCM delivery priority — wakes up device
            ),
            apns=fb_messaging.APNSConfig(
                headers={'apns-priority': '10'},
                payload=fb_messaging.APNSPayload(
                    aps=fb_messaging.Aps(content_available=True),
                ),
            ),
            token=token,
        )
        fb_messaging.send(message)
        print(f'[FCM] ✉ "{title}" → user {user_id}')
    except Exception as e:
        print(f'[FCM] Error sending to user {user_id}: {e}')


def _safe_delete_tasks(cursor, task_ids):
    """Remove all FK-referenced rows for the given task ID(s) so the caller can
    then safely DELETE FROM tasks.

    Preserves history notifications (task_posted, task_expired,
    task_cancelled_confirmation) by NULLing their task_id rather than
    deleting them — the poster keeps a record even after the task is gone.
    wallet_transactions are also NULLed (audit trail).

    Every statement runs inside its own SAVEPOINT so a single table being
    absent (e.g. in a dev environment) never aborts the whole transaction.
    """
    if not task_ids:
        return
    if isinstance(task_ids, (int, str)):
        task_ids = [task_ids]
    ids = [str(t) for t in task_ids if t is not None]
    if not ids:
        return

    # IDs come from DB queries (not user input) — safe to interpolate.
    in_clause = f"({','.join(ids)})"
    history_types = "('task_posted','task_expired','task_cancelled_confirmation')"

    steps = [
        # Preserve history notifications — NULL the FK ref instead of deleting
        f'UPDATE notifications SET task_id = NULL WHERE task_id IN {in_clause} AND notification_type IN {history_types}',
        # Delete all remaining task-linked notifications (no FK refs left)
        f'DELETE FROM notifications WHERE task_id IN {in_clause}',
        # Preserve wallet transaction audit trail — NULL the FK ref
        f'UPDATE wallet_transactions SET task_id = NULL WHERE task_id IN {in_clause}',
        # Delete all other FK-referencing rows
        f'DELETE FROM task_releases WHERE task_id IN {in_clause}',
        f'DELETE FROM reviews WHERE task_id IN {in_clause}',
        f'DELETE FROM helper_ratings WHERE task_id IN {in_clause}',
        f'DELETE FROM task_proofs WHERE task_id IN {in_clause}',
        f'DELETE FROM chat_messages WHERE task_id IN {in_clause}',
        f'DELETE FROM location_tracking WHERE task_id IN {in_clause}',
        f'DELETE FROM sos_alerts WHERE task_id IN {in_clause}',
        f'DELETE FROM payments WHERE task_id IN {in_clause}',
    ]
    for i, sql in enumerate(steps):
        sp = f'sp_del_{i}'
        try:
            cursor.execute(f'SAVEPOINT {sp}')
            cursor.execute(sql)
            cursor.execute(f'RELEASE SAVEPOINT {sp}')
        except Exception:
            try:
                cursor.execute(f'ROLLBACK TO SAVEPOINT {sp}')
            except Exception:
                pass


# ========================================
# HELPER FUNCTIONS
# ========================================

_suspension_columns_ensured = False
_last_cleanup_time = None  # throttle cleanup_old_tasks to at most once per 5 min
_last_user_tasks_cleanup = None  # throttle 48h cleanup in /api/user/tasks

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
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT FALSE")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS banned_reason VARCHAR(255)")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS banned_at TIMESTAMP")
            else:
                # SQLite
                cursor.execute("PRAGMA table_info(users)")
                cols = [row[1] for row in cursor.fetchall()]
                for col, typ in [('is_suspended', 'BOOLEAN DEFAULT 0'), ('suspension_reason', 'TEXT'),
                                 ('suspended_at', 'TEXT'), ('suspended_until', 'TEXT'),
                                 ('daily_releases', 'INTEGER DEFAULT 0'), ('daily_release_date', 'TEXT'),
                                 ('is_banned', 'BOOLEAN DEFAULT 0'), ('banned_reason', 'TEXT'),
                                 ('banned_at', 'TEXT')]:
                    if col not in cols:
                        cursor.execute(f'ALTER TABLE users ADD COLUMN {col} {typ}')
        _suspension_columns_ensured = True
        print("✅ Suspension columns verified")
    except Exception as e:
        print(f"⚠️ _ensure_suspension_columns error: {e}")

_kyc_columns_ensured = False

_verify_columns_ensured = False

def _ensure_verify_columns():
    """Ensure verified_at, payment_released_at, helper_final_completed_at, is_hidden columns exist in tasks table"""
    global _verify_columns_ensured
    if _verify_columns_ensured:
        return
    try:
        with get_db() as (cursor, conn):
            if PH == '%s':
                # PostgreSQL — DDL needs explicit commit
                cursor.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP")
                cursor.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS payment_released_at TIMESTAMP")
                cursor.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS helper_final_completed_at TIMESTAMP")
                cursor.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN DEFAULT FALSE")
                conn.commit()
            else:
                # SQLite
                cursor.execute("PRAGMA table_info(tasks)")
                cols = [row[1] for row in cursor.fetchall()]
                for col, typ in [('verified_at', 'TEXT'), ('payment_released_at', 'TEXT'),
                                  ('helper_final_completed_at', 'TEXT'), ('is_hidden', 'INTEGER')]:
                    if col not in cols:
                        cursor.execute(f'ALTER TABLE tasks ADD COLUMN {col} {typ}')
                conn.commit()
        _verify_columns_ensured = True
        print("✅ Verify flow columns verified")
    except Exception as e:
        print(f"⚠️ _ensure_verify_columns error: {e}")


def _ensure_helper_ratings_review():
    """Ensure all optional columns exist in helper_ratings table"""
    EXTRA_COLS = [
        ('review',        'TEXT'),
        ('task_title',    'TEXT'),
        ('punctuality',   'INTEGER'),
        ('communication', 'INTEGER'),
        ('quality',       'INTEGER'),
    ]
    try:
        with get_db() as (cursor, conn):
            if PH == '%s':
                # PostgreSQL: ADD COLUMN IF NOT EXISTS is safe to run repeatedly
                for col, typ in EXTRA_COLS:
                    cursor.execute(f"ALTER TABLE helper_ratings ADD COLUMN IF NOT EXISTS {col} {typ}")
            else:
                # SQLite: check column list first
                cursor.execute("PRAGMA table_info(helper_ratings)")
                existing = {row[1] for row in cursor.fetchall()}
                for col, typ in EXTRA_COLS:
                    if col not in existing:
                        cursor.execute(f"ALTER TABLE helper_ratings ADD COLUMN {col} {typ}")
    except Exception as e:
        print(f"⚠️ _ensure_helper_ratings_review: {e}")


def _ensure_kyc_columns():
    """Ensure kyc_document_image_back column exists in users table (one-time per process)"""
    global _kyc_columns_ensured
    if _kyc_columns_ensured:
        return
    try:
        with get_db() as (cursor, conn):
            if PH == '%s':
                # PostgreSQL
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_document_image_back TEXT")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_document_image_hash TEXT")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_flag_reason TEXT")
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_acknowledged_at TIMESTAMP")
            else:
                # SQLite
                cursor.execute("PRAGMA table_info(users)")
                cols = [row[1] for row in cursor.fetchall()]
                if 'kyc_document_image_back' not in cols:
                    cursor.execute("ALTER TABLE users ADD COLUMN kyc_document_image_back TEXT")
                if 'kyc_document_image_hash' not in cols:
                    cursor.execute("ALTER TABLE users ADD COLUMN kyc_document_image_hash TEXT")
                if 'kyc_flag_reason' not in cols:
                    cursor.execute("ALTER TABLE users ADD COLUMN kyc_flag_reason TEXT")
                if 'kyc_acknowledged_at' not in cols:
                    cursor.execute("ALTER TABLE users ADD COLUMN kyc_acknowledged_at TIMESTAMP")
        _kyc_columns_ensured = True
        print("✅ KYC columns verified")
    except Exception as e:
        print(f"⚠️ _ensure_kyc_columns error: {e}")


# ==========================================================
# KYC validation helpers (anti-fraud)
# ==========================================================

# Verhoeff algorithm tables for Aadhaar checksum (UIDAI standard)
_VERHOEFF_D = [
    [0,1,2,3,4,5,6,7,8,9],
    [1,2,3,4,0,6,7,8,9,5],
    [2,3,4,0,1,7,8,9,5,6],
    [3,4,0,1,2,8,9,5,6,7],
    [4,0,1,2,3,9,5,6,7,8],
    [5,9,8,7,6,0,4,3,2,1],
    [6,5,9,8,7,1,0,4,3,2],
    [7,6,5,9,8,2,1,0,4,3],
    [8,7,6,5,9,3,2,1,0,4],
    [9,8,7,6,5,4,3,2,1,0],
]
_VERHOEFF_P = [
    [0,1,2,3,4,5,6,7,8,9],
    [1,5,7,6,2,8,3,0,9,4],
    [5,8,0,3,7,9,6,1,4,2],
    [8,9,1,6,0,4,3,5,2,7],
    [9,4,5,3,1,2,6,8,7,0],
    [4,2,8,6,5,7,3,9,0,1],
    [2,7,9,3,8,0,6,4,1,5],
    [7,0,4,6,9,1,3,2,5,8],
]

def _aadhaar_verhoeff_valid(num_str):
    """Verify a 12-digit Aadhaar number against the Verhoeff checksum used by UIDAI."""
    try:
        if not num_str or len(num_str) != 12 or not num_str.isdigit():
            return False
        c = 0
        for i, ch in enumerate(reversed(num_str)):
            c = _VERHOEFF_D[c][_VERHOEFF_P[i % 8][int(ch)]]
        return c == 0
    except Exception:
        return False


def _kyc_image_quality_check(b64_image):
    """Best-effort image quality check. Returns (ok, reason).
    ok=True means image looks usable. ok=False means flag for admin review (NOT reject).
    Uses PIL if available; if PIL is missing, accepts the image silently.
    """
    try:
        import base64, io
        # Strip data URL prefix
        s = b64_image or ''
        if ',' in s and s.startswith('data:'):
            s = s.split(',', 1)[1]
        try:
            raw = base64.b64decode(s, validate=False)
        except Exception:
            return False, 'Image could not be decoded'
        if len(raw) < 5_000:
            return False, 'Image is too small / low-quality (likely a screenshot)'
        try:
            from PIL import Image  # type: ignore
            img = Image.open(io.BytesIO(raw))
            w, h = img.size
            if w < 400 or h < 250:
                return False, f'Image resolution too low ({w}x{h}); likely a screen photo'
            return True, ''
        except Exception:
            # Pillow not installed — skip dimension check, still accept
            return True, ''
    except Exception:
        return True, ''


def _hash_kyc_image(b64_image):
    """Return SHA-256 hex of the decoded image bytes (used to detect the same Aadhaar/PAN scan re-uploaded by another user)."""
    try:
        import base64, hashlib
        s = b64_image or ''
        if ',' in s and s.startswith('data:'):
            s = s.split(',', 1)[1]
        raw = base64.b64decode(s, validate=False)
        if len(raw) < 1000:
            return None
        return hashlib.sha256(raw).hexdigest()
    except Exception:
        return None


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


def screen_task_content(title, description, category):
    """Screen task content for spam/fraud/abuse patterns.
    Returns (allowed: bool, reason: str). When allowed is False, the task must be rejected.
    Patterns target: bulk account creation, OTP/SMS-for-hire, click farms, money mule,
    selling personal documents/KYC, crypto pump scams, fake reviews, and explicitly illegal work.
    """
    import re as _re
    text = ' '.join([str(title or ''), str(description or '')]).lower()
    if not text.strip():
        return True, ''

    # Each entry: (compiled_regex, reason). Order matters — first hit wins.
    patterns = [
        # Bulk email / account creation (the example case)
        (r'\b(create|make|open|register|sign[- ]?up|generate|bulk)\b[^.]{0,40}\b(email|emails|gmail|yahoo|outlook|hotmail|account|accounts|id|ids|profile|profiles)\b',
         'Bulk account or email creation tasks are not allowed (anti-spam policy).'),
        (r'\b(per|each|/)\s*(email|account|id|signup|sign[- ]?up|profile)\b',
         'Tasks paying per account/email creation are not allowed.'),

        # Selling / buying accounts or credentials
        (r'\b(sell|buy|rent|hire)\b[^.]{0,30}\b(account|accounts|gmail|whatsapp|instagram|facebook|telegram|otp|sim|number)\b',
         'Buying or selling accounts/credentials is prohibited.'),

        # OTP / SMS verification work
        (r'\b(receive|share|forward|read|provide|give|sell)\b[^.]{0,30}\b(otp|otps|one[- ]time[- ]password|verification\s*code|sms\s*code)\b',
         'OTP/verification-code sharing tasks are prohibited.'),
        (r'\botp\s*(work|task|job|earn)\b', 'OTP-based earning tasks are prohibited.'),

        # KYC / Aadhaar / PAN abuse
        (r'\b(use|share|rent|sell)\b[^.]{0,30}\b(aadhaar|aadhar|pan\s*card|kyc|bank\s*account|upi\s*id)\b',
         'Sharing or renting personal KYC documents is prohibited.'),

        # Click farm / fake engagement
        (r'\b(fake|paid|bulk)\b[^.]{0,20}\b(reviews?|ratings?|likes?|followers?|subscribers?|comments?|votes?)\b',
         'Fake review / engagement / follower tasks are prohibited.'),
        (r'\b(click|watch)\s*(ads|advertisements|videos)\s*(bot|farm|loop)\b',
         'Click-fraud tasks are prohibited.'),

        # Crypto / investment / money mule
        (r'\b(usdt|btc|bitcoin|crypto|forex)\b[^.]{0,30}\b(investment|trade|trading|deposit|recharge|profit|earn)\b',
         'Crypto/forex investment tasks are not permitted on Workmate4u.'),
        (r'\b(money\s*mule|transfer\s*money|launder|cash[- ]out)\b',
         'Money transfer / mule activity is strictly prohibited.'),

        # Hacking / illegal access
        (r'\b(hack|crack|bypass|unlock)\b[^.]{0,30}\b(password|account|server|whatsapp|instagram|facebook|gmail|wifi|otp)\b',
         'Hacking or unauthorized access tasks are prohibited.'),

        # Adult / illicit
        (r'\b(escort|webcam\s*model|adult\s*content|nude|sex\s*chat|drugs?|weed|cocaine|heroin)\b',
         'Adult/illicit-content tasks are not allowed.'),

        # Generic spam keywords
        (r'\b(captcha\s*solving|typing\s*captcha)\b', 'Captcha-solving/spam tasks are not allowed.'),
        (r'\b(spam|spamming)\b[^.]{0,20}\b(email|sms|whatsapp|message)\b',
         'Spam/bulk messaging tasks are not allowed.'),
    ]

    for rx, reason in patterns:
        try:
            if _re.search(rx, text, _re.IGNORECASE):
                return False, reason
        except _re.error:
            continue

    # Heuristic: very low pay-per-unit phrasing ("₹10 per ...") is a strong fraud signal
    if _re.search(r'(₹|rs\.?|inr)\s*\d{1,3}\s*(per|each|/)\s*(email|account|signup|sign[- ]?up|otp|click|like|follower|review)', text):
        return False, 'Per-unit micro-payments for accounts/OTPs/clicks/reviews are not allowed.'

    # Additional hard-block scam categories
    extra_blocks = [
        # Advance-fee / fake-job scams
        (r'\b(registration|joining|training|security|refundable)\s*(fee|deposit|amount|charge)\b',
         'Charging registration/security/joining fees from helpers is prohibited.'),
        (r'\b(pay|deposit|send|transfer)\b[^.]{0,30}\b(first|upfront|in\s*advance|before\s*start)\b',
         'Tasks requiring upfront payment from the helper are not allowed.'),

        # Money / value transfer scams
        (r'\b(gift\s*card|itunes\s*card|amazon\s*voucher|paytm\s*voucher|google\s*play\s*card)\b',
         'Gift-card / voucher purchase tasks are not allowed (common scam vector).'),
        (r'\b(western\s*union|moneygram|wire\s*transfer)\b',
         'Wire-transfer / money-remittance tasks are not allowed.'),
        (r'\b(double|2x|triple)\s*your\s*(money|investment|amount)\b',
         'Investment doubling / get-rich-quick tasks are prohibited.'),
        (r'\b(guaranteed)\s*(returns?|profit|income|earning)\b',
         'Guaranteed-return investment tasks are prohibited.'),
        (r'\b(mlm|multi[- ]level|pyramid|ponzi|chain\s*scheme|matrix\s*scheme)\b',
         'MLM / pyramid / chain schemes are prohibited.'),
        (r'\b(recharge|deposit)\b[^.]{0,20}\b(usdt|btc|trx|binance|crypto)\b',
         'Crypto recharge / deposit tasks are prohibited.'),

        # Account / OTP / KYC theft (additional patterns)
        (r'\bshare\s*(your\s*)?(otp|cvv|pin|password|net[- ]?banking|atm\s*pin)\b',
         'Sharing of OTP/PIN/CVV/banking credentials is strictly prohibited.'),
        (r'\b(give|tell|send)\s*(me\s*)?(your\s*)?(aadhaar|pan|bank|otp|cvv|pin)\b[^.]{0,20}(number|details|copy|photo)?',
         'Asking helpers for Aadhaar/PAN/bank/OTP details is prohibited.'),

        # Fake documents / fraudulent services
        (r'\b(fake|duplicate|forged?)\s*(aadhaar|pan|certificate|degree|marksheet|id|licence|license|passport)\b',
         'Fake/forged document tasks are illegal and prohibited.'),
        (r'\b(buy|sell)\s*(fake|stolen)\b',
         'Sale of fake/stolen goods is prohibited.'),

        # Misleading "earn from home" / no-work scams
        (r'\bearn\s*(₹|rs\.?|inr)?\s*\d{3,}\s*(per\s*)?(day|hour|hr)\b[^.]{0,40}\b(home|mobile|copy[- ]paste|just\s*refer|no\s*work)\b',
         'Misleading earn-from-home / no-work tasks are not allowed.'),
        (r'\b(get\s*rich\s*quick|easy\s*money|no\s*work\s*required)\b',
         'Misleading earnings claims are not allowed.'),

        # Platform-bypass / cash-only outside the app
        (r'\b(pay|paid|payment)\b[^.]{0,15}\b(outside|off)\b[^.]{0,15}\b(app|platform|workmate)\b',
         'Tasks asking to pay outside the platform are not allowed.'),
        (r'\b(skip|bypass|avoid)\b[^.]{0,15}\b(commission|platform|service\s*charge)\b',
         'Bypassing platform commission is not allowed.'),
        (r'\bcash\s*only\b[^.]{0,30}\b(outside|hand|direct)\b',
         'Cash-only / off-platform payment tasks are not allowed.'),

        # Weapons / drugs / illegal services (extra)
        (r'\b(gun|pistol|firearm|ammunition|knife\s*for\s*sale|country\s*made)\b',
         'Weapons-related tasks are prohibited.'),
        (r'\b(mdma|lsd|ganja|hashish|opium|brown\s*sugar)\b',
         'Drug-related tasks are prohibited.'),
    ]
    for rx, reason in extra_blocks:
        try:
            if _re.search(rx, text, _re.IGNORECASE):
                return False, reason
        except _re.error:
            continue

    # Phone / email in title or description → forces in-app contact (anti-bypass)
    if _re.search(r'(?:\+?91[\s\-]?)?[6-9]\d{9}', text):
        return False, 'Sharing phone numbers in the task is not allowed. Helpers can contact you through in-app chat.'
    if _re.search(r'[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}', text):
        return False, 'Sharing email addresses in the task is not allowed. Use in-app chat instead.'
    # Whatsapp/telegram links
    if _re.search(r'\b(?:wa\.me|t\.me|telegram\.me|chat\.whatsapp\.com)\b', text):
        return False, 'External chat links (WhatsApp/Telegram) are not allowed in tasks.'

    return True, ''


def flag_task_content(title, description):
    """Soft-flag suspicious-but-ambiguous tasks for admin review.
    Returns (flagged: bool, reason: str). Task is still posted; admin sees it in fraud alerts.
    """
    import re as _re
    text = ' '.join([str(title or ''), str(description or '')]).lower()
    if not text.strip():
        return False, ''

    soft_patterns = [
        (r'\b(deposit|advance|token\s*amount)\b', 'Mentions deposit/advance — review for advance-fee scam.'),
        (r'\b(refer|referral)\b[^.]{0,20}\b(earn|bonus|reward)\b', 'Referral-earning language — possible MLM.'),
        (r'\b(work\s*from\s*home|wfh)\b[^.]{0,30}\b(earn|income|salary|₹|rs)\b', 'Generic WFH earnings claim — review.'),
        (r'\b(easy|simple)\s*(work|task|job)\b[^.]{0,20}\b(high|good)\s*(pay|earnings?)\b', 'Vague high-pay easy-work claim.'),
        (r'\b(urgent|immediate)\s*(payment|cash|money)\b', 'Urgent-payment language — review for pressure tactics.'),
        (r'\b(survey|surveys)\b[^.]{0,20}\b(earn|pay|reward)\b', 'Paid-survey task — verify legitimacy.'),
        (r'\b(data\s*entry)\b[^.]{0,30}\b(₹|rs\.?|inr)?\s*\d{3,}', 'High-pay data-entry — common scam template.'),
    ]
    for rx, reason in soft_patterns:
        try:
            if _re.search(rx, text, _re.IGNORECASE):
                return True, reason
        except _re.error:
            continue
    return False, ''


def get_service_charge(category):
    """Return service charge for the given category.
    Service charge ONLY applies to Delivery/Pick&Drop categories (delivery, pickup, transport, moving).
    All other categories return 0.
    Commission rates: Delivery/Pickup/Transport/Moving = 15%, all others = 17%."""
    # Only Delivery/Pick&Drop categories carry a service charge
    DELIVERY_CATEGORIES = {'delivery', 'pickup', 'transport', 'moving'}
    if category not in DELIVERY_CATEGORIES:
        return 0
    # Flat fallback on backend (frontend uses distance-aware calculation)
    delivery_charges = {
        'delivery': 15,
        'pickup':   15,
        'transport': 15,
        'moving':   40,
    }
    return delivery_charges.get(category, 15)


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
    _ensure_bio_skills_columns()
    _ensure_gender_column()
    import json as _json_u
    _skills_raw = user.get('skills')
    if isinstance(_skills_raw, list):
        _skills = _skills_raw
    elif isinstance(_skills_raw, str) and _skills_raw.strip():
        try:
            _skills = _json_u.loads(_skills_raw)
        except Exception:
            _skills = []
    else:
        _skills = []
    
    # Get wallet balance
    wallet = get_or_create_wallet(user['id'])
    wallet_balance = float(wallet.get('balance', 0))
    wallet_low = wallet_balance < 100
    debt_suspended = wallet_balance < 0
    
    # Check admin suspension (is_suspended=True without suspended_until)
    is_suspended = bool(user.get('is_suspended', False))
    admin_suspended = False
    suspension_reason = user.get('suspension_reason', '')
    is_banned = bool(user.get('is_banned', False))
    
    if is_suspended and not user.get('suspended_until'):
        admin_suspended = True  # Permanent admin suspension
    
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
                        cursor.execute(f'UPDATE users SET suspended_until = NULL, is_suspended = FALSE, suspension_reason = NULL WHERE id = {PH}', (user['id'],))
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
        'avatar': user.get('profile_photo'),
        'bio': user.get('bio'),
        'skills': _skills,
        'rating': float(user.get('rating') or 0),
        'ratingCount': 0,
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
        'adminSuspended': admin_suspended,
        'suspensionReason': suspension_reason or None,
        'isBanned': is_banned,
        'dailyReleaseCount': daily_release_count,
        'emailVerified': bool(user.get('email_verified', False)),
        'authProvider': user.get('auth_provider', 'email'),
        'kycStatus': user.get('kyc_status', 'none'),
        'kycDocumentType': user.get('kyc_document_type'),
        'phoneVerified': bool(user.get('phone_verified', False)),
        'gender': user.get('gender')
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
        
        token = auth_header.replace('Bearer ', '')
        if not token:
            return jsonify({'success': False, 'message': 'Authentication required'}), 401
        
        payload = verify_jwt_token(token)
        if not payload:
            return jsonify({'success': False, 'message': 'Invalid or expired token'}), 401
        
        # Verify session is still active (not logged out)
        user_id = payload['user_id']
        try:
            with get_db() as (cursor, conn):
                cursor.execute(f'SELECT session_token FROM users WHERE id = {PH}', (user_id,))
                row = cursor.fetchone()
                if row and row[0] is None:
                    return jsonify({'success': False, 'message': 'Session expired. Please login again.'}), 401
        except Exception:
            pass  # If DB check fails, allow request (don't lock out users on DB hiccup)
        
        request.user_id = user_id
        request.user_email = payload['email']
        return f(*args, **kwargs)
    return decorated


def require_admin(f):
    """Decorator to require admin privileges (is_admin=True in DB)"""
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        # First ensure the user is authenticated
        auth_header = request.headers.get('Authorization', '')
        token = auth_header.replace('Bearer ', '')
        if not token:
            return jsonify({'success': False, 'message': 'Authentication required'}), 401
        payload = verify_jwt_token(token)
        if not payload:
            return jsonify({'success': False, 'message': 'Invalid or expired token'}), 401
        user_id = payload['user_id']
        request.user_id = user_id
        request.user_email = payload['email']
        # Mark this request as admin context so get_db() uses ADMIN_DATABASE_URL
        from flask import g
        g.use_admin_db = True
        # Check is_admin flag
        try:
            with get_db() as (cursor, conn):
                cursor.execute(f'SELECT is_admin FROM users WHERE id = {PH}', (user_id,))
                row = cursor.fetchone()
                if not row or not dict_from_row(row).get('is_admin'):
                    return jsonify({'success': False, 'message': 'Admin access required'}), 403
        except Exception:
            return jsonify({'success': False, 'message': 'Admin access required'}), 403
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
    if not data:
        return jsonify({'success': False, 'message': 'Request body required'}), 400

    try:
        # ---- TRIAL MODE CHECKS ----
        if config.TRIAL_ACTIVE:
            import datetime as _dt
            # Check invite code
            invite_code = (data.get('invite_code') or '').strip().upper()
            if invite_code != config.TRIAL_INVITE_CODE.upper():
                return jsonify({'success': False, 'message': 'Invalid invite code. This is a closed beta — you need an invite code to join.'}), 403
            # Check trial end date
            try:
                end_date = _dt.date.fromisoformat(config.TRIAL_END_DATE)
            except ValueError:
                end_date = _dt.date.today() + _dt.timedelta(days=30)
            if _dt.date.today() > end_date:
                return jsonify({'success': False, 'message': 'The trial period has ended. Stay tuned for the public launch!'}), 403
            # Check user cap
            try:
                with get_db() as (cursor, conn):
                    cursor.execute('SELECT COUNT(*) as cnt FROM users')
                    row = dict_from_row(cursor.fetchone())
                    if (row['cnt'] or 0) >= config.TRIAL_MAX_USERS:
                        return jsonify({'success': False, 'message': 'All 100 trial spots are taken. We\'ll notify you when we launch publicly!'}), 403
            except Exception as _cnt_e:
                _cnt_err = str(_cnt_e).lower()
                if any(k in _cnt_err for k in ['connect', 'relation', 'does not exist']):
                    return jsonify({'success': False, 'message': 'Service is starting up. Please try again in a few seconds.'}), 503
                raise

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

        # Auto-send email verification OTP
        otp = ''.join([str(secrets.randbelow(10)) for _ in range(6)])
        otp_expires = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)).isoformat()

        with get_db() as (cursor, conn):
            cursor.execute(f'''
                INSERT INTO password_resets (user_id, token, otp, created_at, expires_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 'email_verify_' + secrets.token_hex(16), otp,
                  datetime.datetime.now(datetime.timezone.utc).isoformat(), otp_expires))
    
        if config.SENDGRID_API_KEY:
            try:
                from sendgrid import SendGridAPIClient
                from sendgrid.helpers.mail import Mail
                message = Mail(
                    from_email=config.FROM_EMAIL,
                    to_emails=email,
                    subject=f'{config.APP_NAME} - Verify Your Email',
                    html_content=f'''
                        <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;padding:24px;">
                            <h2 style="color:#6366f1;">Welcome to Workmate4u!</h2>
                            <p>Hi {name},</p>
                            <p>Your email verification code is:</p>
                            <h1 style="color:#6366f1;font-size:36px;letter-spacing:6px;text-align:center;
                                background:#f0f0ff;padding:16px;border-radius:10px;">{otp}</h1>
                            <p>This code expires in <strong>10 minutes</strong>.</p>
                            <p style="color:#888;font-size:13px;">If you didn't create this account, please ignore this email.</p>
                        </div>
                    '''
                )
                sg = SendGridAPIClient(config.SENDGRID_API_KEY)
                sg.send(message)
            except Exception as e:
                print(f"⚠️ SendGrid email error: {e}")
        else:
            print(f"⚠️ SendGrid not configured — OTP email not sent for {email}")

        response = {
            'success': True,
            'message': 'Registration successful. Please verify your email.',
            'token': token,
            'user': user_to_response(user),
            'requiresVerification': True
        }
        return jsonify(response), 201

    except Exception as e:
        print(f'[REGISTER] Error: {e}')
        import traceback; traceback.print_exc()
        err = str(e).lower()
        if any(k in err for k in [
            'could not connect', 'connection', 'timeout', 'server closed',
            'operationalerror', 'database', 'relation', 'does not exist',
        ]):
            return jsonify({'success': False, 'message': 'Service is starting up. Please try again in a few seconds.'}), 503
        return jsonify({'success': False, 'message': 'Registration failed. Please try again.'}), 500


# -----------------------------------------------------------------------
# TRIAL STATUS ENDPOINT — public, no auth needed
# Returns whether trial is active, slots remaining, and end date.
# -----------------------------------------------------------------------
@app.route('/api/trial/status', methods=['GET'])
def trial_status():
    """Return current trial status (public endpoint)"""
    import datetime as _dt
    if not config.TRIAL_ACTIVE:
        return jsonify({'trial': False})

    now_date = _dt.date.today()
    try:
        end_date = _dt.date.fromisoformat(config.TRIAL_END_DATE)
    except ValueError:
        end_date = now_date + _dt.timedelta(days=30)

    expired = now_date > end_date

    try:
        with get_db() as (cursor, conn):
            cursor.execute('SELECT COUNT(*) as cnt FROM users')
            row = dict_from_row(cursor.fetchone())
            total_users = row['cnt'] or 0
    except Exception:
        total_users = 0

    slots_remaining = max(0, config.TRIAL_MAX_USERS - total_users)
    full = total_users >= config.TRIAL_MAX_USERS

    return jsonify({
        'trial': True,
        'active': not expired and not full,
        'expired': expired,
        'full': full,
        'slotsRemaining': slots_remaining,
        'totalUsers': total_users,
        'maxUsers': config.TRIAL_MAX_USERS,
        'endDate': config.TRIAL_END_DATE,
    })


@app.route('/api/auth/login', methods=['POST'])
@rate_limit('10 per minute')
def login():
    """Login user"""
    data = request.get_json()
    if not data:
        return jsonify({'success': False, 'message': 'Request body required'}), 400

    email = data.get('email', '').strip().lower()
    password = data.get('password', '')

    if not email or not password:
        return jsonify({'success': False, 'message': 'Email and password required'}), 400

    try:
        # Get user
        user = get_user_by_email(email)
        if not user:
            return jsonify({'success': False, 'message': 'Invalid email or password'}), 401

        # If this account is linked to Google sign-in, guide the user clearly.
        if user.get('auth_provider') == 'google':
            return jsonify({
                'success': False,
                'message': 'This account uses Google Sign-In. Please continue with Google.',
                'needsGoogleSignIn': True
            }), 400

        # Verify password
        if not check_password_hash(user['password_hash'], password):
            return jsonify({'success': False, 'message': 'Invalid email or password'}), 401

        # Check if user is banned
        if user.get('is_banned'):
            return jsonify({'success': False, 'message': 'Your account has been permanently banned. Contact support for assistance.'}), 403

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

    except Exception as e:
        print(f'[LOGIN] Error: {e}')
        import traceback; traceback.print_exc()
        err = str(e).lower()
        if any(k in err for k in [
            'could not connect', 'connection', 'timeout', 'server closed',
            'operationalerror', 'database', 'relation', 'does not exist',
        ]):
            return jsonify({'success': False, 'message': 'Login service is starting up. Please try again in a few seconds.'}), 503
        return jsonify({'success': False, 'message': 'Login failed. Please try again.'}), 500


@app.route('/api/auth/me', methods=['GET'])
@require_auth
def get_current_user():
    """Get current authenticated user with real-time computed stats"""
    user = get_user_by_id(request.user_id)
    if not user:
        return jsonify({'success': False, 'message': 'User not found'}), 404
    
    resp = user_to_response(user)
    
    # Compute real-time stats from DB to ensure accuracy
    try:
        with get_db() as (cursor, conn):
            # Count completed (paid) tasks as helper
            cursor.execute(f'''
                SELECT COUNT(*) as cnt FROM tasks
                WHERE accepted_by = {PH} AND status = 'paid'
            ''', (request.user_id,))
            row = dict_from_row(cursor.fetchone())
            real_completed = int(row['cnt'] or 0)
            
            # Count posted tasks
            cursor.execute(f'''
                SELECT COUNT(*) as cnt FROM tasks
                WHERE posted_by = {PH}
            ''', (request.user_id,))
            row = dict_from_row(cursor.fetchone())
            real_posted = int(row['cnt'] or 0)
            
            # Sum actual earnings from wallet credit transactions for this user
            cursor.execute(f'''
                SELECT COALESCE(SUM(amount), 0) as total FROM wallet_transactions
                WHERE user_id = {PH} AND type = 'credit' AND description LIKE '%%Task payment received%%'
            ''', (request.user_id,))
            row = dict_from_row(cursor.fetchone())
            credit_total = float(row['total'] or 0)
            
            # Sum deductions (commissions)
            cursor.execute(f'''
                SELECT COALESCE(SUM(ABS(amount)), 0) as total FROM wallet_transactions
                WHERE user_id = {PH} AND type = 'deduction' AND description LIKE '%%Commission%%'
            ''', (request.user_id,))
            row = dict_from_row(cursor.fetchone())
            deduction_total = float(row['total'] or 0)
            
            real_earnings = credit_total - deduction_total
            
            # Compute live rating + count from helper_ratings
            cursor.execute(f'''
                SELECT AVG(rating) as avg_r, COUNT(*) as cnt
                FROM helper_ratings WHERE rated_id = {PH}
            ''', (request.user_id,))
            row = dict_from_row(cursor.fetchone())
            reviews_count = int(row['cnt'] or 0)
            
            # Override with computed values
            resp['tasksCompleted'] = max(real_completed, int(resp.get('tasksCompleted') or 0))
            resp['tasksPosted'] = max(real_posted, int(resp.get('tasksPosted') or 0))
            if real_earnings > 0:
                resp['totalEarnings'] = round(real_earnings, 2)
            resp['reviewsCount'] = reviews_count
            resp['ratingCount'] = reviews_count
            avg_r_val = float(row['avg_r'] or 0)
            if reviews_count > 0:
                resp['rating'] = round(avg_r_val, 2)
            # Compute rank from reviews + rating
            if reviews_count == 0:
                resp['rank'] = 'New'
            elif reviews_count >= 50 and avg_r_val >= 4.8:
                resp['rank'] = 'Elite'
            elif reviews_count >= 25 and avg_r_val >= 4.5:
                resp['rank'] = 'Platinum'
            elif reviews_count >= 10 and avg_r_val >= 4.0:
                resp['rank'] = 'Gold'
            elif reviews_count >= 5 and avg_r_val >= 3.5:
                resp['rank'] = 'Silver'
            else:
                resp['rank'] = 'Bronze'
    except Exception as e:
        print(f'⚠️ Stats computation error: {e}')
    
    return jsonify({
        'success': True,
        'user': resp
    })


@app.route('/api/auth/logout', methods=['POST'])
@require_auth
def logout():
    """Logout user (invalidate session and clear FCM token)"""
    with get_db() as (cursor, conn):
        cursor.execute(
            f'UPDATE users SET session_token = NULL, fcm_token = NULL WHERE id = {PH}',
            (request.user_id,)
        )
    
    return jsonify({'success': True, 'message': 'Logged out successfully'})


@app.route('/api/auth/send-verification-otp', methods=['POST'])
@require_auth
@rate_limit('3 per minute')
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
        except Exception as e:
            print(f"⚠️ SendGrid email error: {e}")

    if not email_sent_server:
        print(f"⚠️ SendGrid not configured — verification OTP email not sent for {email}")

    response = {
        'success': True,
        'message': 'Verification code sent to your email'
    }
    return jsonify(response)


@app.route('/api/auth/verify-email', methods=['POST'])
@require_auth
@rate_limit('5 per minute')
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
        except Exception as e:
            print(f"⚠️ SendGrid email error: {e}")
    else:
        print(f"⚠️ SendGrid not configured — forgot-password OTP not sent for {email}")
    
    return jsonify({
        'success': True,
        'message': 'If an account exists with this email, an OTP has been sent',
        'resetToken': reset_token,
        'maskedEmail': email[:3] + '***@' + email.split('@')[1],
        'userName': user['name']
    })


# ============================================================
# Phone OTP verification (separate from email/password reset OTP)
# ============================================================
def _normalize_phone(raw):
    """Strip spaces/dashes, default +91 for 10-digit Indian numbers."""
    if not raw:
        return None
    s = ''.join(ch for ch in str(raw) if ch.isdigit() or ch == '+')
    if not s:
        return None
    if s.startswith('+'):
        return s
    if len(s) == 10:
        return '+91' + s
    if len(s) == 12 and s.startswith('91'):
        return '+' + s
    return s


def _send_sms_otp(phone, otp):
    """Send OTP via Fast2SMS Quick SMS route if FAST2SMS_API_KEY set, else log to console.
    Returns (success, message). Never raises."""
    api_key = os.environ.get('FAST2SMS_API_KEY', '').strip()
    if not api_key:
        # Dev/staging fallback: log only. NOT secure for production.
        print(f"[SMS-OTP-DEV] phone={phone} otp={otp}  (set FAST2SMS_API_KEY to enable real SMS)", flush=True)
        return True, 'logged'
    try:
        import requests
        # Fast2SMS expects bare 10-digit Indian number.
        digits = ''.join(ch for ch in phone if ch.isdigit())
        if digits.startswith('91') and len(digits) == 12:
            digits = digits[2:]
        if len(digits) != 10:
            return False, 'Invalid Indian phone number (need 10 digits)'
        # Quick SMS route ('q') — works without OTP-route website verification.
        # Uses transactional-style message; no template approval needed.
        message = f'Your Workmate4u verification code is {otp}. Valid for 10 minutes. Do not share this code with anyone.'
        resp = requests.post(
            'https://www.fast2sms.com/dev/bulkV2',
            headers={'authorization': api_key, 'Content-Type': 'application/json'},
            json={
                'route': 'q',
                'message': message,
                'language': 'english',
                'flash': 0,
                'numbers': digits,
            },
            timeout=10,
        )
        data = resp.json() if resp.headers.get('Content-Type', '').startswith('application/json') else {}
        if resp.status_code == 200 and data.get('return') is True:
            return True, 'sent'
        # Log the real provider response for debugging, but return a
        # user-friendly generic message — provider-internal text like
        # "complete website verification" is not actionable for end users.
        provider_msg = data.get('message') or f'HTTP {resp.status_code}'
        print(f"[SMS-OTP-PROVIDER-ERR] phone={phone} status={resp.status_code} body={resp.text[:500]}", flush=True)
        # Surface provider message in dev/staging to aid debugging; production users see generic.
        if os.environ.get('SMS_DEBUG', '').lower() in ('1', 'true', 'yes'):
            return False, f'SMS provider: {provider_msg}'
        return False, 'OTP service is temporarily unavailable. Please try again in a few minutes.'
    except Exception as e:
        print(f"[SMS-OTP-ERR] {e}", flush=True)
        return False, 'SMS service unavailable, try again'


@app.route('/api/auth/send-phone-otp', methods=['POST'])
@require_auth
@rate_limit('3 per minute')
def send_phone_otp():
    """Generate + send a 6-digit OTP to the user's phone.
    Body: {phone?: string}  — if omitted, uses the phone already on the user record.
    """
    try:
        data = request.get_json(silent=True) or {}
        raw_phone = data.get('phone') or ''
        user_id = request.user_id

        user = get_user_by_id(user_id)
        if not user:
            return jsonify({'success': False, 'message': 'User not found'}), 404

        phone = _normalize_phone(raw_phone) or _normalize_phone(user.get('phone'))
        if not phone:
            return jsonify({'success': False, 'message': 'Phone number is required'}), 400

        # Generate 6-digit OTP
        otp = ''.join(secrets.choice('0123456789') for _ in range(6))
        expires_at = datetime.datetime.now() + datetime.timedelta(minutes=10)

        with get_db() as (cursor, conn):
            # Ensure phone_otps table exists (defensive — covers DBs that pre-date the migration)
            try:
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS phone_otps (
                        id SERIAL PRIMARY KEY,
                        user_id VARCHAR(20) NOT NULL,
                        phone VARCHAR(20) NOT NULL,
                        otp VARCHAR(10) NOT NULL,
                        attempts INT DEFAULT 0,
                        used BOOLEAN DEFAULT FALSE,
                        created_at TIMESTAMP DEFAULT NOW(),
                        expires_at TIMESTAMP NOT NULL
                    )
                ''')
            except Exception as _e:
                print(f"[PHONE-OTP] table create check: {_e}", flush=True)
            # Invalidate prior unused OTPs for this user
            cursor.execute(f"UPDATE phone_otps SET used = TRUE WHERE user_id = {PH} AND used = FALSE", (user_id,))
            cursor.execute(
                f"INSERT INTO phone_otps (user_id, phone, otp, expires_at) VALUES ({PH}, {PH}, {PH}, {PH})",
                (user_id, phone, otp, expires_at),
            )

        ok, msg = _send_sms_otp(phone, otp)
        if not ok:
            return jsonify({'success': False, 'message': msg}), 502

        masked = phone[:3] + '****' + phone[-2:]
        return jsonify({'success': True, 'message': f'OTP sent to {masked}', 'maskedPhone': masked})
    except Exception as e:
        import traceback
        print(f"[PHONE-OTP-ERR] {e}\n{traceback.format_exc()}", flush=True)
        return jsonify({'success': False, 'message': f'Server error: {str(e)[:200]}'}), 500


@app.route('/api/auth/verify-phone-otp', methods=['POST'])
@require_auth
@rate_limit('10 per minute')
def verify_phone_otp():
    """Verify the 6-digit phone OTP. On success: sets users.phone_verified=TRUE
    and updates users.phone to the verified number."""
    data = request.get_json(silent=True) or {}
    otp = (data.get('otp') or '').strip()
    if not otp or not otp.isdigit() or len(otp) != 6:
        return jsonify({'success': False, 'message': 'Enter the 6-digit OTP'}), 400

    user_id = request.user_id
    try:
        with get_db() as (cursor, conn):
            cursor.execute(
                f"SELECT id, phone, otp, attempts, used, expires_at FROM phone_otps "
                f"WHERE user_id = {PH} AND used = FALSE ORDER BY id DESC LIMIT 1",
                (user_id,),
            )
            row = cursor.fetchone()
            if not row:
                return jsonify({'success': False, 'message': 'No OTP requested. Tap Send OTP first.'}), 400
            # Support both RealDictCursor (PG) and tuple cursor (SQLite)
            if isinstance(row, dict):
                rec = {
                    'id': row['id'], 'phone': row['phone'], 'otp': row['otp'],
                    'attempts': row.get('attempts') or 0, 'used': row['used'],
                    'expires_at': row['expires_at'],
                }
            else:
                rec = {
                    'id': row[0], 'phone': row[1], 'otp': row[2],
                    'attempts': row[3] or 0, 'used': row[4], 'expires_at': row[5],
                }
            if rec['attempts'] >= 5:
                cursor.execute(f"UPDATE phone_otps SET used = TRUE WHERE id = {PH}", (rec['id'],))
                return jsonify({'success': False, 'message': 'Too many attempts. Request a new OTP.'}), 400
            # Compare expiry — handle both datetime and string
            exp = rec['expires_at']
            if isinstance(exp, str):
                try:
                    exp = datetime.datetime.fromisoformat(exp)
                except Exception:
                    exp = None
            if exp and datetime.datetime.now() > exp:
                cursor.execute(f"UPDATE phone_otps SET used = TRUE WHERE id = {PH}", (rec['id'],))
                return jsonify({'success': False, 'message': 'OTP expired. Request a new one.'}), 400
            if rec['otp'] != otp:
                cursor.execute(f"UPDATE phone_otps SET attempts = attempts + 1 WHERE id = {PH}", (rec['id'],))
                return jsonify({'success': False, 'message': 'Incorrect OTP'}), 400

            # Success
            cursor.execute(f"UPDATE phone_otps SET used = TRUE WHERE id = {PH}", (rec['id'],))
            cursor.execute(
                f"UPDATE users SET phone = {PH}, phone_verified = TRUE WHERE id = {PH}",
                (rec['phone'], user_id),
            )

        user = get_user_by_id(user_id)
        return jsonify({'success': True, 'message': 'Phone verified', 'user': user_to_response(user)})
    except Exception as e:
        import traceback
        print(f"[VERIFY-PHONE-OTP-ERR] {e}\n{traceback.format_exc()}", flush=True)
        return jsonify({'success': False, 'message': f'Server error: {str(e)[:200]}'}), 500


@app.route('/api/auth/verify-otp', methods=['POST'])
@rate_limit('5 per minute')
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
        
        # Mark OTP as verified so reset_password can confirm the step was completed
        cursor.execute(f'UPDATE password_resets SET otp_verified = {PH} WHERE token = {PH}',
                       (True if config.USE_POSTGRES else 1, reset_token))
    
    return jsonify({
        'success': True,
        'message': 'OTP verified',
        'resetToken': reset_token
    })


@app.route('/api/auth/reset-password', methods=['POST'])
@rate_limit('5 per minute')
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
        
        # Get reset record — also require that OTP was actually verified
        cursor.execute(f'''
            SELECT * FROM password_resets 
            WHERE token = {PH} AND used = {PH} AND otp_verified = {PH} AND expires_at > {PH}
        ''', (reset_token, False if config.USE_POSTGRES else 0, True if config.USE_POSTGRES else 1, now))
        
        reset_record = cursor.fetchone()
        if not reset_record:
            return jsonify({'success': False, 'message': 'Invalid or expired reset token. Please verify your OTP first.'}), 400
        
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
    _ensure_bio_skills_columns()
    import json as _json_profile

    _ensure_gender_column()
    allowed_fields = ['name', 'phone', 'email', 'profile_photo', 'dob', 'bio', 'gender']
    updates = {k: v for k, v in data.items() if k in allowed_fields}

    # Skills: stored as JSON string in the DB
    if 'skills' in data and isinstance(data['skills'], list):
        updates['skills'] = _json_profile.dumps(data['skills'])

    # Validate DOB / age if provided
    if 'dob' in updates:
        try:
            dob_date = datetime.datetime.strptime(updates['dob'], '%Y-%m-%d')
            age = (datetime.datetime.now() - dob_date).days // 365
            if age < 16:
                return jsonify({'success': False, 'message': 'You must be 16 or older to use Workmate4u'}), 400
        except ValueError:
            return jsonify({'success': False, 'message': 'Invalid date of birth format'}), 400

    # Validate email uniqueness if changing email
    if 'email' in updates:
        new_email = updates['email'].strip().lower()
        if not new_email or '@' not in new_email:
            return jsonify({'success': False, 'message': 'Invalid email address'}), 400
        existing = get_user_by_email(new_email)
        if existing and existing['id'] != request.user_id:
            return jsonify({'success': False, 'message': 'Email already in use'}), 400
        updates['email'] = new_email

    # Validate phone uniqueness if changing phone
    if 'phone' in updates:
        new_phone = (updates['phone'] or '').strip()
        if new_phone:
            # Skip uniqueness check if the number belongs to this user already
            current_user = get_user_by_id(request.user_id)
            current_phone = (current_user.get('phone') or '').strip() if current_user else ''
            if new_phone != current_phone:
                with get_db() as (cursor, _ph_check):
                    cursor.execute(
                        f'SELECT id FROM users WHERE phone = {PH} AND id != {PH}',
                        (new_phone, request.user_id)
                    )
                    if cursor.fetchone():
                        return jsonify({'success': False, 'message': 'Phone number already in use'}), 400
        updates['phone'] = new_phone or None

    if 'profile_photo' in updates and updates.get('profile_photo'):
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


@app.route('/api/user/device-token', methods=['POST'])
@require_auth
def save_device_token():
    """Save or refresh the user's FCM device token for push notifications."""
    _ensure_fcm_token_column()
    body = request.get_json() or {}
    token = body.get('token', '').strip()
    if not token:
        return jsonify({'success': False, 'message': 'token required'}), 400
    try:
        with get_db() as (cursor, conn):
            # Remove this token from any other user first (prevents cross-account notifications)
            cursor.execute(
                f'UPDATE users SET fcm_token = NULL WHERE fcm_token = {PH} AND id != {PH}',
                (token, request.user_id)
            )
            cursor.execute(
                f'UPDATE users SET fcm_token = {PH} WHERE id = {PH}',
                (token, request.user_id)
            )
            conn.commit()
        return jsonify({'success': True})
    except Exception as e:
        print(f'[FCM] device-token save error: {e}')
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/user/location', methods=['POST'])
@require_auth
def update_user_location():
    """Save the user's last known GPS coordinates for proximity-based notifications."""
    _ensure_user_location_columns()
    body = request.get_json() or {}
    lat = body.get('lat')
    lng = body.get('lng')
    if lat is None or lng is None:
        return jsonify({'success': False, 'message': 'lat and lng required'}), 400
    try:
        lat = float(lat)
        lng = float(lng)
    except (TypeError, ValueError):
        return jsonify({'success': False, 'message': 'lat and lng must be numbers'}), 400
    try:
        with get_db() as (cursor, conn):
            cursor.execute(
                f'UPDATE users SET last_lat = {PH}, last_lng = {PH} WHERE id = {PH}',
                (lat, lng, request.user_id)
            )
            conn.commit()
        return jsonify({'success': True})
    except Exception as e:
        print(f'[Location] save error: {e}')
        return jsonify({'success': False, 'message': str(e)}), 500


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
    """Get all active tasks (non-expired) with optional pagination and filtering"""
    import datetime
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    
    # Pagination params
    page = request.args.get('page', type=int)
    limit = request.args.get('limit', request.args.get('per_page', 20, type=int), type=int)
    limit = min(max(limit, 1), 100)  # clamp 1-100

    # Filter params
    category_filter = request.args.get('category', '').strip()
    max_budget = request.args.get('max_budget', type=float)
    min_budget = request.args.get('min_budget', type=float)
    lat = request.args.get('lat', type=float)
    lng = request.args.get('lng', type=float)
    radius_km = request.args.get('radius', type=float)
    
    # Throttle cleanup: run at most once every 5 minutes per process
    global _last_cleanup_time
    try:
        _now_dt = datetime.datetime.now(datetime.timezone.utc)
        if _last_cleanup_time is None or (_now_dt - _last_cleanup_time).total_seconds() > 300:
            _last_cleanup_time = _now_dt
            try:
                cleanup_old_tasks()
            except Exception:
                pass
    except Exception:
        pass
    
    try:
        with get_db() as (cursor, conn):
            # Build WHERE clause with optional filters
            base_where = f"WHERE t.status = 'active' AND t.expires_at > {PH}"
            base_params = [now]

            if category_filter and category_filter != 'all':
                base_where += f" AND t.category = {PH}"
                base_params.append(category_filter)
            if max_budget is not None:
                base_where += f" AND t.price <= {PH}"
                base_params.append(max_budget)
            if min_budget is not None:
                base_where += f" AND t.price >= {PH}"
                base_params.append(min_budget)
            if lat is not None and lng is not None and radius_km is not None:
                # Haversine formula — filter tasks within radius_km of user's location
                base_where += f"""
                    AND t.location_lat IS NOT NULL AND t.location_lng IS NOT NULL
                    AND (6371 * acos(LEAST(1.0,
                        cos(radians({PH})) * cos(radians(t.location_lat)) *
                        cos(radians(t.location_lng) - radians({PH})) +
                        sin(radians({PH})) * sin(radians(t.location_lat))
                    ))) <= {PH}"""
                base_params.extend([lat, lng, lat, radius_km])
            
            if page is not None:
                # Paginated mode
                cursor.execute(f'SELECT COUNT(*) as total FROM tasks t {base_where}', tuple(base_params))
                total = dict_from_row(cursor.fetchone())['total']
                
                offset = (page - 1) * limit
                cursor.execute(f'''
                    SELECT t.id, t.title, t.description, t.category,
                           t.location_lat, t.location_lng, t.location_address,
                           t.drop_location_lat, t.drop_location_lng, t.drop_location_address,
                           t.price, t.service_charge, t.posted_by, t.posted_at, t.expires_at, t.status,
                           COALESCE(u.name, 'Anonymous') AS poster_name,
                           COALESCE(u.rating, 5.0)       AS poster_rating,
                           COALESCE(u.tasks_posted, 0)   AS poster_tasks
                    FROM tasks t
                    LEFT JOIN users u ON u.id = t.posted_by
                    {base_where}
                    ORDER BY t.posted_at DESC
                    LIMIT {PH} OFFSET {PH}
                ''', tuple(base_params) + (limit, offset))
            else:
                # Legacy: return all active (with safety limit), single JOIN
                total = None
                cursor.execute(f'''
                    SELECT t.id, t.title, t.description, t.category,
                           t.location_lat, t.location_lng, t.location_address,
                           t.drop_location_lat, t.drop_location_lng, t.drop_location_address,
                           t.price, t.service_charge, t.posted_by, t.posted_at, t.expires_at, t.status,
                           COALESCE(u.name, 'Anonymous') AS poster_name,
                           COALESCE(u.rating, 5.0)       AS poster_rating,
                           COALESCE(u.tasks_posted, 0)   AS poster_tasks
                    FROM tasks t
                    LEFT JOIN users u ON u.id = t.posted_by
                    {base_where}
                    ORDER BY t.posted_at DESC
                    LIMIT 200
                ''', tuple(base_params))
            
            rows = cursor.fetchall()
            
            task_list = []
            for row in rows:
                task = dict_from_row(row)
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
                    'drop_location': {
                        'lat': task['drop_location_lat'],
                        'lng': task['drop_location_lng'],
                        'address': task.get('drop_location_address') or ''
                    } if task.get('drop_location_lat') else None,
                    'price': float(task['price']),
                    'service_charge': float(task.get('service_charge') or 0),
                    'postedBy': {
                        'id': task.get('posted_by'),
                        'name': task['poster_name'],
                        'rating': float(task['poster_rating']),
                        'tasksPosted': int(task['poster_tasks'])
                    },
                    'postedAt': task['posted_at'],
                    'expiresAt': task['expires_at'],
                    'status': task['status']
                })
        
        response = {'success': True, 'tasks': task_list}
        if total is not None:
            response['pagination'] = {
                'page': page,
                'limit': limit,
                'total': total,
                'totalPages': (total + limit - 1) // limit if limit else 1
            }
        return jsonify(response)
        
    except Exception as e:
        print(f"[GET /api/tasks] Error: {e}")
        import traceback
        traceback.print_exc()
        err = str(e).lower()
        if any(k in err for k in ['could not connect', 'connection', 'timeout', 'server closed', 'operationalerror', 'database']):
            return jsonify({
                'success': True,
                'tasks': [],
                'stale': True,
                'message': 'Server is warming up. Showing empty task list temporarily.'
            }), 200
        return jsonify({
            'success': False,
            'message': 'Failed to load tasks. Please try again.'
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
        err = str(e).lower()
        if any(k in err for k in ['could not connect', 'connection', 'timeout', 'server closed', 'operationalerror', 'database']):
            return jsonify({'success': True, 'counts': {}, 'stale': True}), 200
        return jsonify({'success': False, 'message': 'Failed to load category counts.'}), 500


@app.route('/api/tasks', methods=['POST'])
@require_auth
def create_task():
    """Create a new task"""
    try:
        print('='*60)
        print('🚀 POST /api/tasks - Task creation endpoint called')
        print(f'   User ID: {request.user_id}')
        
        # Check phone number is set (required for task helpers to contact poster)
        user_check = get_user_by_id(request.user_id)
        if user_check and not user_check.get('phone'):
            return jsonify({'success': False, 'message': 'Please add your phone number in Profile before posting tasks. It is required so task helpers can contact you.', 'needsPhone': True}), 400

        # KYC must be verified to post tasks
        kyc_status_post = (user_check.get('kyc_status') if user_check else None) or 'none'
        if kyc_status_post not in ('approved', 'verified'):
            return jsonify({
                'success': False,
                'message': 'KYC verification is required before posting tasks. Please complete KYC in your Profile.',
                'needsKyc': True,
                'kycStatus': kyc_status_post
            }), 403

        # Block task posting when wallet is in debt (negative balance)
        poster_wallet = get_or_create_wallet(request.user_id)
        poster_balance = float(poster_wallet.get('balance', 0))
        if poster_balance < 0:
            return jsonify({
                'success': False,
                'message': f'Your wallet has a negative balance of ₹{abs(poster_balance):.2f}. Please top up to clear your debt before posting tasks.',
                'debtSuspended': True,
                'debtAmount': abs(poster_balance)
            }), 403

        data = request.get_json()
        print(f'   Raw request data: {data}')
        
        required = ['title', 'description', 'category', 'price']
        for field in required:
            if not data.get(field):
                print(f"⚠️ Task creation failed: missing required field '{field}'")
                print(f'   Available fields: {list(data.keys())}')
                return jsonify({'success': False, 'message': f'{field} is required'}), 400
        
        # Input length validation
        if len(str(data.get('title', ''))) > 200:
            return jsonify({'success': False, 'message': 'Title max 200 characters'}), 400
        if len(str(data.get('description', ''))) > 5000:
            return jsonify({'success': False, 'message': 'Description max 5000 characters'}), 400
        
        # Price validation
        try:
            price = float(data['price'])
            if price < 10 or price > 50000:
                return jsonify({'success': False, 'message': 'Price must be between ₹10 and ₹50,000'}), 400
        except (ValueError, TypeError):
            return jsonify({'success': False, 'message': 'Invalid price'}), 400

        # Spam / fraud content screening
        allowed, reason = screen_task_content(data.get('title', ''), data.get('description', ''), data.get('category', ''))
        if not allowed:
            print(f"🚫 Task rejected by content policy: {reason}")
            try:
                # Best-effort flag: increment a counter so admins can spot repeat offenders
                with get_db() as (cursor, conn):
                    try:
                        cursor.execute(f"ALTER TABLE users ADD COLUMN IF NOT EXISTS spam_attempts INTEGER DEFAULT 0")
                        conn.commit()
                    except Exception:
                        conn.rollback()
                    try:
                        cursor.execute(f"UPDATE users SET spam_attempts = COALESCE(spam_attempts, 0) + 1 WHERE id = {PH}", (request.user_id,))
                        conn.commit()
                    except Exception:
                        conn.rollback()
            except Exception as _e:
                print(f"   (spam_attempts increment failed: {_e})")
            return jsonify({
                'success': False,
                'message': 'This task violates our content policy and cannot be posted. ' + reason + ' If you believe this is a mistake, please contact support.',
                'policyViolation': True,
                'reason': reason
            }), 422

        # Soft-flag (post still goes through, but admin sees it for review)
        soft_flagged, soft_reason = flag_task_content(data.get('title', ''), data.get('description', ''))
        if soft_flagged:
            print(f"⚠️  Task flagged for admin review: {soft_reason}")

        print(f"📝 Creating task: '{data.get('title')}'")
        print(f"   Category: {data.get('category')}")
        print(f"   Description: {data.get('description')}")
        print(f"   Price: {data.get('price')}")
        print(f"   Location: {data.get('location')}")
        
        # Service charge: prefer client-supplied value (distance-aware for
        # ride/delivery/moving categories) when it is a sane number; otherwise
        # fall back to the category-only default.
        client_sc = data.get('serviceCharge', data.get('service_charge'))
        try:
            client_sc_val = float(client_sc) if client_sc is not None else None
        except (TypeError, ValueError):
            client_sc_val = None
        if client_sc_val is not None and 0 <= client_sc_val <= 500:
            service_charge = client_sc_val
            print(f"   Service Charge (from client): ₹{service_charge}")
        else:
            service_charge = get_service_charge(data.get('category', 'other'))
            print(f"   Service Charge (default): ₹{service_charge}")
        print(f"   Total Display Value: ₹{float(data.get('price')) + service_charge}")
        
        with get_db() as (cursor, conn):
            posted_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
            expires_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=24)).isoformat()
            
            location = data.get('location', {})
            drop_location = data.get('dropLocation') or data.get('drop_location') or {}
            
            print(f"   Posted at: {posted_at}")
            print(f"   Expires at: {expires_at}")

            # Lazily ensure flag_reason column exists (used for admin soft-flag review)
            try:
                cursor.execute("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS flag_reason TEXT")
                conn.commit()
            except Exception:
                try: conn.rollback()
                except Exception: pass

            # Insert task and get its ID in one atomic operation (RETURNING avoids
            # lastval() race with other concurrent sequences on the same connection).
            print('   Executing INSERT query...')
            if config.USE_POSTGRES:
                cursor.execute(f'''
                    INSERT INTO tasks (title, description, category, location_lat, location_lng,
                                      location_address, drop_location_lat, drop_location_lng, drop_location_address,
                                      price, service_charge, posted_by, posted_at, expires_at, status, flag_reason)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, 'active', {PH})
                    RETURNING id
                ''', (
                    html_escape(data['title']),
                    html_escape(data['description']),
                    html_escape(data['category']),
                    location.get('lat'),
                    location.get('lng'),
                    html_escape(location.get('address', '') or ''),
                    drop_location.get('lat') if drop_location else None,
                    drop_location.get('lng') if drop_location else None,
                    html_escape(drop_location.get('address', '') or '') if drop_location else None,
                    data['price'],
                    service_charge,
                    request.user_id,
                    posted_at,
                    expires_at,
                    soft_reason if soft_flagged else None
                ))
                result = cursor.fetchone()
                task_id = result['id'] if result else None
            else:
                cursor.execute(f'''
                    INSERT INTO tasks (title, description, category, location_lat, location_lng,
                                      location_address, drop_location_lat, drop_location_lng, drop_location_address,
                                      price, service_charge, posted_by, posted_at, expires_at, status, flag_reason)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, 'active', {PH})
                ''', (
                    html_escape(data['title']),
                    html_escape(data['description']),
                    html_escape(data['category']),
                    location.get('lat'),
                    location.get('lng'),
                    html_escape(location.get('address', '') or ''),
                    drop_location.get('lat') if drop_location else None,
                    drop_location.get('lng') if drop_location else None,
                    html_escape(drop_location.get('address', '') or '') if drop_location else None,
                    data['price'],
                    service_charge,
                    request.user_id,
                    posted_at,
                    expires_at,
                    soft_reason if soft_flagged else None
                ))
                task_id = cursor.lastrowid
            print(f'   ✅ INSERT query executed successfully, task_id={task_id}')
            
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
                  f'Your task "{html_escape(data["title"])}" has been posted. Budget: ₹{data["price"]}. It will expire in 24 hours.',
                  'unread', notif_data, posted_at))
            
            print(f"✅ Task created successfully with ID: {task_id}")
        
        # FCM push — confirm to poster that their task was posted
        try:
            send_fcm_to_user(
                request.user_id,
                'Task Posted! 📋',
                f'Your task "{data["title"]}" has been posted. Budget: ₹{data["price"]}. It will expire in 24 hours.',
                data={'type': 'task_posted', 'task_id': str(task_id)},
                channel='workmate4u_main',
            )
        except Exception:
            pass

        # Skill-match and nearby notifications are triggered by the Flutter client
        # via /api/tasks/<id>/notify-skills and /api/tasks/<id>/notify-nearby after
        # task creation. Do NOT send them inline here to avoid duplicates.

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
        return jsonify({'success': False, 'message': 'Task creation failed. Please try again.'}), 500


@app.route('/api/tasks/<int:task_id>/accept', methods=['POST'])
@require_auth
def accept_task(task_id):
    """Accept a task — all checks + write done in a single DB connection"""
    import json as _json_acc
    try:
        # _ensure_suspension_columns is guarded by a flag; noop after first call
        _ensure_suspension_columns()

        poster_id = None
        helper_name = 'Someone'
        task = None

        with get_db() as (cursor, conn):
            # ── 1. Fetch user + wallet balance in one query ──────────────────
            cursor.execute(f'''
                SELECT u.id, u.name, u.phone, u.kyc_status,
                       u.is_suspended, u.suspended_until, u.suspension_reason, u.is_banned,
                       COALESCE(w.balance, 0) AS wallet_balance
                FROM users u
                LEFT JOIN wallets w ON w.user_id = u.id
                WHERE u.id = {PH}
            ''', (request.user_id,))
            user_row = cursor.fetchone()
            if not user_row:
                return jsonify({'success': False, 'message': 'User not found'}), 404
            u = dict_from_row(user_row)

            # ── 2. Phone check ────────────────────────────────────────────────
            if not u.get('phone'):
                return jsonify({
                    'success': False,
                    'message': 'Please add your phone number in Profile before accepting tasks. It is required so the task poster can contact you.',
                    'needsPhone': True
                }), 400

            # ── 3. KYC check ─────────────────────────────────────────────────
            kyc_status_acc = u.get('kyc_status') or 'none'
            if kyc_status_acc not in ('approved', 'verified'):
                return jsonify({
                    'success': False,
                    'message': 'KYC verification is required before accepting tasks. Please complete KYC in your Profile.',
                    'needsKyc': True,
                    'kycStatus': kyc_status_acc
                }), 403

            # ── 4. Ban / suspension checks ───────────────────────────────────
            if u.get('is_banned'):
                return jsonify({'success': False, 'message': 'Your account has been permanently banned. Contact support for assistance.'}), 403

            is_suspended = u.get('is_suspended', False)
            sus_until = u.get('suspended_until')
            sus_reason = u.get('suspension_reason', '')

            if is_suspended and not sus_until:
                return jsonify({'success': False, 'message': f'Your account is suspended by admin. Reason: {sus_reason or "Contact support"}'}), 403

            if sus_until:
                try:
                    sus_dt = datetime.datetime.fromisoformat(str(sus_until).replace('Z', '+00:00')) if isinstance(sus_until, str) else sus_until
                    if sus_dt.tzinfo is None:
                        sus_dt = sus_dt.replace(tzinfo=datetime.timezone.utc)
                    if datetime.datetime.now(datetime.timezone.utc) < sus_dt:
                        return jsonify({'success': False, 'message': 'Your account is suspended. Please wait until the suspension period ends.'}), 403
                    else:
                        # Timer expired — clear inline (non-critical)
                        try:
                            _now_s = datetime.datetime.now(datetime.timezone.utc).isoformat()
                            cursor.execute(f'UPDATE users SET is_suspended = {PH}, suspended_until = {PH}, suspension_reason = {PH} WHERE id = {PH}',
                                           (False, None, None, request.user_id))
                            cursor.execute(f'''
                                INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                            ''', (request.user_id, 'account_restored', 'Account Restored! ✅',
                                  'Your suspension period has ended. You can now accept tasks again.',
                                  'unread', _json_acc.dumps({'type': 'system'}), _now_s))
                        except Exception:
                            pass
                except Exception:
                    pass

            # ── 5. Wallet debt check ─────────────────────────────────────────
            if float(u.get('wallet_balance', 0)) < 0:
                return jsonify({'success': False, 'message': 'Your wallet balance is negative. Add money to bring it back to ₹0 to restore task acceptance.'}), 403

            # ── 6. Fetch task (must be active) ───────────────────────────────
            cursor.execute(f'SELECT * FROM tasks WHERE id = {PH} AND status = {PH}', (task_id, 'active'))
            task_row = cursor.fetchone()
            if not task_row:
                return jsonify({'success': False, 'message': 'Task not found or already taken'}), 404
            task = dict_from_row(task_row)

            if task['posted_by'] == request.user_id:
                return jsonify({'success': False, 'message': 'Cannot accept your own task'}), 400

            # ── 7. One-task-at-a-time check ──────────────────────────────────
            cursor.execute(f'SELECT id, title FROM tasks WHERE accepted_by = {PH} AND status = {PH}', (request.user_id, 'accepted'))
            existing_task = cursor.fetchone()
            if existing_task:
                existing_task = dict_from_row(existing_task)
                return jsonify({
                    'success': False,
                    'message': 'You already have an active task in progress. Complete or release your current task before accepting a new one.',
                    'hasActiveTask': True,
                    'activeTaskId': existing_task['id'],
                    'activeTaskTitle': existing_task['title']
                }), 409

            # ── 8. Accept + notify (all in same transaction) ─────────────────
            helper_name = u.get('name') or 'Someone'
            accepted_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                UPDATE tasks SET status = 'accepted', accepted_by = {PH}, accepted_at = {PH}
                WHERE id = {PH}
            ''', (request.user_id, accepted_at, task_id))

            poster_id = task['posted_by']
            action_data = _json_acc.dumps({'type': 'task', 'label': '👁️ View Task', 'taskId': task_id})

            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (poster_id, task_id, 'task_accepted', 'Task Accepted! 🎉',
                  f'{helper_name} has accepted your task "{task["title"]}". Budget: ₹{task["price"]}',
                  'unread', action_data, accepted_at))

            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, task_id, 'task_assigned', 'Task Assigned! 📌',
                  f'You accepted "{task["title"]}". Budget: ₹{task["price"]}. Complete it before the poster cancels!',
                  'unread', action_data, accepted_at))

        # ── 9. Email (non-critical, outside DB block) ─────────────────────────
        try:
            notify_task_accepted_email(poster_id, helper_name, task['title'])
        except Exception:
            pass

        # Push notification to poster
        try:
            send_push_to_user(
                poster_id,
                'Task Accepted! 🎉',
                f'{helper_name} accepted "{task["title"]}". Budget: ₹{task["price"]}',
                '/posted.html'
            )
        except Exception:
            pass

        # FCM push to poster (Android/iOS)
        try:
            send_fcm_to_user(
                poster_id,
                'Task Accepted! 🎉',
                f'{helper_name} accepted your task "{task["title"]}". Budget: ₹{task["price"]}',
                data={'type': 'task_accepted', 'task_id': str(task_id)},
                channel='workmate4u_main',
            )
        except Exception:
            pass

        # FCM push to helper confirming assignment
        try:
            send_fcm_to_user(
                request.user_id,
                'Task Assigned! 📌',
                f'You accepted "{task["title"]}". Complete it to earn ₹{task["price"]}.',
                data={'type': 'task_assigned', 'task_id': str(task_id)},
                channel='workmate4u_main',
            )
        except Exception:
            pass

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
    """Abandon an accepted task - reverts it to active, charges a 10% release
    penalty to the helper's wallet (can push wallet negative -> debt suspension),
    and records the release (auto-suspends for 48h if daily limit exceeded)."""
    try:
        release_penalty = 0.0
        helper_new_balance = None

        with get_db() as (cursor, conn):
            # Check task exists and is accepted by the current user
            cursor.execute(f'SELECT * FROM tasks WHERE id = {PH} AND accepted_by = {PH} AND status = {PH}', (task_id, request.user_id, 'accepted'))
            task = cursor.fetchone()

            if not task:
                return jsonify({'success': False, 'message': 'Task not found or not accepted by you'}), 404

            task_dict = dict_from_row(task)
            try:
                task_price = float(task_dict.get('price') or 0)
                task_service = float(task_dict.get('service_charge') or 0)
            except (TypeError, ValueError):
                task_price = 0.0
                task_service = 0.0
            total_task_value = task_price + task_service

            # Revert task to active
            cursor.execute(f'''
                UPDATE tasks SET status = 'active', accepted_by = NULL, accepted_at = NULL
                WHERE id = {PH}
            ''', (task_id,))

            # ===== 10% release penalty to helper wallet =====
            # Helper releases mid-flight => 10% of total task value is deducted
            # from helper wallet. This is allowed to push the wallet negative;
            # debt suspension (any negative balance) will then block further
            # actions until the helper tops up.
            release_penalty = round(total_task_value * 0.10, 2)
            if release_penalty > 0:
                helper_wallet = get_or_create_wallet(request.user_id)
                helper_balance = float(helper_wallet.get('balance', 0) or 0)
                helper_new_balance = helper_balance - release_penalty
                penalty_now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                cursor.execute(f'''
                    UPDATE wallets
                    SET balance = {PH}, total_spent = total_spent + {PH}, updated_at = {PH}
                    WHERE user_id = {PH}
                ''', (helper_new_balance, release_penalty, penalty_now, request.user_id))
                cursor.execute(f'''
                    INSERT INTO wallet_transactions (
                        wallet_id, user_id, type, amount, balance_after,
                        description, reference_id, task_id, created_at
                    ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (
                    helper_wallet.get('id'), request.user_id, 'penalty',
                    release_penalty, helper_new_balance,
                    f'Release penalty (10% of \u20b9{total_task_value:.2f} task)',
                    f'release-penalty-{task_id}', task_id, penalty_now
                ))
                print(f"\u26a0\ufe0f Helper {request.user_id} released task {task_id}. Penalty \u20b9{release_penalty:.2f} -> new balance \u20b9{helper_new_balance:.2f}")
                
                # Send FCM notification to helper about penalty deduction
                try:
                    send_fcm_to_user(
                        request.user_id,
                        '⚠️ Release Penalty Deducted',
                        f'₹{release_penalty:.2f} penalty deducted from your wallet for releasing the task.',
                        data={'type': 'penalty_deducted', 'amount': str(release_penalty), 'taskId': str(task_id)},
                        channel='workmate4u_payment',
                    )
                except Exception as fcm_err:
                    print(f"⚠️ Failed to send penalty FCM notification: {fcm_err}")

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
        debt_suspended = (helper_new_balance is not None and helper_new_balance < 0)
        return jsonify({
            'success': True,
            'message': (
                f'Task released. \u20b9{release_penalty:.2f} (10%) was deducted as a release penalty.'
                if release_penalty > 0 else 'Task released. It is now available for others.'
            ),
            'dailyReleaseCount': daily_count,
            'suspended': suspended,
            'suspendedUntil': suspended_until_iso,
            'releasePenalty': release_penalty,
            'newBalance': helper_new_balance,
            'debtSuspended': debt_suspended,
            'debtAmount': abs(helper_new_balance) if (helper_new_balance is not None and helper_new_balance < 0) else 0
        })
    except Exception as e:
        print(f"❌ Error in abandon_task: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Error abandoning task: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/poster-cancel', methods=['POST'])
@require_auth
def poster_cancel_accepted_task(task_id):
    """Poster cancels an accepted task (e.g., helper unresponsive). The task
    is permanently deleted from the database — it will not be visible to any
    user (poster, helper, browse, admin). The previously assigned helper is
    notified. No financial penalty and no suspension."""
    try:
        body = request.get_json(silent=True) or {}
        reason = (body.get('reason') or '').strip()[:300]

        helper_id = None
        task_title = None

        with get_db() as (cursor, conn):
            cursor.execute(
                f'SELECT id, posted_by, accepted_by, status, title FROM tasks WHERE id = {PH}',
                (task_id,)
            )
            task = cursor.fetchone()
            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404
            task = dict_from_row(task)

            if task['posted_by'] != request.user_id:
                return jsonify({'success': False, 'message': 'Only the task poster can cancel this acceptance'}), 403
            if task['status'] != 'accepted':
                return jsonify({
                    'success': False,
                    'message': f"Cannot cancel task with status '{task['status']}'. Only accepted tasks can be cancelled."
                }), 400

            helper_id = task['accepted_by']
            task_title = task['title']

            # Permanently delete task and clean up FK references
            # NOTE: helper + poster DB notifications are inserted AFTER this cleanup.
            _safe_delete_tasks(cursor, task_id)

            cursor.execute(f'DELETE FROM tasks WHERE id = {PH}', (task_id,))

            # Store cancellation confirmation in DB for the poster
            # Must be done AFTER the task_id cleanup so it isn't deleted.
            # No task_id on this record so it persists permanently.
            try:
                cursor.execute('SAVEPOINT sp_poster_notif')
                import json as _json_cancel
                _now_cancel = datetime.datetime.now(datetime.timezone.utc).isoformat()
                _poster_db_msg = f'Your task "{task_title}" has been cancelled and removed.'
                if reason:
                    _poster_db_msg += f' Reason: {reason}'
                cursor.execute(f'''
                    INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (request.user_id, 'task_cancelled_confirmation',
                      'Task Cancelled ✅', _poster_db_msg,
                      'unread', _json_cancel.dumps({'type': 'task_cancelled_confirmation'}), _now_cancel))
                cursor.execute('RELEASE SAVEPOINT sp_poster_notif')
            except Exception as _pn_err:
                print(f"⚠️ Failed to create poster cancel DB notification: {_pn_err}")
                try: cursor.execute('ROLLBACK TO SAVEPOINT sp_poster_notif')
                except Exception: pass

            # Store cancellation notification for the helper too.
            # Done AFTER task deletion + cleanup, WITHOUT task_id, so it is never
            # deleted by the "DELETE FROM notifications WHERE task_id=X" cleanup.
            if helper_id:
                try:
                    cursor.execute('SAVEPOINT sp_helper_notif')
                    import json as _json_helper
                    _now_helper = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    _helper_msg = f'The poster has cancelled task "{task_title}" and removed it.'
                    if reason:
                        _helper_msg += f' Reason: {reason}'
                    cursor.execute(f'''
                        INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                        VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                    ''', (helper_id, 'task_cancelled_by_poster',
                          'Task Cancelled by Poster ⚠️', _helper_msg,
                          'unread', _json_helper.dumps({'type': 'task_cancelled_by_poster'}), _now_helper))
                    cursor.execute('RELEASE SAVEPOINT sp_helper_notif')
                except Exception as _hn_err:
                    print(f"⚠️ Failed to create helper cancel DB notification: {_hn_err}")
                    try: cursor.execute('ROLLBACK TO SAVEPOINT sp_helper_notif')
                    except Exception: pass

        print(f"✅ Poster {request.user_id} cancelled & deleted task {task_id} (helper {helper_id})")

        # FCM push — tell helper their task was cancelled
        if helper_id:
            try:
                _cancel_msg = f'The poster cancelled task "{task_title}".'
                if reason:
                    _cancel_msg += f' Reason: {reason}'
                send_fcm_to_user(
                    helper_id,
                    'Task Cancelled ⚠️',
                    _cancel_msg,
                    data={'type': 'task_cancelled_by_poster', 'task_id': str(task_id)},
                    channel='workmate4u_main',
                )
            except Exception as _fcm_h_err:
                print(f'[FCM] ❌ Helper cancel notify failed: {_fcm_h_err}')

        # FCM push — confirm to poster that the cancellation was processed
        try:
            _poster_cancel_msg = f'Your task "{task_title}" has been cancelled and removed.'
            if reason:
                _poster_cancel_msg += f' Reason: {reason}'
            print(f'[FCM] Sending task_cancelled_confirmation to poster {request.user_id}')
            send_fcm_to_user(
                request.user_id,
                'Task Cancelled ✅',
                _poster_cancel_msg,
                data={'type': 'task_cancelled_confirmation', 'task_id': str(task_id)},
                channel='workmate4u_main',
            )
        except Exception as _fcm_p_err:
            print(f'[FCM] ❌ Poster cancel notify failed: {_fcm_p_err}')

        return jsonify({
            'success': True,
            'message': 'Task cancelled and removed.',
            'deleted': True
        })
    except Exception as e:
        print(f"❌ Error in poster_cancel_accepted_task: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Error cancelling task: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>', methods=['GET'])
@require_auth
def get_task(task_id):
    """Get a single task by ID — used when tapping a task_matched FCM notification."""
    import datetime as _dt
    _ensure_verify_columns()

    def _iso(v):
        if v is None:
            return None
        if hasattr(v, 'isoformat'):
            if getattr(v, 'tzinfo', None) is None:
                v = v.replace(tzinfo=_dt.timezone.utc)
            return v.isoformat()
        return str(v)

    try:
        with get_db() as (cursor, conn):
            # Use t.* so we never fail on optional columns that may not exist
            # yet (e.g. helper_final_completed_at, drop_location_*). We then
            # access them via .get() which returns None for absent keys.
            cursor.execute(f'''
                SELECT t.*,
                       COALESCE(u.name, 'Anonymous') AS poster_name,
                       COALESCE(u.rating, 5.0)       AS poster_rating,
                       u.phone                        AS poster_phone,
                       h.name                         AS helper_name,
                       h.phone                        AS helper_phone,
                       COALESCE(h.rating, 5.0)        AS helper_rating
                FROM tasks t
                LEFT JOIN users u ON u.id = t.posted_by
                LEFT JOIN users h ON h.id = t.accepted_by
                WHERE t.id = {PH}
                  AND t.status NOT IN ('removed', 'flagged', 'suspicious')
            ''', (task_id,))
            row = cursor.fetchone()
        if not row:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        task = dict_from_row(row)
        show_poster_phone = (str(task.get('accepted_by') or '') == str(request.user_id))
        show_helper_phone = (str(task.get('posted_by') or '') == str(request.user_id))
        completed_at = task.get('completed_at') or task.get('helper_final_completed_at')
        return jsonify({
            'success': True,
            'task': {
                'id': task['id'],
                'title': task.get('title', ''),
                'description': task.get('description', ''),
                'category': task.get('category', ''),
                'location': {
                    'lat': task.get('location_lat'),
                    'lng': task.get('location_lng'),
                    'address': task.get('location_address', '')
                },
                'drop_location': {
                    'lat': task.get('drop_location_lat'),
                    'lng': task.get('drop_location_lng'),
                    'address': task.get('drop_location_address') or ''
                } if task.get('drop_location_lat') else None,
                'price': float(task.get('price') or 0),
                'service_charge': float(task.get('service_charge') or 0),
                'postedBy': {
                    'id': task.get('posted_by'),
                    'name': task.get('poster_name', 'Anonymous'),
                    'rating': float(task.get('poster_rating') or 5.0),
                    'tasksPosted': int(task.get('tasks_posted') or 0),
                    'phone': task.get('poster_phone') or '' if show_poster_phone else ''
                },
                'poster_phone': task.get('poster_phone') or '' if show_poster_phone else '',
                'helper_phone': task.get('helper_phone') or '' if show_helper_phone else '',
                'accepted_by': task.get('accepted_by'),
                'is_paid': task.get('is_paid', False),
                'status': task.get('status', 'active'),
                'postedAt': _iso(task.get('posted_at')),
                'expiresAt': _iso(task.get('expires_at')),
                'accepted_at': _iso(task.get('accepted_at')),
                'completed_at': _iso(completed_at),
            }
        })
    except Exception as e:
        print(f"[GET /api/tasks/{task_id}] Error: {e}")
        import traceback; traceback.print_exc()
        return jsonify({'success': False, 'message': 'Failed to load task.'}), 500


@app.route('/api/tasks/<int:task_id>', methods=['PUT'])
@require_auth
def update_task(task_id):
    """Update a task (only poster can edit, only while active)"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT posted_by, status FROM tasks WHERE id = {PH}', (task_id,))
            task = cursor.fetchone()

            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404

            task = dict_from_row(task)

            if task['posted_by'] != request.user_id:
                return jsonify({'success': False, 'message': 'Only the task poster can edit this task'}), 403

            if task['status'] != 'active':
                return jsonify({'success': False, 'message': 'Only active tasks can be edited'}), 400

            data = request.get_json()

            required = ['title', 'description', 'category', 'price']
            for field in required:
                if field not in data or data[field] is None or (isinstance(data[field], str) and not data[field].strip()):
                    return jsonify({'success': False, 'message': f'{field} is required'}), 400

            if not isinstance(data.get('title'), str) or len(data['title']) > 200:
                return jsonify({'success': False, 'message': 'Title max 200 characters'}), 400
            if not isinstance(data.get('description'), str) or len(data['description']) > 5000:
                return jsonify({'success': False, 'message': 'Description max 5000 characters'}), 400

            try:
                price = float(data['price'])
                if price < 10 or price > 50000:
                    return jsonify({'success': False, 'message': 'Price must be between ₹10 and ₹50,000'}), 400
            except (ValueError, TypeError):
                return jsonify({'success': False, 'message': 'Invalid price'}), 400

            allowed, reason = screen_task_content(data.get('title', ''), data.get('description', ''), data.get('category', ''))
            if not allowed:
                return jsonify({'success': False, 'message': 'This task violates our content policy. ' + reason, 'policyViolation': True}), 422

            location = data.get('location', {})
            location_lat = location.get('lat')
            location_lng = location.get('lng')
            location_address = location.get('address', '')

            cursor.execute(f'''
                UPDATE tasks
                SET title = {PH}, description = {PH}, category = {PH},
                    location_lat = {PH}, location_lng = {PH}, location_address = {PH},
                    price = {PH}
                WHERE id = {PH}
            ''', (data['title'], data['description'], data['category'],
                  location_lat, location_lng, location_address,
                  price, task_id))
            conn.commit()

        print(f"✅ Task {task_id} updated by user {request.user_id}")
        return jsonify({'success': True, 'message': 'Task updated successfully'})
    except Exception as e:
        print(f"❌ Error in update_task: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': 'Error updating task. Please try again.'}), 500


@app.route('/api/tasks/<int:task_id>', methods=['DELETE'])
@require_auth
def delete_task(task_id):
    """Delete a task (only poster can delete)"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT posted_by, status, title FROM tasks WHERE id = {PH}', (task_id,))
            task = cursor.fetchone()

            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404

            task = dict_from_row(task)

            if task['posted_by'] != request.user_id:
                return jsonify({'success': False, 'message': 'Only the task poster can delete this task'}), 403

            if task['status'] in ('completed', 'paid'):
                return jsonify({'success': False, 'message': f"Cannot delete task with status '{task['status']}'"}), 400

            task_title = task.get('title', '')

            # Clean up all FK references then delete the task
            _safe_delete_tasks(cursor, task_id)
            cursor.execute(f'DELETE FROM tasks WHERE id = {PH}', (task_id,))

            # Store cancellation confirmation in DB for the poster
            try:
                cursor.execute('SAVEPOINT sp_del_notif')
                import json as _json_del
                _now_del = datetime.datetime.now(datetime.timezone.utc).isoformat()
                cursor.execute(f'''
                    INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (request.user_id, 'task_cancelled_confirmation',
                      'Task Cancelled \u2705',
                      f'Your task "{task_title}" has been cancelled and removed.',
                      'unread', _json_del.dumps({'type': 'task_cancelled_confirmation'}), _now_del))
                cursor.execute('RELEASE SAVEPOINT sp_del_notif')
            except Exception:
                try: cursor.execute('ROLLBACK TO SAVEPOINT sp_del_notif')
                except Exception: pass

        print(f"✅ Task {task_id} deleted by user {request.user_id}")

        # FCM push — confirm to poster (same pattern as task_posted)
        try:
            send_fcm_to_user(
                request.user_id,
                'Task Cancelled \u2705',
                f'Your task "{task_title}" has been cancelled and removed.',
                data={'type': 'task_cancelled_confirmation', 'task_id': str(task_id)},
                channel='workmate4u_main',
            )
        except Exception as _fcm_del_err:
            print(f'[FCM] \u274c delete_task cancel notify failed: {_fcm_del_err}')

        return jsonify({'success': True, 'message': 'Task deleted successfully'})
    except Exception as e:
        print(f"❌ Error in delete_task: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Error deleting task: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/details', methods=['GET'])
@require_auth
def get_task_details(task_id):
    """Get task details with provider and helper info for Task In Progress page"""
    with get_db() as (cursor, conn):
        # Get task with poster and helper details
        cursor.execute(f'''
            SELECT t.*, 
                   poster.name as provider_name, poster.phone as provider_phone, 
                   poster.rating as provider_rating, poster.tasks_completed as provider_tasks,
                   helper.name as helper_name, helper.phone as helper_phone,
                   helper.rating as helper_rating, helper.tasks_completed as helper_tasks_completed
            FROM tasks t
            LEFT JOIN users poster ON t.posted_by = poster.id
            LEFT JOIN users helper ON t.accepted_by = helper.id
            WHERE t.id = {PH} AND t.status IN ('accepted', 'completed', 'done', 'verify_pending', 'payment_released', 'paid')
        ''', (task_id,))
        task = cursor.fetchone()
        
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404
        
        task = dict_from_row(task)

        # Check who has already rated for this task
        poster_has_rated_helper = False
        helper_has_rated_poster = False
        if task.get('posted_by') and task.get('accepted_by'):
            cursor.execute(f'''
                SELECT rater_id FROM helper_ratings WHERE task_id = {PH} AND rater_id IN ({PH}, {PH})
            ''', (task_id, task['posted_by'], task['accepted_by']))
            raters = {row[0] if isinstance(row, (list, tuple)) else dict_from_row(row).get('rater_id')
                      for row in cursor.fetchall()}
            poster_has_rated_helper = task['posted_by'] in raters
            helper_has_rated_poster = task['accepted_by'] in raters

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
                'accepted_at': task.get('accepted_at'),
                'completed_at': task.get('completed_at'),
                'accepted_by': task.get('accepted_by'),
                'helper_id': task.get('accepted_by'),
                'helper_name': task.get('helper_name'),
                'helper_phone': task.get('helper_phone'),
                'helper_rating': float(task['helper_rating']) if task.get('helper_rating') else None,
                'helper_tasks_completed': task.get('helper_tasks_completed'),
                'poster_has_rated_helper': poster_has_rated_helper,
                'helper_has_rated_poster': helper_has_rated_poster,
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
            # Task Posting Fee removed — poster pays only the task value.
            # poster_deduction = total_task_value * 0.05  # DISABLED
            total_poster_cost = total_task_value  # No posting fee
            _DELIVERY_CATS = {'delivery', 'pickup', 'transport', 'moving'}
            _commission_rate = 0.15 if task.get('category', 'other') in _DELIVERY_CATS else 0.17
            helper_total_deduction = total_task_value * _commission_rate
            helper_net_receives = total_task_value - helper_total_deduction
            
            print(f"\n💵 AMOUNTS (for notification):")
            print(f"   Total Task Value: ₹{total_task_value:.2f}")
            print(f"   Poster will pay: ₹{total_poster_cost:.2f} (no posting fee)")
            print(f"   Helper commission rate: {_commission_rate*100:.0f}%")
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

            # Send email notification to poster
            try:
                notify_task_completed_email(poster_id, helper_name, task['title'], task_amount, service_charge, 0, total_poster_cost, task_id)
            except Exception:
                pass

            # FCM push — tell poster to pay
            try:
                send_fcm_to_user(
                    poster_id,
                    'Task Completed! 💰 Pay Now',
                    f'{helper_name} completed "{task["title"]}". Please pay ₹{total_poster_cost:.2f}.',
                    data={'type': 'task_completed', 'task_id': str(task_id), 'amount': str(round(total_poster_cost, 2))},
                    channel='workmate4u_payment',
                )
            except Exception:
                pass

            # FCM push — tell helper to wait for payment
            try:
                send_fcm_to_user(
                    helper_id,
                    'Task Done! ✅ Awaiting Payment',
                    f'You completed "{task["title"]}". Waiting for poster to pay ₹{helper_net_receives:.2f}.',
                    data={'type': 'task_completed_helper', 'task_id': str(task_id)},
                    channel='workmate4u_main',
                )
            except Exception:
                pass
            
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


@app.route('/api/tasks/<int:task_id>/verify', methods=['POST'])
@require_auth
def verify_task(task_id):
    """
    NEW FLOW — Step 1: Helper clicks 'Verify Task Done'.
    - Sets task status: accepted → verify_pending
    - Sends 'Verify & Pay Now' notification to poster
    - Sends confirmation notification to helper
    """
    try:
        _ensure_verify_columns()
        with get_db() as (cursor, conn):
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

            # Calculate amounts for notification
            # poster_deduction = total_task_value * 0.05  # DISABLED — posting fee removed
            total_poster_cost = total_task_value  # No posting fee
            _DELIVERY_CATS = {'delivery', 'pickup', 'transport', 'moving'}
            _commission_rate = 0.15 if task.get('category', 'other') in _DELIVERY_CATS else 0.17
            helper_total_deduction = total_task_value * _commission_rate
            helper_net_receives = total_task_value - helper_total_deduction

            # Update task status to verify_pending
            cursor.execute(f'''
                UPDATE tasks SET status = 'verify_pending', verified_at = {PH}
                WHERE id = {PH}
            ''', (now, task_id))

            # Get helper name
            cursor.execute(f'SELECT name FROM users WHERE id = {PH}', (helper_id,))
            helper_row = cursor.fetchone()
            helper_name = (dict_from_row(helper_row) if helper_row else {}).get('name', 'Your helper')

            import json
            # Notify poster: Verify & Pay Now
            poster_action = json.dumps({
                'type': 'verify_and_pay',
                'label': '✅ Verify & Pay Now',
                'taskId': task_id,
                'amount': round(total_poster_cost, 2)
            })
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (poster_id, task_id, 'verify_and_pay',
                  'Task Verified! ✅ Pay Now',
                  f'{helper_name} has verified your task "{task["title"]}" is done. Please pay ₹{total_poster_cost:.2f} to release payment.',
                  'unread', poster_action, now))

            # Notify helper: waiting for poster
            helper_action = json.dumps({
                'type': 'task',
                'label': '👁️ View Status',
                'taskId': task_id
            })
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (helper_id, task_id, 'task_verify_sent',
                  'Verification Sent! ⏳',
                  f'You marked "{task["title"]}" as done. Waiting for poster to verify and pay ₹{helper_net_receives:.2f}.',
                  'unread', helper_action, now))

        print(f"✅ Task {task_id} verified by helper {helper_id}. Status: accepted → verify_pending")

        # FCM push — tell poster to verify and pay
        try:
            send_fcm_to_user(
                poster_id,
                'Verify & Pay Now ✅',
                f'{helper_name} verified "{task["title"]}" is done. Pay ₹{total_poster_cost:.2f} to release payment.',
                data={'type': 'verify_and_pay', 'task_id': str(task_id), 'amount': str(round(total_poster_cost, 2))},
                channel='workmate4u_payment',
            )
        except Exception:
            pass

        # FCM push — tell helper verification is sent
        try:
            send_fcm_to_user(
                helper_id,
                'Verification Sent! ⏳',
                f'You marked "{task["title"]}" as done. Waiting for poster to pay ₹{helper_net_receives:.2f}.',
                data={'type': 'task_verify_sent', 'task_id': str(task_id)},
                channel='workmate4u_main',
            )
        except Exception:
            pass

        return jsonify({
            'success': True,
            'message': 'Verification sent! Waiting for poster to pay.',
            'taskId': task_id,
            'status': 'verify_pending',
            'helperWillReceive': round(helper_net_receives, 2),
            'totalPosterCost': round(total_poster_cost, 2)
        }), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Failed to verify task: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/mark-completed', methods=['POST'])
@require_auth
def mark_task_completed(task_id):
    """
    NEW FLOW — Step 3: Helper clicks 'Mark as Completed' after receiving payment.
    - Task status: payment_released → completed (final)
    - Increments tasks_completed + total_earnings for helper
    - Returns showRatingPopup flag to trigger optional rating
    - Task is deleted after 48 hours (via helper_final_completed_at)
    """
    try:
        _ensure_verify_columns()
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT * FROM tasks WHERE id = {PH} AND accepted_by = {PH} AND status IN ({PH}, {PH})
            ''', (task_id, request.user_id, 'payment_released', 'paid'))
            task = cursor.fetchone()
            if not task:
                return jsonify({'success': False, 'message': 'Task not found or payment not yet released'}), 404

            task = dict_from_row(task)
            task_amount = float(task['price'])
            # Only apply service_charge for delivery-type tasks (new pricing model: non-delivery sc=0)
            _DELIVERY_CATS = {'delivery', 'pickup', 'transport', 'moving'}
            _category = task.get('category', 'other')
            _raw_sc = float(task.get('service_charge', 0))
            service_charge = _raw_sc if _category in _DELIVERY_CATS else 0.0
            total_task_value = task_amount + service_charge
            _commission_rate = 0.15 if _category in _DELIVERY_CATS else 0.17
            helper_total_deduction = total_task_value * _commission_rate
            helper_earnings = total_task_value - helper_total_deduction
            helper_id = request.user_id
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()

            # Set final completed status with 48h expiry anchor.
            # Use 'done' (not 'completed') so /user/tasks can return this in
            # a separate completedTasks field and the mobile moves the task to
            # the Completed tab — even after an app restart.
            cursor.execute(f'''
                UPDATE tasks SET status = 'done', helper_final_completed_at = {PH}
                WHERE id = {PH}
            ''', (now, task_id))

            # Increment tasks_completed and total_earnings for helper
            cursor.execute(f'''
                UPDATE users
                SET tasks_completed = COALESCE(tasks_completed, 0) + 1,
                    total_earnings = COALESCE(total_earnings, 0) + {PH}
                WHERE id = {PH}
            ''', (helper_earnings, helper_id))

            # Final completion notification for helper (DB)
            import json
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (helper_id, task_id, 'task_final_completed',
                  'Task Completed! 🏆',
                  f'You\'ve successfully completed "{task["title"]}" and earned ₹{helper_earnings:.2f}. Great work!',
                  'unread', json.dumps({'type': 'task', 'taskId': task_id}), now))

            # Final completion notification for poster (DB)
            poster_id = task.get('posted_by')
            if poster_id:
                cursor.execute(f'''
                    INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (poster_id, task_id, 'task_final_completed_poster',
                      'All Done! ✅',
                      f'Your task "{task["title"]}" has been fully completed.',
                      'unread', json.dumps({'type': 'task', 'taskId': task_id}), now))

        print(f"✅ Task {task_id} final-completed by helper {helper_id}. Earned ₹{helper_earnings:.2f}")

        # FCM push — tell helper they finished and earned
        try:
            send_fcm_to_user(
                helper_id,
                'Task Complete! 🏆',
                f'You\'ve fully completed "{task["title"]}" and earned ₹{helper_earnings:.2f}. Awesome work!',
                data={'type': 'task_final_completed', 'task_id': str(task_id),
                      'earnings': str(round(helper_earnings, 2))},
                channel='workmate4u_payment',
            )
        except Exception:
            pass

        # FCM push — tell poster the task is fully done
        poster_id = task.get('posted_by')
        if poster_id:
            try:
                send_fcm_to_user(
                    poster_id,
                    'All Done! ✅',
                    f'Your task "{task["title"]}" has been fully completed by the helper.',
                    data={'type': 'task_final_completed_poster', 'task_id': str(task_id)},
                    channel='workmate4u_main',
                )
            except Exception:
                pass

        return jsonify({
            'success': True,
            'message': 'Task completed! Great work!',
            'taskId': task_id,
            'status': 'completed',
            'helperEarnings': round(helper_earnings, 2),
            'showRatingPopup': True
        }), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Failed to mark completed: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/rate', methods=['POST'])
@require_auth
def rate_task_poster(task_id):
    """
    Bidirectional rating after task completion.
    Helper rates poster, OR poster rates helper — determined by who calls it.
    Body: {rating: int(1-5), review/comment: string (optional)}
    """
    try:
        _ensure_helper_ratings_review()
        data = request.get_json() or {}
        rating = data.get('rating')
        # Accept both 'review' and 'comment' field names
        review = (data.get('review') or data.get('comment') or '').strip()[:500]

        try:
            rating = int(rating)
            if rating < 1 or rating > 5:
                raise ValueError()
        except (TypeError, ValueError):
            return jsonify({'success': False, 'message': 'Rating must be 1–5'}), 400

        with get_db() as (cursor, conn):
            # Fetch the task — caller must be poster or helper, task must be in a terminal status
            cursor.execute(f'''
                SELECT id, title, posted_by, accepted_by, status FROM tasks
                WHERE id = {PH} AND status IN ({PH}, {PH}, {PH}, {PH}, {PH})
                  AND (posted_by = {PH} OR accepted_by = {PH})
            ''', (task_id, 'completed', 'done', 'payment_released', 'paid', 'verified',
                  request.user_id, request.user_id))
            task = cursor.fetchone()
            if not task:
                return jsonify({'success': False, 'message': 'Task not found or not eligible for rating'}), 404

            task = dict_from_row(task)
            rater_id = request.user_id
            poster_id = task['posted_by']
            helper_id = task['accepted_by']

            # Determine who is rating whom
            if rater_id == poster_id:
                # Poster rates helper
                rated_id = helper_id
                if not rated_id:
                    return jsonify({'success': False, 'message': 'No helper to rate'}), 400
            elif rater_id == helper_id:
                # Helper rates poster
                rated_id = poster_id
            else:
                return jsonify({'success': False, 'message': 'You are not a participant of this task'}), 403

            task_title = task.get('title', '')
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()

            # Check if already rated (one rating per rater per task)
            cursor.execute(f'SELECT id FROM helper_ratings WHERE task_id = {PH} AND rater_id = {PH}', (task_id, rater_id))
            if cursor.fetchone():
                return jsonify({'success': False, 'message': 'You already rated this task'}), 400

            # Insert rating (store task_title to survive task deletion)
            cursor.execute(f'''
                INSERT INTO helper_ratings (task_id, rater_id, rated_id, rating, review, task_title, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (task_id, rater_id, rated_id, rating, review, task_title, now))

            # Update rated user's average rating
            cursor.execute(f'''
                SELECT AVG(rating) as avg_r FROM helper_ratings WHERE rated_id = {PH}
            ''', (rated_id,))
            avg_row = dict_from_row(cursor.fetchone())
            avg_r = float(avg_row['avg_r'] or 5.0)
            cursor.execute(f'UPDATE users SET rating = {PH} WHERE id = {PH}', (round(avg_r, 2), rated_id))

        return jsonify({'success': True, 'message': 'Rating submitted. Thank you!'}), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Failed to submit rating: {str(e)}'}), 500


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
                return jsonify({
                    'success': False,
                    'message': 'Payment service temporarily unavailable. Please try again later.'
                }), 503
    
    except Exception as e:
        print(f"❌ Error creating payment order: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'message': f'Server error: {str(e)}'}), 500


@app.route('/api/tasks/<int:task_id>/pay-helper', methods=['POST'])
@require_auth
def pay_helper(task_id):
    """
    Poster pays for verified task (NEW FLOW) or completed task (legacy flow).
    NEW FLOW: status verify_pending → payment_released (helper must then click Mark as Completed)
    LEGACY FLOW: status completed → paid (kept for backward compat)
    - Deduct helper commission (17% general / 15% delivery) from helper wallet
    - Credit helper with task amount minus commission
    - Send platform income to Razorpay UPI
    - Task Posting Fee: DISABLED (0%)
    """
    print(f"\n{'='*60}")
    print(f"💰 Payment Processing: Task {task_id}")
    print(f"Poster (payer): {request.user_id}")
    print('='*60)

    try:
        _ensure_verify_columns()
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

            # Accept verify_pending (new flow) OR completed (legacy flow)
            is_new_flow = task['status'] == 'verify_pending'
            if task['status'] not in ('verify_pending', 'completed'):
                print(f"❌ Task status not payable (status: {task['status']})")
                return jsonify({'success': False, 'message': 'Task must be verified or completed first'}), 400

            # Verify the poster is the one paying
            if task['posted_by'] != request.user_id:
                print(f"❌ Only task poster can pay (poster: {task['posted_by']}, requester: {request.user_id})")
                return jsonify({'success': False, 'message': 'Only task poster can pay'}), 403

            helper_id = task['accepted_by']
            task_amount = float(task['price'])
            # Only apply service_charge for delivery-type tasks (new pricing model: non-delivery sc=0)
            _DELIVERY_CATS = {'delivery', 'pickup', 'transport', 'moving'}
            _category = task.get('category', 'other')
            _raw_sc = float(task.get('service_charge', 0))
            service_charge = _raw_sc if _category in _DELIVERY_CATS else 0.0
            total_task_value = task_amount + service_charge
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()

            # Commission: 15% for delivery/pickup/transport/moving, 17% for all others.
            _commission_rate = 0.15 if _category in _DELIVERY_CATS else 0.17
            helper_total_deduction = total_task_value * _commission_rate
            # helper_commission = total_task_value * 0.10  # DISABLED
            # helper_fee = total_task_value * 0.02  # DISABLED
            # poster_deduction = total_task_value * 0.05  # DISABLED — posting fee removed
            poster_deduction = 0  # No posting fee
            
            print(f"\n💵 PAYMENT BREAKDOWN:")
            print(f"   Base Task Price: ₹{task_amount:.2f}")
            print(f"   Service Charge ({task.get('category', 'other')}): ₹{service_charge:.2f}")
            print(f"   ✨ TOTAL TASK VALUE: ₹{total_task_value:.2f}")
            print(f"   Commission Rate ({task.get('category','other')}): {_commission_rate*100:.0f}%")
            print(f"   Helper Total Deduction: ₹{helper_total_deduction:.2f}")
            print(f"   Poster Fee: ₹0.00 (disabled)")
            
            # ===== CHECK POSTER BALANCE FIRST =====
            poster_wallet = get_or_create_wallet(request.user_id)
            poster_balance = float(poster_wallet.get('balance', 0))
            total_poster_cost = total_task_value  # No posting fee
            
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
            print(f"   Total deduction: -₹{total_poster_cost:.2f} (no posting fee)")
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
            # Posting fee transaction DISABLED — poster_deduction = 0
            
            # ===== HELPER WALLET OPERATIONS (credit after poster deducted) =====
            helper_wallet = get_or_create_wallet(helper_id)
            helper_balance = float(helper_wallet.get('balance', 0))
            
            helper_balance_after_credit = helper_balance + total_task_value
            helper_new_balance = helper_balance_after_credit - helper_total_deduction
            
            print(f"\n👥 Helper Wallet Operations:")
            print(f"   Current balance: ₹{helper_balance:.2f}")
            print(f"   Adding task earning: +₹{total_task_value:.2f}")
            print(f"   Deducting commission ({_commission_rate*100:.0f}%): -₹{helper_total_deduction:.2f}")
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
                f'Platform commission ({_commission_rate*100:.0f}%): ₹{helper_total_deduction:.2f}',
                f'task-commission-{task_id}', task_id, now
            ))
            
            # ===== COMPANY WALLET OPERATIONS =====
            # Company receives: Helper commission only (posting fee disabled)
            total_platform_income = helper_total_deduction  # no poster_deduction
            
            company_wallet = get_or_create_wallet('1')
            company_balance = float(company_wallet.get('balance', 0))
            company_new_balance = company_balance + total_platform_income
            
            print(f"\n🏢 Company/Platform Income:")
            print(f"   Helper Commission ({_commission_rate*100:.0f}%): ₹{helper_total_deduction:.2f}")
            print(f"   Poster Fee: ₹0.00 (disabled)")
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
                f'Helper commission ({_commission_rate*100:.0f}%) from task #{task_id}: ₹{helper_total_deduction:.2f}',
                f'task-commission-{task_id}', task_id, now
            ))
            # Posting fee company transaction DISABLED
            
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

            helper_earnings = total_task_value - helper_total_deduction

            if is_new_flow:
                # NEW FLOW: payment_released — helper still needs to click "Mark as Completed"
                cursor.execute(f'''
                    UPDATE tasks SET status = 'payment_released', payment_released_at = {PH}
                    WHERE id = {PH}
                ''', (now, task_id))
                # tasks_completed / total_earnings updated in /mark-completed instead
            else:
                # LEGACY FLOW: mark as paid immediately (old complete → pay path)
                cursor.execute(f'''
                    UPDATE tasks SET status = 'paid', paid_at = {PH}
                    WHERE id = {PH}
                ''', (now, task_id))
                cursor.execute(f'''
                    UPDATE users
                    SET tasks_completed = COALESCE(tasks_completed, 0) + 1,
                        total_earnings = COALESCE(total_earnings, 0) + {PH}
                    WHERE id = {PH}
                ''', (helper_earnings, helper_id))

            # Update poster's tasks_posted count
            cursor.execute(f'''
                UPDATE users
                SET tasks_posted = (
                    SELECT COUNT(*) FROM tasks WHERE posted_by = {PH} AND status IN ('accepted','completed','paid','verify_pending','payment_released')
                )
                WHERE id = {PH}
            ''', (request.user_id, request.user_id))

            # Clear payment / verify notification for poster
            cursor.execute(f'''
                DELETE FROM notifications
                WHERE task_id = {PH} AND user_id = {PH} AND notification_type IN ('task_completed', 'verify_and_pay')
            ''', (task_id, request.user_id))

            import json
            # Full breakdown payload — used by the frontend "Payment Received" popup.
            _breakdown_base = {
                'taskId': task_id,
                'taskTitle': task['title'],
                'taskAmount': round(task_amount, 2),
                'serviceCharge': round(service_charge, 2),
                'totalTaskValue': round(total_task_value, 2),
                'helperEarnings': round(helper_earnings, 2),
                'commission': round(helper_total_deduction, 2),
                'commissionPct': round(_commission_rate * 100),
                'helperNewBalance': round(helper_new_balance, 2),
            }
            if is_new_flow:
                # NEW FLOW: Tell helper to mark as completed
                helper_notif_data = json.dumps({
                    **_breakdown_base,
                    'type': 'mark_complete',
                    'label': '🎉 Mark as Completed',
                    'amount': round(helper_earnings, 2)
                })
                cursor.execute(f'''
                    INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (helper_id, task_id, 'payment_released',
                      'Payment Released! 🎉 Mark as Completed',
                      f'₹{helper_earnings:.2f} has been released to your wallet for "{task["title"]}". Tap to mark the task as completed.',
                      'unread', helper_notif_data, now))
            else:
                # LEGACY FLOW: Payment received
                cursor.execute(f'''
                    INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (helper_id, task_id, 'payment_received',
                      'Payment Received! 💰',
                      f'You received ₹{helper_earnings:.2f} for completing "{task["title"]}".',
                      'unread', json.dumps({
                          **_breakdown_base,
                          'type': 'payment_received',
                          'label': '💰 View Breakdown',
                          'amount': round(helper_earnings, 2)
                      }), now))

            # Create "Payment Done" notification for poster
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, task_id, 'payment_done',
                  'Payment Done! ✅',
                  f'You paid ₹{total_poster_cost:.2f} for "{task["title"]}". Payment released to helper.',
                  'unread', json.dumps({'type': 'success', 'taskId': task_id, 'amount': total_poster_cost}), now))

            conn.commit()

            final_status = 'payment_released' if is_new_flow else 'paid'
            print(f"\n✅ PAYMENT COMPLETE!")
            print(f"   Task status: {task['status']} → {final_status}")
            print(f"   Helper final balance: ₹{helper_new_balance:.2f}")
            print(f"   Poster final balance: ₹{poster_new_balance:.2f}")
            print(f"   Company final balance: ₹{company_new_balance:.2f}")
            print('='*60 + "\n")

            # Send email notification to helper
            try:
                notify_payment_received_email(helper_id, task['title'], helper_earnings,
                    task_amount=task_amount, service_charge=service_charge,
                    commission=helper_total_deduction)
            except Exception:
                pass

            # FCM push — tell helper payment released / received
            try:
                if is_new_flow:
                    send_fcm_to_user(
                        helper_id,
                        'Payment Released! 🎉',
                        f'₹{helper_earnings:.2f} released for "{task["title"]}". Tap to mark task as completed.',
                        data={'type': 'payment_released', 'task_id': str(task_id), 'amount': str(round(helper_earnings, 2))},
                        channel='workmate4u_payment',
                    )
                else:
                    send_fcm_to_user(
                        helper_id,
                        'Payment Received! 💰',
                        f'You received ₹{helper_earnings:.2f} for "{task["title"]}".',
                        data={'type': 'payment_received', 'task_id': str(task_id), 'amount': str(round(helper_earnings, 2))},
                        channel='workmate4u_payment',
                    )
            except Exception:
                pass

            # FCM push — confirm payment to poster
            try:
                send_fcm_to_user(
                    request.user_id,
                    'Payment Done! ✅',
                    f'You paid ₹{total_poster_cost:.2f} for "{task["title"]}". Helper has been notified.',
                    data={'type': 'payment_done', 'task_id': str(task_id), 'amount': str(round(total_poster_cost, 2))},
                    channel='workmate4u_payment',
                )
            except Exception:
                pass

            return jsonify({
                'success': True,
                'message': 'Payment successful! Helper has been notified.' if is_new_flow else 'Payment successful and funds transferred',
                'taskId': task_id,
                'status': final_status,
                'amount': task_amount,
                'serviceCharge': service_charge,
                'totalTaskValue': total_task_value,
                'helperEarnings': round(helper_earnings, 2),
                'helperCommission': helper_total_deduction,
                'posterFee': poster_deduction,
                'platformIncome': total_platform_income,
                'helperNewBalance': helper_new_balance,
                'posterNewBalance': poster_new_balance,
                'companyNewBalance': company_new_balance,
                'upiTransferStatus': upi_transfer_result.get('transfer_status', 'initiated'),
                'requiresMarkComplete': is_new_flow
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
    # Throttle the 48h cleanup: run at most once every 5 minutes per process
    global _last_user_tasks_cleanup
    _run_48h_cleanup = False
    try:
        import datetime as _dt_utc
        _now_utc = _dt_utc.datetime.now(_dt_utc.timezone.utc)
        if _last_user_tasks_cleanup is None or (_now_utc - _last_user_tasks_cleanup).total_seconds() > 300:
            _last_user_tasks_cleanup = _now_utc
            _run_48h_cleanup = True
    except Exception:
        pass

    with get_db() as (cursor, conn):
        if _run_48h_cleanup:
            # --- 48-hour cleanup: wipe paid tasks older than 48 hours ---
            try:
                if config.USE_POSTGRES:
                    cutoff_expr = "NOW() - INTERVAL '48 hours'"
                else:
                    cutoff_expr = "datetime('now', '-48 hours')"
                cursor.execute(f"SELECT id FROM tasks WHERE status = 'paid' AND paid_at < {cutoff_expr}")
                old_task_rows = cursor.fetchall()
                old_ids = [str(r['id'] if isinstance(r, dict) else r[0]) for r in old_task_rows]
                if old_ids:
                    _safe_delete_tasks(cursor, old_ids)
                    cursor.execute(f"DELETE FROM tasks WHERE id IN ({','.join(old_ids)})")
                    conn.commit()
            except Exception as cleanup_err:
                print(f'[/api/user/tasks] 48h cleanup skipped: {cleanup_err}')
                try:
                    conn.rollback()
                except Exception:
                    pass

            # --- 48-hour cleanup: also wipe completed tasks (new flow) older than 48 hours ---
            try:
                if config.USE_POSTGRES:
                    cutoff_expr = "NOW() - INTERVAL '48 hours'"
                else:
                    cutoff_expr = "datetime('now', '-48 hours')"
                cursor.execute(f"SELECT id FROM tasks WHERE status = 'done' AND helper_final_completed_at IS NOT NULL AND helper_final_completed_at < {cutoff_expr}")
                completed_old_rows = cursor.fetchall()
                completed_old_ids = [str(r['id'] if isinstance(r, dict) else r[0]) for r in completed_old_rows]
                if completed_old_ids:
                    _safe_delete_tasks(cursor, completed_old_ids)
                    cursor.execute(f"DELETE FROM tasks WHERE id IN ({','.join(completed_old_ids)})")
                    conn.commit()
            except Exception as cleanup_err2:
                print(f'[/api/user/tasks] completed 48h cleanup skipped: {cleanup_err2}')
                try:
                    conn.rollback()
                except Exception:
                    pass

        # Posted tasks — exclude tasks removed/flagged by admin/AI (those are deleted or hidden)
        cursor.execute(f'''
            SELECT t.*, u.name as helper_name, u.phone as helper_phone,
                   u.rating as helper_rating, u.tasks_completed as helper_tasks_completed
            FROM tasks t
            LEFT JOIN users u ON t.accepted_by = u.id
            WHERE t.posted_by = {PH} AND t.status NOT IN ('removed', 'flagged', 'suspicious')
            ORDER BY t.posted_at DESC
        ''', (request.user_id,))
        posted = [dict_from_row(t) for t in cursor.fetchall()]

        # Accepted tasks — include all active statuses + new flow statuses + legacy paid.
        # Exclude tasks where helper_final_completed_at is set (legacy status='completed'
        # tasks already fully finished) — those go into completedTasks instead.
        cursor.execute(f'''
            SELECT t.*, u.name as poster_name, u.phone as poster_phone,
                   u.email as poster_email, u.id as poster_user_id,
                   u.rating as poster_rating
            FROM tasks t
            LEFT JOIN users u ON t.posted_by = u.id
            WHERE t.accepted_by = {PH}
              AND t.status IN ('accepted', 'completed', 'paid', 'verify_pending', 'payment_released')
              AND (t.helper_final_completed_at IS NULL OR t.status != 'completed')
            ORDER BY t.accepted_at DESC
        ''', (request.user_id,))
        accepted = [dict_from_row(t) for t in cursor.fetchall()]

        # Completed tasks — helper clicked final "Mark as Completed".
        # Includes new flow (status='done') AND legacy tasks that were already
        # fully finished (status='completed' + helper_final_completed_at set).
        cursor.execute(f'''
            SELECT t.*, u.name as poster_name, u.phone as poster_phone,
                   u.email as poster_email, u.id as poster_user_id,
                   u.rating as poster_rating
            FROM tasks t
            LEFT JOIN users u ON t.posted_by = u.id
            WHERE t.accepted_by = {PH}
              AND (t.status = 'done'
                   OR (t.status = 'completed' AND t.helper_final_completed_at IS NOT NULL))
            ORDER BY t.helper_final_completed_at DESC NULLS LAST
        ''', (request.user_id,))
        completed = [dict_from_row(t) for t in cursor.fetchall()]

        # Task IDs the current user has already rated (to mark UI as "rated")
        cursor.execute(f'SELECT task_id FROM helper_ratings WHERE rater_id = {PH}', (request.user_id,))
        rated_task_ids = [str(row['task_id'] if isinstance(row, dict) else row[0])
                          for row in cursor.fetchall()]

    return jsonify({
        'success': True,
        'postedTasks': posted,
        'acceptedTasks': accepted,
        'completedTasks': completed,
        'ratedTaskIds': rated_task_ids
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


@app.route('/api/user/active-task', methods=['GET'])
@require_auth
def get_user_active_task():
    """Return the current user's active accepted task (as helper), if any.
    Used by the browse page to enforce the one-task-at-a-time rule."""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT id, title, price, category, accepted_at
                FROM tasks WHERE accepted_by = {PH} AND status = {PH}
                LIMIT 1
            ''', (request.user_id, 'accepted'))
            task = cursor.fetchone()
            if task:
                task = dict_from_row(task)
                return jsonify({
                    'success': True,
                    'hasActiveTask': True,
                    'task': {
                        'id': task['id'],
                        'title': task['title'],
                        'price': float(task['price']),
                        'category': task['category'],
                        'acceptedAt': task['accepted_at']
                    }
                })
            return jsonify({'success': True, 'hasActiveTask': False, 'task': None})
    except Exception as e:
        print(f'❌ Error in get_user_active_task: {e}')
        return jsonify({'success': False, 'message': str(e)}), 500


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
                'address': task.get('drop_location_address') or task['location_address'] or 'Delivery Location',
                'lat': float(task['drop_location_lat']) if task.get('drop_location_lat') else (float(task['location_lat']) if task['location_lat'] else None),
                'lng': float(task['drop_location_lng']) if task.get('drop_location_lng') else (float(task['location_lng']) if task['location_lng'] else None)
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
        return wallet_dict


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
    old_balance = float(wallet['balance'])
    new_balance = old_balance + total_credit
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    wallet_id = wallet.get('id')
    
    # Calculate how much of this top-up covers negative (debt) balance
    debt_recovered = 0
    if old_balance < 0:
        debt_recovered = min(amount, abs(old_balance))
    
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
        
        # Credit debt recovery to company wallet as revenue
        if debt_recovered > 0:
            company_wallet = get_or_create_wallet('1')
            company_balance = float(company_wallet.get('balance', 0))
            company_new_balance = company_balance + debt_recovered
            
            cursor.execute(f'''
                UPDATE wallets
                SET balance = {PH}, total_earned = total_earned + {PH}, updated_at = {PH}
                WHERE user_id = {PH}
            ''', (company_new_balance, debt_recovered, now, '1'))
            
            cursor.execute(f'''
                INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, reference_id, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (company_wallet.get('id'), '1', 'penalty', debt_recovered, company_new_balance,
                  f'Debt recovery from user {request.user_id} (topped up ₹{amount}, covered ₹{debt_recovered:.2f} debt)',
                  f'debt-recovery-{request.user_id}', now))
            
            print(f"💰 Debt recovery: ₹{debt_recovered:.2f} from user {request.user_id} credited to company wallet")
        
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

    # FCM push — notify user their wallet has been topped up
    try:
        cashback_msg_fcm = f' (includes ₹{cashback:.2f} cashback!)' if cashback > 0 else ''
        print(f'[FCM] Sending wallet_topup to user {request.user_id}')
        send_fcm_to_user(
            request.user_id,
            'Wallet Topped Up! 💰',
            f'₹{amount:.2f} added to your wallet{cashback_msg_fcm}. New balance: ₹{new_balance:.2f}',
            data={'type': 'wallet_topup', 'amount': str(amount), 'new_balance': str(new_balance)},
            channel='workmate4u_payment',
        )
    except Exception as _fcm_wallet_err:
        print(f'[FCM] ❌ wallet_topup FCM failed: {_fcm_wallet_err}')

    debt_cleared = new_balance >= 0
    return jsonify({
        'success': True,
        'message': f'₹{amount} added successfully' + (f' + ₹{cashback:.2f} cashback!' if cashback > 0 else ''),
        'newBalance': new_balance,
        'cashback': cashback,
        'debtSuspended': new_balance < 0,
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
        
        # Revenue is NOT credited here — penalty may push balance negative.
        # Actual revenue is recorded when the user tops up their negative balance
        # (debt recovery in add_money_to_wallet).
        
        conn.commit()
    
    debt_suspended = new_balance < 0
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
        'debtSuspended': new_balance < 0
    })


@app.route('/api/wallet/transactions', methods=['GET'])
@require_auth
def get_transactions():
    """Get wallet transaction history"""
    page = int(request.args.get('page', 1))
    limit = min(int(request.args.get('limit', 20)), 100)  # Cap at 100
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
    
    # Eligibility gate: KYC approved is mandatory. Phone verification is optional
    # (skipped while we evaluate SMS providers).
    user = get_user_by_id(request.user_id)
    if not user:
        return jsonify({'success': False, 'message': 'User not found'}), 404
    if (user.get('kyc_status') or 'none') not in ('approved', 'verified'):
        return jsonify({
            'success': False,
            'message': 'Complete KYC verification before withdrawing. Go to Profile → Identity Verification.',
            'requiresVerification': 'kyc',
            'kycStatus': user.get('kyc_status') or 'none'
        }), 403

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

    # Push notification confirming withdrawal request
    try:
        send_push_to_user(
            request.user_id,
            'Withdrawal Requested 🏦',
            f'₹{amount:.2f} will be transferred to your bank account within 24 hours.',
            '/wallet.html'
        )
    except Exception:
        pass
    try:
        send_fcm_to_user(
            request.user_id,
            'Withdrawal Requested 🏦',
            f'₹{amount:.2f} withdrawal submitted. Transfer within 24 hours.',
            data={'type': 'withdrawal_requested', 'amount': str(amount)},
            channel='workmate4u_payment',
        )
    except Exception as _fcm_wdl_req_err:
        print(f'[FCM] ❌ withdrawal_requested FCM failed: {_fcm_wdl_req_err}')

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
# ADMIN: PROCESS WITHDRAWAL (approve / reject)
# ========================================

@app.route('/api/admin/withdrawals', methods=['GET'])
@require_admin
def admin_list_withdrawals():
    """List withdrawal requests for admin panel."""
    status_filter = request.args.get('status', '').strip().lower()
    PH = get_placeholder()
    try:
        with get_db() as (cursor, conn):
            if status_filter:
                cursor.execute(
                    f"""SELECT wr.id, wr.user_id, wr.amount, wr.account_number, wr.ifsc_code,
                               wr.bank_name, wr.status, wr.created_at, wr.note,
                               u.name AS user_name, u.email
                        FROM withdrawal_requests wr
                        LEFT JOIN users u ON u.id = wr.user_id
                        WHERE wr.status = {PH}
                        ORDER BY wr.created_at DESC LIMIT 100""",
                    (status_filter,)
                )
            else:
                cursor.execute(
                    """SELECT wr.id, wr.user_id, wr.amount, wr.account_number, wr.ifsc_code,
                               wr.bank_name, wr.status, wr.created_at, wr.note,
                               u.name AS user_name, u.email
                        FROM withdrawal_requests wr
                        LEFT JOIN users u ON u.id = wr.user_id
                        ORDER BY wr.created_at DESC LIMIT 100"""
                )
            rows = cursor.fetchall()
            cols = [d[0] for d in cursor.description]
            withdrawals = [dict(zip(cols, r)) for r in rows]

            cursor.execute("SELECT COUNT(*) FROM withdrawal_requests WHERE status='pending'")
            pending_count = cursor.fetchone()[0]

        return jsonify({'success': True, 'withdrawals': withdrawals, 'pending_count': pending_count})
    except Exception as e:
        logger.error(f'admin_list_withdrawals error: {e}')
        return jsonify({'success': False, 'message': 'Failed to load withdrawals'}), 500


@app.route('/api/admin/withdrawal/process', methods=['POST'])
@require_admin
def admin_process_withdrawal():
    """Admin approves or rejects a user withdrawal request."""
    data = request.get_json() or {}
    withdrawal_id = data.get('withdrawal_id')
    action = (data.get('action') or '').strip().lower()   # 'approve' or 'reject'
    note = (data.get('note') or '').strip()

    if not withdrawal_id or action not in ('approve', 'reject'):
        return jsonify({'success': False, 'message': 'withdrawal_id and action (approve|reject) are required'}), 400

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()

    with get_db() as (cursor, conn):
        cursor.execute(f'SELECT * FROM withdrawal_requests WHERE id = {PH}', (withdrawal_id,))
        wr = dict_from_row(cursor.fetchone())
        if not wr:
            return jsonify({'success': False, 'message': 'Withdrawal not found'}), 404
        if wr['status'] != 'pending':
            return jsonify({'success': False, 'message': f'Cannot process — status is already {wr["status"]}'}), 400

        user_id = str(wr['user_id'])
        amount = float(wr['amount'])

        if action == 'approve':
            new_status = 'completed'
            cursor.execute(f'''
                UPDATE withdrawal_requests SET status = {PH}, updated_at = {PH}, admin_note = {PH}
                WHERE id = {PH}
            ''', (new_status, now, note or 'Approved by admin', withdrawal_id))

            # Create notification
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 'payment_received',
                  '💰 Withdrawal Processed!',
                  f'Your withdrawal of ₹{amount:.0f} has been processed. It will reach your bank in 1–3 business days.',
                  'unread', now))

        else:  # reject
            new_status = 'rejected'
            # Refund amount back to wallet
            wallet = get_or_create_wallet(user_id)
            new_bal = float(wallet['balance']) + amount
            cursor.execute(f'UPDATE wallets SET balance = {PH}, updated_at = {PH} WHERE user_id = {PH}',
                           (new_bal, now, user_id))
            cursor.execute(f'''
                INSERT INTO wallet_transactions
                (wallet_id, user_id, type, amount, balance_after, description, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (wallet['id'], user_id, 'refund', amount, new_bal,
                  f'Withdrawal rejected — refunded. {note}'.strip(), now))
            cursor.execute(f'''
                UPDATE withdrawal_requests SET status = {PH}, updated_at = {PH}, admin_note = {PH}
                WHERE id = {PH}
            ''', (new_status, now, note or 'Rejected by admin', withdrawal_id))

            # Create notification
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 'wallet_topup',
                  '↩ Withdrawal Rejected',
                  f'Your withdrawal of ₹{amount:.0f} was rejected and refunded to your wallet. {note}'.strip(),
                  'unread', now))

        log_admin_action(cursor, request.user_id, f'withdrawal_{action}', 'withdrawal_requests',
                         withdrawal_id, f'{action.capitalize()} ₹{amount} withdrawal. {note}'.strip(),
                         request.remote_addr)
        conn.commit()

    # Email + push notification (non-blocking)
    try:
        notify_withdrawal_processed_email(user_id, amount, new_status)
    except Exception as e:
        print(f'[withdrawal] email error: {e}')
    try:
        push_msg = (f'₹{amount:.0f} withdrawal processed — arriving in 1–3 days 🏦'
                    if action == 'approve'
                    else f'₹{amount:.0f} withdrawal rejected and refunded to wallet.')
        send_push_to_user(user_id, '💰 Withdrawal Update', push_msg, '/wallet.html')
    except Exception as e:
        print(f'[withdrawal] push error: {e}')
    try:
        _wdl_type = 'withdrawal_approved' if action == 'approve' else 'withdrawal_rejected'
        _wdl_title = '💰 Withdrawal Processed' if action == 'approve' else 'Withdrawal Rejected'
        send_fcm_to_user(
            user_id, _wdl_title, push_msg,
            data={'type': _wdl_type, 'amount': str(amount)},
            channel='workmate4u_payment',
        )
    except Exception as e:
        print(f'[FCM] withdrawal push error: {e}')

    return jsonify({'success': True, 'message': f'Withdrawal {action}d successfully', 'newStatus': new_status})

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
@rate_limit('20 per minute')
def send_chat_message(task_id):
    """Send a chat message (REST fallback for Socket.IO)"""
    data = request.get_json()
    message = data.get('message', '').strip()
    
    if not message:
        return jsonify({'success': False, 'message': 'Message cannot be empty'}), 400
    
    if len(message) > 5000:
        return jsonify({'success': False, 'message': 'Message too long (max 5000 chars)'}), 400
    
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
    
    # Validate upload size (max 2.8MB base64)
    if image_url and len(image_url) > 2800000:
        return jsonify({'success': False, 'message': 'Image too large. Maximum 2MB allowed.'}), 400
    
    # Validate image type if base64
    if image_url and image_url.startswith('data:') and not image_url.startswith('data:image/'):
        return jsonify({'success': False, 'message': 'Only image uploads are allowed'}), 400
    
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
    _ensure_helper_ratings_review()
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
        task_title = task.get('title', '')
        
        # Add rating (store task_title to survive task deletion)
        cursor.execute(f'''
            INSERT INTO helper_ratings (task_id, rater_id, rated_id, rating, review, punctuality, communication, quality, task_title, created_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (task_id, request.user_id, rated_id, rating, review, punctuality, communication, quality, task_title, now))
        
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
@require_auth
def get_user_reviews(user_id):
    """Get reviews for a user"""
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            SELECT hr.*, u.name as rater_name, COALESCE(t.title, hr.task_title, 'Task') as task_title
            FROM helper_ratings hr
            LEFT JOIN users u ON hr.rater_id = u.id
            LEFT JOIN tasks t ON hr.task_id = t.id
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
    
    alert_id = cursor.lastrowid

    # Notify all admins via push + in-app notification
    try:
        with get_db() as (cursor2, conn2):
            cursor2.execute(f"SELECT id FROM users WHERE is_admin = TRUE OR role = 'admin'")
            admins = cursor2.fetchall()
        admin_ids = [str(row[0]) for row in (admins or [])]
        sos_body = f"🆘 SOS from {user.get('name', 'User')} (ID {request.user_id}). Immediate action required."
        now_n = datetime.datetime.now(datetime.timezone.utc).isoformat()
        for admin_id in admin_ids:
            send_push_to_user(admin_id, '🆘 Emergency SOS Alert', sos_body, '/admin.html')
            try:
                with get_db() as (cn, co):
                    cn.execute(f'''
                        INSERT INTO notifications (user_id, notification_type, title, message, status, created_at)
                        VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                    ''', (admin_id, 'sos_alert', '🆘 SOS Alert', sos_body, 'unread', now_n))
            except Exception:
                pass
    except Exception as e:
        print(f'[SOS] Could not notify admins: {e}')

    return jsonify({
        'success': True,
        'message': 'SOS alert sent! Emergency contacts have been notified.',
        'alertId': alert_id
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
        # MANDATORY: Verify Razorpay payment signature
        if signature and config.RAZORPAY_KEY_SECRET:
            message = f'{order_id}|{payment_id}'
            expected_signature = hmac.new(
                config.RAZORPAY_KEY_SECRET.encode(),
                message.encode(),
                hashlib.sha256
            ).hexdigest()
            
            if expected_signature != signature:
                print(f"❌ Payment signature verification FAILED for order {order_id}")
                return jsonify({'success': False, 'message': 'Payment verification failed - invalid signature'}), 400
        elif config.RAZORPAY_KEY_SECRET and not signature:
            print(f"❌ Missing payment signature for order {order_id}")
            return jsonify({'success': False, 'message': 'Payment signature required'}), 400
        
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
                
                # Check poster has sufficient balance before deducting
                if poster_balance < task_amount:
                    return jsonify({
                        'success': False,
                        'message': f'Insufficient wallet balance. Need ₹{task_amount:.2f}, have ₹{poster_balance:.2f}. Please top up your wallet first.'
                    }), 400
                
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
        # Frontend sends amount in RUPEES. Convert to paise for Razorpay.
        amount_rupees = int(data.get('amount', 0))
        
        print(f'  Amount (raw rupees from frontend): {amount_rupees}')
        
        if amount_rupees < 10:  # Minimum Rs.10
            return jsonify({'success': False, 'message': 'Minimum top-up is Rs.10'}), 400
        if amount_rupees > 100000:  # Maximum Rs.1,00,000 per transaction
            return jsonify({'success': False, 'message': 'Maximum top-up is Rs.1,00,000'}), 400
        
        amount = amount_rupees * 100  # Convert to paise for Razorpay
        
        print(f'  Amount (converted): {amount} paise (Rs.{amount_rupees})')
        
        
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
        # Amount is in PAISE (sent from Flutter's _pendingTopUpAmountPaise)
        amount = float(data.get('amount', 0))
        
        print('[WALLET] ===== WALLET TOP-UP VERIFICATION =====')
        print(f'[WALLET] Order ID: {order_id}')
        print(f'[WALLET] Payment ID: {payment_id}')
        print(f'[WALLET] Amount: {amount} paise = Rs.{amount/100}')
        print(f'[WALLET] User: {request.user_id}')
        
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
        
        # SECURITY: Verify amount from the Razorpay order, not client-supplied amount
        try:
            rzp_order = razorpay_client.order.fetch(order_id)
            verified_amount = rzp_order.get('amount', 0)  # in paise
            if verified_amount != amount:
                print(f"⚠️ [WALLET] Client amount ({amount}) != Razorpay order amount ({verified_amount}), using Razorpay amount")
                amount = verified_amount
        except Exception as order_err:
            print(f"⚠️ [WALLET] Could not fetch order from Razorpay: {order_err}, using client amount")
        
        with get_db() as (cursor, conn):
            # Idempotency check: skip if already credited by webhook or previous call
            cursor.execute(f'''
                SELECT id FROM wallet_transactions 
                WHERE reference_id = {PH} AND user_id = {PH} AND type = {PH}
            ''', (payment_id, request.user_id, 'razorpay_topup'))
            existing = cursor.fetchone()
            
            if existing:
                print(f"⚠️ [WALLET] Already credited for {payment_id}, returning current balance")
                wallet = get_or_create_wallet(request.user_id)
                return jsonify({
                    'success': True,
                    'message': f'Wallet already credited',
                    'newBalance': float(wallet.get('balance', 0)),
                    'transactionId': payment_id
                }), 200
            
            # Get or create wallet for user
            wallet = get_or_create_wallet(request.user_id)
            current_balance = float(wallet.get('balance', 0))
            credit_amount = amount / 100.0  # Convert from paise to rupees
            new_balance = current_balance + credit_amount
            
            print(f"[WALLET] Current balance: ₹{current_balance}")
            print(f"[WALLET] Crediting: ₹{credit_amount}")
            print(f"[WALLET] New balance: ₹{new_balance}")
            
            # Calculate debt recovery — if user had negative balance, the portion
            # covering that debt is real revenue (penalty collection)
            debt_recovered = 0
            if current_balance < 0:
                debt_recovered = min(credit_amount, abs(current_balance))
                print(f"[WALLET] Debt recovery: ₹{debt_recovered:.2f} from negative balance ₹{current_balance:.2f}")
            
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
            
            # Credit debt recovery to company wallet as penalty revenue
            if debt_recovered > 0:
                company_wallet = get_or_create_wallet('1')
                company_balance = float(company_wallet.get('balance', 0))
                company_new_balance = company_balance + debt_recovered
                
                cursor.execute(f'''
                    UPDATE wallets
                    SET balance = {PH}, total_earned = total_earned + {PH}, updated_at = {PH}
                    WHERE user_id = {PH}
                ''', (company_new_balance, debt_recovered, now, '1'))
                
                cursor.execute(f'''
                    INSERT INTO wallet_transactions (
                        wallet_id, user_id, type, amount, balance_after,
                        description, reference_id, created_at
                    ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (
                    company_wallet.get('id'), '1', 'penalty',
                    debt_recovered, company_new_balance,
                    f'Debt recovery from user {request.user_id} (topped up ₹{credit_amount:.2f}, covered ₹{debt_recovered:.2f} debt)',
                    f'debt-recovery-{request.user_id}', now
                ))
                
                print(f"💰 [WALLET] Debt recovery: ₹{debt_recovered:.2f} credited to company wallet as penalty revenue")
            
            # Auto-clear debt suspension if balance is back to >= 0
            if new_balance >= 0:
                clear_debt_suspension_if_needed(request.user_id, cursor)
            
            conn.commit()
        
        print(f"✅ [WALLET] Wallet credited successfully: ₹{credit_amount}")
        print(f"[WALLET] New balance: ₹{new_balance}")
        print(f"[WALLET] Transaction recorded with ID: {wallet_id}")

        # DB notification for the user
        try:
            import json as _vwt_json
            _vwt_now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            with get_db() as (_vwt_cur, _vwt_conn):
                _vwt_cur.execute(f'''
                    INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (request.user_id, 'wallet_topup',
                      'Wallet Topped Up! 💰',
                      f'₹{credit_amount:.2f} added to your wallet via Razorpay. New balance: ₹{new_balance:.2f}',
                      'unread', _vwt_json.dumps({'type': 'wallet_topup', 'amount': credit_amount}), _vwt_now))
        except Exception as _vwt_notif_err:
            print(f'⚠️ [WALLET] verify DB notification failed: {_vwt_notif_err}')

        # FCM push — notify user their wallet has been topped up
        try:
            print(f'[FCM] Sending wallet_topup (verify) to user {request.user_id}')
            send_fcm_to_user(
                request.user_id,
                '💰 Wallet Topped Up!',
                f'₹{credit_amount:.2f} added to your wallet. Balance: ₹{new_balance:.2f}',
                data={
                    'type': 'wallet_topup',
                    'amount': str(credit_amount),
                    'new_balance': str(new_balance),
                },
                channel='workmate4u_payment',
            )
        except Exception as _fcm_verify_err:
            print(f'[FCM] ❌ verify_wallet_topup FCM failed: {_fcm_verify_err}')

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
        
        # Verify signature — mandatory in production
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
        elif not webhook_secret:
            print("❌ Webhook secret not configured — rejecting request")
            return jsonify({'success': False, 'message': 'Webhook not configured'}), 503
        elif not signature:
            print("❌ Missing webhook signature — rejecting request")
            return jsonify({'success': False, 'message': 'Signature required'}), 401
        
        # Parse JSON payload
        data = json.loads(raw_body)
        event = data.get('event')
        payload = data.get('payload', {})
        
        print(f"📨 Razorpay Webhook Event: {event}")
        
        if event == 'payment.authorized' or event == 'payment.captured':
            payment_entity = payload.get('payment', {}).get('entity', {})
            payment_id = payment_entity.get('id')
            order_id = payment_entity.get('order_id')
            amount = payment_entity.get('amount', 0) / 100  # Convert paise to rupees
            notes = payment_entity.get('notes', {})
            
            print(f"💰 Payment captured: {payment_id} (Order: {order_id}, Amount: ₹{amount})")
            
            # Check if this is a wallet topup payment
            is_wallet_topup = notes.get('type') == 'wallet_topup'
            topup_user_id = notes.get('userId') or notes.get('user_id')
            
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
                
                # Credit wallet for topup payments (idempotent — skip if already credited)
                if is_wallet_topup and topup_user_id and event == 'payment.captured':
                    # Check if this payment was already credited (prevent double-credit)
                    cursor.execute(f'''
                        SELECT id FROM wallet_transactions 
                        WHERE reference_id = {PH} AND user_id = {PH} AND type = {PH}
                    ''', (payment_id, topup_user_id, 'razorpay_topup'))
                    existing = cursor.fetchone()
                    
                    if existing:
                        print(f"⚠️ [WEBHOOK] Wallet already credited for {payment_id}, skipping")
                    else:
                        print(f"💳 [WEBHOOK] Crediting wallet for user {topup_user_id}: ₹{amount}")
                        wallet = get_or_create_wallet(topup_user_id)
                        current_balance = float(wallet.get('balance', 0))
                        new_balance = current_balance + amount
                        wallet_id = wallet.get('id')
                        
                        cursor.execute(f'''
                            UPDATE wallets
                            SET balance = {PH}, total_added = total_added + {PH}
                            WHERE user_id = {PH}
                        ''', (new_balance, amount, topup_user_id))
                        
                        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                        cursor.execute(f'''
                            INSERT INTO wallet_transactions (
                                wallet_id, user_id, type, amount, balance_after,
                                description, reference_id, created_at
                            ) VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                        ''', (
                            wallet_id, topup_user_id, 'razorpay_topup',
                            amount, new_balance,
                            f'Wallet top-up via Razorpay - ₹{amount:.2f}',
                            payment_id, now
                        ))
                        
                        print(f"✅ [WEBHOOK] Wallet credited: ₹{amount} → new balance ₹{new_balance}")

                        # DB notification for the user
                        import json as _wh_json
                        try:
                            cursor.execute(f'''
                                INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                            ''', (topup_user_id, 'wallet_topup',
                                  'Wallet Topped Up! 💰',
                                  f'₹{amount:.2f} added to your wallet via Razorpay. New balance: ₹{new_balance:.2f}',
                                  'unread', _wh_json.dumps({'type': 'wallet_topup', 'amount': amount}), now))
                        except Exception as _wh_notif_err:
                            print(f'⚠️ [WEBHOOK] DB notification failed: {_wh_notif_err}')

                        # FCM push
                        try:
                            print(f'[FCM] Sending wallet_topup (webhook) to user {topup_user_id}')
                            send_fcm_to_user(
                                topup_user_id,
                                'Wallet Topped Up! 💰',
                                f'₹{amount:.2f} added to your wallet. New balance: ₹{new_balance:.2f}',
                                data={'type': 'wallet_topup', 'amount': str(amount), 'new_balance': str(new_balance)},
                                channel='workmate4u_payment',
                            )
                        except Exception as _wh_fcm_err:
                            print(f'[FCM] ❌ webhook wallet_topup FCM failed: {_wh_fcm_err}')
                
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
    db_connected = False
    db_error = None
    try:
        with get_db() as (cursor, conn):
            cursor.execute('SELECT 1')
            cursor.fetchone()
            db_connected = True
    except Exception as e:
        db_error = str(e)

    return jsonify({
        'success': True,
        'status': 'healthy' if db_connected else 'degraded',
        'database': {
            'connected': db_connected,
            'engine': 'postgresql',
            'error': db_error
        },
        'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
    })


@app.route('/api/diagnostic', methods=['GET'])
@require_admin
def diagnostic():
    """Diagnostic endpoint - admin only"""
    return jsonify({
        'success': True,
        'message': 'Flask API is running correctly',
        'status': 'operational',
        'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
    })


@app.route('/api/init-db', methods=['POST'])
@require_admin
def init_database_endpoint():
    """Manually initialize database tables - admin only"""
    try:
        init_db()
        return jsonify({
            'success': True,
            'message': 'Database initialized successfully',
            'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
        }), 200
    except Exception as e:
        print(f"ERROR during database init: {e}")
        return jsonify({
            'success': False,
            'message': 'Failed to initialize database'
        }), 500


# ========================================
# DATABASE CLEANUP
# ========================================

def cleanup_old_tasks():
    """Delete expired tasks immediately and delete old completed/paid tasks"""
    try:
        with get_db() as (cursor, conn):
            try:
                import json
                now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                thirty_days_ago = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=30)).isoformat()
                
                # Find active tasks that have expired — notify posters then DELETE immediately
                cursor.execute(f'''
                    SELECT id, title, posted_by, price FROM tasks
                    WHERE status = 'active' AND expires_at < {PH}
                ''', (now,))
                expired_tasks = [dict_from_row(r) for r in cursor.fetchall()]
                
                for t in expired_tasks:
                    # Notify poster — insert WITHOUT task_id so there is no FK
                    # reference on a row that is about to be deleted.
                    notif_data = json.dumps({'type': 'task', 'taskId': t['id']})
                    try:
                        cursor.execute(f'''
                            INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                        ''', (t['posted_by'], 'task_expired',
                              'Task Expired ⏰',
                              f'Your task "{t["title"]}" has expired without being accepted. You can post it again.',
                              'unread', notif_data, now))
                    except Exception:
                        pass
                    # Clean up all FK references then delete the task
                    _safe_delete_tasks(cursor, t['id'])
                    cursor.execute(f'DELETE FROM tasks WHERE id = {PH}', (t['id'],))
                
                if expired_tasks:
                    print(f"✅ Deleted {len(expired_tasks)} expired tasks and notified posters")
                
                # Delete completed/paid tasks older than 30 days.
                # Must fetch IDs first and use _safe_delete_tasks to avoid FK violations.
                cursor.execute(f'''
                    SELECT id FROM tasks
                    WHERE (status = 'completed' OR status = 'paid')
                    AND completed_at IS NOT NULL
                    AND completed_at < {PH}
                ''', (thirty_days_ago,))
                old_rows = cursor.fetchall()
                old_task_ids = [str(r['id'] if isinstance(r, dict) else r[0]) for r in old_rows]
                deleted_count = 0
                if old_task_ids:
                    _safe_delete_tasks(cursor, old_task_ids)
                    cursor.execute(f"DELETE FROM tasks WHERE id IN ({','.join(old_task_ids)})")
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


def cleanup_expired_suspensions():
    """Auto-clear timer-based suspensions that have expired"""
    try:
        with get_db() as (cursor, conn):
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                UPDATE users SET is_suspended = FALSE, suspended_until = NULL, suspension_reason = NULL
                WHERE suspended_until IS NOT NULL AND suspended_until < {PH}
            ''', (now,))
            cleared = cursor.rowcount
            if cleared > 0:
                print(f"✅ Auto-cleared {cleared} expired timer suspension(s)")
            return cleared
    except Exception as e:
        print(f"⚠️  Suspension cleanup error: {e}")
        return 0


def _run_periodic_cleanup():
    """Background thread that periodically cleans up expired suspensions"""
    import time
    while True:
        time.sleep(300)  # Every 5 minutes
        try:
            cleanup_expired_suspensions()
        except Exception as e:
            print(f"⚠️  Periodic suspension cleanup error: {e}")


# ========================================
# CONTACT MESSAGES API
# ========================================

@app.route('/api/contact', methods=['POST'])
@rate_limit('5 per minute')
def submit_contact_message():
    """Save a contact form message"""
    data = request.get_json()
    name = (data.get('from_name') or data.get('name', '')).strip()
    email = (data.get('from_email') or data.get('email', '')).strip()
    subject = data.get('subject', '').strip()
    message = data.get('message', '').strip()

    if not name or not email or not message:
        return jsonify({'success': False, 'message': 'Name, email and message are required'}), 400

    if len(name) > 200 or len(email) > 200 or len(subject) > 500 or len(message) > 10000:
        return jsonify({'success': False, 'message': 'Input too long'}), 400

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
@require_admin
def get_contact_messages():
    """Get all contact messages (admin only)"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT * FROM contact_messages ORDER BY created_at DESC LIMIT 100')
            messages = [dict_from_row(row) for row in cursor.fetchall()]
        return jsonify({'success': True, 'messages': messages}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# FEEDBACK / REVIEWS API (public form on /feedback.html)
# ========================================

@app.route('/api/feedback', methods=['POST'])
@rate_limit('5 per minute')
def submit_feedback():
    """Save a feedback / review form submission and email it to support."""
    data = request.get_json(silent=True) or {}

    # Validate / coerce
    try:
        rating = int(data.get('rating') or 0)
    except (TypeError, ValueError):
        rating = 0
    if rating < 1 or rating > 5:
        return jsonify({'success': False, 'message': 'Rating must be between 1 and 5'}), 400

    name = (data.get('name') or '').strip()
    email = (data.get('email') or '').strip()
    message = (data.get('message') or '').strip()
    role = (data.get('role') or '').strip()[:40]
    city = (data.get('city') or '').strip()[:80]
    topic = (data.get('topic') or 'General').strip()[:60]
    consent_public = bool(data.get('consent'))

    if not name or not email or not message:
        return jsonify({'success': False, 'message': 'Name, email and message are required'}), 400
    if '@' not in email or len(email) > 200:
        return jsonify({'success': False, 'message': 'Valid email required'}), 400
    if len(name) > 120:
        return jsonify({'success': False, 'message': 'Name too long'}), 400
    if len(message) > 5000:
        return jsonify({'success': False, 'message': 'Message too long (max 5000 chars)'}), 400

    # Optional auth
    user_id = None
    auth_header = request.headers.get('Authorization', '')
    if auth_header.startswith('Bearer '):
        token = auth_header[7:]
        if token:
            try:
                with get_db() as (cursor, conn):
                    cursor.execute(f'SELECT id FROM users WHERE session_token = {PH}', (token,))
                    row = cursor.fetchone()
                    if row:
                        user_id = dict_from_row(row)['id']
            except Exception:
                pass

    ip_addr = (request.headers.get('X-Forwarded-For') or request.remote_addr or '')[:64]
    user_agent = (request.headers.get('User-Agent') or '')[:255]
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()

    # Save to DB
    feedback_id = None
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                INSERT INTO feedback (rating, role, name, city, email, topic, message,
                                      consent_public, user_id, ip_address, user_agent,
                                      status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                RETURNING id
            ''', (rating, role, name, city, email, topic, message,
                  consent_public, user_id, ip_addr, user_agent, 'pending', now))
            row = cursor.fetchone()
            if row:
                feedback_id = dict_from_row(row).get('id')
    except Exception as e:
        print(f"[feedback] DB insert error: {e}")
        # Don't bail — still try email so the message isn't lost

    # Email notification to support
    email_sent = False
    if config.SENDGRID_API_KEY:
        try:
            from sendgrid import SendGridAPIClient
            from sendgrid.helpers.mail import Mail
            stars = '★' * rating + '☆' * (5 - rating)
            safe_msg = (message
                        .replace('&', '&amp;')
                        .replace('<', '&lt;')
                        .replace('>', '&gt;')
                        .replace('\n', '<br>'))
            html = f'''
                <h2>New Workmate4u Feedback</h2>
                <p><strong>Rating:</strong> {stars} ({rating}/5)<br>
                   <strong>Role:</strong> {role or '-'}<br>
                   <strong>Topic:</strong> {topic}<br>
                   <strong>Name:</strong> {name}<br>
                   <strong>City:</strong> {city or '-'}<br>
                   <strong>Email:</strong> <a href="mailto:{email}">{email}</a><br>
                   <strong>Public review consent:</strong> {'Yes' if consent_public else 'No'}<br>
                   <strong>User ID:</strong> {user_id or 'guest'}<br>
                   <strong>IP:</strong> {ip_addr or '-'}<br>
                   <strong>Submitted:</strong> {now}</p>
                <hr>
                <p style="white-space:pre-wrap; font-size:1.02rem; line-height:1.6;">{safe_msg}</p>
                <hr>
                <p style="color:#64748b;font-size:0.85rem;">Feedback ID: {feedback_id or 'n/a'}</p>
            '''
            subject = f'[Feedback {rating}★] {topic} - {name}'
            mail = Mail(
                from_email=config.FROM_EMAIL,
                to_emails='info@workmate4u.com',
                subject=subject,
                html_content=html
            )
            mail.reply_to = email  # so admin can hit Reply
            sg = SendGridAPIClient(config.SENDGRID_API_KEY)
            sg.send(mail)
            email_sent = True
        except Exception as e:
            print(f"[feedback] SendGrid error: {e}")
    else:
        print(f"[feedback] SendGrid not configured — feedback {feedback_id} saved to DB only")

    return jsonify({
        'success': True,
        'message': 'Thanks! Your feedback has been received.',
        'id': feedback_id,
        'emailed': email_sent
    }), 200


@app.route('/api/admin/feedback', methods=['GET'])
@require_admin
def get_feedback_list():
    """Admin: list all feedback submissions."""
    try:
        with get_db() as (cursor, conn):
            cursor.execute('SELECT * FROM feedback ORDER BY created_at DESC LIMIT 200')
            rows = [dict_from_row(r) for r in cursor.fetchall()]
        return jsonify({'success': True, 'feedback': rows}), 200
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
            cursor.execute(f'''
                SELECT n.*, t.title as task_title
                FROM notifications n
                LEFT JOIN tasks t ON n.task_id = t.id
                WHERE n.user_id = {PH}
                ORDER BY n.created_at DESC
                LIMIT 50
            ''', (request.user_id,))
            
            rows = cursor.fetchall()
            notifications = []
            for row in rows:
                n = dict_from_row(row)
                # Flask 3.0 serialises datetime as RFC 7231 ("Thu, 11 Jul 2024 10:35:42 GMT")
                # which Dart's DateTime.tryParse cannot handle.  Convert to ISO 8601 explicitly.
                for field in ('created_at', 'read_at'):
                    val = n.get(field)
                    if hasattr(val, 'isoformat'):
                        # psycopg2 returns naive datetimes for TIMESTAMP columns;
                        # the column stores UTC values, so attach the UTC marker.
                        if getattr(val, 'tzinfo', None) is None:
                            import datetime as _dt
                            val = val.replace(tzinfo=_dt.timezone.utc)
                        n[field] = val.isoformat()
                notifications.append(n)
            
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
@require_admin
def update_bank_details():
    """Update company bank details for settlements"""
    try:
        # Only admin can update bank details (user_id = 1)
        
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
@require_admin
def get_bank_details():
    """Get company bank details (masked)"""
    try:
        
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
@require_admin
def process_settlement():
    """Process platform settlement - transfer to bank account"""
    try:
        
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
@require_admin
def get_settlements():
    """Get settlement history"""
    try:
        
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
@require_admin
def get_settlement_stats():
    """Get settlement statistics"""
    try:
        
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


@app.route('/api/admin/dashboard-stats', methods=['GET'])
@require_admin
def get_admin_dashboard_stats():
    """Get comprehensive admin dashboard statistics with real data"""
    try:
        # Mark stale active tasks as expired so admin sees correct status
        try:
            cleanup_old_tasks()
        except Exception:
            pass

        with get_db() as (cursor, conn):
            now = datetime.datetime.now(datetime.timezone.utc)
            thirty_days_ago = (now - datetime.timedelta(days=30)).isoformat()
            seven_days_ago = (now - datetime.timedelta(days=7)).isoformat()

            # Total users
            cursor.execute('SELECT COUNT(*) FROM users')
            total_users = cursor.fetchone()[0]

            # New users (30d)
            cursor.execute(f'SELECT COUNT(*) FROM users WHERE created_at >= {PH}', (thirty_days_ago,))
            new_users_30d = cursor.fetchone()[0]

            # Total tasks
            cursor.execute('SELECT COUNT(*) FROM tasks')
            total_tasks = cursor.fetchone()[0]

            # Active tasks
            cursor.execute(f"SELECT COUNT(*) FROM tasks WHERE status = 'active'")
            active_tasks = cursor.fetchone()[0]

            # Completed tasks
            cursor.execute(f"SELECT COUNT(*) FROM tasks WHERE status IN ('completed', 'paid')")
            completed_tasks = cursor.fetchone()[0]

            # Completion rate
            completion_rate = round((completed_tasks / total_tasks * 100), 1) if total_tasks > 0 else 0

            # Company wallet balance (total revenue)
            cursor.execute(f'SELECT balance FROM wallets WHERE user_id = {PH}', ('1',))
            wallet = cursor.fetchone()
            current_balance = float(wallet[0]) if wallet else 0

            # Total revenue earned (all time) - sum of commission + platform_fee
            cursor.execute(f"""
                SELECT COALESCE(SUM(amount), 0) FROM wallet_transactions
                WHERE user_id = {PH} AND transaction_type IN ('commission', 'platform_fee')
            """, ('1',))
            total_revenue = float(cursor.fetchone()[0])

            # Revenue last 30 days
            cursor.execute(f"""
                SELECT COALESCE(SUM(amount), 0) FROM wallet_transactions
                WHERE user_id = {PH} AND transaction_type IN ('commission', 'platform_fee')
                AND created_at >= {PH}
            """, ('1', thirty_days_ago))
            revenue_30d = float(cursor.fetchone()[0])

            # Commission vs Platform fee breakdown (30d)
            cursor.execute(f"""
                SELECT
                    COALESCE(SUM(CASE WHEN transaction_type = 'commission' THEN amount ELSE 0 END), 0) as commission_30d,
                    COALESCE(SUM(CASE WHEN transaction_type = 'platform_fee' THEN amount ELSE 0 END), 0) as fees_30d
                FROM wallet_transactions
                WHERE user_id = {PH} AND created_at >= {PH}
                AND transaction_type IN ('commission', 'platform_fee')
            """, ('1', thirty_days_ago))
            breakdown = cursor.fetchone()
            commission_30d = float(breakdown[0])
            fees_30d = float(breakdown[1])

            # Daily revenue for last 7 days
            daily_revenue = []
            for i in range(6, -1, -1):
                day_start = (now - datetime.timedelta(days=i)).replace(hour=0, minute=0, second=0).isoformat()
                day_end = (now - datetime.timedelta(days=i)).replace(hour=23, minute=59, second=59).isoformat()
                cursor.execute(f"""
                    SELECT COALESCE(SUM(amount), 0) FROM wallet_transactions
                    WHERE user_id = {PH} AND transaction_type IN ('commission', 'platform_fee')
                    AND created_at >= {PH} AND created_at <= {PH}
                """, ('1', day_start, day_end))
                day_amount = float(cursor.fetchone()[0])
                day_label = (now - datetime.timedelta(days=i)).strftime('%a')
                daily_revenue.append({'day': day_label, 'amount': day_amount})

            # Task category distribution
            cursor.execute("""
                SELECT category, COUNT(*) as cnt FROM tasks
                GROUP BY category ORDER BY cnt DESC LIMIT 10
            """)
            categories = [{'category': row[0] or 'other', 'count': row[1]} for row in cursor.fetchall()]

            # Recent tasks (10)
            cursor.execute(f"""
                SELECT t.id, t.title, t.price, t.status, t.category, t.created_at,
                       u.first_name || ' ' || u.last_name as poster_name
                FROM tasks t
                LEFT JOIN users u ON CAST(t.posted_by AS TEXT) = CAST(u.id AS TEXT)
                ORDER BY t.created_at DESC LIMIT 10
            """)
            recent_tasks = []
            for row in cursor.fetchall():
                r = dict_from_row(row) if hasattr(row, 'keys') else {
                    'id': row[0], 'title': row[1], 'price': float(row[2] or 0),
                    'status': row[3], 'category': row[4], 'created_at': row[5],
                    'poster_name': row[6] or 'Unknown'
                }
                recent_tasks.append(r)

            # Recent users (10)
            cursor.execute("""
                SELECT id, first_name, last_name, email, created_at, rating,
                       kyc_status, kyc_document_type, kyc_document_number, kyc_verified_at
                FROM users ORDER BY created_at DESC LIMIT 10
            """)
            recent_users = []
            for row in cursor.fetchall():
                r = dict_from_row(row) if hasattr(row, 'keys') else {
                    'id': row[0], 'first_name': row[1], 'last_name': row[2],
                    'email': row[3], 'created_at': row[4], 'rating': float(row[5] or 0),
                    'kyc_status': row[6] or 'none', 'kyc_document_type': row[7],
                    'kyc_document_number': row[8], 'kyc_verified_at': row[9]
                }
                recent_users.append(r)

            # Total settled
            cursor.execute("SELECT COALESCE(SUM(amount_settled), 0), COUNT(*) FROM platform_settlements WHERE status IN ('completed', 'initiated')")
            settle_row = cursor.fetchone()
            total_settled = float(settle_row[0])
            settlement_count = settle_row[1]

            return jsonify({
                'success': True,
                'total_users': total_users,
                'new_users_30d': new_users_30d,
                'total_tasks': total_tasks,
                'active_tasks': active_tasks,
                'completed_tasks': completed_tasks,
                'completion_rate': completion_rate,
                'current_balance': current_balance,
                'total_revenue': total_revenue,
                'revenue_30d': revenue_30d,
                'commission_30d': commission_30d,
                'fees_30d': fees_30d,
                'daily_revenue': daily_revenue,
                'categories': categories,
                'recent_tasks': recent_tasks,
                'recent_users': recent_users,
                'total_settled': total_settled,
                'settlement_count': settlement_count
            }), 200

    except Exception as e:
        print(f"❌ Error getting dashboard stats: {e}")
        import traceback
        traceback.print_exc()
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
                # Initialize with bank details from environment variables
                acct = os.environ.get('COMPANY_BANK_ACCOUNT', '')
                ifsc = os.environ.get('COMPANY_BANK_IFSC', '')
                holder = os.environ.get('COMPANY_BANK_HOLDER', 'TaskEarn Platform')
                bank = os.environ.get('COMPANY_BANK_NAME', 'Kotak Bank')
                if acct and ifsc:
                    now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    cursor.execute(f'''
                        INSERT INTO company_bank_details
                        (account_number, ifsc_code, account_holder_name, bank_name, is_active, created_at, updated_at)
                        VALUES ({PH}, {PH}, {PH}, {PH}, TRUE, {PH}, {PH})
                    ''', (acct, ifsc, holder, bank, now, now))
                    print(f"💾 Bank details initialized: {ifsc} ****{acct[-4:]}")
                else:
                    print("⚠️  COMPANY_BANK_ACCOUNT and COMPANY_BANK_IFSC env vars not set — skipping bank init")
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
@require_admin
def get_audit_log():
    """Get admin audit log entries"""
    try:
        
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
@require_admin
def admin_manual_refund():
    """Admin manually credits a user's wallet"""
    try:
        
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
@require_admin
def admin_hide_task(task_id):
    """Admin hides/removes an inappropriate task"""
    try:
        
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
@require_admin
def admin_restore_task(task_id):
    """Admin restores a hidden task back to active"""
    try:
        
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
@require_admin
def admin_analytics():
    """Get platform analytics for admin dashboard"""
    try:
        # Mark stale active tasks as expired so analytics are accurate
        try:
            cleanup_old_tasks()
        except Exception:
            pass

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
# ADMIN: USER MANAGEMENT (Suspend/Ban/Delete)
# ========================================

@app.route('/api/admin/users/<user_id>/suspend', methods=['POST'])
@require_admin
def admin_suspend_user(user_id):
    """Admin suspends a user (with optional duration)"""
    try:
        _ensure_suspension_columns()
        data = request.get_json() or {}
        reason = data.get('reason', 'Suspended by admin').strip()
        duration_hours = data.get('duration_hours')  # None = indefinite

        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        suspended_until = None
        if duration_hours:
            suspended_until = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=int(duration_hours))).isoformat()

        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id, name FROM users WHERE id = {PH}', (user_id,))
            user = cursor.fetchone()
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404

            cursor.execute(f'''
                UPDATE users SET is_suspended = {PH}, suspension_reason = {PH},
                    suspended_at = {PH}, suspended_until = {PH}
                WHERE id = {PH}
            ''', (True, reason, now, suspended_until, user_id))

            # Send notification to user
            import json
            notif_msg = f'Your account has been suspended by admin. Reason: {reason}'
            if suspended_until:
                notif_msg += f' (until {datetime.datetime.fromisoformat(suspended_until).strftime("%b %d, %I:%M %p")} UTC)'
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 'account_suspended', 'Account Suspended ⛔',
                  notif_msg, 'unread', json.dumps({'type': 'system', 'reason': reason}), now))

            log_admin_action(cursor, request.user_id, 'suspend_user', 'user', user_id,
                           f'Suspended. Reason: {reason}. Duration: {duration_hours or "indefinite"}h', request.remote_addr)

        # Send email notification
        try:
            notify_account_suspended_email(user_id, reason)
        except Exception:
            pass

        return jsonify({'success': True, 'message': f'User {user_id} suspended'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/admin/users/<user_id>/unsuspend', methods=['POST'])
@require_admin
def admin_unsuspend_user(user_id):
    """Admin unsuspends a user"""
    try:
        _ensure_suspension_columns()
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()

        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id, name FROM users WHERE id = {PH}', (user_id,))
            user = cursor.fetchone()
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404

            cursor.execute(f'''
                UPDATE users SET is_suspended = {PH}, suspension_reason = {PH},
                    suspended_at = {PH}, suspended_until = {PH}
                WHERE id = {PH}
            ''', (False, None, None, None, user_id))

            import json
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 'account_restored', 'Account Restored! ✅',
                  'Your account suspension has been lifted by admin. You can now accept tasks again.',
                  'unread', json.dumps({'type': 'system'}), now))

            log_admin_action(cursor, request.user_id, 'unsuspend_user', 'user', user_id,
                           'User unsuspended by admin', request.remote_addr)

        return jsonify({'success': True, 'message': f'User {user_id} unsuspended'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/admin/users/<user_id>/ban', methods=['POST'])
@require_admin
def admin_ban_user(user_id):
    """Admin permanently bans a user (blocks login + all actions)"""
    try:
        _ensure_suspension_columns()
        data = request.get_json() or {}
        reason = data.get('reason', 'Banned by admin').strip()
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()

        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id, name FROM users WHERE id = {PH}', (user_id,))
            user = cursor.fetchone()
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404

            cursor.execute(f'''
                UPDATE users SET is_banned = {PH}, banned_reason = {PH}, banned_at = {PH},
                    is_suspended = {PH}, suspension_reason = {PH}, session_token = {PH}
                WHERE id = {PH}
            ''', (True, reason, now, True, f'Banned: {reason}', None, user_id))

            import json
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 'account_banned', 'Account Permanently Banned 🚫',
                  f'Your account has been permanently banned. Reason: {reason}. Contact support if you believe this is an error.',
                  'unread', json.dumps({'type': 'system', 'reason': reason}), now))

            log_admin_action(cursor, request.user_id, 'ban_user', 'user', user_id,
                           f'Permanently banned. Reason: {reason}', request.remote_addr)

        return jsonify({'success': True, 'message': f'User {user_id} permanently banned'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/admin/users/<user_id>/unban', methods=['POST'])
@require_admin
def admin_unban_user(user_id):
    """Admin lifts a permanent ban"""
    try:
        _ensure_suspension_columns()
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()

        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id, name FROM users WHERE id = {PH}', (user_id,))
            user = cursor.fetchone()
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404

            cursor.execute(f'''
                UPDATE users SET is_banned = {PH}, banned_reason = {PH}, banned_at = {PH},
                    is_suspended = {PH}, suspension_reason = {PH}
                WHERE id = {PH}
            ''', (False, None, None, False, None, user_id))

            import json
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, data, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 'account_restored', 'Account Restored! ✅',
                  'Your account ban has been lifted. You can now use the platform again.',
                  'unread', json.dumps({'type': 'system'}), now))

            log_admin_action(cursor, request.user_id, 'unban_user', 'user', user_id,
                           'Ban lifted by admin', request.remote_addr)

        return jsonify({'success': True, 'message': f'User {user_id} unbanned'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/admin/users/<user_id>', methods=['DELETE'])
@require_admin
def admin_delete_user(user_id):
    """Admin permanently deletes a user and all their data"""
    try:
        if user_id == '1':
            return jsonify({'success': False, 'message': 'Cannot delete admin user'}), 400

        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id, name, email FROM users WHERE id = {PH}', (user_id,))
            user = cursor.fetchone()
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404
            user = dict_from_row(user) if not isinstance(user, dict) else user

            # Delete in dependency order
            cursor.execute(f'DELETE FROM notifications WHERE user_id = {PH}', (user_id,))
            cursor.execute(f'DELETE FROM wallet_transactions WHERE user_id = {PH}', (user_id,))
            cursor.execute(f'DELETE FROM withdrawal_requests WHERE user_id = {PH}', (user_id,))
            cursor.execute(f'DELETE FROM wallets WHERE user_id = {PH}', (user_id,))
            cursor.execute(f'DELETE FROM tasks WHERE posted_by = {PH} AND status = {PH}', (user_id, 'active'))
            cursor.execute(f'UPDATE tasks SET accepted_by = NULL, status = {PH} WHERE accepted_by = {PH} AND status = {PH}', ('active', user_id, 'accepted'))
            cursor.execute(f'DELETE FROM users WHERE id = {PH}', (user_id,))

            log_admin_action(cursor, request.user_id, 'delete_user', 'user', user_id,
                           f'Deleted user: {user.get("name")} ({user.get("email")})', request.remote_addr)

        return jsonify({'success': True, 'message': f'User {user_id} permanently deleted'}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/admin/users/<user_id>/adjust-balance', methods=['POST'])
@require_admin
def admin_adjust_balance(user_id):
    """Admin adjusts a user's wallet balance (add or deduct)"""
    try:
        data = request.get_json() or {}
        amount = float(data.get('amount', 0))
        reason = data.get('reason', '').strip()

        if amount == 0 or not reason:
            return jsonify({'success': False, 'message': 'Non-zero amount and reason are required'}), 400
        if abs(amount) > 50000:
            return jsonify({'success': False, 'message': 'Amount cannot exceed ±₹50,000'}), 400

        now = datetime.datetime.now(datetime.timezone.utc).isoformat()

        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id, name FROM users WHERE id = {PH}', (user_id,))
            user = cursor.fetchone()
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404

            cursor.execute(f'UPDATE wallets SET balance = balance + {PH}, updated_at = {PH} WHERE user_id = {PH}', (amount, now, user_id))
            if cursor.rowcount == 0:
                return jsonify({'success': False, 'message': 'User wallet not found'}), 404

            cursor.execute(f'SELECT balance FROM wallets WHERE user_id = {PH}', (user_id,))
            new_balance = float(cursor.fetchone()[0])

            txn_type = 'admin_credit' if amount > 0 else 'admin_debit'
            cursor.execute(f'''
                INSERT INTO wallet_transactions (user_id, wallet_id, type, amount, balance_after, description, status, created_at)
                SELECT {PH}, w.id, {PH}, {PH}, {PH}, {PH}, 'completed', {PH}
                FROM wallets w WHERE w.user_id = {PH}
            ''', (user_id, txn_type, abs(amount), new_balance, f'Admin: {reason}', now, user_id))

            log_admin_action(cursor, request.user_id, 'adjust_balance', 'wallet', user_id,
                           f'{"+" if amount > 0 else ""}{amount}. Reason: {reason}. New balance: {new_balance}', request.remote_addr)

        return jsonify({'success': True, 'message': f'Balance adjusted by ₹{amount}', 'new_balance': new_balance}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# STATIC FILE SERVING (Must come AFTER all API routes)
# ========================================


# ========================================
# ACCOUNT DELETION (GDPR)
# ========================================

@app.route('/api/user/delete-account', methods=['POST'])
@require_auth
def delete_account():
    """Delete user account and all associated data (GDPR right to be forgotten)"""
    data = request.get_json() or {}
    password = data.get('password', '')

    try:
        with get_db() as (cursor, conn):
            # Fetch user: need password_hash, auth_provider, email, google_id
            cursor.execute(
                f'SELECT password_hash, auth_provider, email, google_id FROM users WHERE id = {PH}',
                (request.user_id,)
            )
            user = cursor.fetchone()
            if not user:
                return jsonify({'success': False, 'message': 'User not found'}), 404
            user = dict_from_row(user)

            auth_provider = user.get('auth_provider', 'email')
            user_email = user.get('email')
            google_id = user.get('google_id')

            # Password check: email users must provide correct password;
            # Google-only users are already authenticated via JWT — skip password check
            if auth_provider != 'google':
                if not password:
                    return jsonify({'success': False, 'message': 'Password required to confirm deletion'}), 400
                from werkzeug.security import check_password_hash
                if not check_password_hash(user['password_hash'], password):
                    return jsonify({'success': False, 'message': 'Incorrect password'}), 401

            # Check for active tasks
            cursor.execute(
                f"SELECT COUNT(*) as cnt FROM tasks WHERE (posted_by = {PH} OR accepted_by = {PH}) AND status IN ('active', 'accepted')",
                (request.user_id, request.user_id)
            )
            active = dict_from_row(cursor.fetchone())
            if active and active['cnt'] > 0:
                return jsonify({'success': False, 'message': 'Cannot delete account with active tasks. Complete or cancel them first.'}), 400

            # Check for pending withdrawals
            cursor.execute(
                f"SELECT COUNT(*) as cnt FROM withdrawal_requests WHERE user_id = {PH} AND status = 'pending'",
                (request.user_id,)
            )
            pending = dict_from_row(cursor.fetchone())
            if pending and pending['cnt'] > 0:
                return jsonify({'success': False, 'message': 'Cannot delete account with pending withdrawals.'}), 400

            uid = request.user_id
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()

            # Block the email/google_id so this user cannot re-register via Google
            if user_email:
                try:
                    cursor.execute(
                        f"INSERT INTO deleted_accounts (email, google_id, deleted_at) VALUES ({PH}, {PH}, {PH}) ON CONFLICT (email) DO NOTHING",
                        (user_email, google_id, now)
                    )
                except Exception as e:
                    print(f"[DELETE ACCOUNT] Warning: could not write deleted_accounts: {e}")

            # Delete user data in order (foreign key safe)
            cursor.execute(f'DELETE FROM phone_otps WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM notifications WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM chat_messages WHERE sender_id = {PH} OR receiver_id = {PH}', (uid, uid))
            cursor.execute(f'DELETE FROM helper_ratings WHERE helper_id = {PH} OR rater_id = {PH}', (uid, uid))
            cursor.execute(f'DELETE FROM wallet_transactions WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM wallets WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM referrals WHERE referrer_id = {PH} OR referred_id = {PH}', (uid, uid))
            cursor.execute(f'DELETE FROM location_tracking WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM task_proofs WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM password_resets WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM withdrawal_requests WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM sos_alerts WHERE user_id = {PH}', (uid,))
            cursor.execute(f'DELETE FROM contact_messages WHERE user_id = {PH}', (uid,))

            # Anonymize completed tasks (keep for records but remove PII)
            cursor.execute(f"UPDATE tasks SET posted_by = NULL WHERE posted_by = {PH} AND status IN ('paid', 'expired', 'removed')", (uid,))
            cursor.execute(f"UPDATE tasks SET accepted_by = NULL WHERE accepted_by = {PH} AND status IN ('paid', 'expired', 'removed')", (uid,))

            # Delete the user
            cursor.execute(f'DELETE FROM users WHERE id = {PH}', (uid,))

            conn.commit()

            print(f"🗑️ Account deleted: user {uid} ({user_email})")

        return jsonify({'success': True, 'message': 'Account deleted successfully'}), 200

    except Exception as e:
        print(f"❌ Error deleting account: {e}")
        return jsonify({'success': False, 'message': 'Failed to delete account'}), 500


# ========================================
# TASK NOTIFICATION BROADCAST ENDPOINTS
# ========================================

@app.route('/api/tasks/<int:task_id>/notify-skills', methods=['POST'])
@require_auth
def notify_task_skills(task_id):
    """Push FCM notification (type: skill_matched) to every user whose profile
    skills overlap with this task's category/title/description.
    No location radius — purely skill-based matching.
    Only the task poster may call this endpoint."""
    import json as _nsj
    try:
        with get_db() as (cursor, _):
            cursor.execute(
                f'SELECT id, posted_by, title, category, description, price FROM tasks WHERE id = {PH}',
                (task_id,)
            )
            task = dict_from_row(cursor.fetchone()) if cursor.rowcount != 0 else None
            if task is None:
                cursor.execute(
                    f'SELECT id, posted_by, title, category, description, price FROM tasks WHERE id = {PH}',
                    (task_id,)
                )
                row = cursor.fetchone()
                task = dict_from_row(row) if row else None
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404

        poster_id = str(task.get('posted_by', ''))
        if str(request.user_id) != poster_id:
            return jsonify({'success': False, 'message': 'Not authorised'}), 403

        _task_category = (task.get('category') or '').lower()
        _task_title    = (task.get('title')    or '').lower()
        _task_desc     = (task.get('description') or '').lower()
        _task_price    = task.get('price', 0)
        _task_title_display = task.get('title', '')
        _task_cat_display   = task.get('category', 'General')

        _ensure_bio_skills_columns()
        _ensure_fcm_token_column()

        with get_db() as (cursor, _):
            cursor.execute(f'''
                SELECT id, fcm_token, skills FROM users
                WHERE fcm_token IS NOT NULL
                  AND id != {PH}
                  AND skills IS NOT NULL
                  AND skills NOT IN ({PH}, {PH}, {PH})
            ''', (request.user_id, '[]', '', 'null'))
            candidates = [dict_from_row(r) for r in cursor.fetchall()]

        notified = 0
        for user in candidates:
            try:
                raw_skills = user.get('skills', '[]')
                user_skills = [s.lower() for s in (
                    _nsj.loads(raw_skills) if isinstance(raw_skills, str) else (raw_skills or [])
                )]
                matched = any(
                    sk in _task_category or _task_category in sk or
                    sk in _task_title    or sk in _task_desc
                    for sk in user_skills
                )
                if not matched:
                    continue
                import datetime as _nsdt, json as _nsj2
                _n_title = '\U0001f4bc Task Matching Your Skills!'
                _n_body  = f'"{_task_title_display}" \u2014 \u20b9{_task_price} \u2014 {_task_cat_display}'
                _n_data  = _nsj2.dumps({'type': 'skill_matched', 'taskId': str(task_id),
                                        'label': '\U0001f441\ufe0f View Task'})
                _now = _nsdt.datetime.now(_nsdt.timezone.utc).isoformat()
                # Insert in-app notification (bell icon)
                try:
                    with get_db() as (_nc, _nconn):
                        _nc.execute(f'''
                            INSERT INTO notifications
                                (user_id, task_id, notification_type, title, message, status, data, created_at)
                            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                        ''', (user['id'], task_id, 'skill_matched',
                              _n_title, _n_body, 'unread', _n_data, _now))
                        _nconn.commit()
                except Exception:
                    pass
                # FCM push
                if user.get('fcm_token'):
                    send_fcm_to_user(
                        user['id'],
                        _n_title,
                        _n_body,
                        data={'type': 'skill_matched', 'task_id': str(task_id)},
                        channel='workmate4u_matched',
                    )
                notified += 1
            except Exception:
                pass

        print(f'[FCM] notify-skills task={task_id}: notified {notified} user(s)')
        return jsonify({'success': True, 'notified': notified})
    except Exception as e:
        print(f'[FCM] notify-skills error: {e}')
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/tasks/<int:task_id>/notify-nearby', methods=['POST'])
@require_auth
def notify_task_nearby(task_id):
    """Push FCM notification (type: nearby_task) to every user within 10 km of
    the task's location, regardless of their skills or the task's category.
    Only the task poster may call this endpoint."""
    try:
        with get_db() as (cursor, _):
            cursor.execute(
                f'SELECT id, posted_by, title, category, description, price, '
                f'location_lat, location_lng FROM tasks WHERE id = {PH}',
                (task_id,)
            )
            row = cursor.fetchone()
            task = dict_from_row(row) if row else None
        if not task:
            return jsonify({'success': False, 'message': 'Task not found'}), 404

        poster_id = str(task.get('posted_by', ''))
        if str(request.user_id) != poster_id:
            return jsonify({'success': False, 'message': 'Not authorised'}), 403

        task_lat = task.get('location_lat')
        task_lng = task.get('location_lng')
        if task_lat is None or task_lng is None:
            # No location — cannot do proximity filtering; skip silently
            return jsonify({'success': True, 'notified': 0, 'reason': 'task has no location'})

        task_lat = float(task_lat)
        task_lng = float(task_lng)
        _task_title_display = task.get('title', '')
        _task_cat_display   = task.get('category', 'General')
        _task_price         = task.get('price', 0)

        _ensure_user_location_columns()
        _ensure_fcm_token_column()

        with get_db() as (cursor, _):
            cursor.execute(f'''
                SELECT id, fcm_token, last_lat, last_lng FROM users
                WHERE fcm_token IS NOT NULL
                  AND id != {PH}
                  AND last_lat IS NOT NULL
                  AND last_lng IS NOT NULL
            ''', (request.user_id,))
            candidates = [dict_from_row(r) for r in cursor.fetchall()]

        # Pre-fetch users already notified via notify-skills for this task
        # so we skip them here and avoid duplicate FCM pushes.
        try:
            with get_db() as (_dc, _):
                _dc.execute(f'''
                    SELECT DISTINCT user_id FROM notifications
                    WHERE task_id = {PH}
                      AND notification_type = 'skill_matched'
                ''', (task_id,))
                _already_skill_notified = {str(r[0]) for r in _dc.fetchall()}
        except Exception:
            _already_skill_notified = set()

        notified = 0
        for user in candidates:
            try:
                u_lat = user.get('last_lat')
                u_lng = user.get('last_lng')
                if u_lat is None or u_lng is None:
                    continue
                if _haversine_km(task_lat, task_lng, float(u_lat), float(u_lng)) > 10.0:
                    continue
                # Skip users who already received a skill_matched notification
                # for this task — they don't need a second nearby_task push.
                if str(user['id']) in _already_skill_notified:
                    continue
                # Store in-app notification so it shows in the bell icon
                try:
                    import json as _nj, datetime as _dt
                    _ndata = _nj.dumps({'type': 'nearby_task', 'taskId': task_id,
                                        'label': '\U0001f441\ufe0f View Task'})
                    _now = _dt.datetime.now(_dt.timezone.utc).isoformat()
                    with get_db() as (_nc, _nconn):
                        _nc.execute(f'''
                            INSERT INTO notifications
                                (user_id, task_id, notification_type, title, message, status, data, created_at)
                            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                        ''', (user['id'], task_id, 'nearby_task',
                              '\U0001f4cd New Task Near You!',
                              f'"{_task_title_display}" \u2014 \u20b9{_task_price} \u2014 {_task_cat_display}',
                              'unread', _ndata, _now))
                        _nconn.commit()
                except Exception:
                    pass
                send_fcm_to_user(
                    user['id'],
                    '\U0001f4cd New Task Near You!',
                    f'"{_task_title_display}" \u2014 \u20b9{_task_price} \u2014 {_task_cat_display}',
                    data={'type': 'nearby_task', 'task_id': str(task_id)},
                    channel='workmate4u_matched',
                )
                notified += 1
            except Exception:
                pass

        print(f'[FCM] notify-nearby task={task_id}: notified {notified} user(s)')
        return jsonify({'success': True, 'notified': notified})
    except Exception as e:
        print(f'[FCM] notify-nearby error: {e}')
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# DISPUTE RESOLUTION SYSTEM
# ========================================

@app.route('/api/tasks/<int:task_id>/dispute', methods=['POST'])
@require_auth
def file_dispute(task_id):
    """File a dispute for a task"""
    data = request.get_json()
    reason = data.get('reason', '').strip()
    details = data.get('details', '').strip()
    
    if not reason:
        return jsonify({'success': False, 'message': 'Dispute reason is required'}), 400
    
    if len(reason) > 200:
        return jsonify({'success': False, 'message': 'Reason must be under 200 characters'}), 400
    
    try:
        with get_db() as (cursor, conn):
            # Verify task exists and user is involved
            cursor.execute(f'SELECT id, posted_by, accepted_by, status FROM tasks WHERE id = {PH}', (task_id,))
            task = dict_from_row(cursor.fetchone())
            if not task:
                return jsonify({'success': False, 'message': 'Task not found'}), 404
            
            if request.user_id not in [str(task.get('posted_by', '')), str(task.get('accepted_by', ''))]:
                return jsonify({'success': False, 'message': 'You are not involved in this task'}), 403
            
            # Check for existing open dispute
            cursor.execute(f"SELECT id FROM disputes WHERE task_id = {PH} AND status IN ('open', 'under_review')", (task_id,))
            if cursor.fetchone():
                return jsonify({'success': False, 'message': 'A dispute is already open for this task'}), 400
            
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                INSERT INTO disputes (task_id, filed_by, reason, details, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (task_id, request.user_id, html_escape(reason), html_escape(details), 'open', now))
            
            # Notify admin
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', ('1', task_id, 'dispute', 'New Dispute Filed',
                  f'Dispute filed by user {request.user_id} for task #{task_id}: {reason}',
                  'unread', now))
            
            conn.commit()
        
        return jsonify({'success': True, 'message': 'Dispute filed successfully. Our team will review it.'}), 201
        
    except Exception as e:
        print(f"❌ Error filing dispute: {e}")
        return jsonify({'success': False, 'message': 'Failed to file dispute'}), 500


@app.route('/api/user/disputes', methods=['GET'])
@require_auth
def get_user_disputes():
    """Get disputes for current user"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT d.*, t.title as task_title
                FROM disputes d
                JOIN tasks t ON d.task_id = t.id
                WHERE d.filed_by = {PH}
                ORDER BY d.created_at DESC
            ''', (request.user_id,))
            disputes = [dict_from_row(row) for row in cursor.fetchall()]
        
        return jsonify({'success': True, 'disputes': disputes}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to load disputes'}), 500


@app.route('/api/admin/disputes', methods=['GET'])
@require_admin
def admin_get_disputes():
    """Admin: get all disputes"""
    
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT d.*, t.title as task_title, u.name as filed_by_name
                FROM disputes d
                JOIN tasks t ON d.task_id = t.id
                JOIN users u ON d.filed_by = u.id
                ORDER BY d.created_at DESC
                LIMIT 50
            ''')
            disputes = [dict_from_row(row) for row in cursor.fetchall()]
        
        return jsonify({'success': True, 'disputes': disputes}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to load disputes'}), 500


@app.route('/api/admin/disputes/<int:dispute_id>/resolve', methods=['POST'])
@require_admin
def admin_resolve_dispute(dispute_id):
    """Admin: resolve a dispute"""
    
    data = request.get_json()
    decision = data.get('decision', '').strip()
    refund_amount = float(data.get('refundAmount', 0))
    
    if not decision:
        return jsonify({'success': False, 'message': 'Decision is required'}), 400
    
    try:
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT * FROM disputes WHERE id = {PH}', (dispute_id,))
            dispute = dict_from_row(cursor.fetchone())
            if not dispute:
                return jsonify({'success': False, 'message': 'Dispute not found'}), 404
            
            cursor.execute(f'''
                UPDATE disputes SET status = 'resolved', resolution = {PH}, resolved_by = {PH}, resolved_at = {PH}
                WHERE id = {PH}
            ''', (html_escape(decision), request.user_id, now, dispute_id))
            
            # Process refund if applicable
            if refund_amount > 0:
                filed_by = dispute['filed_by']
                wallet = get_or_create_wallet(filed_by)
                new_balance = float(wallet['balance']) + refund_amount
                
                cursor.execute(f'''
                    UPDATE wallets SET balance = {PH}, total_earned = total_earned + {PH} WHERE user_id = {PH}
                ''', (new_balance, refund_amount, filed_by))
                
                cursor.execute(f'''
                    INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, task_id, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', (wallet['id'], filed_by, 'credit', refund_amount, new_balance,
                      f'Dispute resolution refund', dispute['task_id'], now))
            
            # Notify the filer
            cursor.execute(f'''
                INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (dispute['filed_by'], dispute['task_id'], 'dispute_resolved',
                  'Dispute Resolved',
                  f'Your dispute has been resolved: {decision}' + (f' Refund: ₹{refund_amount:.2f}' if refund_amount > 0 else ''),
                  'unread', now))
            
            conn.commit()
        
        return jsonify({'success': True, 'message': 'Dispute resolved'}), 200
    except Exception as e:
        print(f"❌ Error resolving dispute: {e}")
        return jsonify({'success': False, 'message': 'Failed to resolve dispute'}), 500


# ========================================
# BOOKMARKS
# ========================================

@app.route('/api/tasks/<int:task_id>/bookmark', methods=['POST'])
@require_auth
def toggle_bookmark(task_id):
    """Toggle bookmark on a task"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id FROM bookmarks WHERE user_id = {PH} AND task_id = {PH}', 
                          (request.user_id, task_id))
            existing = cursor.fetchone()
            
            if existing:
                cursor.execute(f'DELETE FROM bookmarks WHERE user_id = {PH} AND task_id = {PH}', 
                              (request.user_id, task_id))
                conn.commit()
                return jsonify({'success': True, 'bookmarked': False, 'message': 'Bookmark removed'}), 200
            else:
                now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                cursor.execute(f'''
                    INSERT INTO bookmarks (user_id, task_id, created_at) VALUES ({PH}, {PH}, {PH})
                ''', (request.user_id, task_id, now))
                conn.commit()
                return jsonify({'success': True, 'bookmarked': True, 'message': 'Task bookmarked'}), 201
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to update bookmark'}), 500


@app.route('/api/user/bookmarks', methods=['GET'])
@require_auth
def get_bookmarks():
    """Get user's bookmarked tasks"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT t.*, u.name as poster_name, u.rating as poster_rating
                FROM bookmarks b
                JOIN tasks t ON b.task_id = t.id
                LEFT JOIN users u ON t.posted_by = u.id
                WHERE b.user_id = {PH}
                ORDER BY b.created_at DESC
            ''', (request.user_id,))
            tasks = [dict_from_row(row) for row in cursor.fetchall()]
        
        return jsonify({'success': True, 'tasks': tasks}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to load bookmarks'}), 500


# ========================================
# TRANSACTION EXPORT
# ========================================

@app.route('/api/wallet/export', methods=['GET'])
@require_auth
def export_transactions():
    """Export wallet transactions as CSV"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT type, amount, balance_after, description, created_at
                FROM wallet_transactions
                WHERE user_id = {PH}
                ORDER BY created_at DESC
            ''', (request.user_id,))
            rows = [dict_from_row(row) for row in cursor.fetchall()]
        
        import io, csv
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(['Date', 'Type', 'Amount (₹)', 'Balance After (₹)', 'Description'])
        for r in rows:
            writer.writerow([
                r.get('created_at', ''),
                r.get('type', ''),
                r.get('amount', 0),
                r.get('balance_after', 0),
                r.get('description', '')
            ])
        
        from flask import Response
        csv_data = output.getvalue()
        return Response(
            csv_data,
            mimetype='text/csv',
            headers={'Content-Disposition': f'attachment; filename=transactions_{request.user_id}.csv'}
        )
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to export transactions'}), 500



# ========================================
# AI TASK MATCHING — RECOMMENDED FOR YOU
# ========================================

def _haversine_km(lat1, lon1, lat2, lon2):
    """Return distance in km between two lat/lng points."""
    import math
    R = 6371
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


@app.route('/api/tasks/recommended', methods=['GET'])
@require_auth
def get_recommended_tasks():
    """
    Return up to 10 tasks ranked by a smart scoring algorithm:
      - Category affinity  (50 pts for top category, 30 for second)
      - Distance           (closer = more points)
      - Price              (higher pay = bonus)
      - Freshness          (posted recently = bonus)
    Requires ?lat=&lng= query params (user's current location).
    """
    try:
        user_lat = request.args.get('lat', type=float)
        user_lng = request.args.get('lng', type=float)
        if user_lat is None or user_lng is None:
            return jsonify({'success': False, 'message': 'lat and lng are required'}), 400

        now = datetime.datetime.now(datetime.timezone.utc)

        with get_db() as (cursor, conn):
            # ── 1. Discover user's top 2 preferred categories from history ──
            cursor.execute(f"""
                SELECT category, COUNT(*) AS cnt
                FROM tasks
                WHERE accepted_by = {PH} AND status IN ('completed', 'active')
                GROUP BY category
                ORDER BY cnt DESC
                LIMIT 5
            """, (request.user_id,))
            rows = cursor.fetchall()
            cat_ranks = {}
            for i, r in enumerate(rows):
                cat_ranks[r['category']] = max(0, 50 - i * 10)  # 50, 40, 30, 20, 10 …

            # ── 2. Fetch all active tasks (exclude tasks posted by this user) ──
            cursor.execute(f"""
                SELECT id, title, description, category,
                       location_lat, location_lng, location_address,
                       price, service_charge, posted_by, posted_at, expires_at
                FROM tasks
                WHERE status = 'active'
                  AND expires_at > {PH}
                  AND posted_by != {PH}
                ORDER BY posted_at DESC
                LIMIT 200
            """, (now.isoformat(), request.user_id))
            tasks_raw = cursor.fetchall()

            # ── 3. Score each task ──
            scored = []
            for t in tasks_raw:
                score = 0

                # Category affinity
                score += cat_ranks.get(t['category'], 0)

                # Distance (penalise far tasks, reward nearby)
                if t['location_lat'] and t['location_lng']:
                    dist_km = _haversine_km(user_lat, user_lng,
                                            float(t['location_lat']),
                                            float(t['location_lng']))
                    if dist_km <= 1:
                        score += 40
                    elif dist_km <= 3:
                        score += 30
                    elif dist_km <= 5:
                        score += 20
                    elif dist_km <= 10:
                        score += 10
                    elif dist_km > 20:
                        score -= 20
                else:
                    dist_km = None

                # Price attractiveness (log scale, capped at 30 pts)
                import math
                score += min(30, int(math.log1p(float(t['price'])) * 4))

                # Freshness bonus
                try:
                    posted = datetime.datetime.fromisoformat(str(t['posted_at']).replace('Z', '+00:00'))
                    if posted.tzinfo is None:
                        posted = posted.replace(tzinfo=datetime.timezone.utc)
                    age_hours = (now - posted).total_seconds() / 3600
                    if age_hours < 1:
                        score += 20
                    elif age_hours < 3:
                        score += 10
                    elif age_hours < 6:
                        score += 5
                except Exception:
                    pass

                scored.append((score, dist_km, t))

            # ── 4. Sort by score desc, return top 10 ──
            scored.sort(key=lambda x: x[0], reverse=True)
            results = []
            for score, dist_km, t in scored[:10]:
                results.append({
                    'id': t['id'],
                    'title': t['title'],
                    'description': t['description'],
                    'category': t['category'],
                    'location': {
                        'lat': float(t['location_lat']) if t['location_lat'] else None,
                        'lng': float(t['location_lng']) if t['location_lng'] else None,
                        'address': t['location_address'],
                    },
                    'price': float(t['price']),
                    'serviceCharge': float(t['service_charge'] or 0),
                    'postedAt': str(t['posted_at']),
                    'expiresAt': str(t['expires_at']),
                    'distanceKm': round(dist_km, 2) if dist_km is not None else None,
                    'matchScore': score,
                })

        return jsonify({'success': True, 'tasks': results})
    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'success': False, 'message': 'Could not fetch recommendations'}), 500


# ========================================
# TASK SEARCH BY KEYWORD (SERVER-SIDE)
# ========================================

@app.route('/api/tasks/search', methods=['GET'])
def search_tasks():
    """Search tasks by keyword with server-side filtering"""
    keyword = request.args.get('q', '').strip()
    category = request.args.get('category', '').strip()
    min_price = request.args.get('min_price', type=float) or request.args.get('min_budget', type=float)
    max_price = request.args.get('max_price', type=float) or request.args.get('max_budget', type=float)
    page = request.args.get('page', 1, type=int)
    limit = request.args.get('limit', 20, type=int)
    limit = min(max(limit, 1), 100)

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()

    try:
        with get_db() as (cursor, conn):
            conditions = [f"status = 'active'", f"expires_at > {PH}"]
            params = [now]

            if keyword:
                conditions.append(f"(LOWER(title) LIKE {PH} OR LOWER(description) LIKE {PH} OR LOWER(category) LIKE {PH})")
                kw = f"%{keyword.lower()}%"
                params.extend([kw, kw, kw])

            if category and category != 'all':
                conditions.append(f"category = {PH}")
                params.append(category)

            if min_price is not None:
                conditions.append(f"price >= {PH}")
                params.append(min_price)

            if max_price is not None:
                conditions.append(f"price <= {PH}")
                params.append(max_price)

            where = " AND ".join(conditions)

            # Count total
            cursor.execute(f'SELECT COUNT(*) as total FROM tasks WHERE {where}', tuple(params))
            total = dict_from_row(cursor.fetchone())['total']

            # Paginated results
            offset = (page - 1) * limit
            cursor.execute(f'''
                SELECT id, title, description, category, location_lat, location_lng,
                       location_address, price, service_charge, posted_by, posted_at, expires_at, status
                FROM tasks WHERE {where}
                ORDER BY posted_at DESC
                LIMIT {PH} OFFSET {PH}
            ''', tuple(params) + (limit, offset))

            rows = cursor.fetchall()
            task_list = []
            for task in rows:
                task = dict_from_row(task)
                poster_name = 'Anonymous'
                poster_rating = 5.0
                try:
                    if task.get('posted_by'):
                        cursor.execute(f'SELECT name, rating FROM users WHERE id = {PH}', (task['posted_by'],))
                        u = cursor.fetchone()
                        if u:
                            u = dict_from_row(u)
                            poster_name = u.get('name', 'Anonymous')
                            poster_rating = float(u.get('rating', 5.0))
                except:
                    pass

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
                        'rating': poster_rating
                    },
                    'postedAt': task['posted_at'],
                    'expiresAt': task['expires_at'],
                    'status': task['status']
                })

            return jsonify({
                'success': True,
                'tasks': task_list,
                'pagination': {
                    'page': page,
                    'limit': limit,
                    'total': total,
                    'totalPages': (total + limit - 1) // limit if limit else 1
                }
            })
    except Exception as e:
        print(f"[SEARCH] Error: {e}")
        return jsonify({'success': False, 'message': 'Search failed'}), 500


# ========================================
# REPORT USER / BLOCK USER
# ========================================

@app.route('/api/user/<user_id>/report', methods=['POST'])
@require_auth
@rate_limit('5 per minute')
def report_user(user_id):
    """Report a user for violation"""
    data = request.get_json()
    reason = data.get('reason', '').strip()
    details = data.get('details', '').strip()
    task_id = data.get('taskId')

    if not reason:
        return jsonify({'success': False, 'message': 'Reason is required'}), 400

    valid_reasons = ['harassment', 'fraud', 'spam', 'inappropriate', 'fake_profile', 'no_show', 'other']
    if reason not in valid_reasons:
        return jsonify({'success': False, 'message': 'Invalid report reason'}), 400

    if len(details) > 2000:
        return jsonify({'success': False, 'message': 'Details too long (max 2000 chars)'}), 400

    if user_id == request.user_id:
        return jsonify({'success': False, 'message': 'You cannot report yourself'}), 400

    try:
        with get_db() as (cursor, conn):
            # Check target user exists
            cursor.execute(f'SELECT id FROM users WHERE id = {PH}', (user_id,))
            if not cursor.fetchone():
                return jsonify({'success': False, 'message': 'User not found'}), 404

            # Check for duplicate recent report
            cursor.execute(f'''
                SELECT id FROM user_reports
                WHERE reporter_id = {PH} AND reported_id = {PH}
                AND created_at > {PH}
            ''', (request.user_id, user_id,
                  (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=24)).isoformat()))
            if cursor.fetchone():
                return jsonify({'success': False, 'message': 'You already reported this user recently'}), 429

            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                INSERT INTO user_reports (reporter_id, reported_id, reason, details, task_id, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, user_id, reason, details, task_id, now))

            # Notify admins via notification
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', ('1', 'user_report', '🚨 New User Report',
                  f'User reported for: {reason}', 'unread', now))

        return jsonify({'success': True, 'message': 'Report submitted. We will review it shortly.'})
    except Exception as e:
        print(f"[REPORT] Error: {e}")
        return jsonify({'success': False, 'message': 'Failed to submit report'}), 500


@app.route('/api/user/<user_id>/block', methods=['POST'])
@require_auth
def block_user(user_id):
    """Block a user"""
    if user_id == request.user_id:
        return jsonify({'success': False, 'message': 'You cannot block yourself'}), 400

    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'SELECT id FROM users WHERE id = {PH}', (user_id,))
            if not cursor.fetchone():
                return jsonify({'success': False, 'message': 'User not found'}), 404

            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            try:
                cursor.execute(f'''
                    INSERT INTO user_blocks (blocker_id, blocked_id, created_at)
                    VALUES ({PH}, {PH}, {PH})
                ''', (request.user_id, user_id, now))
            except:
                return jsonify({'success': False, 'message': 'User already blocked'}), 409

        return jsonify({'success': True, 'message': 'User blocked successfully'})
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to block user'}), 500


@app.route('/api/user/<user_id>/unblock', methods=['POST'])
@require_auth
def unblock_user(user_id):
    """Unblock a user"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                DELETE FROM user_blocks WHERE blocker_id = {PH} AND blocked_id = {PH}
            ''', (request.user_id, user_id))
        return jsonify({'success': True, 'message': 'User unblocked'})
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to unblock user'}), 500


@app.route('/api/user/blocked', methods=['GET'])
@require_auth
def get_blocked_users():
    """Get list of blocked users"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT b.blocked_id, u.name, u.profile_photo, b.created_at
                FROM user_blocks b
                JOIN users u ON u.id = b.blocked_id
                WHERE b.blocker_id = {PH}
                ORDER BY b.created_at DESC
            ''', (request.user_id,))
            rows = [dict_from_row(r) for r in cursor.fetchall()]

        return jsonify({
            'success': True,
            'blocked': [{
                'userId': r['blocked_id'],
                'name': r['name'],
                'profilePhoto': r.get('profile_photo'),
                'blockedAt': r['created_at']
            } for r in rows]
        })
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to get blocked users'}), 500


# ========================================
# ADMIN: USER REPORTS MANAGEMENT
# ========================================

@app.route('/api/admin/reports', methods=['GET'])
@require_admin
def get_reports():
    """Get all user reports (admin)"""
    status = request.args.get('status', 'pending')
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT r.*, 
                       reporter.name as reporter_name,
                       reported.name as reported_name
                FROM user_reports r
                JOIN users reporter ON reporter.id = r.reporter_id
                JOIN users reported ON reported.id = r.reported_id
                WHERE r.status = {PH}
                ORDER BY r.created_at DESC
                LIMIT 100
            ''', (status,))
            rows = [dict_from_row(r) for r in cursor.fetchall()]

        return jsonify({'success': True, 'reports': rows})
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to load reports'}), 500


@app.route('/api/admin/reports/<int:report_id>/resolve', methods=['POST'])
@require_admin
def resolve_report(report_id):
    """Resolve a user report (admin)"""
    data = request.get_json()
    action = data.get('action', 'dismiss')  # dismiss, warn, suspend, ban
    admin_notes = data.get('notes', '')

    try:
        with get_db() as (cursor, conn):
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                UPDATE user_reports SET status = 'resolved', admin_notes = {PH},
                resolved_by = {PH}, resolved_at = {PH}
                WHERE id = {PH}
            ''', (f'{action}: {admin_notes}', request.user_id, now, report_id))

            # Log admin action
            cursor.execute(f'''
                INSERT INTO admin_audit_log (admin_id, action, resource_type, resource_id, details, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, f'report_{action}', 'report', str(report_id), admin_notes, now))

        return jsonify({'success': True, 'message': f'Report resolved ({action})'})
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to resolve report'}), 500


# ========================================
# ADMIN: TASK CATEGORIES MANAGEMENT
# ========================================

@app.route('/api/categories', methods=['GET'])
def get_categories():
    """Get all active task categories"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute('''
                SELECT id, slug, name, icon, service_charge_percent, sort_order
                FROM task_categories
                WHERE is_active = TRUE
                ORDER BY sort_order ASC, name ASC
            ''')
            rows = cursor.fetchall()

            if not rows:
                # Return default categories if none exist in DB
                defaults = [
                    {'slug': 'household', 'name': 'Household Chores', 'icon': 'fas fa-home', 'service_charge_percent': 10},
                    {'slug': 'delivery', 'name': 'Delivery Services', 'icon': 'fas fa-truck', 'service_charge_percent': 8},
                    {'slug': 'tutoring', 'name': 'Online Tutoring', 'icon': 'fas fa-graduation-cap', 'service_charge_percent': 12},
                    {'slug': 'cleaning', 'name': 'Cleaning Services', 'icon': 'fas fa-broom', 'service_charge_percent': 10},
                    {'slug': 'shopping', 'name': 'Shopping & Errands', 'icon': 'fas fa-shopping-bag', 'service_charge_percent': 8},
                    {'slug': 'repair', 'name': 'Repair & Maintenance', 'icon': 'fas fa-wrench', 'service_charge_percent': 12},
                    {'slug': 'moving', 'name': 'Moving & Packing', 'icon': 'fas fa-box', 'service_charge_percent': 15},
                    {'slug': 'petcare', 'name': 'Pet Care', 'icon': 'fas fa-paw', 'service_charge_percent': 10},
                    {'slug': 'other', 'name': 'Other', 'icon': 'fas fa-ellipsis-h', 'service_charge_percent': 10}
                ]
                return jsonify({'success': True, 'categories': defaults})

            categories = [dict_from_row(r) for r in rows]
            return jsonify({'success': True, 'categories': categories})
    except Exception as e:
        print(f"[CATEGORIES] Error: {e}")
        # Fallback defaults
        return jsonify({'success': True, 'categories': [
            {'slug': 'household', 'name': 'Household Chores', 'icon': 'fas fa-home', 'service_charge_percent': 10},
            {'slug': 'delivery', 'name': 'Delivery Services', 'icon': 'fas fa-truck', 'service_charge_percent': 8},
            {'slug': 'other', 'name': 'Other', 'icon': 'fas fa-ellipsis-h', 'service_charge_percent': 10}
        ]})


@app.route('/api/admin/categories', methods=['POST'])
@require_admin
def create_category():
    """Create a new task category (admin)"""
    data = request.get_json()
    name = html_escape(data.get('name', '').strip())
    slug = data.get('slug', '').strip().lower().replace(' ', '-')
    icon = data.get('icon', 'fas fa-tasks').strip()
    charge = data.get('service_charge_percent', 10)
    sort_order = data.get('sort_order', 0)

    if not name or not slug:
        return jsonify({'success': False, 'message': 'Name and slug are required'}), 400

    if len(slug) > 50 or len(name) > 100:
        return jsonify({'success': False, 'message': 'Name or slug too long'}), 400

    try:
        with get_db() as (cursor, conn):
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            cursor.execute(f'''
                INSERT INTO task_categories (slug, name, icon, service_charge_percent, sort_order, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (slug, name, icon, charge, sort_order, now))

            cursor.execute(f'''
                INSERT INTO admin_audit_log (admin_id, action, resource_type, resource_id, details, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, 'create_category', 'category', slug, f'Created: {name}', now))

        return jsonify({'success': True, 'message': f'Category "{name}" created'})
    except Exception as e:
        return jsonify({'success': False, 'message': 'Category slug already exists or creation failed'}), 400


@app.route('/api/admin/categories/<int:category_id>', methods=['PUT'])
@require_admin
def update_category(category_id):
    """Update a task category (admin)"""
    data = request.get_json()
    try:
        with get_db() as (cursor, conn):
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            updates = []
            params = []
            for field in ['name', 'icon', 'service_charge_percent', 'sort_order', 'is_active']:
                if field in data:
                    updates.append(f"{field} = {PH}")
                    val = data[field]
                    if field == 'name':
                        val = html_escape(str(val).strip())
                    params.append(val)

            if not updates:
                return jsonify({'success': False, 'message': 'No fields to update'}), 400

            updates.append(f"updated_at = {PH}")
            params.append(now)
            params.append(category_id)

            cursor.execute(f'''
                UPDATE task_categories SET {", ".join(updates)} WHERE id = {PH}
            ''', tuple(params))

        return jsonify({'success': True, 'message': 'Category updated'})
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to update category'}), 500


@app.route('/api/admin/categories/<int:category_id>', methods=['DELETE'])
@require_admin
def delete_category(category_id):
    """Soft-delete a task category (admin)"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'UPDATE task_categories SET is_active = FALSE WHERE id = {PH}', (category_id,))
        return jsonify({'success': True, 'message': 'Category disabled'})
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to delete category'}), 500


# ========================================
# EMAIL NOTIFICATIONS FOR KEY EVENTS
# ========================================

def send_event_email(to_email, to_name, subject, body_html):
    """Send transactional email for key platform events"""
    if not config.SENDGRID_API_KEY:
        print(f"⚠️ SendGrid not configured — skipping email to {to_email}")
        return False
    try:
        from sendgrid import SendGridAPIClient
        from sendgrid.helpers.mail import Mail
        message = Mail(
            from_email=config.FROM_EMAIL,
            to_emails=to_email,
            subject=f'{config.APP_NAME} - {subject}',
            html_content=f'''
                <div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px;border:1px solid #e2e8f0;border-radius:12px;">
                    <div style="text-align:center;margin-bottom:16px;">
                        <h2 style="color:#6366f1;margin:0;">Workmate4u</h2>
                    </div>
                    <p>Hi {html_escape(to_name)},</p>
                    {body_html}
                    <hr style="border:none;border-top:1px solid #e2e8f0;margin:20px 0;">
                    <p style="color:#888;font-size:12px;text-align:center;">
                        You're receiving this because you have an account on Workmate4u.<br>
                        <a href="https://www.workmate4u.com" style="color:#6366f1;">www.workmate4u.com</a>
                    </p>
                </div>
            '''
        )
        sg = SendGridAPIClient(config.SENDGRID_API_KEY)
        sg.send(message)
        print(f"📧 Event email sent to {to_email}: {subject}")
        return True
    except Exception as e:
        print(f"⚠️ Event email failed for {to_email}: {e}")
        return False


def notify_task_accepted_email(poster_id, helper_name, task_title):
    """Email poster when their task is accepted"""
    try:
        user = get_user_by_id(poster_id)
        if user:
            send_event_email(user['email'], user['name'],
                'Your Task Was Accepted! ✅',
                f'<p>Great news! <strong>{html_escape(helper_name)}</strong> has accepted your task:</p>'
                f'<div style="background:#f0f0ff;padding:12px;border-radius:8px;margin:12px 0;">'
                f'<strong>{html_escape(task_title)}</strong></div>'
                f'<p>You can chat with them to discuss details.</p>')
    except Exception as e:
        print(f"⚠️ notify_task_accepted_email error: {e}")


def notify_task_completed_email(poster_id, helper_name, task_title, task_amount, service_charge, poster_fee, total_cost, task_id=None):
    """Email poster when task is completed with price breakdown and Pay Now button"""
    try:
        user = get_user_by_id(poster_id)
        if user:
            breakdown_html = (
                f'<p><strong>{html_escape(helper_name)}</strong> has completed your task:</p>'
                f'<div style="background:#f9fafb;border:1px solid #e5e7eb;border-radius:10px;padding:16px;margin:16px 0;">'
                f'<h3 style="margin:0 0 12px 0;color:#374151;font-size:16px;">{html_escape(task_title)}</h3>'
                f'<table style="width:100%;border-collapse:collapse;font-size:14px;">'
                f'<tr style="border-bottom:1px solid #f3f4f6;">'
                f'<td style="padding:8px 0;color:#6b7280;">Budget</td>'
                f'<td style="padding:8px 0;text-align:right;font-weight:600;color:#111827;">₹{task_amount:.2f}</td></tr>'
            )
            if service_charge > 0:
                breakdown_html += (
                    f'<tr style="border-bottom:1px solid #f3f4f6;">'
                    f'<td style="padding:8px 0;color:#6b7280;">Service Charge</td>'
                    f'<td style="padding:8px 0;text-align:right;font-weight:600;color:#d97706;">+₹{service_charge:.2f}</td></tr>'
                )
            # poster_fee row removed (posting fee disabled)
            breakdown_html += (
                f'<tr>'
                f'<td style="padding:10px 0;color:#111827;font-weight:700;font-size:16px;">Total to Pay</td>'
                f'<td style="padding:10px 0;text-align:right;font-weight:800;font-size:16px;color:#dc2626;">₹{total_cost:.2f}</td></tr>'
                f'</table></div>'
                f'<div style="text-align:center;margin:20px 0 8px 0;">'
                f'<a href="https://www.workmate4u.com/index.html?pay={task_id}" '
                f'style="display:inline-block;background:#6366f1;color:#ffffff;padding:14px 36px;'
                f'border-radius:8px;text-decoration:none;font-weight:700;font-size:15px;">'
                f'💳 Pay Now</a></div>'
                f'<p style="color:#6b7280;font-size:12px;text-align:center;margin-top:8px;">'
                f'Log in to your account and approve the payment from your wallet.</p>'
            )
            send_event_email(user['email'], user['name'],
                'Task Completed! 🎉', breakdown_html)
    except Exception as e:
        print(f"⚠️ notify_task_completed_email error: {e}")


def notify_payment_received_email(helper_id, task_title, amount, task_amount=0, service_charge=0, commission=0):
    """Email helper when they receive payment with earnings breakdown"""
    try:
        user = get_user_by_id(helper_id)
        if user:
            breakdown_html = (
                f'<p>Great news! You\'ve been paid for completing:</p>'
                f'<div style="background:#f9fafb;border:1px solid #e5e7eb;border-radius:10px;padding:16px;margin:16px 0;">'
                f'<h3 style="margin:0 0 12px 0;color:#374151;font-size:16px;">{html_escape(task_title)}</h3>'
                f'<table style="width:100%;border-collapse:collapse;font-size:14px;">'
                f'<tr style="border-bottom:1px solid #f3f4f6;">'
                f'<td style="padding:8px 0;color:#6b7280;">Task Price</td>'
                f'<td style="padding:8px 0;text-align:right;font-weight:600;color:#111827;">₹{task_amount:.2f}</td></tr>'
            )
            if service_charge > 0:
                breakdown_html += (
                    f'<tr style="border-bottom:1px solid #f3f4f6;">'
                    f'<td style="padding:8px 0;color:#6b7280;">Service Charge</td>'
                    f'<td style="padding:8px 0;text-align:right;font-weight:600;color:#d97706;">+₹{service_charge:.2f}</td></tr>'
                )
            total_task_val = task_amount + service_charge
            breakdown_html += (
                f'<tr style="border-bottom:1px solid #f3f4f6;">'
                f'<td style="padding:8px 0;color:#6b7280;font-weight:700;">Task Value</td>'
                f'<td style="padding:8px 0;text-align:right;font-weight:700;color:#111827;">₹{total_task_val:.2f}</td></tr>'
                f'<tr style="border-bottom:1px solid #f3f4f6;">'
                f'<td style="padding:8px 0;color:#6b7280;">Platform Commission</td>'
                f'<td style="padding:8px 0;text-align:right;font-weight:600;color:#dc2626;">-₹{commission:.2f}</td></tr>'
                f'<tr>'
                f'<td style="padding:10px 0;color:#059669;font-weight:700;font-size:16px;">Your Earnings</td>'
                f'<td style="padding:10px 0;text-align:right;font-weight:800;font-size:16px;color:#059669;">₹{amount:.2f}</td></tr>'
                f'</table></div>'
                f'<p style="color:#374151;">The money has been added to your wallet. You can withdraw anytime.</p>'
            )
            send_event_email(user['email'], user['name'],
                'Payment Received! 💰', breakdown_html)
    except Exception as e:
        print(f"⚠️ notify_payment_received_email error: {e}")


def notify_withdrawal_processed_email(user_id, amount, status):
    """Email user when withdrawal is processed"""
    try:
        user = get_user_by_id(user_id)
        if user:
            if status == 'completed':
                send_event_email(user['email'], user['name'],
                    'Withdrawal Processed! 🏦',
                    f'<p>Your withdrawal of <strong>₹{amount}</strong> has been processed and sent to your bank account.</p>'
                    f'<p>It may take 1-3 business days to reflect in your account.</p>')
            else:
                send_event_email(user['email'], user['name'],
                    'Withdrawal Update',
                    f'<p>Your withdrawal request of <strong>₹{amount}</strong> status: <strong>{status}</strong></p>')
    except Exception as e:
        print(f"⚠️ notify_withdrawal_email error: {e}")


def notify_account_suspended_email(user_id, reason):
    """Email user when account is suspended"""
    try:
        user = get_user_by_id(user_id)
        if user:
            send_event_email(user['email'], user['name'],
                'Account Suspended ⚠️',
                f'<p>Your account has been suspended.</p>'
                f'<p><strong>Reason:</strong> {html_escape(reason or "Policy violation")}</p>'
                f'<p>If you believe this is an error, please contact support.</p>')
    except Exception as e:
        print(f"⚠️ notify_suspended_email error: {e}")


# ========================================
# USER VERIFICATION / KYC
# ========================================

@app.route('/api/user/kyc/submit', methods=['POST'])
@require_auth
def submit_kyc():
    """Submit KYC document for verification (with anti-fraud checks).
    Accepts two request formats:
      - multipart/form-data (mobile app): files in 'documentImageFront' / 'documentImageBack'
      - application/json     (website):   base64 data URIs in JSON body
    Images are always stored as 'data:<mime>;base64,<b64>' so the admin panel
    can render them directly with <img src="..."> without triggering 414 errors.
    """
    import base64 as _b64

    def _file_to_data_uri(field_name):
        """Convert a multipart file field to a base64 data URI string."""
        f = request.files.get(field_name)
        if not f:
            return ''
        raw = f.read()
        if not raw:
            return ''
        mime = (f.content_type or 'image/jpeg').split(';')[0].strip() or 'image/jpeg'
        return f'data:{mime};base64,{_b64.b64encode(raw).decode()}'

    content_type = request.content_type or ''
    if 'multipart/form-data' in content_type:
        # Mobile app sends binary files via multipart — convert to data URIs for DB storage
        doc_type = (request.form.get('documentType') or '').strip()
        doc_number = (request.form.get('documentNumber') or '').strip()
        acknowledged = request.form.get('acknowledged', 'false').lower() in ('true', '1', 'yes')
        doc_image_front = _file_to_data_uri('documentImageFront')
        doc_image_back = _file_to_data_uri('documentImageBack')
    else:
        # Website sends JSON with base64 data URI strings
        data = request.get_json() or {}
        doc_type = (data.get('documentType') or '').strip()
        doc_number = (data.get('documentNumber') or '').strip()
        # Accept new front/back fields; fall back to legacy documentImage field
        doc_image_front = data.get('documentImageFront') or data.get('documentImage', '')
        doc_image_back = data.get('documentImageBack') or ''
        if doc_image_front:
            doc_image_front = doc_image_front.strip()
        if doc_image_back:
            doc_image_back = doc_image_back.strip()
        # Ensure stored value always has the data URI prefix so <img src> renders inline
        def _ensure_data_uri(s):
            if s and not s.startswith('data:'):
                return f'data:image/jpeg;base64,{s}'
            return s
        doc_image_front = _ensure_data_uri(doc_image_front)
        doc_image_back = _ensure_data_uri(doc_image_back)
        acknowledged = bool(data.get('acknowledged'))

    # Mandatory legal declaration (acts as legal evidence in case of fraud)
    if not acknowledged:
        return jsonify({
            'success': False,
            'message': 'You must accept the legal declaration that the documents are genuine and belong to you. Submitting fake or stolen documents is a punishable offence under the IT Act and IPC §420.',
            'needsAcknowledge': True
        }), 400

    valid_types = ['aadhaar', 'pan', 'voter_id', 'driving_license']
    if doc_type not in valid_types:
        return jsonify({'success': False, 'message': 'Invalid document type'}), 400

    if not doc_number or len(doc_number) < 6 or len(doc_number) > 20:
        return jsonify({'success': False, 'message': 'Invalid document number'}), 400

    if not doc_image_front:
        return jsonify({'success': False, 'message': 'Please upload the front side of the document'}), 400

    if doc_type == 'aadhaar' and not doc_image_back:
        return jsonify({'success': False, 'message': 'Please upload the back side of your Aadhaar card'}), 400

    # Validate image sizes (max 5MB each; base64 overhead ~33%)
    if len(doc_image_front) > 7_000_000:
        return jsonify({'success': False, 'message': 'Front image too large (max 5MB)'}), 400
    if doc_image_back and len(doc_image_back) > 7_000_000:
        return jsonify({'success': False, 'message': 'Back image too large (max 5MB)'}), 400

    # Format validation
    import re
    doc_number_norm = doc_number.upper().replace(' ', '')
    if doc_type == 'aadhaar':
        if not re.match(r'^\d{12}$', doc_number_norm):
            return jsonify({'success': False, 'message': 'Aadhaar must be 12 digits'}), 400
        # UIDAI Verhoeff checksum — rejects randomly typed 12-digit numbers
        if not _aadhaar_verhoeff_valid(doc_number_norm):
            return jsonify({
                'success': False,
                'message': 'This Aadhaar number is invalid (failed checksum). Please re-enter the correct number from your card.'
            }), 400
    if doc_type == 'pan':
        if not re.match(r'^[A-Z]{5}[0-9]{4}[A-Z]$', doc_number_norm):
            return jsonify({'success': False, 'message': 'Invalid PAN format (e.g. ABCDE1234F)'}), 400

    _ensure_kyc_columns()

    # Image quality check (soft — flags for review, doesn't reject)
    flags = []
    q_ok_front, q_reason_front = _kyc_image_quality_check(doc_image_front)
    if not q_ok_front:
        flags.append(f'front: {q_reason_front}')
    if doc_image_back:
        q_ok_back, q_reason_back = _kyc_image_quality_check(doc_image_back)
        if not q_ok_back:
            flags.append(f'back: {q_reason_back}')

    # Duplicate-image hash detection (anti-fraud: same Aadhaar scan reused by different account)
    front_hash = _hash_kyc_image(doc_image_front)
    back_hash = _hash_kyc_image(doc_image_back) if doc_image_back else None
    duplicate_user_id = None
    try:
        with get_db() as (cursor, conn):
            for h in [x for x in (front_hash, back_hash) if x]:
                cursor.execute(
                    f"SELECT id FROM users WHERE kyc_document_image_hash = {PH} AND id != {PH} LIMIT 1",
                    (h, request.user_id),
                )
                row = cursor.fetchone()
                if row:
                    duplicate_user_id = row[0] if not isinstance(row, dict) else row.get('id')
                    break
            # Same document number used by a different user
            cursor.execute(
                f"SELECT id FROM users WHERE kyc_document_number = {PH} AND id != {PH} LIMIT 1",
                (doc_number_norm, request.user_id),
            )
            num_dup = cursor.fetchone()
    except Exception as _e:
        print(f"[KYC SUBMIT] dup-check failed: {_e}")
        num_dup = None

    if duplicate_user_id:
        # Hard reject — same image already submitted by another user
        try:
            with get_db() as (cursor, conn):
                cursor.execute(
                    f"UPDATE users SET kyc_status = 'rejected', kyc_flag_reason = {PH} WHERE id = {PH}",
                    (f'Duplicate document image (also used by user {duplicate_user_id})', request.user_id),
                )
                now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                cursor.execute(f'''
                    INSERT INTO notifications (user_id, notification_type, title, message, status, created_at)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                ''', ('1', 'kyc_request', '🚨 KYC Fraud Alert',
                      f'User {request.user_id} tried to submit a document image already used by user {duplicate_user_id}. Auto-rejected.',
                      'unread', now))
        except Exception:
            pass
        return jsonify({
            'success': False,
            'message': 'This document has already been submitted by another account. Submitting another person\'s documents is fraud and has been reported. If this is a mistake, contact support.',
            'fraudDetected': True
        }), 409

    if num_dup:
        return jsonify({
            'success': False,
            'message': 'This document number is already registered with another account. If you believe this is wrong, contact support.',
        }), 409

    # Decide final status: pending if any quality flag, else verified
    final_status = 'pending' if flags else 'verified'
    flag_reason_text = '; '.join(flags) if flags else None

    try:
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                UPDATE users SET kyc_document_type = {PH}, kyc_document_number = {PH},
                kyc_document_image = {PH}, kyc_document_image_back = {PH},
                kyc_document_image_hash = {PH},
                kyc_status = {PH}, kyc_verified_at = {PH},
                kyc_flag_reason = {PH}, kyc_acknowledged_at = {PH}
                WHERE id = {PH}
            ''', (doc_type, doc_number_norm, doc_image_front, doc_image_back or None,
                  front_hash,
                  final_status, (now if final_status == 'verified' else None),
                  flag_reason_text, now,
                  request.user_id))

            # Notify user
            if final_status == 'verified':
                user_msg = '✅ Your KYC verification has been approved!'
            else:
                user_msg = '📝 KYC received. Our team will review your documents shortly (usually within 24 hours).'
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, 'kyc_result', 'KYC Verification Update', user_msg, 'unread', now))

            # Log for admin
            admin_msg = f'User {request.user_id} submitted {doc_type} — '
            admin_msg += 'auto-verified' if final_status == 'verified' else f'pending review ({flag_reason_text})'
            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', ('1', 'kyc_request',
                  '📋 KYC Submitted' if final_status == 'verified' else '⚠️ KYC Needs Review',
                  admin_msg, 'unread', now))

        if final_status == 'verified':
            return jsonify({'success': True, 'message': 'KYC verified successfully! Your identity has been confirmed.', 'status': 'verified'})
        return jsonify({'success': True, 'message': 'KYC submitted. Our team will review and approve within 24 hours.', 'status': 'pending'})
    except Exception as e:
        print(f"[KYC SUBMIT] Error: {e}")
        return jsonify({'success': False, 'message': 'Failed to submit KYC'}), 500


@app.route('/api/user/kyc/status', methods=['GET'])
@require_auth
def get_kyc_status():
    """Get KYC verification status"""
    _ensure_kyc_columns()
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT kyc_status, kyc_document_type, kyc_document_number, kyc_verified_at,
                       phone_verified, email_verified, kyc_flag_reason,
                       CASE WHEN kyc_document_image IS NOT NULL THEN TRUE ELSE FALSE END AS has_image
                FROM users WHERE id = {PH}
            ''', (request.user_id,))
            row = cursor.fetchone()

        if not row:
            return jsonify({'success': False, 'message': 'User not found'}), 404

        row = dict_from_row(row)
        has_image = bool(row.get('has_image'))
        return jsonify({
            'success': True,
            'kyc': {
                'status': row.get('kyc_status', 'none'),
                'documentType': row.get('kyc_document_type'),
                'documentNumber': row.get('kyc_document_number'),
                'hasDocumentImage': has_image,
                'verifiedAt': row.get('kyc_verified_at'),
                'phoneVerified': bool(row.get('phone_verified')),
                'emailVerified': bool(row.get('email_verified')),
                'flagReason': row.get('kyc_flag_reason')
            }
        })
    except Exception as e:
        print(f"[KYC STATUS] Error: {e}")
        return jsonify({'success': False, 'message': 'Failed to get KYC status'}), 500


@app.route('/api/admin/user/<user_id>/kyc', methods=['GET'])
@require_admin
def admin_get_user_kyc(user_id):
    """Admin: get user KYC details including document image"""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                SELECT name, email, kyc_status, kyc_document_type, kyc_document_number,
                       kyc_document_image, kyc_document_image_back, kyc_verified_at
                FROM users WHERE id = {PH}
            ''', (user_id,))
            row = cursor.fetchone()
            if not row:
                return jsonify({'success': False, 'message': 'User not found'}), 404
            user_data = dict_from_row(row)

        return jsonify({
            'success': True,
            'user': {
                'name': user_data.get('name'),
                'email': user_data.get('email'),
                'kycStatus': user_data.get('kyc_status', 'none'),
                'documentType': user_data.get('kyc_document_type'),
                'documentNumber': user_data.get('kyc_document_number'),
                'documentImageFront': user_data.get('kyc_document_image'),
                'documentImageBack': user_data.get('kyc_document_image_back'),
                'verifiedAt': user_data.get('kyc_verified_at')
            }
        })
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to get KYC details'}), 500


@app.route('/api/admin/kyc/<user_id>/verify', methods=['POST'])
@require_admin
def admin_verify_kyc(user_id):
    """Admin: approve or reject KYC (admin)"""
    data = request.get_json()
    action = data.get('action', 'approve')  # approve or reject

    try:
        with get_db() as (cursor, conn):
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            if action == 'approve':
                cursor.execute(f'''
                    UPDATE users SET kyc_status = 'verified', kyc_verified_at = {PH}
                    WHERE id = {PH}
                ''', (now, user_id))
                msg = '✅ Your KYC verification has been approved!'
            else:
                cursor.execute(f'''
                    UPDATE users SET kyc_status = 'rejected'
                    WHERE id = {PH}
                ''', (user_id,))
                msg = '❌ Your KYC verification was rejected. Please resubmit.'

            cursor.execute(f'''
                INSERT INTO notifications (user_id, notification_type, title, message, status, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (user_id, 'kyc_result', 'KYC Verification Update', msg, 'unread', now))

            cursor.execute(f'''
                INSERT INTO admin_audit_log (admin_id, action, resource_type, resource_id, details, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            ''', (request.user_id, f'kyc_{action}', 'user', user_id, f'KYC {action}d', now))

        return jsonify({'success': True, 'message': f'KYC {action}d for user {user_id}'})
    except Exception as e:
        return jsonify({'success': False, 'message': 'Failed to process KYC'}), 500


# ========================================
# AI TEAM PANEL INTEGRATION ROUTES
# ========================================

_AI_TEAM_TOKEN = os.environ.get('WORKMATE_AI_TOKEN', 'workmate-ai-internal-2026')

def _require_ai_token(f):
    """Simple token auth for internal AI team calls (no JWT needed)."""
    from functools import wraps
    @wraps(f)
    def _inner(*args, **kwargs):
        token = request.headers.get('X-AI-Token', '')
        if token != _AI_TEAM_TOKEN:
            return jsonify({'success': False, 'message': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return _inner


@app.route('/api/ai-team/actions', methods=['GET'])
@require_admin
def ai_team_actions_list():
    """Admin: list all actions taken by the AI team (audit log entries from ai_team)."""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f"""
                SELECT id, action, resource_type, resource_id, details, created_at
                FROM admin_audit_log
                WHERE admin_id = 'ai_team'
                ORDER BY created_at DESC
                LIMIT 100
            """)
            rows = cursor.fetchall()
            actions = []
            for r in rows:
                row = dict_from_row(r)
                actions.append({
                    'id':            row.get('id'),
                    'action':        row.get('action'),
                    'resource_type': row.get('resource_type'),
                    'resource_id':   row.get('resource_id'),
                    'details':       row.get('details'),
                    'created_at':    str(row.get('created_at', ''))[:16],
                })
        return jsonify({'success': True, 'actions': actions})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/ai-team/flagged-tasks', methods=['GET'])
@require_admin
def ai_team_flagged_tasks():
    """Admin: list all tasks currently flagged or suspicious by the AI fraud agent."""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f"""
                SELECT t.id, t.title, t.description, t.price, t.status, t.category,
                       t.posted_at, u.name AS poster_name, u.email AS poster_email
                FROM tasks t
                JOIN users u ON t.posted_by = u.id
                WHERE t.status IN ('flagged', 'suspicious', 'removed')
                ORDER BY t.posted_at DESC
                LIMIT 50
            """)
            rows = cursor.fetchall()
            tasks = []
            for r in rows:
                row = dict_from_row(r)
                tasks.append({
                    'id':           row.get('id'),
                    'title':        row.get('title'),
                    'description':  str(row.get('description') or '')[:100],
                    'price':        row.get('price'),
                    'status':       row.get('status'),
                    'category':     row.get('category'),
                    'posted_at':    str(row.get('posted_at', ''))[:16],
                    'poster_name':  row.get('poster_name'),
                    'poster_email': row.get('poster_email'),
                })
        return jsonify({'success': True, 'tasks': tasks})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/ai-team/reports', methods=['GET'])
@require_admin
def ai_team_get_reports():
    """Admin: get agent reports optionally filtered by agent_id."""
    agent_id = request.args.get('agent_id', '').strip()
    limit = min(int(request.args.get('limit', 50)), 200)
    try:
        with get_db() as (cursor, conn):
            if agent_id:
                cursor.execute(f"""
                    SELECT id, action, resource_id, details, created_at
                    FROM admin_audit_log
                    WHERE admin_id = 'ai_team'
                      AND resource_type = 'ai_agent'
                      AND action LIKE 'agent_report:%'
                      AND resource_id = {PH}
                    ORDER BY created_at DESC
                    LIMIT {PH}
                """, (agent_id, limit))
            else:
                cursor.execute(f"""
                    SELECT id, action, resource_id, details, created_at
                    FROM admin_audit_log
                    WHERE admin_id = 'ai_team'
                      AND resource_type = 'ai_agent'
                      AND action LIKE 'agent_report:%'
                    ORDER BY created_at DESC
                    LIMIT {PH}
                """, (limit,))
            rows = cursor.fetchall()
            import json as _json
            reports = []
            for r in rows:
                row = dict_from_row(r)
                try:
                    details = _json.loads(row.get('details', '{}') or '{}')
                except Exception:
                    details = {}
                reports.append({
                    'id':         row.get('id'),
                    'agent_id':   row.get('resource_id'),
                    'status':     (row.get('action', '') or '').split(':')[-1],
                    'title':      details.get('title', ''),
                    'summary':    details.get('summary', ''),
                    'stats':      details.get('stats', {}),
                    'created_at': str(row.get('created_at', ''))[:16],
                })
        return jsonify({'success': True, 'reports': reports})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/ai-team/fixes', methods=['GET'])
@require_admin
def ai_team_get_fixes():
    """Admin: get actions/fixes taken by the AI team, optionally filtered by agent_id stored in details."""
    agent_id = request.args.get('agent_id', '').strip()
    limit = min(int(request.args.get('limit', 50)), 200)
    try:
        with get_db() as (cursor, conn):
            if agent_id:
                # Filter: action must NOT be an agent_report, and details must contain the agent_id
                if config.USE_POSTGRES:
                    cursor.execute(f"""
                        SELECT id, action, resource_type, resource_id, details, created_at
                        FROM admin_audit_log
                        WHERE admin_id = 'ai_team'
                          AND action NOT LIKE 'agent_report:%'
                          AND details::text LIKE {PH}
                        ORDER BY created_at DESC
                        LIMIT {PH}
                    """, (f'%{agent_id}%', limit))
                else:
                    cursor.execute(f"""
                        SELECT id, action, resource_type, resource_id, details, created_at
                        FROM admin_audit_log
                        WHERE admin_id = 'ai_team'
                          AND action NOT LIKE 'agent_report:%'
                          AND details LIKE {PH}
                        ORDER BY created_at DESC
                        LIMIT {PH}
                    """, (f'%{agent_id}%', limit))
            else:
                cursor.execute(f"""
                    SELECT id, action, resource_type, resource_id, details, created_at
                    FROM admin_audit_log
                    WHERE admin_id = 'ai_team'
                      AND action NOT LIKE 'agent_report:%'
                    ORDER BY created_at DESC
                    LIMIT {PH}
                """, (limit,))
            rows = cursor.fetchall()
            import json as _json
            fixes = []
            for r in rows:
                row = dict_from_row(r)
                try:
                    details = _json.loads(row.get('details', '{}') or '{}')
                except Exception:
                    details = {}
                fixes.append({
                    'id':            row.get('id'),
                    'action':        row.get('action'),
                    'resource_type': row.get('resource_type'),
                    'resource_id':   row.get('resource_id'),
                    'details':       details,
                    'created_at':    str(row.get('created_at', ''))[:16],
                })
        return jsonify({'success': True, 'fixes': fixes})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/ai-team/report', methods=['POST'])
def ai_team_receive_report():
    """AI Team Panel posts its agent reports here so admin panel can display them.
    Auth: X-AI-Token header. No JWT required (internal service-to-service)."""
    token = request.headers.get('X-AI-Token', '')
    if token != _AI_TEAM_TOKEN:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401

    data = request.get_json() or {}
    report = data.get('report', {})
    if not report or not report.get('agent_id'):
        return jsonify({'success': False, 'message': 'Invalid report payload'}), 400

    try:
        with get_db() as (cursor, conn):
            import json as _json
            now = datetime.datetime.now(datetime.timezone.utc).isoformat()
            # Store in admin_audit_log as a JSON blob for now
            cursor.execute(f"""
                INSERT INTO admin_audit_log
                    (admin_id, action, resource_type, resource_id, details, created_at)
                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH})
            """, (
                'ai_team',
                f"agent_report:{report.get('status','info')}",
                'ai_agent',
                report.get('agent_id'),
                _json.dumps({
                    'title':   report.get('title', ''),
                    'summary': report.get('summary', ''),
                    'status':  report.get('status', 'info'),
                    'stats':   report.get('stats', {}),
                    'fixes':   report.get('fixes', []),
                }, ensure_ascii=False)[:4000],
                now,
            ))
        return jsonify({'success': True, 'message': 'Report stored'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# ========================================
# PUBLIC PLATFORM STATS (no auth required)
# ========================================

@app.route('/api/platform-stats', methods=['GET'])
@rate_limit('30 per minute')
def platform_stats():
    """Return real-time platform statistics for the hero section (public, cached)."""
    try:
        with get_db() as (cursor, conn):
            # Count tasks in any "finished work" state. After a task is paid by the
            # poster it transitions completed -> paid, so we must include both to
            # avoid the counter shrinking over time.
            cursor.execute(f'''
                SELECT
                    (SELECT COUNT(*) FROM users) AS total_users,
                    (SELECT COUNT(*) FROM tasks WHERE status IN ('completed', 'paid')) AS completed_tasks,
                    (SELECT COALESCE(SUM(total_earned), 0) FROM wallets) AS total_earned
            ''')
            row = cursor.fetchone()
            if row:
                r = dict_from_row(row) if not isinstance(row, dict) else row
                return jsonify({
                    'success': True,
                    'users': int(r.get('total_users', 0)),
                    'completedTasks': int(r.get('completed_tasks', 0)),
                    'totalEarned': float(r.get('total_earned', 0))
                })
        return jsonify({'success': False}), 500
    except Exception as e:
        print(f"[PLATFORM STATS] Error: {e}")
        return jsonify({'success': False}), 500


# ========================================
# GOOGLE SOCIAL LOGIN
# ========================================

@app.route('/api/config/google-client-id', methods=['GET'])
def get_google_client_id():
    """Return the Google Client ID for frontend initialization."""
    client_id = os.environ.get('GOOGLE_CLIENT_ID', '')
    if not client_id:
        return jsonify({'success': False, 'message': 'Google Sign-In not configured'}), 404
    return jsonify({'success': True, 'clientId': client_id})


def _ensure_google_auth_schema():
    """Ensure Google auth columns/tables exist before running login queries.

    Retries once after calling init_db() if the users table does not exist yet
    (race condition during cold start while background init_db thread is still
    running).  Errors are re-raised so the caller can surface an HTTP 503.
    """
    global _google_auth_schema_ensured
    if _google_auth_schema_ensured:
        return

    import time as _time_sch
    for _attempt in range(2):
        try:
            with get_db() as (cursor, conn):
                cursor.execute('ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(255) UNIQUE')
                cursor.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(20) DEFAULT 'email'")
                cursor.execute('ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT FALSE')
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS deleted_accounts (
                        email VARCHAR(255) PRIMARY KEY,
                        google_id VARCHAR(255),
                        deleted_at TIMESTAMP DEFAULT NOW()
                    )
                ''')
                cursor.execute('''
                    CREATE INDEX IF NOT EXISTS idx_deleted_accounts_google_id
                    ON deleted_accounts (google_id) WHERE google_id IS NOT NULL
                ''')
            _google_auth_schema_ensured = True
            return
        except Exception as _sch_exc:
            if _attempt == 0:
                _sch_err = str(_sch_exc).lower()
                if any(k in _sch_err for k in ['relation', 'does not exist', 'no such table', 'undefined table']):
                    # Tables not created yet — background init_db may still be
                    # running on cold start. Trigger a synchronous init and retry.
                    print(f'[GOOGLE AUTH SCHEMA] users table missing, running init_db: {_sch_exc}')
                    try:
                        init_db()
                    except Exception as _init_e:
                        print(f'[GOOGLE AUTH SCHEMA] init_db failed: {_init_e}')
                    _time_sch.sleep(0.5)
                    continue
            # Second attempt or unexpected error — propagate to caller
            raise

@app.route('/api/auth/google', methods=['POST'])
@rate_limit('10 per minute')
def google_login():
    """Login or register via Google ID token"""
    data = request.get_json(silent=True) or {}
    id_token = data.get('credential', '')
    invite_code = (data.get('invite_code') or '').strip().upper()

    if not id_token:
        return jsonify({'success': False, 'message': 'Google credential is required'}), 400

    try:
        # Ensure Google auth schema is ready. Return 503 if the DB isn't up
        # yet (background init_db may still be running on cold start); the
        # Netlify proxy retries automatically on 5xx.
        try:
            _ensure_google_auth_schema()
        except Exception as _sch_e:
            print(f'[GOOGLE LOGIN] Schema ensure failed: {_sch_e}')
            return jsonify({'success': False, 'message': 'Login service is starting up. Please try again in a few seconds.'}), 503

        # Verify Google ID token
        import urllib.request
        import urllib.error
        import json as json_mod
        # Use Google's tokeninfo endpoint to verify
        token_url = f'https://oauth2.googleapis.com/tokeninfo?id_token={id_token}'
        req = urllib.request.Request(token_url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            google_data = json_mod.loads(resp.read().decode())

        # Verify the token audience matches our client ID
        expected_client_id = os.environ.get('GOOGLE_CLIENT_ID', '')
        token_aud = google_data.get('aud', '')
        if expected_client_id and token_aud != expected_client_id:
            return jsonify({'success': False, 'message': 'Invalid token audience'}), 401

        google_id = google_data.get('sub')
        email = google_data.get('email', '').lower()
        name = google_data.get('name', '')
        picture = google_data.get('picture', '')

        if not google_id or not email:
            return jsonify({'success': False, 'message': 'Invalid Google token'}), 401

        # Retry DB block for transient startup/connectivity failures.
        user = None
        for db_attempt in range(2):
            try:
                with get_db() as (cursor, conn):
                    # Check if user exists by google_id
                    cursor.execute(f'SELECT id FROM users WHERE google_id = {PH}', (google_id,))
                    existing = cursor.fetchone()

                    if existing:
                        # Existing Google user — login (no invite code needed)
                        user_id = dict_from_row(existing)['id']
                        last_login = datetime.datetime.now(datetime.timezone.utc).isoformat()
                        cursor.execute(f'UPDATE users SET last_login = {PH} WHERE id = {PH}', (last_login, user_id))
                    else:
                        # Check if this email/google_id was previously deleted by admin
                        cursor.execute(f'SELECT email FROM deleted_accounts WHERE email = {PH} OR google_id = {PH}', (email, google_id))
                        if cursor.fetchone():
                            return jsonify({'success': False, 'message': 'This account has been removed. Contact support if you believe this is a mistake.'}), 403

                        # Check if email already registered (link accounts — also no invite needed)
                        cursor.execute(f'SELECT id FROM users WHERE email = {PH}', (email,))
                        email_user = cursor.fetchone()

                        if email_user:
                            user_id = dict_from_row(email_user)['id']
                            # Guard against linking a Google ID already attached to a different account.
                            cursor.execute(f'SELECT id FROM users WHERE google_id = {PH}', (google_id,))
                            existing_google_owner = cursor.fetchone()
                            if existing_google_owner and dict_from_row(existing_google_owner)['id'] != user_id:
                                return jsonify({
                                    'success': False,
                                    'message': 'This Google account is already linked to another user.'
                                }), 409
                            cursor.execute(f'''
                                UPDATE users SET google_id = {PH}, auth_provider = 'google'
                                WHERE id = {PH}
                            ''', (google_id, user_id))
                        else:
                            # Brand-new user — apply trial checks before creating account
                            if config.TRIAL_ACTIVE:
                                import datetime as _dt
                                # Validate invite code
                                if invite_code != config.TRIAL_INVITE_CODE.upper():
                                    return jsonify({'success': False, 'message': 'Invalid invite code. This is a closed beta — you need an invite code to join.', 'needsInviteCode': True}), 403
                                # Check trial end date
                                try:
                                    end_date = _dt.date.fromisoformat(config.TRIAL_END_DATE)
                                except ValueError:
                                    end_date = _dt.date.today() + _dt.timedelta(days=30)
                                if _dt.date.today() > end_date:
                                    return jsonify({'success': False, 'message': 'The trial period has ended. Stay tuned for the public launch!'}), 403
                                # Check user cap
                                cursor.execute('SELECT COUNT(*) as cnt FROM users')
                                row = dict_from_row(cursor.fetchone())
                                if (row['cnt'] or 0) >= config.TRIAL_MAX_USERS:
                                    return jsonify({'success': False, 'message': "All trial spots are taken. We'll notify you when we launch publicly!"}), 403

                            # Register new Google user
                            user_id = generate_user_id()
                            joined_at = datetime.datetime.now(datetime.timezone.utc).isoformat()
                            # Google users get a random password (they never use it)
                            random_pw = generate_password_hash(secrets.token_hex(32), method='pbkdf2:sha256')
                            cursor.execute(f'''
                                INSERT INTO users (id, name, email, password_hash, google_id, auth_provider,
                                                  email_verified, profile_photo, joined_at)
                                VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
                            ''', (user_id, name, email, random_pw, google_id, 'google',
                                  True, picture, joined_at))

                            # Create wallet
                            cursor.execute(f'''
                                INSERT INTO wallets (user_id, balance, created_at)
                                VALUES ({PH}, 0, {PH})
                            ''', (user_id, joined_at))

                    user = get_user_by_id(user_id)
                    if user and user.get('is_banned'):
                        return jsonify({'success': False, 'message': 'Account is banned'}), 403
                break
            except Exception as db_exc:
                err = str(db_exc).lower()
                if any(k in err for k in ['unique constraint', 'duplicate key value', 'already exists']):
                    return jsonify({
                        'success': False,
                        'message': 'This Google account is already linked. Please sign in with the linked account.'
                    }), 409
                # If schema is not ready yet (cold deploy / partial migration),
                # run init and retry once before failing the request.
                schema_missing = any(k in err for k in [
                    'relation', 'does not exist', 'undefined table', 'undefined column',
                    'no such table', 'no such column'
                ])
                if schema_missing and db_attempt == 0:
                    try:
                        init_db()
                    except Exception:
                        pass
                    import time as _time
                    _time.sleep(0.6)
                    continue
                transient = any(k in err for k in ['could not connect', 'connection', 'timeout', 'server closed', 'operationalerror', 'database'])
                if transient and db_attempt == 0:
                    import time as _time
                    _time.sleep(0.8)
                    continue
                raise

        token = generate_jwt_token(user_id, email)
        user = user or get_user_by_id(user_id)

        return jsonify({
            'success': True,
            'message': 'Google login successful',
            'token': token,
            'user': user_to_response(user)
        })

    except urllib.error.URLError:
        return jsonify({'success': False, 'message': 'Could not verify Google token'}), 401
    except Exception as e:
        print(f"[GOOGLE LOGIN] Error: {e}")
        import traceback
        traceback.print_exc()
        err = str(e).lower()
        if any(k in err for k in [
            'could not connect', 'connection', 'timeout', 'server closed',
            'operationalerror', 'database', 'relation', 'does not exist',
            'no such table', 'undefined table',
        ]):
            return jsonify({'success': False, 'message': 'Login service is warming up. Please try again in a few seconds.'}), 503
        return jsonify({'success': False, 'message': 'Google login failed'}), 500


# ========================================
# PUSH NOTIFICATION SUBSCRIPTIONS
# ========================================

@app.route('/api/push/vapid-key', methods=['GET'])
def get_vapid_key():
    """Return the VAPID public key so the frontend can subscribe."""
    return jsonify({'success': True, 'publicKey': VAPID_PUBLIC_KEY})


@app.route('/api/push/subscribe', methods=['POST'])
@require_auth
def push_subscribe():
    """Save (or update) a push subscription for the authenticated user."""
    data = request.get_json() or {}
    subscription = data.get('subscription')
    if not subscription:
        return jsonify({'success': False, 'message': 'No subscription object provided'}), 400
    lat = data.get('lat')
    lng = data.get('lng')
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        with get_db() as (cursor, conn):
            # Upsert: update subscription if user already has one
            cursor.execute(
                f'''INSERT INTO push_subscriptions (user_id, subscription_json, created_at, lat, lng)
                    VALUES ({PH}, {PH}, {PH}, {PH}, {PH})
                    ON CONFLICT (user_id) DO UPDATE
                        SET subscription_json = EXCLUDED.subscription_json,
                            lat = EXCLUDED.lat,
                            lng = EXCLUDED.lng''',
                (str(request.user_id), json.dumps(subscription), now, lat, lng)
            )
        return jsonify({'success': True})
    except Exception as e:
        print(f'[push] subscribe error: {e}')
        return jsonify({'success': False, 'message': 'Could not save subscription'}), 500


@app.route('/api/push/unsubscribe', methods=['POST'])
@require_auth
def push_unsubscribe():
    """Remove the push subscription for the authenticated user."""
    try:
        with get_db() as (cursor, conn):
            cursor.execute(
                f'DELETE FROM push_subscriptions WHERE user_id = {PH}',
                (str(request.user_id),)
            )
        return jsonify({'success': True})
    except Exception as e:
        print(f'[push] unsubscribe error: {e}')
        return jsonify({'success': False, 'message': 'Error removing subscription'}), 500


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
    
    # Clear expired timer suspensions on startup + start periodic cleanup
    try:
        cleanup_expired_suspensions()
        import threading
        t = threading.Thread(target=_run_periodic_cleanup, daemon=True)
        t.start()
        print("✅ Periodic suspension cleanup thread started (every 5 min)")
    except Exception as susp_error:
        print(f"⚠️  Suspension cleanup failed at startup (non-fatal): {susp_error}")
    
    # Get port from environment (Railway/Render provide this)
    port = int(os.environ.get('PORT', 5000))
    
    print("=" * 50)
    print(f"🚀 {config.APP_NAME} Backend Server")
    print("=" * 50)
    print(f"📍 Running on: http://0.0.0.0:{port}")
    print(f"📚 API Docs: /api/health")
    print("💾 Database: PostgreSQL")
    print("=" * 50)
    
    # Run Flask server
    app.run(host='0.0.0.0', port=port, debug=False, threaded=True)

