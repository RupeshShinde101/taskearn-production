"""
Database module for TaskEarn
PostgreSQL-only database backend
"""

import os
import datetime
from contextlib import contextmanager
from config import get_config

config = get_config()

# Try to import psycopg2 for PostgreSQL
try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
    POSTGRES_AVAILABLE = True
except ImportError:
    POSTGRES_AVAILABLE = False
    print("❌ psycopg2 not installed")


# ========================================
# DATABASE CONNECTION
# ========================================

def _build_secure_dsn(database_url: str, connect_timeout: int = 3) -> str:
    """
    Build a DSN for Railway PostgreSQL.

    Railway private networking (*.railway.internal):
      - No TLS on the internal network → sslmode=disable
      - "Connection terminated unexpectedly" is caused by sslmode=require/prefer
        sending a TLS handshake that the private Postgres instance rejects.

    Railway public proxy (*.proxy.rlwy.net or external host):
      - TLS is terminated at the proxy layer, not on Postgres itself.
      - sslmode=require causes the same "Connection terminated unexpectedly"
        because the Postgres process behind the proxy doesn't speak TLS.
      - sslmode=prefer tries TLS and silently falls back → safe.

    Rule: use disable for internal hostnames, prefer for everything else.
    """
    import urllib.parse as _up
    parsed = _up.urlparse(database_url)
    qs = dict(_up.parse_qsl(parsed.query))

    # Detect Railway private-network hostnames
    hostname = parsed.hostname or ''
    is_private = (
        hostname.endswith('.railway.internal')
        or hostname == 'postgres.railway.internal'
        or hostname.endswith('.internal')
    )

    if 'sslmode' not in qs:
        qs['sslmode'] = 'disable' if is_private else 'prefer'

    # Fail fast on network issues
    qs.setdefault('connect_timeout', str(connect_timeout))
    new_query = _up.urlencode(qs)
    secured = parsed._replace(query=new_query)
    return _up.urlunparse(secured)


def get_postgres_connection(retries: int = 2, delay: float = 0.3, connect_timeout: int = 3,
                            database_url: str = None):
    """
    Get a PostgreSQL connection with retry logic for transient Railway
    proxy drops (e.g. during deploys or idle-connection recycling).

    Pass database_url to override the default DATABASE_URL (used by admin routes
    to connect via the public proxy URL instead of the internal hostname).
    """
    if not POSTGRES_AVAILABLE:
        raise Exception("PostgreSQL driver not installed")

    import time as _time

    url = database_url or config.DATABASE_URL
    dsn = _build_secure_dsn(url, connect_timeout=connect_timeout)
    last_exc = None
    for attempt in range(1, retries + 1):
        try:
            conn = psycopg2.connect(dsn)
            with conn.cursor() as _cur:
                # Enforce a per-statement timeout (30 s is generous for this app)
                _cur.execute("SET statement_timeout = '30s'")
                _cur.execute("SET search_path = public")
            conn.commit()
            return conn
        except psycopg2.OperationalError as exc:
            last_exc = exc
            if attempt < retries:
                print(f"⚠️  DB connection attempt {attempt} failed: {exc} — retrying in {delay}s")
                _time.sleep(delay)
                delay *= 2  # exponential back-off
            else:
                print(f"❌  DB connection failed after {retries} attempts: {exc}")
    raise last_exc


@contextmanager
def get_db():
    """
    Get PostgreSQL database connection.

    When called from an admin route (require_admin sets flask.g.use_admin_db = True),
    automatically uses ADMIN_DATABASE_URL (public proxy) instead of DATABASE_URL
    (internal hostname) so admin-panel requests work even when private networking
    DNS is unavailable.
    """
    conn = None
    try:
        if not POSTGRES_AVAILABLE:
            raise RuntimeError("PostgreSQL driver not installed")

        # Check if this is an admin-context request (set by require_admin decorator)
        db_url = None
        try:
            from flask import g as _g
            if getattr(_g, 'use_admin_db', False):
                db_url = config.ADMIN_DATABASE_URL
        except RuntimeError:
            pass  # Outside request context — use default URL

        conn = get_postgres_connection(database_url=db_url)
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        yield cursor, conn
    except Exception as e:
        if conn:
            conn.rollback()
        raise e
    else:
        # Only commit if no exception occurred
        if conn:
            conn.commit()
    finally:
        if conn:
            conn.close()


# ========================================
# DATABASE INITIALIZATION
# ========================================

def init_postgres_db():
    """Initialize PostgreSQL database tables"""
    try:
        conn = get_postgres_connection()
        cursor = conn.cursor()
        
        print("[DB] Creating PostgreSQL tables...")
        
        # Users table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id VARCHAR(50) PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                email VARCHAR(255) UNIQUE NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                phone VARCHAR(20),
                dob VARCHAR(20),
                rating DECIMAL(3,2) DEFAULT 5.0,
                tasks_posted INTEGER DEFAULT 0,
                tasks_completed INTEGER DEFAULT 0,
                total_earnings DECIMAL(12,2) DEFAULT 0,
                is_suspended BOOLEAN DEFAULT FALSE,
                suspension_reason VARCHAR(255),
                suspended_at TIMESTAMP,
                suspended_until TIMESTAMP,
                daily_releases INTEGER DEFAULT 0,
                daily_release_date VARCHAR(20),
                profile_photo TEXT,
                joined_at TIMESTAMP NOT NULL,
                last_login TIMESTAMP,
                session_token VARCHAR(255)
            )
        ''')
        
        # Tasks table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS tasks (
                id SERIAL PRIMARY KEY,
                title VARCHAR(255) NOT NULL,
                description TEXT,
                category VARCHAR(50),
                location_lat DECIMAL(10,8),
                location_lng DECIMAL(11,8),
                location_address TEXT,
                price DECIMAL(10,2) NOT NULL,
                service_charge DECIMAL(10,2) DEFAULT 0,
                posted_by VARCHAR(50) NOT NULL REFERENCES users(id),
                posted_at TIMESTAMP NOT NULL,
                expires_at TIMESTAMP,
                accepted_by VARCHAR(50) REFERENCES users(id),
                accepted_at TIMESTAMP,
                completed_at TIMESTAMP,
                status VARCHAR(20) DEFAULT 'active'
            )
        ''')
        
        # Password resets table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS password_resets (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                token VARCHAR(255) NOT NULL,
                otp VARCHAR(10) NOT NULL,
                created_at TIMESTAMP NOT NULL,
                expires_at TIMESTAMP NOT NULL,
                used BOOLEAN DEFAULT FALSE,
                otp_verified BOOLEAN DEFAULT FALSE
            )
        ''')
        
        # Payments table (for Razorpay)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS payments (
                id SERIAL PRIMARY KEY,
                task_id INTEGER REFERENCES tasks(id),
                poster_id INTEGER REFERENCES users(id),
                helper_id INTEGER REFERENCES users(id),
                razorpay_order_id VARCHAR(255),
                razorpay_payment_id VARCHAR(255),
                razorpay_signature VARCHAR(255),
                amount DECIMAL(10,2) NOT NULL,
                platform_fee DECIMAL(10,2),
                currency VARCHAR(10) DEFAULT 'INR',
                status VARCHAR(20) DEFAULT 'pending',
                created_at TIMESTAMP NOT NULL,
                verified_at TIMESTAMP,
                paid_at TIMESTAMP
            )
        ''')
        
        # Location tracking table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS location_tracking (
                id SERIAL PRIMARY KEY,
                task_id INTEGER NOT NULL REFERENCES tasks(id),
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                user_type VARCHAR(20) NOT NULL,
                latitude DECIMAL(10,8) NOT NULL,
                longitude DECIMAL(11,8) NOT NULL,
                accuracy DECIMAL(10,2),
                heading DECIMAL(5,2),
                speed DECIMAL(6,2),
                recorded_at TIMESTAMP NOT NULL,
                is_active BOOLEAN DEFAULT TRUE
            )
        ''')
        
        # Create index for faster location queries
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_location_task 
            ON location_tracking(task_id, user_id, recorded_at DESC)
        ''')
        
        # Wallet table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS wallets (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(50) UNIQUE NOT NULL REFERENCES users(id),
                balance DECIMAL(12,2) DEFAULT 0,
                total_added DECIMAL(12,2) DEFAULT 0,
                total_spent DECIMAL(12,2) DEFAULT 0,
                total_earned DECIMAL(12,2) DEFAULT 0,
                total_cashback DECIMAL(12,2) DEFAULT 0,
                created_at TIMESTAMP NOT NULL,
                updated_at TIMESTAMP
            )
        ''')
        
        # Wallet transactions table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS wallet_transactions (
                id SERIAL PRIMARY KEY,
                wallet_id INTEGER NOT NULL REFERENCES wallets(id),
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                type VARCHAR(30) NOT NULL,
                amount DECIMAL(10,2) NOT NULL,
                balance_after DECIMAL(12,2) NOT NULL,
                description TEXT,
                reference_id VARCHAR(100),
                task_id INTEGER REFERENCES tasks(id),
                status VARCHAR(20) DEFAULT 'completed',
                created_at TIMESTAMP NOT NULL
            )
        ''')
        
        # Referrals table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS referrals (
                id SERIAL PRIMARY KEY,
                referrer_id VARCHAR(50) NOT NULL REFERENCES users(id),
                referred_id VARCHAR(50) NOT NULL REFERENCES users(id),
                referral_code VARCHAR(20) NOT NULL,
                reward_amount DECIMAL(10,2) DEFAULT 50,
                referrer_rewarded BOOLEAN DEFAULT FALSE,
                referred_rewarded BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMP NOT NULL
            )
        ''')
        
        # Chat messages table (group chat per task)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS chat_messages (
                id SERIAL PRIMARY KEY,
                task_id INTEGER NOT NULL,
                user_id VARCHAR(50) NOT NULL,
                user_name VARCHAR(255),
                message TEXT NOT NULL,
                timestamp TIMESTAMP NOT NULL,
                FOREIGN KEY (task_id) REFERENCES tasks(id),
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        ''')
        
        # Task proofs table (photo proof)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS task_proofs (
                id SERIAL PRIMARY KEY,
                task_id INTEGER NOT NULL REFERENCES tasks(id),
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                proof_type VARCHAR(30) NOT NULL,
                image_url TEXT,
                otp_code VARCHAR(6),
                otp_verified BOOLEAN DEFAULT FALSE,
                notes TEXT,
                created_at TIMESTAMP NOT NULL
            )
        ''')
        
        # Helper ratings table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS helper_ratings (
                id SERIAL PRIMARY KEY,
                task_id INTEGER NOT NULL REFERENCES tasks(id),
                rater_id VARCHAR(50) NOT NULL REFERENCES users(id),
                rated_id VARCHAR(50) NOT NULL REFERENCES users(id),
                rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
                review TEXT,
                task_title TEXT,
                punctuality INTEGER,
                communication INTEGER,
                quality INTEGER,
                created_at TIMESTAMP NOT NULL
            )
        ''')
        
        # SOS alerts table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS sos_alerts (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                task_id INTEGER REFERENCES tasks(id),
                latitude DECIMAL(10,8),
                longitude DECIMAL(11,8),
                alert_type VARCHAR(30) DEFAULT 'emergency',
                status VARCHAR(20) DEFAULT 'active',
                resolved_at TIMESTAMP,
                created_at TIMESTAMP NOT NULL
            )
        ''')
        
        # Scheduled tasks table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS scheduled_tasks (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                task_template TEXT NOT NULL,
                schedule_type VARCHAR(20) NOT NULL,
                schedule_time TIME,
                schedule_days VARCHAR(50),
                next_run TIMESTAMP,
                last_run TIMESTAMP,
                is_active BOOLEAN DEFAULT TRUE,
                created_at TIMESTAMP NOT NULL
            )
        ''')
        
        # Withdrawal requests table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS withdrawal_requests (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                amount DECIMAL(10,2) NOT NULL,
                bank_name VARCHAR(100) NOT NULL,
                account_holder_name VARCHAR(100) NOT NULL,
                account_number VARCHAR(50) NOT NULL,
                ifsc_code VARCHAR(20) NOT NULL,
                status VARCHAR(20) DEFAULT 'pending',
                transaction_id VARCHAR(100),
                rejection_reason TEXT,
                requested_at TIMESTAMP NOT NULL,
                processed_at TIMESTAMP,
                created_at TIMESTAMP NOT NULL,
                updated_at TIMESTAMP
            )
        ''')
        
        # Notifications table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS notifications (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                task_id INTEGER REFERENCES tasks(id),
                notification_type VARCHAR(50) NOT NULL,
                title VARCHAR(255) NOT NULL,
                message TEXT,
                status VARCHAR(20) DEFAULT 'unread',
                data TEXT,
                created_at TIMESTAMP NOT NULL,
                read_at TIMESTAMP
            )
        ''')
        
        # Create index for faster notification queries
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_notifications_user_status 
            ON notifications(user_id, status)
        ''')
        
        # Platform settlements table - tracks payouts to company bank account
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS platform_settlements (
                id SERIAL PRIMARY KEY,
                settlement_date DATE NOT NULL,
                period_start TIMESTAMP NOT NULL,
                period_end TIMESTAMP NOT NULL,
                total_income DECIMAL(12,2) NOT NULL,
                helper_commission DECIMAL(12,2) NOT NULL,
                poster_fees DECIMAL(12,2) NOT NULL,
                amount_settled DECIMAL(12,2) NOT NULL,
                razorpay_payout_id VARCHAR(255),
                status VARCHAR(20) DEFAULT 'pending',
                bank_account_last4 VARCHAR(4),
                notes TEXT,
                processed_at TIMESTAMP,
                created_at TIMESTAMP NOT NULL,
                updated_at TIMESTAMP
            )
        ''')
        
        # Company bank details table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS company_bank_details (
                id SERIAL PRIMARY KEY,
                account_number VARCHAR(50) NOT NULL,
                ifsc_code VARCHAR(20) NOT NULL,
                account_holder_name VARCHAR(100),
                bank_name VARCHAR(100),
                is_active BOOLEAN DEFAULT TRUE,
                updated_at TIMESTAMP NOT NULL,
                created_at TIMESTAMP NOT NULL
            )
        ''')
        
        # Contact messages table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS contact_messages (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                email VARCHAR(255) NOT NULL,
                subject VARCHAR(100) NOT NULL,
                message TEXT NOT NULL,
                user_id VARCHAR(50),
                status VARCHAR(20) DEFAULT 'new',
                created_at TIMESTAMP NOT NULL
            )
        ''')

        # Feedback / reviews table (from /feedback.html submissions)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS feedback (
                id SERIAL PRIMARY KEY,
                rating INTEGER NOT NULL,
                role VARCHAR(40),
                name VARCHAR(120) NOT NULL,
                city VARCHAR(80),
                email VARCHAR(200) NOT NULL,
                topic VARCHAR(60),
                message TEXT NOT NULL,
                consent_public BOOLEAN DEFAULT FALSE,
                user_id VARCHAR(50),
                ip_address VARCHAR(64),
                user_agent VARCHAR(255),
                status VARCHAR(20) DEFAULT 'pending',
                created_at TIMESTAMP NOT NULL
            )
        ''')
        
        # Admin audit log table - tracks all admin actions
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS admin_audit_log (
                id SERIAL PRIMARY KEY,
                admin_id VARCHAR(50) NOT NULL,
                action VARCHAR(50) NOT NULL,
                resource_type VARCHAR(50) NOT NULL,
                resource_id VARCHAR(50),
                details TEXT,
                ip_address VARCHAR(45),
                created_at TIMESTAMP NOT NULL
            )
        ''')

        cursor.execute('''
            CREATE TABLE IF NOT EXISTS disputes (
                id SERIAL PRIMARY KEY,
                task_id INTEGER NOT NULL REFERENCES tasks(id),
                filed_by VARCHAR(50) NOT NULL REFERENCES users(id),
                reason VARCHAR(200) NOT NULL,
                details TEXT,
                status VARCHAR(20) DEFAULT 'open',
                resolution TEXT,
                resolved_by VARCHAR(50),
                resolved_at TIMESTAMP,
                created_at TIMESTAMP NOT NULL
            )
        ''')

        cursor.execute('''
            CREATE TABLE IF NOT EXISTS bookmarks (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(50) NOT NULL REFERENCES users(id),
                task_id INTEGER NOT NULL REFERENCES tasks(id),
                created_at TIMESTAMP NOT NULL,
                UNIQUE(user_id, task_id)
            )
        ''')

        # User reports table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS user_reports (
                id SERIAL PRIMARY KEY,
                reporter_id VARCHAR(50) NOT NULL REFERENCES users(id),
                reported_id VARCHAR(50) NOT NULL REFERENCES users(id),
                reason VARCHAR(50) NOT NULL,
                details TEXT,
                task_id INTEGER REFERENCES tasks(id),
                status VARCHAR(20) DEFAULT 'pending',
                admin_notes TEXT,
                resolved_by VARCHAR(50),
                resolved_at TIMESTAMP,
                created_at TIMESTAMP NOT NULL
            )
        ''')

        # User blocks table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS user_blocks (
                id SERIAL PRIMARY KEY,
                blocker_id VARCHAR(50) NOT NULL REFERENCES users(id),
                blocked_id VARCHAR(50) NOT NULL REFERENCES users(id),
                created_at TIMESTAMP NOT NULL,
                UNIQUE(blocker_id, blocked_id)
            )
        ''')

        # Task categories table (admin-managed)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS task_categories (
                id SERIAL PRIMARY KEY,
                slug VARCHAR(50) UNIQUE NOT NULL,
                name VARCHAR(100) NOT NULL,
                icon VARCHAR(50) DEFAULT 'fas fa-tasks',
                service_charge_percent DECIMAL(5,2) DEFAULT 10.0,
                is_active BOOLEAN DEFAULT TRUE,
                sort_order INTEGER DEFAULT 0,
                created_at TIMESTAMP NOT NULL,
                updated_at TIMESTAMP
            )
        ''')
        
        # Push notification subscriptions
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS push_subscriptions (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(50) NOT NULL,
                subscription_json TEXT NOT NULL,
                created_at TIMESTAMP NOT NULL,
                UNIQUE(user_id)
            )
        ''')

        # Deleted accounts blocklist — prevents re-registration via Google or email
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
        
        # Commit CREATE TABLEs and ensure clean transaction state for ALTER TABLEs
        conn.commit()
        
        # Add referral_code to users
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code VARCHAR(20) UNIQUE
        ''')
        
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS referred_by VARCHAR(50)
        ''')
        
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS helper_level VARCHAR(20) DEFAULT 'bronze'
        ''')
        
        # Suspension timer columns (server-side suspension sync across devices)
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMP
        ''')
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_releases INTEGER DEFAULT 0
        ''')
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS daily_release_date VARCHAR(20)
        ''')
        
        # Email verification column
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT FALSE
        ''')

        # Google OAuth columns
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(255) UNIQUE
        ''')
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(20) DEFAULT 'email'
        ''')

        # KYC columns
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN DEFAULT FALSE
        ''')
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_status VARCHAR(20) DEFAULT 'none'
        ''')
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_document_type VARCHAR(30)
        ''')
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_document_number VARCHAR(50)
        ''')
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_verified_at TIMESTAMP
        ''')
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS kyc_document_image TEXT
        ''')

        # Phone OTP table (separate from password_resets, with phone column)
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
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_phone_otps_user ON phone_otps(user_id, used, expires_at)
        ''')

        # Language preference
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(10) DEFAULT 'en'
        ''')

        # Banned column
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT FALSE
        ''')

        # Admin flag column
        cursor.execute('''
            ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE
        ''')
        # Grant admin to system user (id='1') if not already set
        cursor.execute("UPDATE users SET is_admin = TRUE WHERE id = '1' AND (is_admin IS NULL OR is_admin = FALSE)")
        
        # Ensure service_charge column exists in tasks table (migration)
        print("[DB] Adding service_charge column to tasks table if missing...")
        try:
            cursor.execute('''
                ALTER TABLE tasks ADD COLUMN IF NOT EXISTS service_charge DECIMAL(10,2) DEFAULT 0
            ''')
            print("[DB] ✅ service_charge column added or already exists")
        except Exception as e:
            print(f"[DB] ⚠️  Could not add service_charge column: {e}")
        
        # Ensure paid_at column exists (for tracking when task was paid)
        try:
            cursor.execute('''
                ALTER TABLE tasks ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP
            ''')
            print("[DB] ✅ paid_at column added or already exists")
        except Exception as e:
            print(f"[DB] ⚠️  Could not add paid_at column: {e}")

        # Add lat/lng to push_subscriptions for geo-targeted notifications
        try:
            cursor.execute('''
                ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS lat DECIMAL(10,8)
            ''')
            cursor.execute('''
                ALTER TABLE push_subscriptions ADD COLUMN IF NOT EXISTS lng DECIMAL(11,8)
            ''')
            print("[DB] ✅ push_subscriptions lat/lng columns added or already exist")
        except Exception as e:
            print(f"[DB] ⚠️  Could not add lat/lng to push_subscriptions: {e}")

        # Ensure otp_verified column exists in password_resets (security migration)
        try:
            cursor.execute('''
                ALTER TABLE password_resets ADD COLUMN IF NOT EXISTS otp_verified BOOLEAN DEFAULT FALSE
            ''')
            print("[DB] \u2705 otp_verified column added or already exists in password_resets")
        except Exception as e:
            print(f"[DB] \u26a0\ufe0f  Could not add otp_verified to password_resets: {e}")

        # Add drop location columns for delivery/transport tasks
        try:
            cursor.execute('ALTER TABLE tasks ADD COLUMN IF NOT EXISTS drop_location_lat DECIMAL(10,8)')
            cursor.execute('ALTER TABLE tasks ADD COLUMN IF NOT EXISTS drop_location_lng DECIMAL(11,8)')
            cursor.execute('ALTER TABLE tasks ADD COLUMN IF NOT EXISTS drop_location_address TEXT')
            print("[DB] \u2705 drop_location columns added or already exist")
        except Exception as e:
            print(f"[DB] \u26a0\ufe0f  Could not add drop_location columns: {e}")
        
        # ========================================
        # CREATE SYSTEM/COMPANY USER
        # ========================================
        # Ensure a company user with id '1' exists for the platform wallet
        try:
            cursor.execute('SELECT id FROM users WHERE id = %s', ('1',))
            company_user = cursor.fetchone()
            
            if not company_user:
                print("[DB] Creating system company user...")
                cursor.execute('''
                    INSERT INTO users (
                        id, name, email, password_hash, rating, 
                        tasks_posted, tasks_completed, joined_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                ''', (
                    '1',  # user_id
                    'TaskEarn System',
                    'system@taskearn.com',
                    'SYSTEM_ACCOUNT_NO_PASSWORD',
                    5.0,
                    0,
                    0,
                    datetime.datetime.now(datetime.timezone.utc).isoformat()
                ))
                print("[DB] ✅ System user created successfully")
            else:
                print("[DB] System user already exists")
        except Exception as e:
            print(f"[DB] ⚠️  System user creation warning: {e}")
            # Don't fail if user already exists or has a unique constraint issue
        
        conn.commit()
        cursor.close()
        conn.close()
        print("[DB] ✅ PostgreSQL database initialized successfully")
        
    except Exception as e:
        print(f"[DB] ❌ PostgreSQL initialization error: {e}")
        import traceback
        traceback.print_exc()
        raise


def init_sqlite_db():
    """Deprecated. SQLite support has been removed."""
    raise RuntimeError("SQLite support has been removed. Configure DATABASE_URL for PostgreSQL.")


def _harden_postgres_security():
    """
    Drop dangerous PostgreSQL extensions and set protective timeouts.
    Called automatically on every backend startup when using PostgreSQL.
    This ensures the database cannot be used for outbound network scanning
    even if an attacker gains access to the DB session.
    """
    DANGEROUS_EXTENSIONS = ['dblink', 'postgres_fdw', 'pg_net', 'http', 'plperlu', 'plpythonu']
    try:
        conn = get_postgres_connection()
        with conn.cursor() as cur:
            # Drop network-capable extensions that were used for port scanning
            for ext in DANGEROUS_EXTENSIONS:
                try:
                    cur.execute(f"DROP EXTENSION IF EXISTS {ext} CASCADE")
                    print(f"[Security] ✅ Dropped extension (if existed): {ext}")
                except Exception as ex:
                    print(f"[Security] ℹ️  Could not drop {ext}: {ex}")

            # Set DB-level statement timeout (60s max per query)
            try:
                cur.execute("ALTER DATABASE railway SET statement_timeout = '60s'")
                print("[Security] ✅ statement_timeout = 60s set on database")
            except Exception as ex:
                print(f"[Security] ℹ️  statement_timeout not set: {ex}")

            # Kill abandoned transactions after 2 minutes
            try:
                cur.execute("ALTER DATABASE railway SET idle_in_transaction_session_timeout = '120s'")
                print("[Security] ✅ idle_in_transaction_session_timeout = 120s set on database")
            except Exception as ex:
                print(f"[Security] ℹ️  idle_in_transaction_session_timeout not set: {ex}")

            # Revoke file-system access from public
            for fn in [
                "pg_read_server_files(text)",
                "pg_ls_dir(text)",
            ]:
                try:
                    cur.execute(f"REVOKE EXECUTE ON FUNCTION {fn} FROM PUBLIC")
                    print(f"[Security] ✅ Revoked PUBLIC execute on {fn}")
                except Exception:
                    pass  # Function may not exist in this PG version

        conn.commit()
        conn.close()
        print("[Security] ✅ PostgreSQL hardening complete")
    except Exception as e:
        print(f"[Security] ⚠️  PostgreSQL hardening skipped: {e}")


def init_db():
    """Initialize database based on configuration"""
    if not POSTGRES_AVAILABLE:
        raise RuntimeError("PostgreSQL driver not installed")

    print("[DB] Initializing PostgreSQL database...")
    init_postgres_db()
    # Harden DB security on every startup (idempotent — safe to run repeatedly)
    _harden_postgres_security()


# ========================================
# DATABASE HELPERS
# ========================================

def dict_from_row(row):
    """Convert database row to dictionary"""
    if row is None:
        return None
    if isinstance(row, dict):
        return row
    return dict(row)


def get_placeholder():
    """Get SQL placeholder for PostgreSQL."""
    return '%s'
