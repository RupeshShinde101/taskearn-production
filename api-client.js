// ========================================
// TaskEarn API Client
// Connect frontend to Python backend
// ========================================

// Detect if user is on mobile (using User-Agent sniffing)
function isMobileDevice() {
    const userAgent = navigator.userAgent || navigator.vendor || window.opera;
    return /android|webos|iphone|ipad|ipod|blackberry|iemobile|opera mini/i.test(userAgent.toLowerCase());
}

// Detect if we're on Netlify (production frontend)
function isNetlifyDeployed() {
    return window.location.hostname.includes('netlify.app') || 
           window.location.hostname.includes('taskearn');
}

// API URL Configuration with fallback logic
let API_BASE_URL = window.TASKEARN_API_URL;
let RAILWAY_CHECKED = false;
let RAILWAY_AVAILABLE = false;
let PROXY_CHECKED = false;
let PROXY_AVAILABLE = false;
const MOBILE = isMobileDevice();
const ON_NETLIFY = isNetlifyDeployed();

// Set default API URL immediately (don't wait for async detection)
if (!API_BASE_URL) {
    // Check if we're on localhost (development)
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
        API_BASE_URL = 'http://localhost:5000/api';
        console.log('🔧 Development Mode: Using local backend');
    } else {
        // Production mode
        if (MOBILE && ON_NETLIFY) {
            // MOBILE on Netlify: Try to use Netlify proxy first (bypasses ISP/carrier blocking)
            API_BASE_URL = '/.netlify/functions/api-proxy/api';
            console.log('📱 Mobile on Netlify: Will use proxy relay (testing availability first)');
        } else {
            // Desktop or direct Railway: Use Railway directly
            API_BASE_URL = 'https://taskearn-production-production.up.railway.app/api';
            console.log('🌍 Production Mode: Using Railway backend directly');
        }
    }
}

console.log('📡 API Base URL:', API_BASE_URL);
console.log('📱 Mobile device:', MOBILE);
console.log('☁️ On Netlify:', ON_NETLIFY);

// Try to determine if Railway is actually available (run in background, non-blocking)
async function checkRailwayHealth() {
    if (RAILWAY_CHECKED || API_BASE_URL === 'OFFLINE') {
        return; // Already checked or explicitly offline
    }
    
    // Skip health check for mobile users using proxy (proxy handles it)
    if (MOBILE && ON_NETLIFY && PROXY_AVAILABLE) {
        console.log('⏭️ Skipping Railway health check for mobile users (using proxy)');
        RAILWAY_CHECKED = true;
        RAILWAY_AVAILABLE = true; // Assume available when using proxy
        return;
    }
    
    const railwayURL = 'https://taskearn-production-production.up.railway.app/api';
    
    try {
        // Quick health check for Railway (non-blocking, 5 second timeout)
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
        
        const response = await fetch(railwayURL + '/health', {
            method: 'GET',
            signal: controller.signal,
            mode: 'cors'
        });
        
        clearTimeout(timeoutId);
        
        if (response.ok) {
            RAILWAY_AVAILABLE = true;
            console.log('✅ Railway backend is available');
        } else {
            RAILWAY_AVAILABLE = false;
            console.warn('⚠️ Railway responded but with error status:', response.status);
        }
    } catch (error) {
        RAILWAY_AVAILABLE = false;
        console.warn('⚠️ Railway health check failed:', error.message);
    }
    
    RAILWAY_CHECKED = true;
}

// Check if Netlify proxy is working (for mobile users)
async function checkProxyHealth() {
    if (PROXY_CHECKED || !MOBILE || !ON_NETLIFY) {
        return; // Already checked or not applicable
    }
    
    try {
        console.log('🔍 Testing Netlify proxy availability...');
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
        
        const response = await fetch('/.netlify/functions/api-proxy/api/health', {
            method: 'GET',
            signal: controller.signal,
            mode: 'cors'
        });
        
        clearTimeout(timeoutId);
        
        if (response.ok || response.status === 404) {
            // 200 OK or 404 is fine (means proxy is working)
            PROXY_AVAILABLE = true;
            console.log('✅ Netlify proxy is available for mobile');
        } else {
            PROXY_AVAILABLE = false;
            console.warn('⚠️ Proxy returned unexpected status:', response.status);
            // Fallback to Railway
            API_BASE_URL = 'https://taskearn-production-production.up.railway.app/api';
            console.log('📱 Proxy unavailable, falling back to Railway for mobile');
        }
    } catch (error) {
        PROXY_AVAILABLE = false;
        console.warn('⚠️ Proxy health check failed:', error.message);
        // Fallback to Railway
        API_BASE_URL = 'https://taskearn-production-production.up.railway.app/api';
        console.log('📱 Proxy check failed, falling back to Railway');
    }
    
    PROXY_CHECKED = true;
}

// Run health checks in the background (non-blocking)
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        setTimeout(() => {
            checkProxyHealth();
            checkRailwayHealth();
        }, 50); // Start checking after DOM is ready
    });
} else {
    setTimeout(() => {
        checkProxyHealth();
        checkRailwayHealth();
    }, 50); // DOM already ready
}

// ========================================
// API HELPER FUNCTIONS
// ========================================

async function apiRequest(endpoint, options = {}) {
    // If explicitly offline mode, return cached data
    if (API_BASE_URL === 'OFFLINE') {
        console.log('📴 Offline mode - returning cached data for:', endpoint);
        return {
            success: false,
            status: 503,
            data: {
                success: false,
                message: 'Backend server temporarily unavailable. Working with offline data.',
                offline: true
            }
        };
    }
    
    const url = `${API_BASE_URL}${endpoint}`;

    
    const headers = {
        'Content-Type': 'application/json',
        ...options.headers
    };
    
    // ALWAYS fetch fresh token from localStorage (don't cache it!)
    const authToken = localStorage.getItem('taskearn_token');
    if (authToken) {
        headers['Authorization'] = `Bearer ${authToken}`;
        console.log('🔐 Using auth token for request:', endpoint);
    } else {
        console.warn('⚠️ No auth token available for request:', endpoint);
    }
    
    try {
        console.log('🌐 Making API request to:', url);
        console.log('📤 Method:', options.method || 'GET');
        console.log('📦 Headers:', headers);
        if (options.body) console.log('📄 Body:', options.body);
        
        const response = await fetch(url, {
            ...options,
            headers
        });
        
        console.log('📥 Response status:', response.status, response.statusText);
        
        const data = await response.json();
        console.log('📄 Response data:', data);
        
        // Handle token expiration - only clear if we actually had an API token
        if (response.status === 401 && data.message === 'Invalid or expired token') {
            // Clear API token from localStorage
            localStorage.removeItem('taskearn_token');
            // Don't clear taskearn_user or taskearn_current_user - let local login still work
            console.log('⚠️ API token expired, cleared token but kept local session');
        }
        
        return { success: response.ok, status: response.status, data };
    } catch (error) {
        console.error('❌ API Request Failed!');
        console.error('❌ Error type:', error.name);
        console.error('❌ Error message:', error.message);
        console.error('❌ Full error:', error);
        console.error('❌ URL was:', url);
        console.error('❌ Network error - check if backend is running at:', url);
        
        // Show more helpful error message
        let errorMessage = 'Network error: ' + error.message;
        if (error.message.includes('Failed to fetch')) {
            if (MOBILE) {
                // Mobile-specific help message
                errorMessage = '📱 MOBILE: Your carrier network is blocking the backend. Try connecting to WiFi or using a VPN to continue.';
            } else {
                // Desktop help message  
                errorMessage = `❌ Cannot connect to Railway backend at ${url}\nDesktop users: Try connecting to VPN if your network is blocking the backend.`;
            }
        }
        
        return { 
            success: false, 
            status: 0, 
            data: { 
                success: false, 
                message: errorMessage
            }
        };
    }
}

function setAuthToken(token) {
    localStorage.setItem('taskearn_token', token);
    console.log('✅ Auth token saved to localStorage');
}

function clearAuthToken() {
    localStorage.removeItem('taskearn_token');
    localStorage.removeItem('taskearn_user');
    localStorage.removeItem('taskearn_current_user');
}

function saveUserToStorage(user) {
    localStorage.setItem('taskearn_user', JSON.stringify(user));
    // Also save to taskearn_current_user for consistency across all pages
    localStorage.setItem('taskearn_current_user', JSON.stringify(user));
}

function getUserFromStorage() {
    const user = localStorage.getItem('taskearn_user');
    return user ? JSON.parse(user) : null;
}

// ========================================
// AUTH API
// ========================================

const AuthAPI = {
    // Register new user
    async register(userData) {
        console.log('📝 Starting registration with data:', userData);
        const result = await apiRequest('/auth/register', {
            method: 'POST',
            body: JSON.stringify(userData)
        });
        
        console.log('✅ Register API response:', result);
        
        if (result.success && result.data && result.data.token) {
            console.log('🎯 Setting auth token...');
            setAuthToken(result.data.token);
            saveUserToStorage(result.data.user);
        } else if (result.success && result.data) {
            console.log('⚠️ Success but no token in response:', result.data);
        } else if (!result.success) {
            console.log('❌ Registration failed:', result.data?.message || result.data);
        }
        
        // Return the actual response data from backend
        return result.data || { success: false, message: 'No response data' };
    },
    
    // Login user
    async login(email, password) {
        console.log('🔑 Starting login for:', email);
        const result = await apiRequest('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ email, password })
        });
        
        console.log('✅ Login API response:', result);
        
        if (result.success && result.data && result.data.token) {
            console.log('🎯 Setting auth token...');
            setAuthToken(result.data.token);
            saveUserToStorage(result.data.user);
        } else if (result.success && result.data) {
            console.log('⚠️ Success but no token:', result.data);
        } else if (!result.success) {
            console.log('❌ Login failed:', result.data?.message || result.data);
        }
        
        // Return the actual response data from backend
        return result.data || { success: false, message: 'No response data' };
    },
    
    // Get current user
    async getCurrentUser() {
        const result = await apiRequest('/auth/me', {
            method: 'GET'
        });
        
        if (result.success && result.data.user) {
            saveUserToStorage(result.data.user);
        }
        
        return result.data;
    },
    
    // Logout
    async logout() {
        await apiRequest('/auth/logout', {
            method: 'POST'
        });
        clearAuthToken();
    },
    
    // Forgot password - find account
    async forgotPassword(email) {
        const result = await apiRequest('/auth/forgot-password', {
            method: 'POST',
            body: JSON.stringify({ email })
        });
        return result.data;
    },
    
    // Verify OTP
    async verifyOTP(resetToken, otp) {
        const result = await apiRequest('/auth/verify-otp', {
            method: 'POST',
            body: JSON.stringify({ resetToken, otp })
        });
        return result.data;
    },
    
    // Reset password
    async resetPassword(resetToken, newPassword) {
        const result = await apiRequest('/auth/reset-password', {
            method: 'POST',
            body: JSON.stringify({ resetToken, newPassword })
        });
        return result.data;
    },
    
    // Check if logged in
    isLoggedIn() {
        return !!authToken;
    },
    
    // Get stored user
    getUser() {
        return getUserFromStorage();
    }
};

// ========================================
// USER API
// ========================================

const UserAPI = {
    // Update profile
    async updateProfile(updates) {
        const result = await apiRequest('/user/profile', {
            method: 'PUT',
            body: JSON.stringify(updates)
        });
        
        if (result.success && result.data.user) {
            saveUserToStorage(result.data.user);
        }
        
        return result.data;
    },
    
    // Change password
    async changePassword(currentPassword, newPassword) {
        const result = await apiRequest('/user/change-password', {
            method: 'POST',
            body: JSON.stringify({ currentPassword, newPassword })
        });
        return result.data;
    },
    
    // Get user's tasks
    async getTasks() {
        const result = await apiRequest('/user/tasks', {
            method: 'GET'
        });
        return result.data;
    }
};

// ========================================
// TASKS API
// ========================================

const TasksAPI = {
    // Get all active tasks
    async getAll() {
        const result = await apiRequest('/tasks', {
            method: 'GET'
        });
        
        // Cache successful results
        if (result.data && result.data.success && result.data.tasks) {
            try {
                localStorage.setItem('cached_tasks', JSON.stringify(result.data.tasks));
                console.log('💾 Tasks cached to localStorage');
            } catch (e) {
                console.warn('⚠️ Could not cache tasks:', e);
            }
        }
        
        return result.data;
    },
    
    // Create task
    async create(taskData) {
        const result = await apiRequest('/tasks', {
            method: 'POST',
            body: JSON.stringify(taskData)
        });
        return result.data;
    },
    
    // Accept task
    async accept(taskId) {
        const result = await apiRequest(`/tasks/${taskId}/accept`, {
            method: 'POST'
        });
        return result.data;
    },
    
    // Complete task
    async complete(taskId) {
        const result = await apiRequest(`/tasks/${taskId}/complete`, {
            method: 'POST'
        });
        return result.data;
    }
};

// ========================================
// WALLET API
// ========================================

const WalletAPI = {
    // Get wallet details
    async get() {
        const result = await apiRequest('/wallet', { method: 'GET' });
        return result.data;
    },
    
    // Add money to wallet
    async addMoney(amount, paymentId) {
        const result = await apiRequest('/wallet/add-money', {
            method: 'POST',
            body: JSON.stringify({ amount, paymentId })
        });
        return result.data;
    },
    
    // Pay from wallet
    async pay(amount, taskId, description) {
        const result = await apiRequest('/wallet/pay', {
            method: 'POST',
            body: JSON.stringify({ amount, taskId, description })
        });
        return result.data;
    },
    
    // Get transactions
    async getTransactions(page = 1) {
        const result = await apiRequest(`/wallet/transactions?page=${page}`, { method: 'GET' });
        return result.data;
    },
    
    // Request withdrawal
    async withdraw(options) {
        const result = await apiRequest('/wallet/withdraw', {
            method: 'POST',
            body: JSON.stringify({
                amount: options.amount,
                bankName: options.bankName,
                accountHolder: options.accountHolder,
                accountNumber: options.accountNumber,
                ifscCode: options.ifscCode
            })
        });
        return result.data;
    },
    
    // Get withdrawal history
    async getWithdrawals(page = 1) {
        const result = await apiRequest(`/wallet/withdrawals?page=${page}`, { method: 'GET' });
        return result.data;
    },
    
    // Cancel withdrawal
    async cancelWithdrawal(withdrawalId) {
        const result = await apiRequest(`/wallet/withdrawal/${withdrawalId}/cancel`, {
            method: 'POST'
        });
        return result.data;
    }
};

// ========================================
// CHAT API
// ========================================

const ChatAPI = {
    // Get messages for a task
    async getMessages(taskId) {
        const result = await apiRequest(`/chat/${taskId}/messages`, { method: 'GET' });
        return result.data;
    },
    
    // Send message
    async send(taskId, message, type = 'text') {
        const result = await apiRequest(`/chat/${taskId}/send`, {
            method: 'POST',
            body: JSON.stringify({ message, type })
        });
        return result.data;
    },
    
    // Get unread count
    async getUnreadCount() {
        const result = await apiRequest('/chat/unread', { method: 'GET' });
        return result.data;
    }
};

// ========================================
// PROOF & DELIVERY API
// ========================================

const ProofAPI = {
    // Generate delivery OTP
    async generateOTP(taskId) {
        const result = await apiRequest(`/task/${taskId}/generate-otp`, { method: 'POST' });
        return result.data;
    },
    
    // Verify OTP
    async verifyOTP(taskId, otp) {
        const result = await apiRequest(`/task/${taskId}/verify-otp`, {
            method: 'POST',
            body: JSON.stringify({ otp })
        });
        return result.data;
    },
    
    // Upload proof
    async upload(taskId, type, imageUrl, notes = '') {
        const result = await apiRequest(`/task/${taskId}/upload-proof`, {
            method: 'POST',
            body: JSON.stringify({ type, imageUrl, notes })
        });
        return result.data;
    },
    
    // Get proofs
    async getProofs(taskId) {
        const result = await apiRequest(`/task/${taskId}/proofs`, { method: 'GET' });
        return result.data;
    }
};

// ========================================
// RATINGS API
// ========================================

const RatingsAPI = {
    // Rate user
    async rate(taskId, rating, review, details = {}) {
        const result = await apiRequest(`/task/${taskId}/rate`, {
            method: 'POST',
            body: JSON.stringify({ rating, review, ...details })
        });
        return result.data;
    },
    
    // Get user reviews
    async getReviews(userId) {
        const result = await apiRequest(`/user/${userId}/reviews`, { method: 'GET' });
        return result.data;
    }
};

// ========================================
// REFERRAL API
// ========================================

const ReferralAPI = {
    // Get referral code
    async getCode() {
        const result = await apiRequest('/referral/code', { method: 'GET' });
        return result.data;
    },
    
    // Apply code
    async apply(code) {
        const result = await apiRequest('/referral/apply', {
            method: 'POST',
            body: JSON.stringify({ code })
        });
        return result.data;
    },
    
    // Get stats
    async getStats() {
        const result = await apiRequest('/referral/stats', { method: 'GET' });
        return result.data;
    }
};

// ========================================
// SOS API
// ========================================

const SosAPI = {
    // Send alert
    async sendAlert(taskId, latitude, longitude, alertType = 'emergency') {
        const result = await apiRequest('/sos/alert', {
            method: 'POST',
            body: JSON.stringify({ taskId, latitude, longitude, alertType })
        });
        return result.data;
    },
    
    // Resolve alert
    async resolve(alertId) {
        const result = await apiRequest(`/sos/resolve/${alertId}`, { method: 'POST' });
        return result.data;
    }
};

// ========================================
// HELPER DASHBOARD API
// ========================================

const HelperAPI = {
    // Get dashboard
    async getDashboard() {
        const result = await apiRequest('/helper/dashboard', { method: 'GET' });
        return result.data;
    }
};

// ========================================
// HEALTH CHECK
// ========================================

async function checkBackendHealth() {
    const result = await apiRequest('/health', { method: 'GET' });
    return result.success;
}

// Export for use
window.AuthAPI = AuthAPI;
window.UserAPI = UserAPI;
window.TasksAPI = TasksAPI;
window.WalletAPI = WalletAPI;
window.ChatAPI = ChatAPI;
window.ProofAPI = ProofAPI;
window.RatingsAPI = RatingsAPI;
window.ReferralAPI = ReferralAPI;
window.SosAPI = SosAPI;
window.HelperAPI = HelperAPI;
window.checkBackendHealth = checkBackendHealth;

// Log backend status on load
checkBackendHealth().then(healthy => {
    if (healthy) {
        console.log('✅ Backend server connected');
    } else {
        console.warn('⚠️ Backend server not available. Run: python backend/server.py');
    }
});
