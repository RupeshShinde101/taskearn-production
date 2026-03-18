"""
Database module for TaskEarn
Supports both SQLite (development) and PostgreSQL (production)
"""

import os
import sqlite3
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
    print("⚠️ psycopg2 not installed, using SQLite only")


# ========================================
# DATABASE CONNECTION
# ========================================

def get_postgres_connection():
    """Get PostgreSQL connection"""
    if not POSTGRES_AVAILABLE:
        raise Exception("PostgreSQL driver not installed")
    
    conn = psycopg2.connect(config.DATABASE_URL)
    return conn


def get_sqlite_connection():
    """Get SQLite connection"""
    conn = sqlite3.connect(config.SQLITE_DATABASE)
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def get_db():
    """Get database connection (PostgreSQL or SQLite)"""
    conn = None
    try:
        if config.USE_POSTGRES and POSTGRES_AVAILABLE:
            conn = get_postgres_connection()
            cursor = conn.cursor(cursor_factory=RealDictCursor)
        else:
            conn = get_sqlite_connection()
            cursor = conn.cursor()
        
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
                used BOOLEAN DEFAULT FALSE
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
    """Initialize SQLite database tables"""
    with get_db() as (cursor, conn):
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
                is_suspended BOOLEAN DEFAULT 0,
                suspension_reason TEXT,
                suspended_at TEXT,
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
        
        # Password resets table
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
        
        # Payments table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS payments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER,
                poster_id INTEGER,
                helper_id INTEGER,
                razorpay_order_id TEXT,
                razorpay_payment_id TEXT,
                razorpay_signature TEXT,
                amount REAL NOT NULL,
                platform_fee REAL,
                currency TEXT DEFAULT 'INR',
                status TEXT DEFAULT 'pending',
                created_at TEXT NOT NULL,
                verified_at TEXT,
                paid_at TEXT,
                FOREIGN KEY (task_id) REFERENCES tasks(id),
                FOREIGN KEY (poster_id) REFERENCES users(id),
                FOREIGN KEY (helper_id) REFERENCES users(id)
            )
        ''')
        
        # Location tracking table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS location_tracking (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                user_type TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                accuracy REAL,
                heading REAL,
                speed REAL,
                recorded_at TEXT NOT NULL,
                is_active INTEGER DEFAULT 1,
                FOREIGN KEY (task_id) REFERENCES tasks(id),
                FOREIGN KEY (user_id) REFERENCES users(id)
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
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT UNIQUE NOT NULL,
                balance REAL DEFAULT 0,
                total_added REAL DEFAULT 0,
                total_spent REAL DEFAULT 0,
                total_earned REAL DEFAULT 0,
                total_cashback REAL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        ''')
        
        # Wallet transactions table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS wallet_transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                type TEXT NOT NULL,
                amount REAL NOT NULL,
                balance_after REAL NOT NULL,
                description TEXT,
                reference_id TEXT,
                task_id INTEGER,
                status TEXT DEFAULT 'completed',
                created_at TEXT NOT NULL,
                FOREIGN KEY (wallet_id) REFERENCES wallets(id),
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (task_id) REFERENCES tasks(id)
            )
        ''')
        
        # Referrals table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS referrals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                referrer_id TEXT NOT NULL,
                referred_id TEXT NOT NULL,
                referral_code TEXT NOT NULL,
                reward_amount REAL DEFAULT 50,
                referrer_rewarded INTEGER DEFAULT 0,
                referred_rewarded INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                FOREIGN KEY (referrer_id) REFERENCES users(id),
                FOREIGN KEY (referred_id) REFERENCES users(id)
            )
        ''')
        
        # Chat messages table (group chat per task)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS chat_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                user_name TEXT,
                message TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                FOREIGN KEY (task_id) REFERENCES tasks(id),
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        ''')
        
        # Task proofs table (photo proof)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS task_proofs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                proof_type TEXT NOT NULL,
                image_url TEXT,
                otp_code TEXT,
                otp_verified INTEGER DEFAULT 0,
                notes TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (task_id) REFERENCES tasks(id),
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        ''')
        
        # Helper ratings table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS helper_ratings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                rater_id TEXT NOT NULL,
                rated_id TEXT NOT NULL,
                rating INTEGER NOT NULL,
                review TEXT,
                punctuality INTEGER,
                communication INTEGER,
                quality INTEGER,
                created_at TEXT NOT NULL,
                FOREIGN KEY (task_id) REFERENCES tasks(id),
                FOREIGN KEY (rater_id) REFERENCES users(id),
                FOREIGN KEY (rated_id) REFERENCES users(id)
            )
        ''')
        
        # SOS alerts table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS sos_alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                task_id INTEGER,
                latitude REAL,
                longitude REAL,
                alert_type TEXT DEFAULT 'emergency',
                status TEXT DEFAULT 'active',
                resolved_at TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (task_id) REFERENCES tasks(id)
            )
        ''')
        
        # Scheduled tasks table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS scheduled_tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                task_template TEXT NOT NULL,
                schedule_type TEXT NOT NULL,
                schedule_time TEXT,
                schedule_days TEXT,
                next_run TEXT,
                last_run TEXT,
                is_active INTEGER DEFAULT 1,
                created_at TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        ''')
        
        print("[DB] ✅ SQLite database initialized successfully")


def init_db():
    """Initialize database based on configuration"""
    try:
        if config.USE_POSTGRES and POSTGRES_AVAILABLE:
            print("[DB] Initializing PostgreSQL database...")
            init_postgres_db()
        else:
            print("[DB] Initializing SQLite database...")
            init_sqlite_db()
    except Exception as e:
        print(f"[DB] ⚠️  Database initialization warning: {e}")
        # Don't crash the app, just log the warning
        # Tables might already exist


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
    """Get SQL placeholder based on database type"""
    if config.USE_POSTGRES and POSTGRES_AVAILABLE:
        return '%s'
    return '?'
