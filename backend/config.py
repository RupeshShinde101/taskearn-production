"""
Configuration settings for TaskEarn Backend
Loads from environment variables for production
"""

import os
from dotenv import load_dotenv

# Load .env file if exists (for local development)
load_dotenv()

class Config:
    """Base configuration"""
    
    # Secret key for JWT and sessions - MUST be set via environment variable in production
    SECRET_KEY = os.environ.get('SECRET_KEY', '')
    if not SECRET_KEY:
        if os.environ.get('DATABASE_URL'):
            raise RuntimeError("SECRET_KEY must be set in production (DATABASE_URL is configured)")
        import secrets as _secrets
        SECRET_KEY = _secrets.token_hex(32)
        print("⚠️  SECRET_KEY not set in environment — using random key (sessions won't survive restarts)")
    else:
        print("🔐 SECRET_KEY loaded from environment")
    
    # JWT Settings
    JWT_EXPIRATION_HOURS = int(os.environ.get('JWT_EXPIRATION_HOURS', 24))
    
    # Database URL
    # Format: postgresql://user:password@host:port/database
    DATABASE_URL = os.environ.get('DATABASE_URL')
    
    # For SQLite fallback (local development)
    SQLITE_DATABASE = os.environ.get('SQLITE_DATABASE', 'taskearn.db')
    
    # Use PostgreSQL if DATABASE_URL is set, otherwise SQLite
    USE_POSTGRES = DATABASE_URL is not None
    
    # CORS Settings - set CORS_ORIGINS env var to comma-separated allowed origins
    # Default allows your known domains; set to '*' only for local dev
    CORS_ORIGINS = os.environ.get('CORS_ORIGINS', 'https://www.workmate4u.com,https://workmate4u.com,https://workmate4u.netlify.app').split(',')
    
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
    
    # Production database
    if DATABASE_URL and DATABASE_URL.startswith('postgres://'):
        # Railway uses postgres:// which psycopg2 recognizes
        pass
    elif DATABASE_URL and DATABASE_URL.startswith('postgresql://'):
        # Standard PostgreSQL format
        pass
    else:
        # Fallback to SQLite if no DATABASE_URL
        USE_POSTGRES = False


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
