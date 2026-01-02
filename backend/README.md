# TaskEarn Backend Server

A Python Flask backend with SQLite database, bcrypt password hashing, and JWT authentication.

## Setup

### 1. Install Python
Make sure you have Python 3.8+ installed.

### 2. Create Virtual Environment (Recommended)
```bash
cd backend
python -m venv venv

# Windows
venv\Scripts\activate

# Mac/Linux
source venv/bin/activate
```

### 3. Install Dependencies
```bash
pip install -r requirements.txt
```

### 4. Run Server
```bash
python server.py
```

Server will start at: `http://localhost:5000`

## API Endpoints

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register` | Register new user |
| POST | `/api/auth/login` | Login user |
| GET | `/api/auth/me` | Get current user (auth required) |
| POST | `/api/auth/logout` | Logout user (auth required) |
| POST | `/api/auth/forgot-password` | Request password reset |
| POST | `/api/auth/verify-otp` | Verify OTP |
| POST | `/api/auth/reset-password` | Reset password |

### User
| Method | Endpoint | Description |
|--------|----------|-------------|
| PUT | `/api/user/profile` | Update profile (auth required) |
| POST | `/api/user/change-password` | Change password (auth required) |
| GET | `/api/user/tasks` | Get user's tasks (auth required) |

### Tasks
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/tasks` | Get all active tasks |
| POST | `/api/tasks` | Create task (auth required) |
| POST | `/api/tasks/:id/accept` | Accept task (auth required) |
| POST | `/api/tasks/:id/complete` | Complete task (auth required) |

## Security Features

- **Password Hashing**: PBKDF2-SHA256 with Werkzeug
- **JWT Tokens**: 24-hour expiration
- **OTP**: 6-digit codes with 10-minute expiration
- **Session Tokens**: Secure random tokens

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SECRET_KEY` | JWT secret key | Random 32-byte hex |

## Database

SQLite database (`taskearn.db`) is created automatically with tables:
- `users` - User accounts
- `tasks` - Tasks posted
- `password_resets` - Password reset tokens
