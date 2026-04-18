// ========================================
// Workmate4u API Client
// Connect frontend to Python backend
// ========================================

// Production: suppress debug logs (keep console.warn and console.error)
(function() {
    if (location.hostname !== 'localhost' && location.hostname !== '127.0.0.1') {
        const noop = function() {};
        console.log = noop;
        console.debug = noop;
        console.info = noop;
    }
})();

// Detect if user is on mobile (using User-Agent sniffing)
function isMobileDevice() {
    const userAgent = navigator.userAgent || navigator.vendor || window.opera;
    const isMobile = /android|webos|iphone|ipad|ipot|blackberry|iemobile|opera mini/i.test(userAgent.toLowerCase());
    console.log('� User-Agent substring:', userAgent.substring(0, 100));
    console.log('📱 Detected as mobile:', isMobile ? '✅ YES' : '❌ NO');
    return isMobile;
}

// Detect if we're on Netlify (production frontend)
function isNetlifyDeployed() {
    const hostname = window.location.hostname;
    const isNetlify = hostname.includes('netlify.app') || hostname.includes('workmate4u') || hostname.includes('taskearn');
    console.log('🌍 Current hostname:', hostname);
    console.log('☁️ Detected as Netlify:', isNetlify ? '✅ YES' : '❌ NO');
    return isNetlify;
}

// API URL Configuration with fallback logic
let API_BASE_URL = window.API_BASE_URL || undefined;  // Use pre-set value from HTML inline script
let RAILWAY_CHECKED = false;
let RAILWAY_AVAILABLE = false;
let PROXY_CHECKED = false;
let PROXY_AVAILABLE = false;
const MOBILE = isMobileDevice();
const ON_NETLIFY = isNetlifyDeployed();
const FORCE_MOBILE_PROXY = window.FORCE_MOBILE_PROXY || false;

console.log('🔍 API Client Initialization');
console.log('Pre-set API_BASE_URL from HTML:', window.API_BASE_URL);
console.log('📱 Mobile device:', MOBILE);
console.log('☁️ On Netlify:', ON_NETLIFY);
console.log('🔒 Force mobile proxy:', FORCE_MOBILE_PROXY);

// If not pre-set by inline HTML script, determine it now
if (!API_BASE_URL) {
    if (MOBILE && ON_NETLIFY) {
        API_BASE_URL = '/.netlify/functions/api-proxy/api';
        console.log('📱 Mobile on Netlify: Using proxy');
    } else {
        API_BASE_URL = 'https://taskearn-production-production.up.railway.app/api';
        console.log('🌍 Using Railway production server');
    }
}

console.log('=====================================');
console.log('✅ FINAL API_BASE_URL:', API_BASE_URL);
console.log('✅ Mobile proxy enforced:', FORCE_MOBILE_PROXY);
console.log('=====================================');

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
        const timeoutId = setTimeout(() => controller.abort(), 3000);
        
        const response = await fetch('/.netlify/functions/api-proxy/api/health', {
            method: 'GET',
            signal: controller.signal,
            mode: 'cors',
            credentials: 'omit'  // Important: don't send cookies to proxy
        });
        
        clearTimeout(timeoutId);
        
        console.log('Proxy response status:', response.status);
        console.log('Proxy response content-type:', response.headers.get('content-type'));
        
        if (response.ok) {
            // 200 OK - proxy is working
            PROXY_AVAILABLE = true;
            console.log('✅ Netlify proxy is available for mobile');
        } else if (response.status === 404 || response.status === 200) {
            // 404 or 200 means proxy function is responding (even if endpoint doesn't exist)
            PROXY_AVAILABLE = true;
            console.log('✅ Netlify proxy is responding');
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
        
        // IMPORTANT: If proxy is blocked (CORB error), fall back to Railway immediately
        if (error.message.includes('Failed to fetch') || error.name === 'AbortError') {
            console.log('📱 Proxy blocked or timeout - using Railway backend directly');
            // Try to use Railway directly (some carriers might not block it on this second attempt)
            API_BASE_URL = 'https://taskearn-production-production.up.railway.app/api';
        }
    }
    
    PROXY_CHECKED = true;
}

// Run health checks in the background (non-blocking)
// SKIP for mobile on Netlify - they MUST use proxy, no fallback needed
if (!MOBILE || !ON_NETLIFY) {
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            setTimeout(() => {
                checkProxyHealth();
                checkRailwayHealth();
            }, 50);
        });
    } else {
        setTimeout(() => {
            checkProxyHealth();
            checkRailwayHealth();
        }, 50);
    }
} else {
    console.log('📱 Mobile on Netlify: Skipping health checks (using proxy only)');
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
    const isUsingProxy = API_BASE_URL.includes('api-proxy');
    
    const headers = {
        'Content-Type': 'application/json',
        ...options.headers
    };
    
    // ALWAYS fetch fresh token from localStorage (don't cache it!)
    const authToken = localStorage.getItem('taskearn_token');
    if (authToken) {
        headers['Authorization'] = `Bearer ${authToken}`;
    }
    
    try {
        
        const fetchOptions = {
            ...options,
            headers,
            mode: 'cors',
            credentials: 'omit'
        };
        
        const response = await fetch(url, fetchOptions);
        
        // Try to parse JSON
        let data;
        try {
            data = await response.json();
        } catch (parseError) {
            data = { success: false, message: 'Invalid JSON response' };
        }
        
        // Handle token expiration - only clear if we actually had an API token
        if (response.status === 401) {
            const token = localStorage.getItem('taskearn_token');
            console.log('❌ 401 Unauthorized response received!');
            console.log('   Error message:', data.message);
            console.log('   Token exists:', !!token);
            if (token) {
                console.log('   Token length:', token.length);
                console.log('   Token preview:', token.substring(0, 30) + '...');
                localStorage.removeItem('taskearn_token');
                console.log('⚠️  Token cleared from localStorage');
                // Show session expired overlay if not already shown
                if (!document.getElementById('sessionExpiredOverlay')) {
                    const overlay = document.createElement('div');
                    overlay.id = 'sessionExpiredOverlay';
                    overlay.className = 'session-expired-overlay';
                    overlay.innerHTML = `
                        <div class="session-expired-box">
                            <i class="fas fa-clock"></i>
                            <h3>Session Expired</h3>
                            <p>Your session has expired. Please log in again to continue.</p>
                            <button class="btn btn-primary" onclick="document.getElementById('sessionExpiredOverlay').remove(); if(typeof openModal === 'function') openModal('loginModal'); else window.location.href='index.html';">
                                <i class="fas fa-sign-in-alt"></i> Log In Again
                            </button>
                        </div>
                    `;
                    document.body.appendChild(overlay);
                }
            }
        }
        
        return { success: response.ok, status: response.status, data };
        
    } catch (error) {
        console.error('❌ API Request Failed!');
        console.error('❌ Error type:', error.name);
        console.error('❌ Error message:', error.message);
        console.error('❌ URL was:', url);
        
        // Handle network errors
        const isNetworkError = error.message.includes('Failed to fetch') || 
                               error.message.includes('ERR_NAME_NOT_RESOLVED') ||
                               error.name === 'TypeError';
        
        // If mobile is using proxy and proxy fails, try cached data instead of falling back to Railway
        // (because Railway DNS is likely blocked too)
        if (MOBILE && ON_NETLIFY && isUsingProxy && isNetworkError) {
            console.warn('⚠️ Mobile proxy request failed. Checking cached data...');
            
            // Try to use cached data
            const cachedData = localStorage.getItem('taskearn_cached_' + endpoint);
            if (cachedData) {
                console.log('✅ Using cached data for:', endpoint);
                try {
                    return {
                        success: false,
                        status: 0,
                        data: {
                            ...JSON.parse(cachedData),
                            offline: true,
                            message: '📱 Using cached data. Your carrier network may be blocking the backend.'
                        }
                    };
                } catch (e) {
                    console.warn('Could not parse cached data');
                }
            }
            
            // If no cache and on mobile with ISP blocking, provide helpful error
            return {
                success: false,
                status: 0,
                data: {
                    success: false,
                    message: '📱 Your carrier network is blocking the backend. Try:\n1. Switch to WiFi\n2. Use a VPN\n3. Login later when on WiFi',
                    offline: true,
                    carrier_blocked: true
                }
            };
        }
        
        // For desktop or if proxy failed for other reasons, try fallback
        if (isUsingProxy && isNetworkError && !MOBILE) {
            console.warn('⚠️ Desktop proxy request failed. Falling back to Railway...');
            
            // Try Railway directly
            const railwayUrl = `https://taskearn-production-production.up.railway.app/api${endpoint}`;
            
            try {
                const railwayResponse = await fetch(railwayUrl, {
                    ...options,
                    headers,
                    mode: 'cors'
                });
                
                let railwayData;
                try {
                    railwayData = await railwayResponse.json();
                } catch (parseError) {
                    railwayData = { success: false, message: 'Invalid response' };
                }
                
                console.log('✅ Railway fallback successful');
                return { success: railwayResponse.ok, status: railwayResponse.status, data: railwayData };
                
            } catch (railwayError) {
                console.error('❌ Railway fallback also failed:', railwayError.message);
                return {
                    success: false,
                    status: 0,
                    data: {
                        success: false,
                        message: 'Cannot connect to backend. Try VPN.',
                        offline: true
                    }
                };
            }
        }
        
        // Handle other network errors
        let errorMessage = 'Network error: ' + error.message;
        if (isNetworkError) {
            if (MOBILE) {
                errorMessage = '📱 MOBILE: Your carrier network is blocking the backend. Try WiFi or VPN.';
            } else {
                errorMessage = '❌ Cannot connect to backend. Try VPN.';
            }
        }
        
        return { 
            success: false, 
            status: 0, 
            data: { 
                success: false, 
                message: errorMessage,
                offline: true
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
    try {
        localStorage.setItem('taskearn_user', JSON.stringify(user));
        localStorage.setItem('taskearn_current_user', JSON.stringify(user));
    } catch (e) {
        console.warn('⚠️ localStorage save failed (quota?):', e.message);
    }
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
    
    // Send email verification OTP
    async sendVerificationOTP() {
        const result = await apiRequest('/auth/send-verification-otp', { method: 'POST' });
        return result.data;
    },
    
    // Verify email with OTP
    async verifyEmail(otp) {
        const result = await apiRequest('/auth/verify-email', {
            method: 'POST',
            body: JSON.stringify({ otp })
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
        console.log('🚀 TasksAPI.create() called');
        console.log('   Method: POST');
        console.log('   Endpoint: /tasks');
        console.log('   Data:', JSON.stringify(taskData, null, 2));
        
        const result = await apiRequest('/tasks', {
            method: 'POST',
            body: JSON.stringify(taskData)
        });
        
        console.log('📥 TasksAPI.create() response:', JSON.stringify(result, null, 2));
        console.log('   success:', result.success);
        console.log('   status:', result.status);
        console.log('   data:', result.data);
        
        if (!result.success || !result.data) {
            console.error('❌ TasksAPI.create failed:');
            console.error('   Response success:', result.success);
            console.error('   Response status:', result.status);
            console.error('   Response data:', result.data);
        }
        
        return result.data;
    },
    
    // Accept task
    async accept(taskId) {
        const result = await apiRequest(`/tasks/${taskId}/accept`, {
            method: 'POST'
        });
        // Include HTTP success status so caller can check both API and HTTP level
        const data = result.data || {};
        data._httpSuccess = result.success;
        return data;
    },
    
    // Complete task
    async complete(taskId) {
        const result = await apiRequest(`/tasks/${taskId}/complete`, {
            method: 'POST'
        });
        return result.data;
    },

    // Abandon/release an accepted task back to active
    async abandon(taskId) {
        const result = await apiRequest(`/tasks/${taskId}/abandon`, {
            method: 'POST'
        });
        return result.data;
    },

    // Delete task
    async delete(taskId) {
        const result = await apiRequest(`/tasks/${taskId}`, {
            method: 'DELETE'
        });
        return result.data;
    },

    // Get active task counts grouped by category
    async getCategoryCounts() {
        const result = await apiRequest('/tasks/category-counts', {
            method: 'GET'
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
    
    // Pay from wallet (requires sufficient balance)
    async pay(amount, taskId, description) {
        const result = await apiRequest('/wallet/pay', {
            method: 'POST',
            body: JSON.stringify({ amount, taskId, description })
        });
        return result.data;
    },
    
    // Deduct penalty from wallet (allows negative balance)
    async penalty(amount, taskId, description) {
        const result = await apiRequest('/wallet/penalty', {
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
// NOTIFICATIONS API
// ========================================

const NotificationsAPI = {
    // Get all notifications
    async getAll() {
        const result = await apiRequest('/notifications', { method: 'GET' });
        return result.data;
    },
    
    // Mark notification as read
    async markAsRead(notificationId) {
        const result = await apiRequest(`/notifications/${notificationId}/read`, {
            method: 'POST'
        });
        return result.data;
    },
    
    // Delete notification
    async delete(notificationId) {
        const result = await apiRequest(`/notifications/${notificationId}`, {
            method: 'DELETE'
        });
        return result.data;
    },
    
    // Clear all notifications
    async clearAll() {
        const result = await apiRequest('/notifications/clear-all', {
            method: 'DELETE'
        });
        return result.data;
    },

    // Clear task notifications
    async clearTaskNotifications(taskId) {
        const result = await apiRequest(`/notifications/clear-task/${taskId}`, {
            method: 'POST'
        });
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

// ========================================
// SEARCH API
// ========================================

const SearchAPI = {
    async search(params = {}) {
        const qs = new URLSearchParams();
        if (params.q) qs.set('q', params.q);
        if (params.category) qs.set('category', params.category);
        if (params.min_price) qs.set('min_price', params.min_price);
        if (params.max_price) qs.set('max_price', params.max_price);
        if (params.page) qs.set('page', params.page);
        if (params.limit) qs.set('limit', params.limit);
        const result = await apiRequest(`/tasks/search?${qs.toString()}`, { method: 'GET' });
        return result.data;
    }
};

// ========================================
// REPORT & BLOCK API
// ========================================

const ReportAPI = {
    async reportUser(userId, reason, details = '', taskId = null) {
        const result = await apiRequest(`/user/${userId}/report`, {
            method: 'POST',
            body: JSON.stringify({ reason, details, taskId })
        });
        return result.data;
    },

    async blockUser(userId) {
        const result = await apiRequest(`/user/${userId}/block`, { method: 'POST' });
        return result.data;
    },

    async unblockUser(userId) {
        const result = await apiRequest(`/user/${userId}/unblock`, { method: 'POST' });
        return result.data;
    },

    async getBlockedUsers() {
        const result = await apiRequest('/user/blocked', { method: 'GET' });
        return result.data;
    }
};

// ========================================
// CATEGORIES API
// ========================================

const CategoriesAPI = {
    async getAll() {
        const result = await apiRequest('/categories', { method: 'GET' });
        return result.data;
    },

    async create(data) {
        const result = await apiRequest('/admin/categories', {
            method: 'POST',
            body: JSON.stringify(data)
        });
        return result.data;
    },

    async update(categoryId, data) {
        const result = await apiRequest(`/admin/categories/${categoryId}`, {
            method: 'PUT',
            body: JSON.stringify(data)
        });
        return result.data;
    },

    async delete(categoryId) {
        const result = await apiRequest(`/admin/categories/${categoryId}`, {
            method: 'DELETE'
        });
        return result.data;
    }
};

// ========================================
// KYC API
// ========================================

const KYCAPI = {
    async submit(documentType, documentNumber, documentImage) {
        const result = await apiRequest('/user/kyc/submit', {
            method: 'POST',
            body: JSON.stringify({ documentType, documentNumber, documentImage })
        });
        return result.data;
    },

    async getStatus() {
        const result = await apiRequest('/user/kyc/status', { method: 'GET' });
        return result.data;
    }
};

// Push Notifications API
const PushAPI = {
    getVapidKey: () => apiRequest('/api/push/vapid-key'),
    subscribe: (subscription) => apiRequest('/api/push/subscribe', { method: 'POST', body: JSON.stringify({ subscription }) }),
    unsubscribe: () => apiRequest('/api/push/unsubscribe', { method: 'POST' })
};

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
window.NotificationsAPI = NotificationsAPI;
window.SearchAPI = SearchAPI;
window.ReportAPI = ReportAPI;
window.CategoriesAPI = CategoriesAPI;
window.KYCAPI = KYCAPI;
window.PushAPI = PushAPI;
window.checkBackendHealth = checkBackendHealth;

// Log backend status on load
checkBackendHealth().then(healthy => {
    if (healthy) {
        console.log('✅ Backend server connected');
    } else {
        console.warn('⚠️ Backend server not available. Run: python backend/server.py');
    }
});
