"""
Configuration settings for TaskEarn Backend
Loads from environment variables for production
"""

import os
from dotenv import load_dotenv, find_dotenv

# Load .env file if exists (for local development).
# find_dotenv() searches the current directory AND all parent directories,
# so running from backend/ still picks up the root-level .env.
load_dotenv(find_dotenv(usecwd=True), override=False)

class Config:
    """Base configuration"""
    
    # Secret key for JWT and sessions - MUST be set via environment variable in production
    SECRET_KEY = os.environ.get('SECRET_KEY', '')

    # Known-weak / placeholder values that must never be used in production
    _WEAK_KEYS = {
        '', 'change_me', 'changeme', 'secret', 'password',
        'REPLACE_WITH_RANDOM_SECRET_KEY_DO_NOT_COMMIT',
        'TaskEarn-Fixed-Secret-Key-2026-Do-Not-Change',
    }

    if not SECRET_KEY or SECRET_KEY in _WEAK_KEYS:
        if os.environ.get('DATABASE_URL'):
            raise RuntimeError(
                "SECRET_KEY must be set to a strong random value in production. "
                "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
            )
        import secrets as _secrets
        SECRET_KEY = _secrets.token_hex(32)
        print("⚠️  SECRET_KEY not set in environment — using random key (sessions won't survive restarts)")
    elif len(SECRET_KEY) < 32:
        if os.environ.get('DATABASE_URL'):
            raise RuntimeError("SECRET_KEY is too short — must be at least 32 characters in production.")
        print("⚠️  SECRET_KEY is short — consider using a longer random value.")
    else:
        print("🔐 SECRET_KEY loaded from environment")
    
    # JWT Settings — default 4h; set JWT_EXPIRATION_HOURS env var to override
    JWT_EXPIRATION_HOURS = int(os.environ.get('JWT_EXPIRATION_HOURS', 4))
    
    # Database URL (required)
    # Format: postgresql://user:password@host:port/database
    DATABASE_URL = os.environ.get('DATABASE_URL', '').strip()
    if not DATABASE_URL:
        raise RuntimeError(
            "DATABASE_URL is required. SQLite fallback has been removed. "
            "Configure a PostgreSQL connection string in environment variables."
        )

    # Admin Database URL (optional) — set ADMIN_DATABASE_URL to the Railway public
    # proxy URL (e.g. postgresql://postgres:pass@crossover.proxy.rlwy.net:17104/railway)
    # so that admin-panel routes always use the public URL while the rest of the app
    # uses the internal DATABASE_URL.  Falls back to DATABASE_URL if not set.
    ADMIN_DATABASE_URL = os.environ.get('ADMIN_DATABASE_URL', DATABASE_URL).strip() or DATABASE_URL

    # PostgreSQL is the only supported production database for this backend.
    USE_POSTGRES = True
    
    # CORS Settings - set CORS_ORIGINS env var to comma-separated allowed origins
    # Default allows your known domains; set to '*' only for local dev
    CORS_ORIGINS = os.environ.get('CORS_ORIGINS', (
        'https://www.workmate4u.com,'
        'https://workmate4u.com,'
        'https://workmate4u.netlify.app,'
        'https://staging--workmate4u.netlify.app,'
        'https://staging--workmate4.netlify.app,'
        'http://localhost:3000,'
        'http://localhost:8080'
    )).split(',')
    
    # Razorpay Settings
    RAZORPAY_KEY_ID = os.environ.get('RAZORPAY_KEY_ID', '')
    RAZORPAY_KEY_SECRET = os.environ.get('RAZORPAY_KEY_SECRET', '')
    RAZORPAYX_ACCOUNT_NUMBER = os.environ.get('RAZORPAYX_ACCOUNT_NUMBER', '')  # RazorpayX business account number
    
    # Validate Razorpay keys in production
    if DATABASE_URL and (not RAZORPAY_KEY_ID or not RAZORPAY_KEY_SECRET):
        print('⚠️  WARNING: RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET not set — payments will fail!')
    
    # Email Settings (SendGrid)
    SENDGRID_API_KEY = os.environ.get('SENDGRID_API_KEY', '')
    FROM_EMAIL = os.environ.get('FROM_EMAIL', 'info@workmate4u.com')
    
    # App Settings
    APP_NAME = os.environ.get('APP_NAME', 'TaskEarn')
    APP_URL = os.environ.get('APP_URL', 'http://localhost:8080')
    
    # Rate Limiting
    RATE_LIMIT_PER_MINUTE = int(os.environ.get('RATE_LIMIT_PER_MINUTE', 60))
    
    # Debug mode - ALWAYS False in production
    DEBUG = os.environ.get('DEBUG', 'False').lower() == 'true'

    # ----------------------------------------------------------------
    # TRIAL MODE
    # Set TRIAL_INVITE_CODE via Railway environment variable.
    # TRIAL_END_DATE: ISO date string 'YYYY-MM-DD' — trial closes on this date.
    # TRIAL_MAX_USERS: max registrations allowed during trial.
    # Set TRIAL_ACTIVE=false to disable trial restrictions entirely.
    # ----------------------------------------------------------------
    TRIAL_ACTIVE = os.environ.get('TRIAL_ACTIVE', 'true').lower() == 'true'
    TRIAL_INVITE_CODE = os.environ.get('TRIAL_INVITE_CODE', 'WORKMATE100')  # Change in Railway env vars
    TRIAL_END_DATE = os.environ.get('TRIAL_END_DATE', '2026-07-09')  # Extended +30 days (2026-06-09)
    TRIAL_MAX_USERS = int(os.environ.get('TRIAL_MAX_USERS', 100))
    
    # Validate PostgreSQL URL scheme
    if DATABASE_URL.startswith('postgres://'):
        # Railway uses postgres:// which psycopg2 recognizes
        pass
    elif DATABASE_URL.startswith('postgresql://'):
        # Standard PostgreSQL format
        pass
    else:
        raise RuntimeError(
            "DATABASE_URL must start with postgres:// or postgresql://"
        )


class DevelopmentConfig(Config):
    """Development configuration"""
    DEBUG = True


class ProductionConfig(Config):
    """Production configuration"""
    DEBUG = False


# Get config based on environment
def get_config():
    env = os.environ.get('FLASK_ENV', 'development')
    if env == 'production':
        return ProductionConfig()
    return DevelopmentConfig()
