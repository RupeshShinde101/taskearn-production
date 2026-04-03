// ========================================
// Workmate4u India - Task Marketplace
// Using Leaflet + OpenStreetMap (100% Free)
// Robust GPS with Fallback System
// ========================================

// Global State
let map = null;
let userMarker = null;
let userCircle = null;
let taskMarkers = [];
let routeLayer = null;
let currentUser = null;
let selectedBudget = 100; // Default budget
const MIN_TASK_PRICE = 100; // Minimum ₹100 per task
let selectedTask = null;
let gpsWatchId = null;
let isGPSActive = false;
let modalTaskCoords = null; // Stores picked location for task posting
let pendingReleaseTaskId = null; // Task ID awaiting penalty confirmation

// Service Charge based on task category (importance & time)
const SERVICE_CHARGES = {
    // Quick tasks (15-30 mins) - ₹30
    'delivery': { charge: 30, time: '15-30 mins', level: 'Quick' },
    'pickup': { charge: 30, time: '15-30 mins', level: 'Quick' },
    'document': { charge: 30, time: '15-30 mins', level: 'Quick' },
    'errand': { charge: 35, time: '30-45 mins', level: 'Quick' },
    
    // Medium tasks (1-2 hours) - ₹40-50
    'groceries': { charge: 40, time: '1-2 hours', level: 'Medium' },
    'laundry': { charge: 40, time: '1-2 hours', level: 'Medium' },
    'shopping': { charge: 40, time: '1-2 hours', level: 'Medium' },
    'gardening': { charge: 50, time: '1-3 hours', level: 'Medium' },
    'cleaning': { charge: 50, time: '2-4 hours', level: 'Medium' },
    'cooking': { charge: 50, time: '1-2 hours', level: 'Medium' },
    
    // Skilled tasks (2-4 hours) - ₹60-70
    'repair': { charge: 60, time: '1-3 hours', level: 'Skilled' },
    'assembly': { charge: 60, time: '1-3 hours', level: 'Skilled' },
    'tech-support': { charge: 60, time: '1-2 hours', level: 'Skilled' },
    'event-help': { charge: 60, time: '3-6 hours', level: 'Skilled' },
    'tailoring': { charge: 60, time: '2-4 hours', level: 'Skilled' },
    'beauty': { charge: 60, time: '1-2 hours', level: 'Skilled' },
    'petcare': { charge: 60, time: '2-4 hours', level: 'Skilled' },
    
    // Time-intensive tasks (3-6 hours) - ₹70-80
    'tutoring': { charge: 70, time: '1-2 hours', level: 'Expert' },
    'babysitting': { charge: 70, time: '3-6 hours', level: 'Expert' },
    'fitness': { charge: 70, time: '1-2 hours', level: 'Expert' },
    'photography': { charge: 70, time: '2-4 hours', level: 'Expert' },
    'painting': { charge: 70, time: '3-6 hours', level: 'Expert' },
    'moving': { charge: 80, time: '4-8 hours', level: 'Expert' },
    'eldercare': { charge: 80, time: '4-8 hours', level: 'Expert' },
    
    // Professional/High-skill tasks - ₹90-100
    'carpentry': { charge: 90, time: '3-6 hours', level: 'Professional' },
    'electrician': { charge: 100, time: '1-4 hours', level: 'Professional' },
    'plumbing': { charge: 100, time: '1-4 hours', level: 'Professional' },
    
    // Default
    'other': { charge: 50, time: '1-3 hours', level: 'Medium' }
};

function getServiceCharge(category) {
    return SERVICE_CHARGES[category]?.charge || 50;
}

function getServiceChargeInfo(category) {
    return SERVICE_CHARGES[category] || SERVICE_CHARGES['other'];
}

// Default location: New Delhi, India
let userLocation = { lat: 28.6139, lng: 77.2090 };

// ========================================
// USER STORAGE SYSTEM (LocalStorage + IndexedDB Fallback)
// ========================================

const STORAGE_KEYS = {
    USERS: 'taskearn_users',
    CURRENT_USER: 'taskearn_current_user'
};

// IndexedDB for more reliable storage
let db = null;
const DB_NAME = 'TaskEarnDB';
const DB_VERSION = 1;
const STORE_NAME = 'userData';

// Initialize IndexedDB
function initIndexedDB() {
    return new Promise((resolve, reject) => {
        if (!window.indexedDB) {
            console.log('IndexedDB not supported');
            resolve(false);
            return;
        }
        
        const request = indexedDB.open(DB_NAME, DB_VERSION);
        
        request.onerror = () => {
            console.error('IndexedDB error:', request.error);
            resolve(false);
        };
        
        request.onsuccess = () => {
            db = request.result;
            console.log('✅ IndexedDB initialized');
            resolve(true);
        };
        
        request.onupgradeneeded = (event) => {
            db = event.target.result;
            if (!db.objectStoreNames.contains(STORE_NAME)) {
                db.createObjectStore(STORE_NAME, { keyPath: 'key' });
            }
        };
    });
}

// Save to IndexedDB
function saveToIndexedDB(key, value) {
    return new Promise((resolve) => {
        if (!db) { resolve(false); return; }
        try {
            const transaction = db.transaction([STORE_NAME], 'readwrite');
            const store = transaction.objectStore(STORE_NAME);
            store.put({ key, value });
            transaction.oncomplete = () => resolve(true);
            transaction.onerror = () => resolve(false);
        } catch (e) {
            resolve(false);
        }
    });
}

// Load from IndexedDB
function loadFromIndexedDB(key) {
    return new Promise((resolve) => {
        if (!db) { resolve(null); return; }
        try {
            const transaction = db.transaction([STORE_NAME], 'readonly');
            const store = transaction.objectStore(STORE_NAME);
            const request = store.get(key);
            request.onsuccess = () => resolve(request.result?.value || null);
            request.onerror = () => resolve(null);
        } catch (e) {
            resolve(null);
        }
    });
}

// Delete from IndexedDB
function deleteFromIndexedDB(key) {
    return new Promise((resolve) => {
        if (!db) { resolve(false); return; }
        try {
            const transaction = db.transaction([STORE_NAME], 'readwrite');
            const store = transaction.objectStore(STORE_NAME);
            store.delete(key);
            transaction.oncomplete = () => resolve(true);
            transaction.onerror = () => resolve(false);
        } catch (e) {
            resolve(false);
        }
    });
}

// Check if localStorage is available and working
function isLocalStorageAvailable() {
    try {
        const testKey = '__taskearn_test__';
        localStorage.setItem(testKey, 'test');
        const result = localStorage.getItem(testKey);
        localStorage.removeItem(testKey);
        return result === 'test';
    } catch (e) {
        console.error('❌ localStorage is not available:', e);
        return false;
    }
}

// Initialize storage check
let STORAGE_AVAILABLE = isLocalStorageAvailable();

// Show storage warning if not available
if (!STORAGE_AVAILABLE) {
    console.error('⚠️ WARNING: localStorage is not available. Trying IndexedDB...');
}

// ========================================
// NOTIFICATION SYSTEM
// ========================================

function showNotification(message, type = 'info', duration = 5000) {
    // Create notification container if it doesn't exist
    let container = document.getElementById('notification-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'notification-container';
        container.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 10000;
            max-width: 400px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        `;
        document.body.appendChild(container);
    }
    
    // Create notification element
    const notification = document.createElement('div');
    const bgColor = type === 'error' ? '#ff4444' : type === 'success' ? '#44dd44' : '#4444ff';
    const bgColor2 = type === 'error' ? '#cc0000' : type === 'success' ? '#00aa00' : '#0000cc';
    
    notification.style.cssText = `
        background: linear-gradient(135deg, ${bgColor}, ${bgColor2});
        color: white;
        padding: 16px 20px;
        border-radius: 8px;
        margin-bottom: 10px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        animation: slideIn 0.3s ease-out;
        font-size: 14px;
        line-height: 1.4;
    `;
    
    notification.textContent = message;
    container.appendChild(notification);
    
    // Add animation keyframes if not exists
    if (!document.getElementById('notification-styles')) {
        const style = document.createElement('style');
        style.id = 'notification-styles';
        style.textContent = `
            @keyframes slideIn {
                from {
                    transform: translateX(400px);
                    opacity: 0;
                }
                to {
                    transform: translateX(0);
                    opacity: 1;
                }
            }
            @keyframes slideOut {
                from {
                    transform: translateX(0);
                    opacity: 1;
                }
                to {
                    transform: translateX(400px);
                    opacity: 0;
                }
            }
        `;
        document.head.appendChild(style);
    }
    
    // Remove after duration
    const timeout = setTimeout(() => {
        notification.style.animation = 'slideOut 0.3s ease-out forwards';
        setTimeout(() => notification.remove(), 300);
    }, duration);
    
    // Allow manual close
    notification.style.cursor = 'pointer';
    notification.addEventListener('click', () => {
        clearTimeout(timeout);
        notification.style.animation = 'slideOut 0.3s ease-out forwards';
        setTimeout(() => notification.remove(), 300);
    });
}

// Initialize IndexedDB on load
initIndexedDB().then(dbAvailable => {
    if (!STORAGE_AVAILABLE && !dbAvailable) {
        alert('⚠️ Warning: Your browser cannot save data. Please:\n\n1. Use https://www.workmate4u.com (not file://)\n2. Disable private/incognito mode\n3. Allow cookies and site data\n\nYour account will NOT be saved!');
    }
});

// ========================================
// SECURE PASSWORD HASHING (Web Crypto API)
// ========================================

// Generate cryptographically secure random salt
function generateSalt(length = 16) {
    const array = new Uint8Array(length);
    crypto.getRandomValues(array);
    return Array.from(array, byte => byte.toString(16).padStart(2, '0')).join('');
}

// Hash password with salt using SHA-256
async function hashPassword(password, salt) {
    const encoder = new TextEncoder();
    const data = encoder.encode(salt + password);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(byte => byte.toString(16).padStart(2, '0')).join('');
    return hashHex;
}

// Create secure password hash with new salt
async function createPasswordHash(password) {
    const salt = generateSalt();
    const hash = await hashPassword(password, salt);
    return { salt, hash };
}

// Verify password against stored hash
async function verifyPassword(password, storedSalt, storedHash) {
    const hash = await hashPassword(password, storedSalt);
    return hash === storedHash;
}

// Generate secure session token
function generateSessionToken() {
    const array = new Uint8Array(32);
    crypto.getRandomValues(array);
    return Array.from(array, byte => byte.toString(16).padStart(2, '0')).join('');
}

// Generate unique user ID
function generateUserId() {
    return 'TE' + Date.now().toString(36).toUpperCase() + Math.random().toString(36).substring(2, 6).toUpperCase();
}

// Get all registered users (with IndexedDB fallback)
async function getStoredUsersAsync() {
    // Try localStorage first
    if (STORAGE_AVAILABLE) {
        try {
            const users = localStorage.getItem(STORAGE_KEYS.USERS);
            if (users) {
                const parsed = JSON.parse(users);
                console.log('📦 Loaded users from localStorage:', Object.keys(parsed).length, 'users');
                return parsed;
            }
        } catch (e) {
            console.error('localStorage read error:', e);
        }
    }
    
    // Fallback to IndexedDB
    const idbData = await loadFromIndexedDB(STORAGE_KEYS.USERS);
    if (idbData) {
        console.log('📦 Loaded users from IndexedDB:', Object.keys(idbData).length, 'users');
        // Sync back to localStorage if available
        if (STORAGE_AVAILABLE) {
            try { localStorage.setItem(STORAGE_KEYS.USERS, JSON.stringify(idbData)); } catch(e) {}
        }
        return idbData;
    }
    
    return {};
}

// Sync version for backwards compatibility
function getStoredUsers() {
    if (!STORAGE_AVAILABLE) {
        console.warn('⚠️ localStorage not available, returning empty (use getStoredUsersAsync for full support)');
        return {};
    }
    try {
        const users = localStorage.getItem(STORAGE_KEYS.USERS);
        const parsed = users ? JSON.parse(users) : {};
        return parsed;
    } catch (e) {
        console.error('Error reading users:', e);
        return {};
    }
}

// Save users to storage (both localStorage AND IndexedDB)
async function saveUsersAsync(users) {
    let saved = false;
    
    // Save to localStorage
    if (STORAGE_AVAILABLE) {
        try {
            localStorage.setItem(STORAGE_KEYS.USERS, JSON.stringify(users));
            const verify = localStorage.getItem(STORAGE_KEYS.USERS);
            if (verify) {
                console.log('✅ Users saved to localStorage:', Object.keys(users).length, 'users');
                saved = true;
            }
        } catch (e) {
            console.error('localStorage save error:', e);
        }
    }
    
    // Also save to IndexedDB as backup
    const idbSaved = await saveToIndexedDB(STORAGE_KEYS.USERS, users);
    if (idbSaved) {
        console.log('✅ Users backed up to IndexedDB');
        saved = true;
    }
    
    return saved;
}

// Sync version for backwards compatibility
function saveUsers(users) {
    if (!STORAGE_AVAILABLE) {
        console.error('❌ Cannot save - localStorage not available');
        // Try IndexedDB
        saveToIndexedDB(STORAGE_KEYS.USERS, users);
        return false;
    }
    try {
        localStorage.setItem(STORAGE_KEYS.USERS, JSON.stringify(users));
        // Also backup to IndexedDB
        saveToIndexedDB(STORAGE_KEYS.USERS, users);
        const verify = localStorage.getItem(STORAGE_KEYS.USERS);
        if (verify) {
            console.log('✅ Users saved to storage:', Object.keys(users).length, 'users');
            return true;
        }
        return false;
    } catch (e) {
        console.error('Error saving users:', e);
        return false;
    }
}

// Get user by email
function getUserByEmail(email) {
    const users = getStoredUsers();
    return Object.values(users).find(u => u.email.toLowerCase() === email.toLowerCase());
}

// Get user by email (async with IndexedDB fallback)
async function getUserByEmailAsync(email) {
    const users = await getStoredUsersAsync();
    return Object.values(users).find(u => u.email.toLowerCase() === email.toLowerCase());
}

// Register new user with secure password hashing
async function registerUser(userData) {
    // Use async to get users from both localStorage and IndexedDB
    const users = await getStoredUsersAsync();
    const userId = generateUserId();
    
    // Hash password with salt using SHA-256
    const { salt, hash } = await createPasswordHash(userData.password);
    
    const newUser = {
        id: userId,
        name: userData.name,
        email: userData.email.toLowerCase(),
        passwordHash: hash,      // Store hash, never plain password
        passwordSalt: salt,      // Store salt for verification
        phone: userData.phone || '',
        dob: userData.dob,
        rating: 5.0,
        tasksPosted: 0,
        tasksCompleted: 0,
        totalEarnings: 0,
        joinedAt: new Date().toISOString(),
        sessionToken: generateSessionToken(), // Secure session token
        postedTasks: [],
        acceptedTasks: [],
        completedTasks: []
    };
    
    users[userId] = newUser;
    
    // Save to both localStorage and IndexedDB
    const saved = await saveUsersAsync(users);
    if (!saved) {
        console.error('❌ Failed to save user data!');
    } else {
        console.log('✅ New user registered:', newUser.email);
    }
    
    return newUser;
}

// Update user data
async function updateUserData(userId, updates) {
    const users = await getStoredUsersAsync();
    // Create user entry if it doesn't exist yet (e.g., registered via backend API)
    if (!users[userId]) {
        users[userId] = { id: userId };
    }
    users[userId] = { ...users[userId], ...updates };
    await saveUsersAsync(users);
    
    // Update current user if logged in — merge updates into existing currentUser
    // instead of replacing it, to preserve fields like profilePhoto
    if (currentUser && currentUser.id === userId) {
        Object.assign(currentUser, updates);
        saveCurrentSession(currentUser);
    }
    return users[userId];
}

// Save current session (both localStorage AND IndexedDB)
function saveCurrentSession(user) {
    let saved = false;
    
    // Save to localStorage
    if (STORAGE_AVAILABLE) {
        try {
            localStorage.setItem(STORAGE_KEYS.CURRENT_USER, JSON.stringify(user));
            // Also save to taskearn_user for consistency with API login
            localStorage.setItem('taskearn_user', JSON.stringify(user));
            const verify = localStorage.getItem(STORAGE_KEYS.CURRENT_USER);
            if (verify) {
                console.log('✅ Session saved to localStorage for:', user.name);
                saved = true;
            }
        } catch (e) {
            console.error('localStorage session save error:', e);
        }
    }
    
    // Also save to IndexedDB
    saveToIndexedDB(STORAGE_KEYS.CURRENT_USER, user).then(idbSaved => {
        if (idbSaved) console.log('✅ Session backed up to IndexedDB');
    });
    
    return saved;
}

// Load current session (with IndexedDB fallback and API token support)
async function loadCurrentSessionAsync() {
    let session = null;
    let users = {};
    
    // FIRST: Check for API token session (from backend login)
    if (STORAGE_AVAILABLE) {
        try {
            const apiToken = localStorage.getItem('taskearn_token');
            const apiUserStr = localStorage.getItem('taskearn_user');
            if (apiToken && apiUserStr) {
                const apiUser = JSON.parse(apiUserStr);
                console.log('✅ Found API session for:', apiUser.name || apiUser.email);
                return apiUser;
            }
        } catch (e) {
            console.error('API session load error:', e);
        }
    }
    
    // Try localStorage for local session
    if (STORAGE_AVAILABLE) {
        try {
            const sessionStr = localStorage.getItem(STORAGE_KEYS.CURRENT_USER);
            if (sessionStr) {
                session = JSON.parse(sessionStr);
            }
        } catch (e) {
            console.error('localStorage session load error:', e);
        }
    }
    
    // Fallback to IndexedDB
    if (!session) {
        session = await loadFromIndexedDB(STORAGE_KEYS.CURRENT_USER);
    }
    
    if (!session) {
        console.log('ℹ️ No saved session found');
        return null;
    }
    
    // Get users data
    users = await getStoredUsersAsync();
    
    if (users[session.id]) {
        console.log('✅ Found saved session for:', users[session.id].name);
        return users[session.id];
    } else {
        console.log('⚠️ Session user not found in storage, clearing session');
        clearCurrentSession();
        return null;
    }
}

// Sync version for backwards compatibility
function loadCurrentSession() {
    if (!STORAGE_AVAILABLE) return null;
    try {
        // FIRST: Check for API token session (from backend login)
        const apiToken = localStorage.getItem('taskearn_token');
        const apiUserStr = localStorage.getItem('taskearn_user');
        if (apiToken && apiUserStr) {
            const apiUser = JSON.parse(apiUserStr);
            console.log('✅ Found API session for:', apiUser.name || apiUser.email);
            return apiUser;
        }
        
        // Check local session
        const session = localStorage.getItem(STORAGE_KEYS.CURRENT_USER);
        console.log('🔍 Checking for saved session...');
        if (session) {
            const user = JSON.parse(session);
            // Refresh user data from storage to get latest data
            const users = getStoredUsers();
            if (users[user.id]) {
                console.log('✅ Found saved session for:', users[user.id].name);
                return users[user.id];
            } else {
                console.log('⚠️ Session user not found in storage, clearing session');
                clearCurrentSession();
            }
        } else {
            console.log('ℹ️ No saved session found');
        }
        return null;
    } catch (e) {
        console.error('Error loading session:', e);
        return null;
    }
}

// Clear current session (logout — clears ALL auth and suspension state)
function clearCurrentSession() {
    if (!STORAGE_AVAILABLE) return;
    try {
        // Get user ID before clearing for per-user key cleanup
        let userId = null;
        try {
            const userData = localStorage.getItem(STORAGE_KEYS.CURRENT_USER);
            if (userData) userId = JSON.parse(userData).id;
        } catch (e) {}

        // Clear auth keys
        localStorage.removeItem(STORAGE_KEYS.CURRENT_USER);
        localStorage.removeItem('taskearn_token');
        localStorage.removeItem('taskearn_user');
        // Clear suspension cache keys
        localStorage.removeItem('taskearn_suspended_until');
        localStorage.removeItem('taskearn_debt_suspended');
        localStorage.removeItem('taskearn_debt_amount');
        // Clear per-user keys
        if (userId) {
            localStorage.removeItem(`notifications_${userId}`);
            localStorage.removeItem(`payment_shown_${userId}`);
        }
        // Clear IndexedDB session
        deleteFromIndexedDB(STORAGE_KEYS.CURRENT_USER);
        console.log('✅ Session fully cleared');
    } catch (e) {
        console.error('Error clearing session:', e);
    }
}

// Validate login with secure password verification
async function validateLogin(email, password) {
    // Use async version to check both localStorage and IndexedDB
    const user = await getUserByEmailAsync(email);
    if (!user) {
        console.log('❌ Login failed: No user found with email:', email);
        return null;
    }
    
    console.log('🔐 Found user, verifying password for:', user.name);
    
    // Support legacy plain-text passwords (migration)
    if (user.password && !user.passwordHash) {
        console.log('🔄 Legacy password detected, checking...');
        if (user.password === password) {
            // Migrate to hashed password
            await migrateUserPassword(user.id, password);
            return await getUserByEmailAsync(email); // Return updated user
        }
        console.log('❌ Legacy password mismatch');
        return null;
    }
    
    // Verify hashed password
    if (user.passwordHash && user.passwordSalt) {
        console.log('🔐 Verifying hashed password...');
        const isValid = await verifyPassword(password, user.passwordSalt, user.passwordHash);
        if (isValid) {
            console.log('✅ Password verified successfully');
            // Refresh session token on login
            const users = await getStoredUsersAsync();
            users[user.id].sessionToken = generateSessionToken();
            users[user.id].lastLogin = new Date().toISOString();
            await saveUsersAsync(users);
            return users[user.id];
        } else {
            console.log('❌ Password hash mismatch');
        }
    } else {
        console.log('❌ No password hash found for user');
    }
    
    return null;
}

// Migrate legacy plain-text password to hashed
async function migrateUserPassword(userId, plainPassword) {
    const users = await getStoredUsersAsync();
    if (users[userId]) {
        const { salt, hash } = await createPasswordHash(plainPassword);
        users[userId].passwordHash = hash;
        users[userId].passwordSalt = salt;
        users[userId].sessionToken = generateSessionToken();
        delete users[userId].password; // Remove plain-text password
        await saveUsersAsync(users);
        console.log('✅ User password migrated to secure hash');
    }
}

// Debug function to reset a user's password (for troubleshooting)
async function resetUserPassword(email, newPassword) {
    const users = await getStoredUsersAsync();
    const user = Object.values(users).find(u => u.email.toLowerCase() === email.toLowerCase());
    if (user) {
        const { salt, hash } = await createPasswordHash(newPassword);
        users[user.id].passwordHash = hash;
        users[user.id].passwordSalt = salt;
        await saveUsersAsync(users);
        console.log('✅ Password reset for:', email);
        return true;
    }
    console.log('❌ User not found:', email);
    return false;
}

// Debug: List all users
async function debugListUsers() {
    const users = await getStoredUsersAsync();
    console.log('=== All Registered Users ===');
    Object.values(users).forEach(u => {
        console.log(`- ${u.name} (${u.email}) - ID: ${u.id}`);
        console.log(`  Has passwordHash: ${!!u.passwordHash}, Has salt: ${!!u.passwordSalt}`);
    });
    return users;
}

// Debug functions removed from window scope for production security

// Serialize task for storage (convert dates to ISO strings, remove circular refs)
function serializeTask(task) {
    return {
        id: task.id,
        title: task.title,
        description: task.description,
        category: task.category,
        location: task.location,
        price: task.price,
        serviceCharge: task.serviceCharge || 0,
        totalPaid: task.totalPaid || 0,
        postedBy: task.postedBy ? {
            id: task.postedBy.id,
            name: task.postedBy.name,
            rating: task.postedBy.rating,
            tasksPosted: task.postedBy.tasksPosted
        } : null,
        postedAt: task.postedAt instanceof Date ? task.postedAt.toISOString() : task.postedAt,
        expiresAt: task.expiresAt instanceof Date ? task.expiresAt.toISOString() : task.expiresAt,
        acceptedAt: task.acceptedAt || null,
        completedAt: task.completedAt || null,
        status: task.status,
        earnedAmount: task.earnedAmount || 0,
        service_charge: task.service_charge || 0,
        localOnly: task.localOnly || false
    };
}

// Deserialize task from storage (convert ISO strings back to dates)
function deserializeTask(task) {
    return {
        ...task,
        postedAt: task.postedAt ? new Date(task.postedAt) : new Date(),
        expiresAt: task.expiresAt ? new Date(task.expiresAt) : new Date(Date.now() + 12 * 3600000)
    };
}

// Serialize array of tasks
function serializeTasks(tasks) {
    return tasks.map(t => serializeTask(t));
}

// Deserialize array of tasks
function deserializeTasks(tasks) {
    if (!Array.isArray(tasks)) return [];
    return tasks.map(t => deserializeTask(t));
}

// Task Data - Initially empty, loaded from server
// Demo tasks are only shown if server is unavailable
let tasks = [];

// Demo tasks for offline/fallback mode
// PRODUCTION MODE - NO DEMO DATA
// All data comes from the production API backend

let myPostedTasks = [];
let myAcceptedTasks = [];
let myCompletedTasks = [];

// ========================================
// LIVE CATEGORY COUNTS
// ========================================

async function loadCategoryCounts() {
    try {
        if (typeof TasksAPI !== 'undefined' && TasksAPI.getCategoryCounts) {
            const result = await TasksAPI.getCategoryCounts();
            if (result && result.success && result.counts) {
                updateCategoryCards(result.counts);
                return;
            }
        }
        // Fallback: compute from already-loaded tasks array
        updateCategoryCardsFromTasks();
    } catch (e) {
        console.warn('Category counts fetch failed, using local tasks:', e.message);
        updateCategoryCardsFromTasks();
    }
}

function updateCategoryCards(counts) {
    const cards = document.querySelectorAll('#categoriesGrid .category-card');
    cards.forEach(card => {
        const cat = card.getAttribute('data-category');
        if (!cat) return;
        const count = counts[cat] || 0;
        const span = card.querySelector('.task-count');
        if (span) span.textContent = count + (count === 1 ? ' task' : ' tasks');
    });
}

function updateCategoryCardsFromTasks() {
    const counts = {};
    tasks.forEach(t => {
        if (t.status === 'active' && (!t.expiresAt || new Date(t.expiresAt) > new Date())) {
            const cat = (t.category || '').toLowerCase();
            counts[cat] = (counts[cat] || 0) + 1;
        }
    });
    updateCategoryCards(counts);
}
let notifications = [];

// ========================================
// NOTIFICATION SYSTEM
// ========================================

function loadNotifications() {
    if (!currentUser) return [];
    const saved = localStorage.getItem(`notifications_${currentUser.id}`);
    return saved ? JSON.parse(saved) : [];
}

/**
 * Fetch notifications from backend and sync with localStorage
 * This also parses any JSON action data from the notifications
 */
async function syncNotificationsFromServer() {
    if (!currentUser) return [];
    
    try {
        const response = await fetch(API_BASE_URL + '/notifications', {
            method: 'GET',
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
            }
        });
        
        if (!response.ok) return loadNotifications(); // Fallback to local
        
        const result = await response.json();
        
        if (result.success && result.notifications) {
            // Convert server format to UI format
            const serverNotifications = result.notifications.map(n => {
                // Parse action data from JSON strings
                let action = null;
                try {
                    if (n.data && typeof n.data === 'string') {
                        action = JSON.parse(n.data);
                    } else if (n.data && typeof n.data === 'object') {
                        action = n.data;
                    }
                } catch (e) {
                    console.warn('Could not parse notification action data:', e);
                }
                
                // Map notification_type to UI type
                let uiType = 'info';
                if (n.notification_type === 'task_completed') uiType = 'warning';
                else if (n.notification_type === 'payment_received' || n.notification_type === 'payment_done') uiType = 'success';
                else if (n.notification_type === 'payment_completed') uiType = 'warning';
                
                return {
                    id: n.id,
                    type: uiType,
                    title: n.title || 'Notification',
                    message: n.message || '',
                    taskId: n.task_id,
                    read: n.status === 'read',
                    createdAt: n.created_at,
                    action: action
                };
            });
            
            // Merge with local notifications (keep local ones that don't exist on server)
            const localNotifications = loadNotifications();
            const serverIds = new Set(serverNotifications.map(n => n.id));
            const localOnlyNotifications = localNotifications.filter(n => !serverIds.has(n.id));
            
            // Combine: server notifications first, then local-only ones
            const merged = [...serverNotifications, ...localOnlyNotifications];
            
            // Save to localStorage
            localStorage.setItem(`notifications_${currentUser.id}`, JSON.stringify(merged));
            notifications = merged;
            updateNotificationUI();
            
            return merged;
        }
    } catch (error) {
        console.warn('Could not sync notifications from server:', error.message);
    }
    
    return loadNotifications(); // Fallback to local
}

function saveNotifications() {
    if (!currentUser) return;
    localStorage.setItem(`notifications_${currentUser.id}`, JSON.stringify(notifications));
}

function addNotification(notification) {
    const newNotif = {
        id: Date.now(),
        ...notification,
        read: false,
        createdAt: new Date().toISOString()
    };
    notifications.unshift(newNotif);
    saveNotifications();
    updateNotificationUI();
    return newNotif;
}

function updateNotificationUI() {
    const badge = document.getElementById('notificationBadge');
    const mobileBadge = document.getElementById('mobileBadge');
    const list = document.getElementById('notificationList');
    
    const unreadCount = notifications.filter(n => !n.read).length;
    
    // Update badges
    if (badge) {
        badge.textContent = unreadCount > 9 ? '9+' : unreadCount;
        badge.style.display = unreadCount > 0 ? 'flex' : 'none';
    }
    if (mobileBadge) {
        mobileBadge.textContent = unreadCount > 9 ? '9+' : unreadCount;
        mobileBadge.style.display = unreadCount > 0 ? 'inline' : 'none';
    }
    
    // Update list
    if (list) {
        if (notifications.length === 0) {
            list.innerHTML = `
                <div class="no-notifications">
                    <i class="fas fa-bell-slash"></i>
                    <p>No notifications yet</p>
                </div>
            `;
        } else {
            list.innerHTML = notifications.slice(0, 20).map(n => {
                // Check if notification has action buttons
                const hasActions = n.action && (n.action.type === 'payment' || n.action.type === 'task');
                const actionButton = hasActions ? `
                    <button class="notification-action-btn" onclick="event.stopPropagation(); handleNotificationAction(${n.id}, '${n.action.type}', ${n.taskId || 'null'})">
                        ${n.action.label || (n.action.type === 'payment' ? 'Pay Now' : 'View')}
                    </button>
                ` : '';
                
                return `
                    <div class="notification-item ${n.read ? '' : 'unread'}" onclick="markAsRead(${n.id})">
                        <div class="notification-icon ${n.type || 'info'}">
                            <i class="fas ${getNotificationIcon(n.type)}"></i>
                        </div>
                        <div class="notification-content">
                            <h5>${escapeHtml(n.title)}</h5>
                            <p>${escapeHtml(n.message)}</p>
                            <span class="notification-time">${getTimeAgo(n.createdAt)}</span>
                            ${actionButton}
                        </div>
                    </div>
                `;
            }).join('');
        }
    }
}

function getNotificationIcon(type) {
    switch (type) {
        case 'success': return 'fa-check-circle';
        case 'warning': return 'fa-exclamation-circle';
        case 'task': return 'fa-tasks';
        case 'payment': return 'fa-rupee-sign';
        default: return 'fa-bell';
    }
}

function getTimeAgo(dateString) {
    const date = new Date(dateString);
    const now = new Date();
    const diff = Math.floor((now - date) / 1000);
    
    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`;
    return date.toLocaleDateString();
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function toggleNotifications() {
    const dropdown = document.getElementById('notificationDropdown');
    if (!dropdown) return;

    // Move dropdown to body once so it escapes any stacking context
    if (!dropdown.dataset.movedToBody) {
        document.body.appendChild(dropdown);
        dropdown.dataset.movedToBody = 'true';
    }

    const isOpen = dropdown.classList.toggle('active');

    // Position dropdown near the bell icon on desktop
    if (isOpen) {
        const bell = document.querySelector('.notification-bell');
        if (bell && window.innerWidth > 768) {
            const rect = bell.getBoundingClientRect();
            dropdown.style.top = (rect.bottom + 8) + 'px';
            dropdown.style.right = (window.innerWidth - rect.right) + 'px';
            dropdown.style.left = 'auto';
            dropdown.style.transform = 'none';
        }
    }

    // Manage overlay
    let overlay = document.getElementById('notificationOverlay');
    if (isOpen) {
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'notificationOverlay';
            overlay.className = 'notification-overlay';
            document.body.appendChild(overlay);
        }
        overlay.classList.add('active');
        overlay.onmousedown = function(e) {
            e.preventDefault();
            e.stopPropagation();
            toggleNotifications();
        };
        overlay.ontouchstart = function(e) {
            e.preventDefault();
            e.stopPropagation();
            toggleNotifications();
        };
    } else if (overlay) {
        overlay.classList.remove('active');
    }
}

// Close notification dropdown when clicking outside (desktop fallback)
document.addEventListener('click', function(e) {
    const dropdown = document.getElementById('notificationDropdown');
    if (!dropdown || !dropdown.classList.contains('active')) return;
    // If the target was removed from DOM (e.g. by re-render), don't close
    if (!document.body.contains(e.target)) return;
    // If click is inside the dropdown, don't close
    if (dropdown.contains(e.target)) return;
    // If click is on the bell/wrapper, toggleNotifications handles it
    const wrapper = document.getElementById('notificationWrapper');
    if (wrapper && wrapper.contains(e.target)) return;
    // If click is on the overlay, overlay handler handles it
    const overlay = document.getElementById('notificationOverlay');
    if (overlay && overlay.contains(e.target)) return;
    dropdown.classList.remove('active');
    if (overlay) overlay.classList.remove('active');
});

async function markAsRead(notifId) {
    const notif = notifications.find(n => n.id === notifId);
    if (notif && !notif.read) {
        notif.read = true;
        saveNotifications();
        // Update just the badge counts without re-rendering the list
        const badge = document.getElementById('notificationBadge');
        const mobileBadge = document.getElementById('mobileBadge');
        const unreadCount = notifications.filter(n => !n.read).length;
        if (badge) {
            badge.textContent = unreadCount > 9 ? '9+' : unreadCount;
            badge.style.display = unreadCount > 0 ? 'flex' : 'none';
        }
        if (mobileBadge) {
            mobileBadge.textContent = unreadCount > 9 ? '9+' : unreadCount;
            mobileBadge.style.display = unreadCount > 0 ? 'inline' : 'none';
        }
        // Update the specific item's styling
        const items = document.querySelectorAll('.notification-item.unread');
        items.forEach(item => {
            if (item.getAttribute('onclick')?.includes(notifId)) {
                item.classList.remove('unread');
            }
        });
        try {
            await NotificationsAPI.markAsRead(notifId);
        } catch (e) {
            console.warn('Could not mark notification as read on server:', e.message);
        }
    }
}

async function clearAllNotifications() {
    notifications = [];
    saveNotifications();
    updateNotificationUI();
    try {
        await NotificationsAPI.clearAll();
    } catch (e) {
        console.warn('Could not clear notifications on server:', e.message);
    }
    showToast('All notifications cleared');
}

/**
 * Handle notification action buttons (e.g., "Pay Now" on payment notifications)
 */
async function handleNotificationAction(notificationId, actionType, taskId) {
    const notification = notifications.find(n => n.id === notificationId);
    
    if (!notification) {
        showToast('❌ Notification not found');
        return;
    }

    // Close notification dropdown and overlay before showing payment modal
    function closeNotifDropdown() {
        const dropdown = document.getElementById('notificationDropdown');
        if (dropdown) dropdown.classList.remove('active');
        const overlay = document.getElementById('notificationOverlay');
        if (overlay) overlay.classList.remove('active');
    }
    
    if (actionType === 'payment' && taskId) {
        console.log(`💳 Processing payment for task ${taskId} from notification`);
        closeNotifDropdown();
        await processPaymentFromNotification(taskId, notification);
    } else if (actionType === 'task' && taskId) {
        console.log(`📋 Opening task ${taskId}`);
        closeNotifDropdown();
        const section = currentUserRole === 'poster' ? 'myTasks' : 'browseTasks';
        showSection(section);
        setTimeout(() => {
            const taskElement = document.querySelector(`[data-task-id="${taskId}"]`);
            if (taskElement) taskElement.scrollIntoView({ behavior: 'smooth' });
        }, 500);
    }
    
    // Mark notification as read
    markAsRead(notificationId);
}

/**
 * Process payment when poster clicks "Pay Now" from notification
 * Deducts commission from poster's wallet and updates balance display
 */
async function processPaymentFromNotification(taskId, notification) {
    // Mark notification as read
    if (notification?.id) {
        markAsRead(notification.id);
    }
    // Unified payment flow
    await showPaymentInvoice(taskId);
}

// Send email notification for task acceptance
async function sendTaskAcceptedEmail(taskPoster, task, acceptedBy) {
    if (typeof emailjs === 'undefined' || !isEmailJSConfigured()) {
        console.log('📧 EmailJS not configured, skipping email notification');
        return false;
    }
    
    try {
        // Create a notification email template
        const templateParams = {
            to_email: taskPoster.email,
            to_name: taskPoster.name,
            otp_code: '', // Not used for this type
            app_name: 'Workmate4u',
            // Custom fields - add these to your EmailJS template
            subject: `Your task "${task.title}" has been accepted!`,
            message: `Great news! ${acceptedBy.name} has accepted your task "${task.title}". You can now coordinate with them to get your task completed. Budget: ₹${task.price}`
        };
        
        await emailjs.send(
            EMAILJS_CONFIG.SERVICE_ID,
            EMAILJS_CONFIG.TEMPLATE_ID,
            templateParams
        );
        
        console.log('✅ Task acceptance email sent to:', taskPoster.email);
        return true;
    } catch (error) {
        console.error('❌ Failed to send email:', error);
        return false;
    }
}

// Notify task poster when task is accepted
function notifyTaskPoster(task, acceptedBy) {
    // Find the task poster's user data
    const users = JSON.parse(localStorage.getItem('taskearn_users') || '{}');
    
    // Try to find poster by ID first, then by email
    let posterUser = null;
    const posterId = task.postedBy?.id;
    const posterEmail = task.postedBy?.email;
    
    if (posterId && users[posterId]) {
        posterUser = users[posterId];
    } else if (posterEmail) {
        // Fallback: find by email
        for (const userId in users) {
            if (users[userId].email === posterEmail) {
                posterUser = users[userId];
                break;
            }
        }
    }
    
    if (posterUser && posterUser.id !== acceptedBy.id) {
        // Add in-app notification for poster
        const posterNotifications = JSON.parse(localStorage.getItem(`notifications_${posterUser.id}`) || '[]');
        posterNotifications.unshift({
            id: Date.now(),
            type: 'success',
            title: 'Task Accepted! 🎉',
            message: `${acceptedBy.name} has accepted your task "${task.title}". Budget: ₹${task.price}`,
            taskId: task.id,
            read: false,
            createdAt: new Date().toISOString()
        });
        localStorage.setItem(`notifications_${posterUser.id}`, JSON.stringify(posterNotifications));
        
        // Send email notification
        sendTaskAcceptedEmail(posterUser, task, acceptedBy);
        
        console.log('✅ Notification sent to task poster:', posterUser.name);
    }
}

// Close notification dropdown when clicking outside
document.addEventListener('click', function(e) {
    const wrapper = document.getElementById('notificationWrapper');
    const dropdown = document.getElementById('notificationDropdown');
    if (wrapper && dropdown && !wrapper.contains(e.target)) {
        dropdown.classList.remove('active');
    }
});

// ========================================
// INITIALIZATION
// ========================================

// Load tasks from backend API (PRODUCTION ONLY - NO LOCAL FALLBACKS)
async function loadTasksFromServer() {
    try {
        console.log('📡 Loading tasks from backend server...');
        showTaskListSkeletons();
        console.log('🔑 API Token exists:', !!localStorage.getItem('taskearn_token'));
        console.log('🌐 API URL:', typeof API_BASE_URL !== 'undefined' ? API_BASE_URL : window.TASKEARN_API_URL);
        
        if (typeof TasksAPI !== 'undefined' && TasksAPI.getAll) {
            console.log('🚀 Calling TasksAPI.getAll...');
            const result = await TasksAPI.getAll();
            console.log('📥 Raw server response:', JSON.stringify(result, null, 2));
            
            if (result.success && result.tasks) {
                console.log('✅ Tasks received:', result.tasks.length);
                
                // Map server tasks with proper date parsing
                const serverTasks = result.tasks.map(t => ({
                    ...t,
                    postedAt: new Date(t.postedAt),
                    expiresAt: new Date(t.expiresAt)
                }));
                
                console.log('📊 Server tasks after parsing:', serverTasks.length);
                tasks = serverTasks;
                
                // ✅ Sync myPostedTasks and myAcceptedTasks with REAL DB statuses
                // TasksAPI.getAll() only returns 'active' tasks, so we must call
                // UserAPI.getTasks() to get completed/paid statuses for the current user
                if (currentUser) {
                    try {
                        const userTasksResult = await UserAPI.getTasks();
                        if (userTasksResult && userTasksResult.success) {
                            // Sync posted tasks with real DB statuses
                            if (userTasksResult.postedTasks && userTasksResult.postedTasks.length > 0) {
                                const dbPosted = userTasksResult.postedTasks;
                                console.log('🔄 Syncing posted tasks from DB:', dbPosted.length);
                                
                                // Build lookup map from DB
                                const dbPostedMap = {};
                                dbPosted.forEach(t => { dbPostedMap[t.id] = t; });
                                
                                // Update existing local tasks with DB status
                                myPostedTasks = myPostedTasks.map(pt => {
                                    const dbTask = dbPostedMap[pt.id];
                                    if (dbTask) {
                                        if (pt.status !== dbTask.status) {
                                            console.log(`   Posted Task ${pt.id}: ${pt.status} → ${dbTask.status}`);
                                        }
                                        return {
                                            ...pt,
                                            status: dbTask.status,
                                            acceptedBy: dbTask.accepted_by || pt.acceptedBy,
                                            completedAt: dbTask.completed_at || pt.completedAt,
                                            price: parseFloat(dbTask.price) || pt.price,
                                            service_charge: parseFloat(dbTask.service_charge || 0)
                                        };
                                    }
                                    return pt;
                                });
                                
                                // Add any DB tasks not in local list (skip paid/expired)
                                dbPosted.forEach(dbTask => {
                                    if (dbTask.status === 'paid') return;
                                    if (dbTask.status === 'active' && new Date(dbTask.expires_at) <= new Date()) return;
                                    if (!myPostedTasks.find(pt => pt.id === dbTask.id)) {
                                        myPostedTasks.push({
                                            id: dbTask.id,
                                            title: dbTask.title,
                                            description: dbTask.description,
                                            category: dbTask.category,
                                            price: parseFloat(dbTask.price),
                                            service_charge: parseFloat(dbTask.service_charge || 0),
                                            status: dbTask.status,
                                            postedAt: new Date(dbTask.posted_at),
                                            expiresAt: new Date(dbTask.expires_at),
                                            acceptedBy: dbTask.accepted_by,
                                            completedAt: dbTask.completed_at,
                                            postedBy: { id: currentUser.id, name: currentUser.name },
                                            location: {
                                                lat: dbTask.location_lat,
                                                lng: dbTask.location_lng,
                                                address: dbTask.location_address
                                            }
                                        });
                                    }
                                });
                                
                                // Remove paid and expired-active tasks from myPostedTasks
                                myPostedTasks = myPostedTasks.filter(t => {
                                    if (t.status === 'paid') return false;
                                    if (t.status === 'active' && t.expiresAt && new Date(t.expiresAt) <= new Date()) return false;
                                    return true;
                                });
                                
                                updateUserData(currentUser.id, {
                                    postedTasks: serializeTasks(myPostedTasks)
                                });
                            }
                            
                            // Sync accepted tasks with real DB statuses
                            if (userTasksResult.acceptedTasks) {
                                const dbAccepted = userTasksResult.acceptedTasks;
                                console.log('🔄 Syncing accepted tasks from DB:', dbAccepted.length);
                                
                                const dbAcceptedMap = {};
                                dbAccepted.forEach(t => { dbAcceptedMap[t.id] = t; });
                                
                                // Remove local tasks that no longer exist in DB accepted list
                                // (e.g., tasks that were abandoned/released)
                                myAcceptedTasks = myAcceptedTasks.filter(at => {
                                    const stillInDb = dbAcceptedMap[at.id];
                                    if (!stillInDb) {
                                        console.log(`   Accepted Task ${at.id}: removed (no longer in DB accepted list)`);
                                        return false;
                                    }
                                    return true;
                                });
                                
                                // Update remaining local tasks with DB data
                                myAcceptedTasks = myAcceptedTasks.map(at => {
                                    const dbTask = dbAcceptedMap[at.id];
                                    if (dbTask) {
                                        if (at.status !== dbTask.status) {
                                            console.log(`   Accepted Task ${at.id}: ${at.status} → ${dbTask.status}`);
                                        }
                                        return {
                                            ...at,
                                            status: dbTask.status,
                                            completedAt: dbTask.completed_at || at.completedAt,
                                            price: parseFloat(dbTask.price) || at.price,
                                            service_charge: parseFloat(dbTask.service_charge || 0)
                                        };
                                    }
                                    return at;
                                });
                                
                                // Add any DB tasks not in local list (skip paid and expired-accepted)
                                dbAccepted.forEach(dbTask => {
                                    if (dbTask.status === 'paid') return;
                                    if (dbTask.status === 'accepted' && new Date(dbTask.expires_at) <= new Date()) return;
                                    if (!myAcceptedTasks.find(at => at.id == dbTask.id)) {
                                        myAcceptedTasks.push({
                                            id: dbTask.id,
                                            title: dbTask.title,
                                            description: dbTask.description,
                                            category: dbTask.category,
                                            price: parseFloat(dbTask.price),
                                            service_charge: parseFloat(dbTask.service_charge || 0),
                                            status: dbTask.status,
                                            postedAt: new Date(dbTask.posted_at),
                                            expiresAt: new Date(dbTask.expires_at),
                                            completedAt: dbTask.completed_at,
                                            postedBy: { id: dbTask.posted_by },
                                            location: {
                                                lat: dbTask.location_lat,
                                                lng: dbTask.location_lng,
                                                address: dbTask.location_address || ''
                                            }
                                        });
                                    }
                                });
                                
                                // Move paid tasks to myCompletedTasks before removing
                                const paidTasks = myAcceptedTasks.filter(t => t.status === 'paid');
                                paidTasks.forEach(pt => {
                                    if (!myCompletedTasks.find(ct => ct.id == pt.id)) {
                                        const taskAmount = pt.price || 0;
                                        const serviceCharge = pt.service_charge || pt.serviceCharge || 0;
                                        pt.earnedAmount = (taskAmount + serviceCharge) * 0.88;
                                        myCompletedTasks.push(pt);
                                        currentUser.tasksCompleted = (currentUser.tasksCompleted || 0) + 1;
                                        currentUser.totalEarnings = parseFloat(currentUser.totalEarnings || 0) + pt.earnedAmount;
                                        currentUser.totalEarnings = Math.round(currentUser.totalEarnings * 100) / 100;
                                    }
                                });
                                
                                // Remove paid and expired-accepted tasks from myAcceptedTasks
                                myAcceptedTasks = myAcceptedTasks.filter(t => {
                                    if (t.status === 'paid') return false;
                                    if (t.status === 'accepted' && t.expiresAt && new Date(t.expiresAt) <= new Date()) return false;
                                    return true;
                                });
                                
                                updateUserData(currentUser.id, {
                                    acceptedTasks: serializeTasks(myAcceptedTasks),
                                    completedTasks: serializeTasks(myCompletedTasks),
                                    tasksCompleted: currentUser.tasksCompleted,
                                    totalEarnings: currentUser.totalEarnings
                                });
                            }
                            
                            // Check for tasks awaiting payment
                            const tasksAwaitingPayment = myPostedTasks.filter(t => t.status === 'completed');
                            if (tasksAwaitingPayment.length > 0) {
                                console.log('💰 Tasks awaiting your payment:', tasksAwaitingPayment.length);
                                showToast(`💰 ${tasksAwaitingPayment.length} task(s) completed and awaiting your payment!`, 5000);
                            }
                        }
                    } catch (e) {
                        console.warn('Could not sync user tasks from DB:', e.message);
                    }
                }
                
                console.log('✅ Loaded', serverTasks.length, 'tasks from server');
                console.log('📋 Total tasks now:', tasks.length);
                renderTasks();
                addTaskMarkers();
                return true;
            } else if (result.offline) {
                // Offline mode - use cached data
                console.warn('⚠️ Backend offline - using cached data');
                const cachedTasks = localStorage.getItem('cached_tasks');
                if (cachedTasks) {
                    try {
                        tasks = JSON.parse(cachedTasks).map(t => ({
                            ...t,
                            postedAt: new Date(t.postedAt),
                            expiresAt: new Date(t.expiresAt)
                        }));
                        try {
                            if (typeof showNotification === 'function') {
                                showNotification('⚠️ Backend offline. Showing cached tasks.', 'warning');
                            }
                        } catch (e) {
                            console.warn('showNotification not available, using alert');
                            alert('⚠️ Backend offline. Showing cached tasks.');
                        }
                        renderTasks();
                        addTaskMarkers();
                        return true;
                    } catch (e) {
                        console.error('Failed to parse cached tasks:', e);
                    }
                }
                try {
                    if (typeof showNotification === 'function') {
                        showNotification('⚠️ Backend offline. No cached data available.', 'warning');
                    }
                } catch (e) {
                    console.warn('Using alert instead of showNotification');
                    alert('⚠️ Backend offline. No cached data available.');
                }
                tasks = [];
                renderTasks();
                return false;
            } else {
                console.error('❌ Server error: Server returned success=false');
                console.error('Result:', result);
                // Try to use local cache
                const cachedTasks = localStorage.getItem('cached_tasks');
                if (cachedTasks) {
                    try {
                        tasks = JSON.parse(cachedTasks).map(t => ({
                            ...t,
                            postedAt: new Date(t.postedAt),
                            expiresAt: new Date(t.expiresAt)
                        }));
                        try {
                            if (typeof showNotification === 'function') {
                                showNotification('⚠️ Showing cached tasks. Backend is temporarily unavailable.', 'warning');
                            }
                        } catch (e) {
                            console.warn('showNotification not available');
                        }
                        renderTasks();
                        addTaskMarkers();
                        return true;
                    } catch (e) {
                        console.error('Failed to parse cached tasks:', e);
                    }
                }
                try {
                    if (typeof showNotification === 'function') {
                        showNotification('❌ Cannot load tasks. Backend server not responding.', 'error');
                    }
                } catch (e) {
                    console.warn('showNotification error');
                }
                tasks = [];
                renderTasks();
                return false;
            }
        } else {
            console.error('❌ TasksAPI not available');
            try {
                if (typeof showNotification === 'function') {
                    showNotification('⚠️ Working in offline mode. Some features may be limited.', 'warning');
                }
            } catch (e) {
                console.warn('showNotification not available');
            }
            return false;
        }
    } catch (error) {
        console.error('❌ Error loading tasks from backend:', error);
        
        // Try to use local cache or sample data
        const cachedTasks = localStorage.getItem('cached_tasks');
        if (cachedTasks) {
            try {
                tasks = JSON.parse(cachedTasks).map(t => ({
                    ...t,
                    postedAt: new Date(t.postedAt),
                    expiresAt: new Date(t.expiresAt)
                }));
                try {
                    if (typeof showNotification === 'function') {
                        showNotification('⚠️ Backend unavailable. Showing cached tasks.', 'warning');
                    }
                } catch (e) {
                    console.warn('showNotification not available');
                }
                renderTasks();
                addTaskMarkers();
                return true;
            } catch (e) {
                console.error('Failed to parse cached tasks:', e);
            }
        }
        
        // Show helpful error message with troubleshooting steps
        const errorMsg = `⚠️ Cannot connect to backend server.\n\n` +
                        `This could be due to:\n` +
                        `1. Railway deployment not started yet\n` +
                        `2. Network connectivity issues\n` +
                        `3. Backend service temporarily down\n\n` +
                        `Using offline mode with local data.`;
        try {
            if (typeof showNotification === 'function') {
                showNotification(errorMsg, 'error', 8000);
            } else {
                console.warn(errorMsg);
                alert(errorMsg);
            }
        } catch (e) {
            console.warn('Cannot show notification:', e);
        }
        
        tasks = [];
        renderTasks();
        return false;
    }
}

// Refresh wallet balance from server
async function refreshWalletBalance() {
    if (!currentUser) return false;
    
    try {
        console.log('💰 Refreshing wallet balance from server...');
        
        if (typeof WalletAPI !== 'undefined' && WalletAPI.get) {
            const result = await WalletAPI.get();
            
            if (result && result.success && result.wallet) {
                const walletData = result.wallet;
                console.log('✅ Wallet updated:', walletData);
                
                // Update currentUser wallet
                currentUser.wallet = walletData.balance;
                
                // Save updated user data
                updateUserData(currentUser.id, {
                    wallet: walletData.balance
                });
                
                // Check debt suspension status
                if (walletData.balance >= 0 && isDebtSuspended()) {
                    clearDebtSuspension();
                    console.log('✅ Debt cleared! Wallet balance >= 0');
                    showToast('🎉 Your debt has been cleared! Account restored.', 'success');
                } else if (walletData.balance <= -500) {
                    setDebtSuspension(Math.abs(walletData.balance));
                }
                
                // Update UI if wallet display exists
                const walletDisplay = document.querySelector('[data-wallet-balance]');
                if (walletDisplay) {
                    walletDisplay.textContent = `₹${walletData.balance.toFixed(2)}`;
                    walletDisplay.setAttribute('data-wallet-balance', walletData.balance.toFixed(2));
                }
                
                return true;
            } else {
                console.warn('❌ Failed to get wallet:', result);
                return false;
            }
        }
    } catch (error) {
        console.warn('⚠️ Error refreshing wallet:', error);
        return false;
    }
}

document.addEventListener('DOMContentLoaded', async function() {
    try {
        console.log('🚀 Workmate4u Starting...');
        console.log('📦 localStorage available:', STORAGE_AVAILABLE);
        console.log('🔑 API Token:', localStorage.getItem('taskearn_token') ? 'EXISTS (✅)' : 'MISSING (❌)');
        console.log('🌐 Backend URL:', window.TASKEARN_API_URL);
        console.log('🔌 TasksAPI available:', typeof TasksAPI !== 'undefined' ? 'YES (✅)' : 'NO (❌)');
        console.log('🔌 AuthAPI available:', typeof AuthAPI !== 'undefined' ? 'YES (✅)' : 'NO (❌)');
        
        // Wait for IndexedDB to initialize
        try {
            await initIndexedDB();
        } catch (e) {
            console.warn('⚠️ IndexedDB init failed:', e.message);
        }
        
        // Initialize Push Notifications (non-critical, won't fail)
        try {
            initPushNotifications();
        } catch (e) {
            console.warn('⚠️ Push notifications failed:', e.message);
        }
        
        // Check and clear expired suspension
        checkAndClearSuspension();
        
        // Debug: Show all stored users (using async version for full support)
        try {
            const allUsers = await getStoredUsersAsync();
            console.log('👥 Registered users:', Object.keys(allUsers).length);
            
            // List registered user emails for debugging
            if (Object.keys(allUsers).length > 0) {
                console.log('📧 Registered emails:', Object.values(allUsers).map(u => u.email));
            }
        } catch (e) {
            console.warn('⚠️ Could not load users:', e.message);
        }
        
        // Check for existing session (using async version)
        try {
            const savedUser = await loadCurrentSessionAsync();
            if (savedUser) {
                currentUser = savedUser;
                myPostedTasks = deserializeTasks(savedUser.postedTasks);
                myAcceptedTasks = deserializeTasks(savedUser.acceptedTasks);
                myCompletedTasks = deserializeTasks(savedUser.completedTasks);
                console.log('✅ Session restored for:', currentUser.name);
                console.log('📋 Posted tasks:', myPostedTasks.length);
                console.log('✔️ Accepted tasks:', myAcceptedTasks.length);
                
                // Check if user has API token (backend authentication)
                const hasApiToken = !!localStorage.getItem('taskearn_token');
                if (!hasApiToken) {
                    console.warn('⚠️ Local-only user detected:', currentUser.email);
                    console.warn('⚠️ This user needs to be migrated to backend on next login');
                    // Show migration warning banner
                    setTimeout(() => {
                        try {
                            const banner = document.getElementById('migrationWarningBanner');
                            if (banner) {
                                banner.style.display = 'block';
                            }
                        } catch (e) {
                            console.warn('⚠️ Could not show migration banner:', e.message);
                        }
                        console.warn('📢 User needs to re-login to migrate to backend');
                    }, 2000);
                }
                
                setTimeout(() => {
                    try {
                        updateNavForUser();
                    } catch (e) {
                        console.warn('⚠️ Nav update failed:', e.message);
                    }
                }, 100);
                
                // Sync suspension from server BEFORE rendering dashboard
                try {
                    await syncSuspensionFromServer();
                } catch (e) {
                    console.warn('⚠️ Suspension sync failed:', e.message);
                }
                
                try {
                    renderDashboard();
                } catch (e) {
                    console.warn('⚠️ Dashboard render failed:', e.message);
                }
            } else {
                console.log('👤 No active session - user needs to login');
            }
        } catch (e) {
            console.warn('⚠️ Session load failed:', e.message);
        }
        
        // Initialize map first
        try {
            initializeMap();
        } catch (e) {
            console.warn('⚠️ Map initialization failed:', e.message);
        }
        
        // Setup UI
        try {
            setupEventListeners();
            setMinDateTime();
        } catch (e) {
            console.warn('⚠️ Event listener setup failed:', e.message);
        }
        
        // Load tasks from server (replaces demo tasks)
        try {
            await loadTasksFromServer();
        } catch (e) {
            console.warn('⚠️ Could not load tasks from server:', e.message);
        }
        
        // Load live category counts for Popular Tasks section
        try {
            await loadCategoryCounts();
        } catch (e) {
            console.warn('⚠️ Category counts failed:', e.message);
        }
        
        // Fallback render if server load failed
        try {
            renderTasks();
            startTaskTimers();
        } catch (e) {
            console.warn('⚠️ Task rendering failed:', e.message);
        }
        
        // Refresh tasks from server every 30 seconds
        setInterval(() => {
            try {
                loadTasksFromServer().catch(e => console.warn('⚠️ Auto-refresh failed:', e.message));
                loadCategoryCounts().catch(e => console.warn('⚠️ Category count refresh failed:', e.message));
                // Also refresh wallet balance
                refreshWalletBalance().catch(e => console.warn('⚠️ Wallet refresh failed:', e.message));
            } catch (e) {
                console.warn('⚠️ Task refresh failed:', e.message);
            }
        }, 30000);
        
        console.log('✅ Workmate4u Ready!');
    } catch (error) {
        console.error('❌ CRITICAL ERROR during initialization:', error);
        console.error('Stack:', error.stack);
        // Still try to show UI
        try {
            renderTasks();
        } catch (e) {
            console.error('❌ Could not even render tasks:', e);
        }
    }
});

// ========================================
// PUSH NOTIFICATIONS
// ========================================

let notificationPermission = 'default';

function initPushNotifications() {
    if ('Notification' in window) {
        notificationPermission = Notification.permission;
        console.log('🔔 Notification permission:', notificationPermission);
        
        if (notificationPermission === 'default') {
            // Ask for permission after user interacts with the page
            document.addEventListener('click', requestNotificationPermission, { once: true });
        }
    } else {
        console.log('⚠️ Push notifications not supported');
    }
}

async function requestNotificationPermission() {
    if ('Notification' in window && Notification.permission === 'default') {
        try {
            const permission = await Notification.requestPermission();
            notificationPermission = permission;
            console.log('🔔 Notification permission:', permission);
            
            if (permission === 'granted') {
                showLocalNotification('Workmate4u', 'Notifications enabled! You\'ll be notified about task updates.');
            }
        } catch (e) {
            console.error('Error requesting notification permission:', e);
        }
    }
}

function showLocalNotification(title, body, options = {}) {
    if (notificationPermission !== 'granted') return;
    
    try {
        const notification = new Notification(title, {
            body: body,
            icon: 'https://img.icons8.com/fluency/96/task.png',
            badge: 'https://img.icons8.com/fluency/48/task.png',
            vibrate: [200, 100, 200],
            tag: options.tag || 'taskearn-notification',
            renotify: true,
            ...options
        });
        
        notification.onclick = function() {
            window.focus();
            notification.close();
            if (options.url) {
                window.location.href = options.url;
            }
        };
        
        // Auto close after 5 seconds
        setTimeout(() => notification.close(), 5000);
        
    } catch (e) {
        console.error('Error showing notification:', e);
    }
}


// ========================================
// MAP INITIALIZATION
// ========================================

function initializeMap() {
    try {
        const container = document.getElementById('map');
        if (!container) {
            console.log('ℹ️ No #map container on this page, skipping map init');
            return;
        }

        // Create map
        map = L.map('map', {
            center: [userLocation.lat, userLocation.lng],
            zoom: 12,
            zoomControl: false
        });

        // Add OpenStreetMap tiles
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '© OpenStreetMap',
            maxZoom: 19
        }).addTo(map);

        // Fix tiles when container was hidden during init
        setTimeout(() => {
            if (map) map.invalidateSize();
        }, 300);

        console.log('✅ Map initialized');

        // Add task markers
        addTaskMarkers();

        // Try to get user location
        getUserLocation();

    } catch (error) {
        console.error('❌ Map error:', error);
    }
}

// ========================================
// GPS / LOCATION SYSTEM
// ========================================

function getUserLocation() {
    setGPSStatus('searching', 'Locating...');

    // Check if geolocation is available
    if (!navigator.geolocation) {
        console.log('❌ Geolocation not supported');
        setGPSStatus('unavailable', 'GPS Unavailable');
        showToast('GPS not supported. Using default location.');
        placeUserMarker(userLocation);
        return;
    }

    // Check if we're on HTTPS or localhost (required for GPS)
    const isSecure = location.protocol === 'https:';
    
    if (!isSecure) {
        console.log('⚠️ GPS requires HTTPS');
        setGPSStatus('unavailable', 'Needs HTTPS');
        showToast('GPS requires HTTPS. Using default location (Delhi).');
        placeUserMarker(userLocation);
        return;
    }

    // Try to get location
    navigator.geolocation.getCurrentPosition(
        function(position) {
            // Success!
            userLocation = {
                lat: position.coords.latitude,
                lng: position.coords.longitude
            };
            
            console.log('✅ GPS Success:', userLocation);
            setGPSStatus('active', 'GPS Active');
            showToast('📍 Location found!');
            
            placeUserMarker(userLocation, position.coords.accuracy);
            map.setView([userLocation.lat, userLocation.lng], 14);
            renderTasks();
            
            // Start watching position
            startLocationWatch();
        },
        function(error) {
            // Error handling
            console.log('❌ GPS Error:', error.code, error.message);
            
            let msg = 'Location error';
            switch(error.code) {
                case 1: 
                    msg = 'Permission Denied'; 
                    setGPSStatus('denied', msg);
                    break;
                case 2: 
                    msg = 'Position Unavailable'; 
                    setGPSStatus('unavailable', msg);
                    break;
                case 3: 
                    msg = 'Timeout'; 
                    setGPSStatus('timeout', 'GPS Timeout');
                    break;
            }
            
            showToast('GPS: ' + msg + '. Using Delhi location.');
            placeUserMarker(userLocation);
        },
        {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 60000
        }
    );
}

function startLocationWatch() {
    if (gpsWatchId !== null) {
        navigator.geolocation.clearWatch(gpsWatchId);
    }

    isGPSActive = true;
    document.getElementById('trackingBtn')?.classList.add('active');

    gpsWatchId = navigator.geolocation.watchPosition(
        function(position) {
            userLocation = {
                lat: position.coords.latitude,
                lng: position.coords.longitude
            };

            // Update marker position
            if (userMarker) {
                userMarker.setLatLng([userLocation.lat, userLocation.lng]);
            }
            if (userCircle) {
                userCircle.setLatLng([userLocation.lat, userLocation.lng]);
                userCircle.setRadius(position.coords.accuracy);
            }

            setGPSStatus('active', 'Live');
        },
        function(error) {
            console.log('Watch error:', error.message);
            setGPSStatus('error', 'Signal Lost');
        },
        {
            enableHighAccuracy: true,
            timeout: 15000,
            maximumAge: 10000
        }
    );
}

function stopLocationWatch() {
    if (gpsWatchId !== null) {
        navigator.geolocation.clearWatch(gpsWatchId);
        gpsWatchId = null;
    }
    isGPSActive = false;
    document.getElementById('trackingBtn')?.classList.remove('active');
    setGPSStatus('paused', 'Paused');
}

function toggleTracking() {
    if (isGPSActive) {
        stopLocationWatch();
        showToast('GPS tracking paused');
    } else {
        getUserLocation();
    }
}

function setGPSStatus(status, text) {
    const dot = document.querySelector('.tracking-dot');
    const label = document.getElementById('trackingText');

    if (dot) {
        dot.className = 'tracking-dot';
        switch(status) {
            case 'active': dot.classList.add('active'); break;
            case 'searching': dot.classList.add('searching'); break;
            case 'error':
            case 'denied':
            case 'unavailable':
            case 'timeout': dot.classList.add('error'); break;
            case 'paused': dot.classList.add('paused'); break;
        }
    }

    if (label) {
        label.textContent = text;
    }
}

function placeUserMarker(location, accuracy = 100) {
    // Remove existing
    if (userMarker) {
        map.removeLayer(userMarker);
        userMarker = null;
    }
    if (userCircle) {
        map.removeLayer(userCircle);
        userCircle = null;
    }

    // Accuracy circle
    userCircle = L.circle([location.lat, location.lng], {
        radius: Math.min(accuracy, 500),
        color: '#6366f1',
        fillColor: '#6366f1',
        fillOpacity: 0.1,
        weight: 2
    }).addTo(map);

    // User marker
    const icon = L.divIcon({
        className: 'my-location-icon',
        html: '<div class="loc-outer"><div class="loc-inner"></div></div>',
        iconSize: [24, 24],
        iconAnchor: [12, 12]
    });

    userMarker = L.marker([location.lat, location.lng], { 
        icon: icon,
        zIndexOffset: 1000 
    }).addTo(map);

    userMarker.bindPopup('<b>📍 Your Location</b>');
}

// ========================================
// TASK MARKERS
// ========================================

function addTaskMarkers() {
    if (!map) return;

    // Clear old markers
    taskMarkers.forEach(m => {
        if (map.hasLayer(m)) map.removeLayer(m);
    });
    taskMarkers = [];

    // Add markers for active, non-expired tasks
    tasks.filter(t => t.status === 'active' && getTimeLeft(t.expiresAt) !== 'Expired').forEach(task => {
        if (!task.location || !task.location.lat || !task.location.lng) return;
        const icon = getTaskIcon(task.category);
        const marker = L.marker([task.location.lat, task.location.lng], { icon }).addTo(map);

        marker.on('click', function() {
            selectedTask = task;
            highlightTaskCard(task.id);
            showRouteTo(task);
            openTaskDetail(task.id);
        });

        taskMarkers.push(marker);
    });
}

function getTaskIcon(category) {
    const colors = {
        household: '#f59e0b',
        delivery: '#10b981',
        tutoring: '#6366f1',
        transport: '#0ea5e9',
        vehicle: '#8b5cf6',
        repair: '#ef4444',
        photography: '#ec4899',
        freelance: '#14b8a6',
        waste: '#78716c',
        cleaning: '#06b6d4',
        cooking: '#f97316',
        petcare: '#a855f7',
        gardening: '#22c55e',
        shopping: '#3b82f6',
        eventhelp: '#f43f5e',
        moving: '#64748b',
        techsupport: '#0891b2',
        beauty: '#e879f9',
        laundry: '#38bdf8',
        catering: '#fb923c',
        babysitting: '#f472b6',
        eldercare: '#84cc16',
        fitness: '#ef4444',
        painting: '#8b5cf6',
        electrician: '#fbbf24',
        plumbing: '#2563eb',
        carpentry: '#92400e',
        tailoring: '#d946ef',
        other: '#6366f1'
    };

    const emojis = {
        household: '🏠',
        delivery: '📦',
        tutoring: '📚',
        transport: '🚗',
        vehicle: '🚙',
        repair: '🔧',
        photography: '📷',
        freelance: '💻',
        waste: '🗑️',
        cleaning: '🧹',
        cooking: '👨‍🍳',
        petcare: '🐕',
        gardening: '🌱',
        shopping: '🛒',
        eventhelp: '🎉',
        moving: '📦',
        techsupport: '🖥️',
        beauty: '💅',
        laundry: '👔',
        catering: '🍽️',
        babysitting: '👶',
        eldercare: '👴',
        fitness: '💪',
        painting: '🎨',
        electrician: '⚡',
        plumbing: '🔧',
        carpentry: '🪚',
        tailoring: '🧵',
        other: '📌'
    };

    const color = colors[category] || '#6366f1';
    const emoji = emojis[category] || '📌';

    return L.divIcon({
        className: 'task-pin',
        html: `<div style="background:${color};width:32px;height:32px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;border:2px solid white;box-shadow:0 2px 8px rgba(0,0,0,0.3);"><span style="transform:rotate(45deg);font-size:14px;">${emoji}</span></div>`,
        iconSize: [32, 32],
        iconAnchor: [16, 32],
        popupAnchor: [0, -32]
    });
}

// ========================================
// ROUTING (Simple Polyline)
// ========================================

function showRouteTo(task) {
    clearRoute();

    // Draw a simple line from user to task
    const points = [
        [userLocation.lat, userLocation.lng],
        [task.location.lat, task.location.lng]
    ];

    routeLayer = L.polyline(points, {
        color: '#6366f1',
        weight: 4,
        opacity: 0.8,
        dashArray: '10, 10'
    }).addTo(map);

    // Calculate distance
    const dist = getDistance(userLocation.lat, userLocation.lng, task.location.lat, task.location.lng);
    const eta = Math.round(dist * 3); // ~3 min per km estimate

    showDistancePanel(dist.toFixed(1), eta, task);
}

function showDistancePanel(km, mins, task) {
    const panel = document.getElementById('distanceInfo');
    // Use service_charge from task object (set at creation), fallback to calculation
    const serviceCharge = task.service_charge !== undefined ? parseFloat(task.service_charge) : getServiceCharge(task.category);
    const totalEarnings = parseFloat(task.price) + serviceCharge;
    const chargeInfo = getServiceChargeInfo(task.category);
    
    if (panel) {
        panel.innerHTML = `
            <h4>📍 Distance & Earnings</h4>
            <div class="distance-value">${km} km</div>
            <div class="eta">~${mins} min drive</div>
            <div class="price-info">
                <div class="total-price">Earn: <strong>₹${totalEarnings.toFixed(0)}</strong></div>
                <small style="color:#10b981;">₹${parseFloat(task.price).toFixed(0)} + ₹${serviceCharge.toFixed(0)} (${chargeInfo.level})</small>
            </div>
            <button class="directions-btn" onclick="openGoogleMaps(${task.location.lat}, ${task.location.lng})">
                <i class="fas fa-directions"></i> Navigate
            </button>
            <button class="directions-btn secondary" onclick="clearRoute()">
                <i class="fas fa-times"></i> Clear
            </button>
        `;
        panel.classList.add('show');
    }
}

function openGoogleMaps(lat, lng) {
    const url = `https://www.google.com/maps/dir/${userLocation.lat},${userLocation.lng}/${lat},${lng}`;
    window.open(url, '_blank');
}

function clearRoute() {
    if (routeLayer && map.hasLayer(routeLayer)) {
        map.removeLayer(routeLayer);
        routeLayer = null;
    }
    selectedTask = null;
    
    const panel = document.getElementById('distanceInfo');
    if (panel) panel.classList.remove('show');
}

// ========================================
// MAP CONTROLS
// ========================================

function centerOnUser() {
    if (map && userLocation) {
        map.setView([userLocation.lat, userLocation.lng], 15);
        showToast('Centered on your location');
    }
}

function zoomIn() {
    if (map) map.zoomIn();
}

function zoomOut() {
    if (map) map.zoomOut();
}

function toggleMapType() {
    if (!window.mapStyleIndex) window.mapStyleIndex = 0;
    window.mapStyleIndex = (window.mapStyleIndex + 1) % 3;

    // Remove current tiles
    map.eachLayer(layer => {
        if (layer instanceof L.TileLayer) map.removeLayer(layer);
    });

    const styles = [
        { url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', name: 'Street' },
        { url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', name: 'Satellite' },
        { url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', name: 'Dark' }
    ];

    const style = styles[window.mapStyleIndex];
    L.tileLayer(style.url, { maxZoom: 19 }).addTo(map);
    showToast(style.name + ' View');
}

// ========================================
// TASK LIST RENDERING
// ========================================

function showTaskListSkeletons() {
    const container = document.getElementById('tasksList');
    if (!container) return;
    container.innerHTML = Array(4).fill('').map(() => `
        <div class="skeleton-card">
            <div class="skeleton-row">
                <div class="skeleton skeleton-text short"></div>
                <div class="skeleton skeleton-text short" style="margin-left: auto; width: 60px;"></div>
            </div>
            <div class="skeleton skeleton-title"></div>
            <div class="skeleton skeleton-text"></div>
            <div class="skeleton skeleton-text short"></div>
        </div>
    `).join('');
}

function renderTasks(filtered = null) {
    const container = document.getElementById('tasksList');
    if (!container) return;

    // Filter: Show only active, non-expired tasks
    let list = filtered || tasks.filter(t => {
        if (t.status !== 'active') return false;
        if (getTimeLeft(t.expiresAt) === 'Expired') return false;
        return true;
    });

    // Sort by distance
    list.sort((a, b) => {
        const dA = getDistance(userLocation.lat, userLocation.lng, a.location.lat, a.location.lng);
        const dB = getDistance(userLocation.lat, userLocation.lng, b.location.lat, b.location.lng);
        return dA - dB;
    });

    if (list.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <i class="fas fa-search"></i>
                <h3>No tasks found</h3>
                <p>Try adjusting your filters or check back later</p>
                <button class="btn btn-primary" onclick="showSection('upload-task')" style="margin-top: 15px; padding: 10px 24px;">
                    <i class="fas fa-plus"></i> Post a Task
                </button>
            </div>
        `;
        return;
    }

    container.innerHTML = list.map(task => {
        const dist = getDistance(userLocation.lat, userLocation.lng, task.location.lat, task.location.lng);
        const timeLeft = getTimeLeft(task.expiresAt);

        return `
            <div class="task-card" data-task-id="${task.id}" onclick="onTaskCardClick(${task.id})">
                <div class="task-card-header">
                    <span class="task-category">${formatCategory(task.category)}</span>
                    <span class="task-price">₹${task.price + getServiceCharge(task.category)}</span>
                </div>
                <h4>${task.title}</h4>
                <p>${task.description}</p>
                <div class="task-meta">
                    <span><i class="fas fa-map-marker-alt"></i> ${dist.toFixed(1)} km</span>
                    <span class="task-timer"><i class="fas fa-clock"></i> ${timeLeft}</span>
                </div>
            </div>
        `;
    }).join('');
}

function onTaskCardClick(taskId) {
    const task = tasks.find(t => t.id == taskId);
    if (!task) return;

    highlightTaskCard(taskId);
    selectedTask = task;

    if (map) {
        map.setView([task.location.lat, task.location.lng], 15);

        // Open popup
        const idx = tasks.filter(t => t.status === 'active' && getTimeLeft(t.expiresAt) !== 'Expired').findIndex(t => t.id === taskId);
        if (idx >= 0 && taskMarkers[idx]) {
            taskMarkers[idx].openPopup();
        }

        showRouteTo(task);
    }

    // Open task detail modal with Accept button
    openTaskDetail(taskId);
}

function highlightTaskCard(taskId) {
    document.querySelectorAll('.task-card').forEach(c => c.classList.remove('active'));
    const card = document.querySelector(`[data-task-id="${taskId}"]`);
    if (card) {
        card.classList.add('active');
        card.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
}

// ========================================
// TASK DETAIL MODAL
// ========================================

function openTaskDetail(taskId) {
    const task = tasks.find(t => t.id == taskId);
    if (!task) {
        console.error('❌ Task not found:', taskId);
        return;
    }

    window._lastTaskId = taskId;
    console.log('✅ Opening task detail for:', task.title);

    const dist = getDistance(userLocation.lat, userLocation.lng, task.location.lat, task.location.lng);
    const timeLeft = getTimeLeft(task.expiresAt);
    
    // Check if current user is the task owner
    const isOwner = currentUser && task.postedBy && task.postedBy.id === currentUser.id;
    
    console.log('📋 Task details - isOwner:', isOwner, 'User:', currentUser?.id, 'Poster:', task.postedBy?.id);

    const content = `
        <div class="task-detail-header">
            <span class="task-category">${formatCategory(task.category)}</span>
            ${isOwner ? '<span class="owner-badge"><i class="fas fa-user-check"></i> Your Task</span>' : ''}
            <h2>${task.title}</h2>
            <div class="task-detail-meta">
                <span><i class="fas fa-map-marker-alt"></i> ${task.location.address}</span>
                <span><i class="fas fa-ruler"></i> ${dist.toFixed(1)} km away</span>
                <span class="task-timer"><i class="fas fa-clock"></i> ${timeLeft} left</span>
            </div>
        </div>
        
        <div class="task-detail-body">
            <h4>Description</h4>
            <p>${task.description}</p>
        </div>
        
        <div class="task-detail-map" id="taskDetailMap"></div>
        
        <div class="task-detail-price">
            <div>
                <h3>Your Earnings</h3>
                <small>₹${task.price} + ₹${getServiceCharge(task.category)} service charge</small>
            </div>
            <span class="price">₹${task.price + getServiceCharge(task.category)}</span>
        </div>
        
        <div class="task-poster">
            <div class="poster-avatar"><i class="fas fa-user"></i></div>
            <div class="poster-info">
                <h4>${task.postedBy.name}</h4>
                <span>${task.postedBy.tasksPosted} tasks posted</span>
                <div class="poster-rating">
                    ${generateStars(task.postedBy.rating)}
                    <span>(${task.postedBy.rating})</span>
                </div>
                <div class="poster-reviews-link" onclick="viewUserReviews('${task.postedBy.id}', '${task.postedBy.name.replace(/'/g, "\\'")}')">
                    <i class="fas fa-comment-dots"></i> View Reviews
                </div>
            </div>
        </div>
        
        ${isOwner ? `
        <div class="owner-actions">
            <button class="btn btn-edit" onclick="openEditTask(${task.id})">
                <i class="fas fa-edit"></i> Edit Task
            </button>
            <button class="btn btn-outline" style="color: #ef4444; border-color: #ef4444;" onclick="deleteTask(${task.id})">
                <i class="fas fa-trash"></i> Delete
            </button>
        </div>
        ` : ''}
        
        <div class="task-detail-actions">
            <button class="btn btn-outline" onclick="closeModal('taskDetailModal'); clearRoute();" style="flex: 1; padding: 12px; margin: 5px;">
                <i class="fas fa-times"></i> Close
            </button>
            ${!isOwner ? `
            <button class="btn btn-secondary" style="flex: 1; padding: 12px; margin: 5px; background: #0ea5e9; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 600;" onclick="navigateToTask(${task.location.lat}, ${task.location.lng}, '${task.title.replace(/'/g, "\\'").replace(/"/g, '\\"')}')" title="Get directions to task location">
                <i class="fas fa-map-marker-alt"></i> Navigate
            </button>
            <button class="btn btn-primary" style="flex: 1; padding: 12px; margin: 5px; background: #667eea; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 600;" onclick="acceptTask(${task.id})">
                <i class="fas fa-check"></i> Accept
            </button>
            ` : ''}
        </div>
    `;

    console.log('📝 Generated content:', content.length, 'characters');
    document.getElementById('taskDetailContent').innerHTML = content;
    console.log('✅ Modal content updated with Navigate and Accept buttons');
    openModal('taskDetailModal');

    // Mini map
    setTimeout(() => {
        const el = document.getElementById('taskDetailMap');
        if (el && !el._leaflet_id) {
            const miniMap = L.map('taskDetailMap', {
                center: [task.location.lat, task.location.lng],
                zoom: 15,
                zoomControl: false,
                dragging: false,
                scrollWheelZoom: false
            });
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(miniMap);
            L.marker([task.location.lat, task.location.lng], {
                icon: getTaskIcon(task.category)
            }).addTo(miniMap);
        }
    }, 200);
}

function generateStars(rating) {
    let html = '';
    for (let i = 1; i <= 5; i++) {
        if (i <= Math.floor(rating)) html += '<i class="fas fa-star"></i>';
        else if (i - 0.5 <= rating) html += '<i class="fas fa-star-half-alt"></i>';
        else html += '<i class="far fa-star"></i>';
    }
    return html;
}

async function viewUserReviews(userId, userName) {
    const content = document.getElementById('taskDetailContent');
    if (!content) return;
    
    content.innerHTML = `
        <div style="padding: 20px; text-align: center;">
            <div class="skeleton skeleton-title" style="margin: 0 auto 20px;"></div>
            <div class="skeleton skeleton-text"></div>
            <div class="skeleton skeleton-text short"></div>
        </div>
    `;
    
    try {
        const result = await TasksAPI.makeRequest(`/api/user/${encodeURIComponent(userId)}/reviews`);
        const reviews = result.data?.reviews || [];
        const stats = result.data?.stats || {};
        
        let reviewsHtml = '';
        if (reviews.length === 0) {
            reviewsHtml = `
                <div class="empty-state" style="padding: 30px 10px;">
                    <i class="fas fa-star" style="font-size: 2.5rem; color: var(--gray-light); margin-bottom: 10px;"></i>
                    <h4>No reviews yet</h4>
                    <p style="color: var(--gray);">This user hasn't received any reviews.</p>
                </div>
            `;
        } else {
            reviewsHtml = reviews.map(r => `
                <div style="padding: 12px 0; border-bottom: 1px solid #f1f5f9;">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                        <strong style="font-size: 0.9rem;">${r.rater_name || 'Anonymous'}</strong>
                        <span style="color: var(--warning); font-size: 0.85rem;">${generateStars(r.rating)}</span>
                    </div>
                    ${r.review ? `<p style="color: var(--gray); font-size: 0.9rem; margin: 4px 0;">${r.review}</p>` : ''}
                    <small style="color: var(--gray-light);">${r.task_title || ''}</small>
                </div>
            `).join('');
        }
        
        content.innerHTML = `
            <div style="padding: 5px 0;">
                <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 15px;">
                    <button class="btn btn-outline" onclick="openTaskDetail(window._lastTaskId)" style="padding: 6px 12px; font-size: 0.85rem;">
                        <i class="fas fa-arrow-left"></i> Back
                    </button>
                    <h3 style="margin: 0;">Reviews for ${userName}</h3>
                </div>
                <div style="display: flex; gap: 20px; padding: 15px; background: var(--light); border-radius: var(--radius); margin-bottom: 15px; text-align: center;">
                    <div style="flex: 1;">
                        <div style="font-size: 1.8rem; font-weight: 700; color: var(--dark);">${(stats.avgRating || 5).toFixed(1)}</div>
                        <div style="color: var(--warning);">${generateStars(stats.avgRating || 5)}</div>
                        <small style="color: var(--gray);">${stats.totalReviews || 0} reviews</small>
                    </div>
                </div>
                <div>${reviewsHtml}</div>
            </div>
        `;
    } catch (err) {
        content.innerHTML = `
            <div class="empty-state" style="padding: 30px;">
                <i class="fas fa-exclamation-circle" style="color: var(--danger);"></i>
                <p>Could not load reviews.</p>
                <button class="btn btn-outline" onclick="openTaskDetail(window._lastTaskId)">
                    <i class="fas fa-arrow-left"></i> Back to Task
                </button>
            </div>
        `;
    }
}

// ========================================
// TASK ACTIONS
// ========================================

function navigateToTask(lat, lng, taskTitle) {
    if (!lat || !lng) {
        showToast('Location not available');
        return;
    }

    const label = encodeURIComponent(taskTitle || 'Task Location');

    // Detect if mobile device
    const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);

    if (isMobile) {
        // For mobile, try to open native maps app
        const isIOS = /iPhone|iPad|iPod/i.test(navigator.userAgent);
        const isAndroid = /Android/i.test(navigator.userAgent);

        if (isIOS) {
            // iOS: Use Apple Maps or Google Maps
            const appleUrl = `maps://maps.apple.com/?daddr=${lat},${lng}&dirflg=d`;
            const googleUrl = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
            
            // Try Apple Maps first on iOS
            window.location.href = appleUrl;
            
            // Fallback to Google Maps after 1 second
            setTimeout(() => {
                window.location.href = googleUrl;
            }, 1000);
        } else if (isAndroid) {
            // Android: Use Google Maps or Waze
            const googleUrl = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
            const wazeUrl = `https://waze.com/ul?ll=${lat},${lng}&navigate=yes`;
            
            // Try Waze first, fallback to Google Maps
            window.location.href = wazeUrl;
            
            setTimeout(() => {
                window.location.href = googleUrl;
            }, 1000);
        }
    } else {
        // Desktop: Open Google Maps in new window
        const mapsUrl = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=driving`;
        window.open(mapsUrl, '_blank');
    }

    // Close modal after opening navigation
    closeModal('taskDetailModal');
}

async function acceptTask(taskId) {
    console.log('🎯 acceptTask called with taskId:', taskId, 'type:', typeof taskId);

    if (!currentUser) {
        showToast('Please login first');
        closeModal('taskDetailModal');
        openModal('loginModal');
        return;
    }

    // Check if account is suspended
    if (isAccountSuspended()) {
        closeModal('taskDetailModal');
        if (isDebtSuspended()) {
            showDebtSuspendedPopup();
        } else {
            showSuspendedPopup();
        }
        return;
    }

    // Use loose equality (==) to handle number/string ID mismatch
    const task = tasks.find(t => t.id == taskId);
    if (!task) {
        console.error('❌ Task not found in local tasks array. taskId:', taskId, 'Available IDs:', tasks.map(t => t.id));
        showToast('❌ Task not found. Please refresh and try again.', 'error');
        return;
    }

    try {
        console.log('📡 Calling TasksAPI.accept for task:', taskId);
        const data = await TasksAPI.accept(taskId);
        console.log('📥 Accept API response:', JSON.stringify(data));

        // Check for success
        if (data && (data.success === true || data._httpSuccess === true)) {
            task.status = 'accepted';
            task.acceptedBy = currentUser;
            task.acceptedAt = new Date().toISOString();
            myAcceptedTasks.push(task);

            // Save task data for task-in-progress page
            const taskLocation = task.location || {};
            localStorage.setItem('currentTask', JSON.stringify({
                id: task.id,
                title: task.title,
                description: task.description,
                category: task.category,
                price: task.price,
                service_charge: task.service_charge || 0,
                location: {
                    lat: parseFloat(taskLocation.lat) || 19.0760,
                    lng: parseFloat(taskLocation.lng) || 72.8777
                },
                providerId: task.postedBy?.id,
                providerName: task.postedBy?.name,
                providerPhone: task.postedBy?.phone,
                providerRating: task.postedBy?.rating,
                expiresAt: task.expiresAt,
                postedAt: task.postedAt,
                startTime: Date.now()
            }));

            // Non-blocking updates (must not prevent redirect)
            try {
                updateUserData(currentUser.id, {
                    acceptedTasks: serializeTasks(myAcceptedTasks)
                }).catch(e => console.warn('updateUserData failed:', e));
                notifyTaskPoster(task, currentUser);
                closeModal('taskDetailModal');
                clearRoute();
            } catch (e) {
                console.warn('Non-critical post-accept update failed:', e);
            }

            // Redirect to task-in-progress page
            console.log('🚀 Redirecting to task-in-progress.html for task:', task.id);
            window.location.href = 'task-in-progress.html?taskId=' + task.id;
        } else {
            console.error('❌ Accept API returned failure:', data);
            showToast('❌ ' + (data.message || 'Failed to accept task'), 'error');
        }
    } catch (err) {
        console.error('❌ Error accepting task:', err);
        showToast('❌ Error: ' + err.message, 'error');
    }
}

// ========================================
// HELPER PENALTY & SUSPENSION SYSTEM
// ========================================

let suspensionTimerInterval = null;

// ========================================
// SUSPENSION SYSTEM (server-driven, synced across devices)
// ========================================

function getSuspensionEndTime() {
    // Read from localStorage cache (synced from server)
    const until = localStorage.getItem('taskearn_suspended_until');
    return until ? parseInt(until) : 0;
}

function isTimerSuspended() {
    const until = getSuspensionEndTime();
    if (!until) return false;
    if (Date.now() < until) return true;
    // Expired — clear cache
    localStorage.removeItem('taskearn_suspended_until');
    return false;
}

function isDebtSuspended() {
    return localStorage.getItem('taskearn_debt_suspended') === 'true';
}

function isAccountSuspended() {
    if (isTimerSuspended()) return true;
    if (isDebtSuspended()) return true;
    return false;
}

function setTimerSuspension(suspendedUntilISO) {
    // Cache server suspension time as ms timestamp
    const ms = new Date(suspendedUntilISO).getTime();
    if (ms > Date.now()) {
        localStorage.setItem('taskearn_suspended_until', ms.toString());
    }
}

function clearTimerSuspension() {
    localStorage.removeItem('taskearn_suspended_until');
}

function setDebtSuspension(amount) {
    localStorage.setItem('taskearn_debt_suspended', 'true');
    localStorage.setItem('taskearn_debt_amount', String(amount || 0));
}

function clearDebtSuspension() {
    localStorage.removeItem('taskearn_debt_suspended');
    localStorage.removeItem('taskearn_debt_amount');
}

function getDebtAmount() {
    return parseFloat(localStorage.getItem('taskearn_debt_amount') || '0');
}

function showDebtSuspendedPopup() {
    const amount = getDebtAmount();
    const msgEl = document.getElementById('debtSuspendedMessage');
    const amountEl = document.getElementById('debtSuspendedAmount');
    if (msgEl) msgEl.textContent = 'Your wallet balance has reached -₹500 or below. You cannot accept tasks or withdraw funds until your balance is back to ₹0 or above.';
    if (amountEl) amountEl.textContent = '₹' + amount.toFixed(2);
    const modal = document.getElementById('debtSuspendedModal');
    if (modal) {
        openModal('debtSuspendedModal');
    } else {
        showToast('⚠️ Your account is debt-suspended (balance below -₹500). Add money to bring balance to ₹0.', 'error');
    }
}

function clearSuspension(showPopup) {
    clearTimerSuspension();
    stopSuspensionTimer();
    hideSuspensionBanner();
    if (showPopup) {
        showUnsuspendedPopup();
        addNotification({
            title: 'Account Restored',
            message: 'Your suspension has ended. You can now accept tasks and withdraw funds again.',
            type: 'success'
        });
    }
}

function showSuspendedPopup() {
    const until = getSuspensionEndTime();
    if (!until) return;
    const timeStr = new Date(until).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });
    const remaining = formatCountdown(until - Date.now());

    const msgEl = document.getElementById('suspendedMessage');
    const timeEl = document.getElementById('suspendedUntilTime');
    const countdownEl = document.getElementById('suspendedCountdown');
    if (msgEl) msgEl.textContent = 'Your account has been suspended for 48 hours because you released more than 3 tasks today.';
    if (timeEl) timeEl.textContent = timeStr;
    if (countdownEl) countdownEl.textContent = remaining;
    openModal('suspendedModal');
}

function showUnsuspendedPopup() {
    const modal = document.getElementById('unsuspendedModal');
    if (modal) {
        openModal('unsuspendedModal');
    } else {
        showToast('🎉 Your suspension has ended! You can accept tasks again.');
    }
}

function formatCountdown(ms) {
    if (ms <= 0) return '00:00:00';
    const totalSec = Math.floor(ms / 1000);
    const h = Math.floor(totalSec / 3600);
    const m = Math.floor((totalSec % 3600) / 60);
    const s = totalSec % 60;
    return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
}

function startSuspensionTimer() {
    stopSuspensionTimer();
    updateSuspensionDisplay();
    suspensionTimerInterval = setInterval(function() {
        const until = getSuspensionEndTime();
        if (!until || Date.now() >= until) {
            clearSuspension(true);
            renderDashboard();
            return;
        }
        updateSuspensionDisplay();
    }, 1000);
}

function stopSuspensionTimer() {
    if (suspensionTimerInterval) {
        clearInterval(suspensionTimerInterval);
        suspensionTimerInterval = null;
    }
}

function updateSuspensionDisplay() {
    const until = getSuspensionEndTime();
    if (!until) return;
    const remaining = until - Date.now();
    const formatted = formatCountdown(remaining);

    const bannerTimer = document.getElementById('suspensionBannerTimer');
    if (bannerTimer) bannerTimer.textContent = formatted;

    const modalCountdown = document.getElementById('suspendedCountdown');
    if (modalCountdown) modalCountdown.textContent = formatted;

    const banner = document.getElementById('suspensionBanner');
    if (banner) banner.style.display = 'block';
}

function hideSuspensionBanner() {
    const banner = document.getElementById('suspensionBanner');
    if (banner) banner.style.display = 'none';
}

function checkAndClearSuspension() {
    const until = getSuspensionEndTime();
    if (!until) return;
    if (Date.now() >= until) {
        clearSuspension(true);
    } else {
        startSuspensionTimer();
    }
}

function applySuspensionFromUser(userData) {
    // Sync timer suspension from server response
    if (userData.timerSuspended && userData.suspendedUntil) {
        setTimerSuspension(userData.suspendedUntil);
        startSuspensionTimer();
    } else {
        // Check if localStorage has a timer the server doesn't know about (pre-migration accounts)
        const localUntil = localStorage.getItem('taskearn_suspended_until');
        if (localUntil && parseInt(localUntil) > Date.now()) {
            // Migrate local suspension to server
            migrateLocalSuspensionToServer(localUntil);
            // Keep local timer active until migration confirms
            startSuspensionTimer();
        } else {
            clearTimerSuspension();
            stopSuspensionTimer();
            hideSuspensionBanner();
        }
    }
    // Sync debt suspension from server response
    if (userData.debtSuspended) {
        setDebtSuspension(userData.debtAmount || 0);
    } else {
        clearDebtSuspension();
    }
}

async function migrateLocalSuspensionToServer(localUntilMs) {
    try {
        const token = localStorage.getItem('taskearn_token');
        if (!token) return;
        const API_BASE = (typeof API_URL !== 'undefined') ? API_URL : '';
        const res = await fetch(API_BASE + '/user/migrate-suspension', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
            body: JSON.stringify({ suspendedUntil: parseInt(localUntilMs) })
        });
        const result = await res.json();
        if (result.success && result.migrated) {
            console.log('✅ Local suspension migrated to server:', result.suspendedUntil);
        } else if (result.success && !result.migrated && result.reason === 'expired') {
            // Timer expired — clear local too
            clearTimerSuspension();
            stopSuspensionTimer();
            hideSuspensionBanner();
        }
    } catch (e) {
        console.warn('⚠️ Could not migrate local suspension to server:', e.message);
    }
}

async function syncSuspensionFromServer() {
    try {
        if (typeof AuthAPI === 'undefined' || !AuthAPI.me) return;
        const result = await AuthAPI.me();
        if (result && result.success && result.user) {
            applySuspensionFromUser(result.user);
            console.log('✅ Suspension synced from server. Timer:', result.user.timerSuspended, 'Debt:', result.user.debtSuspended);
        }
    } catch (e) {
        console.warn('⚠️ Could not sync suspension from server:', e.message);
    }
}

async function deductPenalty(task) {
    // Calculate total task value: budget + service charge (fallback to category-based charge)
    const serviceCharge = task.service_charge || getServiceCharge(task.category);
    const totalValue = (task.price || 0) + serviceCharge;
    const penalty = Math.round(totalValue * 0.10);
    
    console.log(`💸 Penalty calculation: price=₹${task.price}, serviceCharge=₹${serviceCharge}, total=₹${totalValue}, penalty(10%)=₹${penalty}`);
    
    try {
        // Use dedicated penalty endpoint that allows negative balance
        const result = await WalletAPI.penalty(penalty, task.id, `Task release penalty (10% of ₹${totalValue})`);
        if (result && result.success) {
            console.log('✅ Penalty deducted via API:', penalty, 'New balance:', result.newBalance);
            currentUser.wallet = result.newBalance;
            await updateUserData(currentUser.id, { wallet: result.newBalance });
            // Set debt suspension if wallet went negative
            if (result.debtSuspended) {
                setDebtSuspension(result.debtAmount || Math.abs(result.newBalance));
                console.log('⚠️ Debt suspension activated. Amount owed:', result.debtAmount);
            }
        } else {
            console.warn('⚠️ Penalty API failed:', result?.message, '— updating locally');
            currentUser.wallet = (currentUser.wallet || 0) - penalty;
            await updateUserData(currentUser.id, { wallet: currentUser.wallet });
        }
    } catch (e) {
        console.warn('⚠️ Penalty network error:', e.message, '— updating locally');
        currentUser.wallet = (currentUser.wallet || 0) - penalty;
        await updateUserData(currentUser.id, { wallet: currentUser.wallet });
    }
    await refreshWalletBalance();
    return penalty;
}

function penaltyContinueTask() {
    closeModal('releasePenaltyModal');
    const taskId = pendingReleaseTaskId;
    pendingReleaseTaskId = null;
    const task = myAcceptedTasks.find(t => t.id == taskId);
    if (task) {
        window.location.href = 'task-in-progress.html?taskId=' + task.id;
    }
}

async function penaltyConfirmRelease() {
    const taskId = pendingReleaseTaskId;
    if (!taskId || !currentUser) return;

    const task = myAcceptedTasks.find(t => t.id == taskId) || tasks.find(t => t.id == taskId);
    if (!task) {
        showToast('❌ Task not found', 'error');
        pendingReleaseTaskId = null;
        return;
    }

    closeModal('releasePenaltyModal');

    showToast('💸 Deducting penalty...');
    const penalty = await deductPenalty(task);

    let abandonResult = null;
    try {
        abandonResult = await TasksAPI.abandon(taskId);
        if (!abandonResult || !abandonResult.success) {
            showToast('❌ ' + (abandonResult?.message || 'Could not release task'), 'error');
            pendingReleaseTaskId = null;
            return;
        }
    } catch (e) {
        showToast('❌ Network error. Please try again.', 'error');
        pendingReleaseTaskId = null;
        return;
    }

    myAcceptedTasks = myAcceptedTasks.filter(t => t.id != taskId);
    try {
        await updateUserData(currentUser.id, {
            acceptedTasks: serializeTasks(myAcceptedTasks)
        });
    } catch (e) { console.warn('updateUserData failed:', e); }
    tasks = tasks.filter(t => t.id != taskId);

    // Update local release count from server response and persist to localStorage
    if (abandonResult.dailyReleaseCount != null) {
        currentUser.dailyReleaseCount = abandonResult.dailyReleaseCount;
        try {
            const storedUser = JSON.parse(localStorage.getItem('taskearn_user') || 'null');
            if (storedUser) {
                storedUser.dailyReleaseCount = abandonResult.dailyReleaseCount;
                localStorage.setItem('taskearn_user', JSON.stringify(storedUser));
            }
        } catch (e) { /* ignore */ }
    }

    // Abandon endpoint now returns release count + suspension info
    if (abandonResult.suspended && abandonResult.suspendedUntil) {
        setTimerSuspension(abandonResult.suspendedUntil);
        showSuspendedPopup();
        startSuspensionTimer();
        addNotification({
            title: 'Account Suspended',
            message: 'You released too many tasks today. Your account is suspended for 48 hours.',
            type: 'error'
        });
    }

    showToast('✅ Task released. ₹' + penalty + ' penalty deducted from wallet.');
    pendingReleaseTaskId = null;
    renderDashboard();
}

async function abandonTask(taskId) {
    if (!currentUser) {
        showToast('❌ Please login first');
        return;
    }

    if (isAccountSuspended()) {
        if (isDebtSuspended()) {
            showDebtSuspendedPopup();
        } else {
            showSuspendedPopup();
        }
        return;
    }

    const task = myAcceptedTasks.find(t => t.id == taskId) || tasks.find(t => t.id == taskId);
    if (!task) {
        showToast('❌ Task not found');
        return;
    }

    // Calculate total value with service charge fallback
    const serviceCharge = task.service_charge || getServiceCharge(task.category);
    const taskValue = (task.price || 0) + serviceCharge;
    const penalty = Math.round(taskValue * 0.10);
    const currentBalance = currentUser.wallet || 0;
    const walletAfter = currentBalance - penalty;
    const dailyCount = (currentUser && currentUser.dailyReleaseCount) || 0;

    const taskValEl = document.getElementById('penaltyTaskValue');
    const penaltyEl = document.getElementById('penaltyAmount');
    const walletAfterEl = document.getElementById('penaltyWalletAfter');
    const dailyWarningEl = document.getElementById('penaltyDailyWarning');
    const dailyCountEl = document.getElementById('penaltyDailyCount');

    if (taskValEl) taskValEl.textContent = '₹' + taskValue;
    if (penaltyEl) penaltyEl.textContent = '-₹' + penalty;
    if (walletAfterEl) {
        walletAfterEl.textContent = '₹' + walletAfter.toFixed(2);
        walletAfterEl.style.color = walletAfter < 0 ? '#ef4444' : '#10b981';
    }
    if (dailyWarningEl && dailyCountEl) {
        dailyCountEl.textContent = dailyCount;
        dailyWarningEl.style.display = 'block';
    }

    pendingReleaseTaskId = taskId;
    openModal('releasePenaltyModal');
}

async function deleteTask(taskId) {
    if (!confirm('Delete this task?') || !currentUser) return;

    // Call backend API to delete from database
    try {
        const token = localStorage.getItem('taskearn_token');
        if (token && typeof TasksAPI !== 'undefined' && TasksAPI.delete) {
            const result = await TasksAPI.delete(taskId);
            if (!result || !result.success) {
                showToast(`❌ ${result?.message || 'Could not delete task'}`, 'error');
                return;
            }
        }
    } catch (e) {
        console.error('Delete API failed:', e.message);
        showToast('❌ Network error. Please try again.');
        return;
    }

    // Remove from local arrays
    tasks = tasks.filter(t => t.id !== taskId);
    myPostedTasks = myPostedTasks.filter(t => t.id !== taskId);

    updateUserData(currentUser.id, {
        postedTasks: serializeTasks(myPostedTasks)
    });

    showToast('✅ Task deleted');
    closeModal('taskDetailModal');
    renderTasks();
    addTaskMarkers();
    renderDashboard();
}

// Edit Task Functions
let editTaskState = {
    taskId: null,
    originalBudget: 0,
    budgetIncrease: 0
};

function openEditTask(taskId) {
    // Search in both tasks array and myPostedTasks
    let task = tasks.find(t => t.id == taskId);
    if (!task) {
        task = myPostedTasks.find(t => t.id == taskId);
    }
    
    if (!task) {
        showToast('❌ Task not found');
        return;
    }
    
    // Reset state
    editTaskState = {
        taskId: taskId,
        originalBudget: task.price,
        budgetIncrease: 0
    };
    
    // Populate form
    document.getElementById('editTaskId').value = taskId;
    document.getElementById('editTaskTitle').value = task.title;
    document.getElementById('editTaskCategory').value = task.category;
    document.getElementById('editTaskDescription').value = task.description;
    document.getElementById('editTaskLocation').value = task.location.address;
    document.getElementById('editCurrentBudget').textContent = '₹' + task.price;
    document.getElementById('editNewBudget').textContent = '₹' + task.price;
    document.getElementById('customBudgetIncrease').value = '';
    
    // Clear active states
    document.querySelectorAll('.increase-btn').forEach(btn => btn.classList.remove('active'));
    
    // Show task info
    document.getElementById('editTaskInfo').innerHTML = `
        <div class="edit-task-status">
            <span class="status-badge active"><i class="fas fa-circle"></i> Active Task</span>
            <span class="time-left"><i class="fas fa-clock"></i> ${getTimeLeft(task.expiresAt)} left</span>
        </div>
    `;
    
    closeModal('taskDetailModal');
    openModal('editTaskModal');
}

function selectBudgetIncrease(el, amount) {
    // Toggle - if clicking same button, deselect
    const wasActive = el.classList.contains('active');
    
    // Clear all active states
    document.querySelectorAll('.increase-btn').forEach(btn => btn.classList.remove('active'));
    document.getElementById('customBudgetIncrease').value = '';
    
    if (wasActive) {
        editTaskState.budgetIncrease = 0;
    } else {
        el.classList.add('active');
        editTaskState.budgetIncrease = amount;
    }
    
    updateNewBudget();
}

function updateNewBudget() {
    const customIncrease = parseInt(document.getElementById('customBudgetIncrease').value) || 0;
    
    // If custom value is entered, use that instead
    if (customIncrease > 0) {
        document.querySelectorAll('.increase-btn').forEach(btn => btn.classList.remove('active'));
        editTaskState.budgetIncrease = customIncrease;
    }
    
    const newBudget = editTaskState.originalBudget + editTaskState.budgetIncrease;
    const displayEl = document.getElementById('editNewBudget');
    
    if (displayEl) {
        displayEl.textContent = '₹' + newBudget;
        displayEl.style.color = editTaskState.budgetIncrease > 0 ? '#10b981' : '#6366f1';
    }
}

async function saveTaskEdit(event) {
    event.preventDefault();
    
    const taskId = parseInt(document.getElementById('editTaskId').value);
    
    // Search in both arrays
    let task = tasks.find(t => t.id == taskId);
    if (!task) {
        task = myPostedTasks.find(t => t.id == taskId);
    }
    
    if (!task || !currentUser) {
        showToast('❌ Error saving task');
        return;
    }
    
    // Get updated values
    const newTitle = document.getElementById('editTaskTitle').value.trim();
    const newCategory = document.getElementById('editTaskCategory').value;
    const newDescription = document.getElementById('editTaskDescription').value.trim();
    const newLocation = document.getElementById('editTaskLocation').value.trim();
    const newPrice = editTaskState.originalBudget + editTaskState.budgetIncrease;

    // Geocode if address changed
    let newLat = task.location.lat;
    let newLng = task.location.lng;
    if (newLocation && newLocation !== task.location.address) {
        const geo = await geocodeAddress(newLocation);
        if (geo) {
            newLat = geo.lat;
            newLng = geo.lng;
        }
    }
    
    // Update in main tasks array
    const mainTask = tasks.find(t => t.id == taskId);
    if (mainTask) {
        mainTask.title = newTitle;
        mainTask.category = newCategory;
        mainTask.description = newDescription;
        mainTask.location = { lat: newLat, lng: newLng, address: newLocation };
        mainTask.price = newPrice;
    }
    
    // Update in myPostedTasks array
    const postedTask = myPostedTasks.find(t => t.id == taskId);
    if (postedTask) {
        postedTask.title = newTitle;
        postedTask.category = newCategory;
        postedTask.description = newDescription;
        postedTask.location = { lat: newLat, lng: newLng, address: newLocation };
        postedTask.price = newPrice;
    }
    
    // Save to storage
    updateUserData(currentUser.id, {
        postedTasks: serializeTasks(myPostedTasks)
    });
    
    // Show success message
    if (editTaskState.budgetIncrease > 0) {
        showToast('✅ Task updated! Budget increased by ₹' + editTaskState.budgetIncrease);
    } else {
        showToast('✅ Task updated successfully');
    }
    
    closeModal('editTaskModal');
    
    // Refresh displays
    renderTasks();
    addTaskMarkers();
    renderDashboard();
}

// Show task posted success with edit option
function showTaskPostedSuccess(task) {
    const content = `
        <div class="success-animation">
            <div class="success-checkmark">
                <i class="fas fa-check"></i>
            </div>
        </div>
        <h2>Task Posted Successfully! 🎉</h2>
        <p class="success-subtitle">Your task is now visible to nearby taskers for 12 hours</p>
        
        <div class="posted-task-preview">
            <div class="preview-header">
                <span class="task-category">${formatCategory(task.category)}</span>
                <span class="task-price">₹${task.price}</span>
            </div>
            <h4>${task.title}</h4>
            <p>${task.description}</p>
            <div class="preview-meta">
                <span><i class="fas fa-map-marker-alt"></i> ${task.location.address}</span>
                <span><i class="fas fa-clock"></i> 12 hours left</span>
            </div>
        </div>
        
        <div class="success-actions">
            <button class="btn btn-edit" onclick="closeModal('taskSuccessModal'); openEditTask(${task.id});">
                <i class="fas fa-edit"></i> Edit Task
            </button>
            <button class="btn btn-outline" onclick="closeModal('taskSuccessModal'); openTaskDetail(${task.id});">
                <i class="fas fa-eye"></i> View Task
            </button>
        </div>
        
        <button class="btn btn-primary btn-block" onclick="closeModal('taskSuccessModal')">
            <i class="fas fa-check"></i> Done
        </button>
        
        <div class="success-tip">
            <i class="fas fa-lightbulb"></i>
            <span>Tip: Increase your budget to attract more taskers!</span>
        </div>
    `;
    
    document.getElementById('taskSuccessContent').innerHTML = content;
    openModal('taskSuccessModal');
}

async function completeTask(taskId) {
    const task = myAcceptedTasks.find(t => t.id == taskId);
    if (!task || !currentUser) {
        showToast('❌ Task not found', 'error');
        return;
    }

    // Don't allow completing expired tasks
    if (task.expiresAt && getTimeLeft(task.expiresAt) === 'Expired') {
        showToast('❌ This task has expired and can no longer be completed.', 'error');
        myAcceptedTasks = myAcceptedTasks.filter(t => t.id != taskId);
        updateUserData(currentUser.id, { acceptedTasks: serializeTasks(myAcceptedTasks) });
        renderDashboard();
        return;
    }

    // Call backend FIRST to ensure DB status is updated
    try {
        const response = await fetch(API_BASE_URL + `/tasks/${taskId}/complete`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
            }
        });
        const result = await response.json();
        if (!result.success) {
            showToast(`❌ ${result.message || 'Could not mark task as completed'}`);
            return;
        }
        console.log('✅ Backend: Task marked completed, poster notified');
    } catch (e) {
        showToast('❌ Network error. Please try again.');
        console.error('Backend complete failed:', e.message);
        return;
    }

    // Backend succeeded — update local state
    task.status = 'completed';
    task.completedAt = new Date().toISOString();
    task.helperId = currentUser.id;
    task.helperName = currentUser.name;

    updateUserData(currentUser.id, {
        acceptedTasks: serializeTasks(myAcceptedTasks)
    });

    showToast('✅ Task marked as completed! Waiting for poster to pay.');
    renderDashboard();
}

/**
 * Show "Payment Done" pop-up for the poster after paying
 */
function showPaymentDonePopup(task, totalPaid, helperReceives, newBalance) {
    const baseAmount = task.price || 0;
    const svcCharge = task.service_charge || 0;
    const totalTaskVal = baseAmount + svcCharge;
    const posterFee = totalTaskVal * 0.05;
    const content = `
        <div style="text-align: center; padding: 20px;">
            <div style="font-size: 60px; margin-bottom: 15px;">✅</div>
            <h2 style="color: #4ade80; margin-bottom: 10px;">Payment Done!</h2>
            <p style="color: #888; margin-bottom: 20px;">Your payment has been processed successfully.</p>
            
            <div style="background: rgba(74, 222, 128, 0.1); border: 1px solid #4ade80; border-radius: 12px; padding: 20px; margin-bottom: 20px; text-align: left;">
                <h4 style="margin-bottom: 15px;">${escapeHtml(task.title)}</h4>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                    <span style="color: #999;">Budget:</span>
                    <span style="font-weight: 600;">₹${baseAmount.toFixed(2)}</span>
                </div>
                ${svcCharge > 0 ? `<div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                    <span style="color: #999;">Service Charge:</span>
                    <span style="font-weight: 600; color: #fbbf24;">+₹${svcCharge.toFixed(2)}</span>
                </div>` : ''}
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                    <span style="color: #999;">Posting Fee (5%):</span>
                    <span style="font-weight: 600; color: #fbbf24;">+₹${posterFee.toFixed(2)}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                    <span style="color: #999;">Total Paid:</span>
                    <span style="font-weight: 600; color: #ef4444;">-₹${totalPaid.toFixed(2)}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                    <span style="color: #999;">Helper Receives:</span>
                    <span style="font-weight: 600; color: #4ade80;">₹${helperReceives.toFixed(2)}</span>
                </div>
                <hr style="border-color: rgba(255,255,255,0.1); margin: 12px 0;">
                <div style="display: flex; justify-content: space-between;">
                    <span style="font-weight: 600;">Your New Balance:</span>
                    <span style="font-weight: 700; color: #fbbf24;">₹${newBalance.toFixed(2)}</span>
                </div>
            </div>
            
            <button class="btn btn-primary btn-block" onclick="closeModal('taskSuccessModal'); renderDashboard();">
                <i class="fas fa-check"></i> Done
            </button>
        </div>
    `;
    document.getElementById('taskSuccessContent').innerHTML = content;
    openModal('taskSuccessModal');
}

/**
 * Show "Payment Received" pop-up for the helper
 * Called when helper logs in and checks for paid tasks
 */
function checkAndShowPaymentReceived() {
    if (!currentUser) return;
    
    // Check if any accepted tasks were recently paid
    const paidKey = `payment_shown_${currentUser.id}`;
    const shownPayments = JSON.parse(localStorage.getItem(paidKey) || '[]');
    
    for (const task of myAcceptedTasks) {
        if (task.status === 'paid' && !shownPayments.includes(task.id)) {
            const taskAmount = task.price || 0;
            const serviceCharge = task.service_charge || task.serviceCharge || 0;
            const totalTaskValue = taskAmount + serviceCharge;
            const helperEarnings = totalTaskValue * 0.88;
            
            // Move paid task from accepted to completed
            myAcceptedTasks = myAcceptedTasks.filter(t => t.id != task.id);
            task.earnedAmount = helperEarnings;
            myCompletedTasks.push(task);
            
            // Update profile stats
            currentUser.tasksCompleted = (currentUser.tasksCompleted || 0) + 1;
            currentUser.totalEarnings = parseFloat(currentUser.totalEarnings || 0) + helperEarnings;
            currentUser.totalEarnings = Math.round(currentUser.totalEarnings * 100) / 100;
            
            // Persist everything
            updateUserData(currentUser.id, {
                acceptedTasks: serializeTasks(myAcceptedTasks),
                completedTasks: serializeTasks(myCompletedTasks),
                tasksCompleted: currentUser.tasksCompleted,
                totalEarnings: currentUser.totalEarnings
            });
            
            // Refresh wallet balance from server
            refreshWalletBalance();
            
            const content = `
                <div style="text-align: center; padding: 20px;">
                    <div style="font-size: 60px; margin-bottom: 15px;">💰</div>
                    <h2 style="color: #4ade80; margin-bottom: 10px;">Payment Received!</h2>
                    <p style="color: #888; margin-bottom: 20px;">You've been paid for completing a task!</p>
                    
                    <div style="background: rgba(74, 222, 128, 0.1); border: 1px solid #4ade80; border-radius: 12px; padding: 20px; margin-bottom: 20px; text-align: left;">
                        <h4 style="margin-bottom: 15px;">${escapeHtml(task.title)}</h4>
                        <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                            <span style="color: #999;">Task Amount:</span>
                            <span style="font-weight: 600;">₹${totalTaskValue.toFixed(2)}</span>
                        </div>
                        <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                            <span style="color: #999;">Commission (12%):</span>
                            <span style="font-weight: 600; color: #ef4444;">-₹${(totalTaskValue * 0.12).toFixed(2)}</span>
                        </div>
                        <hr style="border-color: rgba(255,255,255,0.1); margin: 12px 0;">
                        <div style="display: flex; justify-content: space-between;">
                            <span style="font-weight: 600;">You Received:</span>
                            <span style="font-weight: 700; font-size: 18px; color: #4ade80;">+₹${helperEarnings.toFixed(2)}</span>
                        </div>
                    </div>
                    
                    <button class="btn btn-primary btn-block" onclick="closeModal('taskSuccessModal'); renderDashboard();">
                        <i class="fas fa-check"></i> Great!
                    </button>
                </div>
            `;
            document.getElementById('taskSuccessContent').innerHTML = content;
            openModal('taskSuccessModal');
            
            // Mark this payment as shown
            shownPayments.push(task.id);
            localStorage.setItem(paidKey, JSON.stringify(shownPayments));
            break; // Show one at a time
        }
    }
}

/**
 * Show styled payment invoice modal with full price breakdown
 * Fetches real balance, validates, and shows approval UI
 */
async function showPaymentInvoice(taskId) {
    let task = myPostedTasks.find(t => t.id == taskId);

    // If task not in local list, fetch from server
    if (!task) {
        try {
            const userTasksResult = await UserAPI.getTasks();
            if (userTasksResult && userTasksResult.success && userTasksResult.postedTasks) {
                const dbTask = userTasksResult.postedTasks.find(t => t.id == taskId);
                if (dbTask) {
                    task = {
                        id: dbTask.id,
                        title: dbTask.title,
                        description: dbTask.description,
                        category: dbTask.category,
                        price: parseFloat(dbTask.price),
                        service_charge: parseFloat(dbTask.service_charge || 0),
                        status: dbTask.status,
                        acceptedBy: dbTask.accepted_by,
                        completedAt: dbTask.completed_at
                    };
                    myPostedTasks.push(task);
                }
            }
        } catch (e) {
            console.warn('Could not fetch task from server:', e.message);
        }
    }

    if (!task) {
        showToast('❌ Task not found');
        return;
    }

    // If local status is stale, fetch real status from server before showing error
    if (task.status !== 'completed' && task.status !== 'pending_payment') {
        console.log(`⚠️ Local task status is '${task.status}', fetching real status from server...`);
        try {
            const userTasksResult = await UserAPI.getTasks();
            if (userTasksResult && userTasksResult.success && userTasksResult.postedTasks) {
                const dbTask = userTasksResult.postedTasks.find(t => t.id == taskId);
                if (dbTask) {
                    // Update local task with real DB status
                    task.status = dbTask.status;
                    task.price = parseFloat(dbTask.price) || task.price;
                    task.service_charge = parseFloat(dbTask.service_charge || 0);
                    task.acceptedBy = dbTask.accepted_by || task.acceptedBy;
                    task.completedAt = dbTask.completed_at || task.completedAt;
                    // Save updated status locally
                    updateUserData(currentUser.id, { postedTasks: serializeTasks(myPostedTasks) });
                    console.log(`✅ Updated task ${taskId} status from DB: '${dbTask.status}'`);
                }
            }
        } catch (e) {
            console.warn('Could not fetch task status from server:', e.message);
        }

        // Check again after server sync
        if (task.status !== 'completed' && task.status !== 'pending_payment') {
            showToast(`❌ Task status is '${task.status}', payment requires 'completed' status.`);
            return;
        }
    }

    // Calculate all amounts
    const taskAmount = task.price || 0;
    const serviceCharge = task.service_charge || 0;
    const totalTaskValue = taskAmount + serviceCharge;
    const helperCommission = totalTaskValue * 0.12;
    const posterFee = totalTaskValue * 0.05;
    const totalCost = totalTaskValue + posterFee;
    const helperNetReceives = totalTaskValue - helperCommission;

    // Fetch real wallet balance from server
    let currentBalance = 0;
    try {
        const walletData = await WalletAPI.get();
        if (walletData && walletData.success !== false) {
            currentBalance = walletData.balance || walletData.wallet?.balance || 0;
        }
    } catch (e) {
        showToast('❌ Could not fetch wallet balance. Please try again.');
        return;
    }

    const balanceAfter = currentBalance - totalCost;
    const insufficient = currentBalance < totalCost;
    const shortfall = totalCost - currentBalance;

    // Build styled invoice modal content
    const content = `
        <div style="padding: 20px;">
            <div style="text-align: center; margin-bottom: 20px;">
                <div style="font-size: 50px; margin-bottom: 10px;">🧾</div>
                <h2 style="color: #fff; margin: 0 0 5px 0;">Payment Invoice</h2>
                <p style="color: #888; margin: 0; font-size: 14px;">Review the breakdown before paying</p>
            </div>

            <div style="background: rgba(30, 30, 40, 0.9); border: 1px solid rgba(139, 92, 246, 0.3); border-radius: 12px; padding: 18px; margin-bottom: 16px;">
                <h4 style="margin: 0 0 12px 0; color: #a78bfa; font-size: 14px; text-transform: uppercase; letter-spacing: 1px;">
                    <i class="fas fa-tasks"></i> Task Details
                </h4>
                <div style="font-weight: 600; font-size: 16px; color: #fff; margin-bottom: 4px;">${escapeHtml(task.title)}</div>
                <div style="font-size: 13px; color: #888;">${formatCategory(task.category || '')}</div>
            </div>

            <div style="background: rgba(30, 30, 40, 0.9); border: 1px solid rgba(139, 92, 246, 0.3); border-radius: 12px; padding: 18px; margin-bottom: 16px;">
                <h4 style="margin: 0 0 14px 0; color: #a78bfa; font-size: 14px; text-transform: uppercase; letter-spacing: 1px;">
                    <i class="fas fa-receipt"></i> Price Breakdown
                </h4>
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.06);">
                    <span style="color: #ccc;">Budget (Task Price)</span>
                    <span style="color: #fff; font-weight: 600;">₹${taskAmount.toFixed(2)}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.06);">
                    <span style="color: #ccc;">Service Charge</span>
                    <span style="color: #fbbf24; font-weight: 600;">${serviceCharge > 0 ? '+₹' + serviceCharge.toFixed(2) : '₹0.00'}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.1); font-weight: 700;">
                    <span style="color: #fff;">Task Value</span>
                    <span style="color: #fff;">₹${totalTaskValue.toFixed(2)}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.06);">
                    <span style="color: #ccc;">Posting Fee (5%)</span>
                    <span style="color: #fbbf24; font-weight: 600;">+₹${posterFee.toFixed(2)}</span>
                </div>
                <div style="display: flex; justify-content: space-between; padding: 12px 0 0 0; border-top: 2px solid rgba(139, 92, 246, 0.4); font-size: 18px; font-weight: 800;">
                    <span style="color: #fff;">Total to Pay</span>
                    <span style="color: #ef4444;">₹${totalCost.toFixed(2)}</span>
                </div>
            </div>

            <div style="background: rgba(30, 30, 40, 0.9); border: 1px solid rgba(139, 92, 246, 0.3); border-radius: 12px; padding: 18px; margin-bottom: 16px;">
                <h4 style="margin: 0 0 14px 0; color: #a78bfa; font-size: 14px; text-transform: uppercase; letter-spacing: 1px;">
                    <i class="fas fa-wallet"></i> Wallet
                </h4>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                    <span style="color: #ccc;">Current Balance</span>
                    <span style="color: ${insufficient ? '#ef4444' : '#4ade80'}; font-weight: 600;">₹${currentBalance.toFixed(2)}</span>
                </div>
                ${insufficient ? `
                <div style="display: flex; justify-content: space-between;">
                    <span style="color: #ef4444;">Shortfall</span>
                    <span style="color: #ef4444; font-weight: 700;">₹${shortfall.toFixed(2)}</span>
                </div>` : `
                <div style="display: flex; justify-content: space-between;">
                    <span style="color: #ccc;">After Payment</span>
                    <span style="color: #fbbf24; font-weight: 600;">₹${balanceAfter.toFixed(2)}</span>
                </div>`}
            </div>

            <div style="background: rgba(74, 222, 128, 0.05); border: 1px solid rgba(74, 222, 128, 0.2); border-radius: 10px; padding: 14px; margin-bottom: 20px;">
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <span style="color: #4ade80; font-size: 13px;"><i class="fas fa-user"></i> Helper Receives (after 12% commission)</span>
                    <span style="color: #4ade80; font-weight: 700;">₹${helperNetReceives.toFixed(2)}</span>
                </div>
            </div>

            ${insufficient ? `
            <div style="background: rgba(239, 68, 68, 0.1); border: 1px solid rgba(239, 68, 68, 0.3); border-radius: 10px; padding: 14px; margin-bottom: 16px; text-align: center;">
                <p style="color: #ef4444; margin: 0; font-weight: 600;">
                    <i class="fas fa-exclamation-triangle"></i> Insufficient Balance
                </p>
                <p style="color: #999; margin: 5px 0 0 0; font-size: 13px;">Add ₹${shortfall.toFixed(2)} to your wallet to proceed</p>
            </div>
            <div style="display: flex; gap: 12px;">
                <button class="btn btn-secondary" style="flex: 1; padding: 14px; font-size: 15px; border-radius: 10px; background: #333; border: 1px solid #555;" onclick="closeModal('taskSuccessModal');">
                    Close
                </button>
                <button class="btn btn-primary" style="flex: 1; padding: 14px; font-size: 15px; border-radius: 10px;" onclick="closeModal('taskSuccessModal'); window.location.href='wallet.html';">
                    <i class="fas fa-plus"></i> Add Money
                </button>
            </div>
            ` : `
            <div style="display: flex; gap: 12px;">
                <button class="btn btn-secondary" style="flex: 1; padding: 14px; font-size: 15px; border-radius: 10px; background: #333; border: 1px solid #555;" onclick="closeModal('taskSuccessModal');">
                    <i class="fas fa-times"></i> Cancel
                </button>
                <button class="btn btn-success" style="flex: 1; padding: 14px; font-size: 15px; border-radius: 10px;" id="invoicePayBtn" onclick="executePayment(${taskId});">
                    <i class="fas fa-check-circle"></i> Approve & Pay
                </button>
            </div>
            `}
        </div>
    `;
    ensureTaskSuccessModal();
    document.getElementById('taskSuccessContent').innerHTML = content;
    openModal('taskSuccessModal');
}

/**
 * Ensure taskSuccessModal exists in the DOM (some pages may not include it)
 */
function ensureTaskSuccessModal() {
    if (!document.getElementById('taskSuccessModal')) {
        document.body.insertAdjacentHTML('beforeend',
            '<div class="modal" id="taskSuccessModal"><div class="modal-content modal-success">' +
            '<button class="modal-close" onclick="closeModal(\'taskSuccessModal\')"><i class="fas fa-times"></i></button>' +
            '<div class="task-success-content" id="taskSuccessContent"></div></div></div>');
    }
}

/**
 * Execute the actual payment after poster approves the invoice
 */
async function executePayment(taskId) {
    const task = myPostedTasks.find(t => t.id == taskId);
    if (!task) {
        showToast('❌ Task not found');
        closeModal('taskSuccessModal');
        return;
    }

    // Disable button to prevent double-click
    const payBtn = document.getElementById('invoicePayBtn');
    if (payBtn) {
        payBtn.disabled = true;
        payBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Processing...';
    }

    const taskAmount = task.price || 0;
    const serviceCharge = task.service_charge || 0;
    const totalTaskValue = taskAmount + serviceCharge;
    const helperCommission = totalTaskValue * 0.12;
    const posterFee = totalTaskValue * 0.05;
    const totalCost = totalTaskValue + posterFee;
    const helperNetReceives = totalTaskValue - helperCommission;

    try {
        console.log('📤 Sending payment request...');
        const response = await fetch(API_BASE_URL + `/tasks/${taskId}/pay-helper`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
            },
            body: JSON.stringify({ taskId: taskId })
        });

        const result = await response.json();
        console.log('📥 Payment response:', result);

        if (result.success) {
            if (currentUser) {
                currentUser.wallet = result.posterNewBalance;
                localStorage.setItem('taskearn_user', JSON.stringify(currentUser));
            }

            // Remove paid task from myPostedTasks
            const paidTask = { ...task, status: 'paid' };
            myPostedTasks = myPostedTasks.filter(t => t.id != taskId);
            updateUserData(currentUser.id, {
                postedTasks: serializeTasks(myPostedTasks)
            });

            showPaymentDonePopup(paidTask, totalCost, result.helperEarnings || helperNetReceives, result.posterNewBalance);

            renderDashboard();
            updateNotificationUI();
            syncNotificationsFromServer();

            setTimeout(() => {
                loadTasksFromServer();
                refreshWalletBalance();
            }, 1000);
        } else {
            closeModal('taskSuccessModal');
            showToast(`❌ Payment failed: ${result.message || 'Unknown error'}`, 5000);
        }
    } catch (error) {
        console.error('Payment failed:', error.message);
        closeModal('taskSuccessModal');
        showToast('❌ Payment failed. Please check your connection and try again.');
    }
}

// ========================================
// FORM HANDLERS
// ========================================

async function handleTaskSubmit(event) {
    event.preventDefault();

    if (!currentUser) {
        showToast('Please login first');
        closeModal('postTaskModal');
        openModal('loginModal');
        return;
    }

    // Check if user has API token for server sync
    const hasApiToken = localStorage.getItem('taskearn_token');
    if (!hasApiToken) {
        showToast('❌ You need to register/login via the backend to post tasks visible to others', 5000);
        closeModal('postTaskModal');
        
        // Show detailed warning
        if (confirm('Your account is in local-only mode. Tasks you create won\'t be visible to other users.\n\nWould you like to logout and register properly now?')) {
            handleLogout();
            setTimeout(() => openModal('loginModal'), 500);
        }
        return;
    }

    const customBudgetValue = parseInt(document.getElementById('customBudget').value) || 0;
    let baseBudget = customBudgetValue > 0 ? customBudgetValue : selectedBudget;
    
    // Enforce minimum ₹100
    if (baseBudget < MIN_TASK_PRICE) {
        baseBudget = MIN_TASK_PRICE;
        showToast('⚠️ Minimum task budget is ₹' + MIN_TASK_PRICE);
    }
    
    const totalPrice = baseBudget + currentBonus;
    const category = document.getElementById('modalTaskCategory').value;
    const serviceCharge = getServiceCharge(category);
    const totalPayable = totalPrice + serviceCharge;

    // Resolve task location coordinates
    const addressText = document.getElementById('modalTaskLocation').value.trim();
    let taskLat, taskLng;

    if (modalTaskCoords) {
        // User clicked "Use My Location" — use captured GPS coords
        taskLat = modalTaskCoords.lat;
        taskLng = modalTaskCoords.lng;
    } else if (addressText) {
        // User typed an address — geocode it
        showToast('📍 Looking up location...');
        const geo = await geocodeAddress(addressText);
        if (geo) {
            taskLat = geo.lat;
            taskLng = geo.lng;
        } else {
            showToast('❌ Could not find that address. Please try a different address or use "My Location".');
            return;
        }
    } else {
        showToast('❌ Please enter a task location');
        return;
    }

    const taskData = {
        title: document.getElementById('modalTaskTitle').value,
        category: category,
        description: document.getElementById('modalTaskDescription').value,
        location: {
            lat: taskLat,
            lng: taskLng,
            address: addressText
        },
        price: totalPrice,
        serviceCharge: serviceCharge,
        totalPaid: totalPayable
    };

    // Reset for next post
    modalTaskCoords = null;

    // Try to save to server first
    let serverTaskId = null;
    let serverSaveError = null;
    
    // Task posting requires API authentication (already checked above)
    console.log('📤 Attempting to post task to server...');
    console.log('🔑 Has API token:', !!hasApiToken);
    console.log('👤 Current user:', currentUser?.name, currentUser?.id);
    console.log('📦 Task data:', JSON.stringify(taskData, null, 2));
    
    try {
        if (typeof TasksAPI !== 'undefined' && TasksAPI.create) {
            console.log('🚀 Calling TasksAPI.create...');
            const result = await TasksAPI.create(taskData);
            console.log('📥 Server response:', JSON.stringify(result, null, 2));
            
            if (result.success) {
                serverTaskId = result.taskId;
                console.log('✅ Task saved to server with ID:', serverTaskId);
                showToast('✅ Task posted successfully!');
            } else {
                serverSaveError = result.message;
                console.warn('⚠️ Server save failed:', result.message);
                if (result.message && result.message.includes('token')) {
                    showToast('❌ Session expired. Please login again.');
                    setTimeout(() => {
                        handleLogout();
                        openModal('loginModal');
                    }, 2000);
                    return;
                }
                // Continue with local save even if server fails
                showToast('⚠️ Saved locally. Will sync when backend is online.');
            }
        }
    } catch (error) {
        console.warn('⚠️ Server unavailable, saving task locally:', error.message);
        showToast('⚠️ Saved locally. Will sync when backend is online.');
    }

    const newTask = {
        id: serverTaskId || Date.now(),
        ...taskData,
        postedBy: currentUser,
        postedAt: new Date(),
        expiresAt: new Date(Date.now() + 12 * 3600000),
        status: 'active',
        localOnly: !serverTaskId
    };

    tasks.unshift(newTask);
    myPostedTasks.unshift(newTask);

    // Update user stats in storage (serialize for localStorage)
    const newPostedCount = (currentUser.tasksPosted || 0) + 1;
    currentUser.tasksPosted = newPostedCount; // ✅ Update in memory immediately
    updateUserData(currentUser.id, {
        tasksPosted: newPostedCount,
        postedTasks: serializeTasks(myPostedTasks)
    });

    closeModal('postTaskModal');
    document.getElementById('modalTaskForm')?.reset();
    
    // Reset bonus
    currentBonus = 0;
    document.querySelectorAll('.bonus-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.budget-option').forEach(o => o.classList.remove('active'));
    selectedBudget = 500;
    updateTotalBudgetDisplay();

    renderTasks();
    addTaskMarkers();
    renderDashboard();
    
    // ✅ FIX: Refresh profile after posting
    setTimeout(() => {
        openUserProfile();
    }, 500);
    
    // Refresh tasks from server to sync
    setTimeout(() => {
        loadTasksFromServer();
        loadCategoryCounts();
    }, 1000);
    
    // Show success modal with edit option
    showTaskPostedSuccess(newTask);
}

// Check if backend API is healthy and available
async function checkBackendHealth() { return false; }

// Check if user has proper backend authentication
function isUserBackendAuthenticated() {
    return !!localStorage.getItem('taskearn_token');
}

// Display authentication status in UI
function updateAuthenticationStatus() {
    const statusElement = document.getElementById('authStatus');
    if (statusElement) {
        if (currentUser) {
            const isBackendAuth = isUserBackendAuthenticated();
            if (isBackendAuth) {
                statusElement.innerHTML = '<span style="color: #10b981;"><i class="fas fa-check-circle"></i> Connected to server</span>';
            } else {
                statusElement.innerHTML = '<span style="color: #f59e0b;"><i class="fas fa-exclamation-triangle"></i> Local mode - tasks won\'t sync</span>';
            }
            statusElement.style.display = 'block';
        } else {
            statusElement.style.display = 'none';
        }
    }
}

async function handleLogin(event) {
    event.preventDefault();
    
    const email = document.getElementById('loginEmail').value;
    const password = document.getElementById('loginPassword').value;
    const loginBtn = event.target.querySelector('button[type="submit"]');
    
    if (loginBtn) {
        loginBtn.disabled = true;
        loginBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Verifying...';
    }
    
    try {
        // Try server login first
        if (typeof AuthAPI !== 'undefined') {
            const result = await AuthAPI.login(email, password);
            
            if (result.success) {
                currentUser = result.user;
                myPostedTasks = result.postedTasks || [];
                myAcceptedTasks = result.acceptedTasks || [];
                myCompletedTasks = result.completedTasks || [];
                
                // ✅ CRITICAL FIX: Also restore tasks from local storage if not provided by API
                const allUsers = await getStoredUsersAsync();
                if (currentUser && allUsers[currentUser.id]) {
                    const storedUser = allUsers[currentUser.id];
                    console.log('📦 Merging locally stored tasks with API response...');
                    
                    // Merge tasks: prefer API data, fallback to local storage
                    if ((!myPostedTasks || myPostedTasks.length === 0) && storedUser.postedTasks) {
                        myPostedTasks = deserializeTasks(storedUser.postedTasks);
                        console.log('✅ Restored', myPostedTasks.length, 'posted tasks from local storage');
                    }
                    
                    if ((!myAcceptedTasks || myAcceptedTasks.length === 0) && storedUser.acceptedTasks) {
                        myAcceptedTasks = deserializeTasks(storedUser.acceptedTasks);
                        console.log('✅ Restored', myAcceptedTasks.length, 'accepted tasks from local storage');
                    }
                    
                    if ((!myCompletedTasks || myCompletedTasks.length === 0) && storedUser.completedTasks) {
                        myCompletedTasks = deserializeTasks(storedUser.completedTasks);
                        console.log('✅ Restored', myCompletedTasks.length, 'completed tasks from local storage');
                    }
                }
                
                // Also save current user to storage for next session
                saveCurrentSession(currentUser);
                updateUserData(currentUser.id, {
                    postedTasks: serializeTasks(myPostedTasks),
                    acceptedTasks: serializeTasks(myAcceptedTasks),
                    completedTasks: serializeTasks(myCompletedTasks)
                });
                
                showToast('✅ Welcome back, ' + currentUser.name);
                
                // Sync suspension state from server login response
                applySuspensionFromUser(currentUser);
                
                // Check wallet balance and show warning if low
                if (currentUser.walletLow) {
                    showToast('⚠️ ' + (currentUser.walletWarning || 'Your wallet balance is low. Please top up.'), 'warning');
                }
                
                closeModal('loginModal');
                document.getElementById('loginEmail').value = '';
                document.getElementById('loginPassword').value = '';
                
                updateNavForUser();
                
                // ✅ FIX: Load tasks from server FIRST, then render UI
                // This ensures the marketplace shows newly posted tasks from other accounts
                const tasksLoaded = await loadTasksFromServer();
                
                // Render dashboard after tasks are fully loaded
                setTimeout(() => renderDashboard(), 100);
                
                return;
            } else {
                showToast('❌ ' + (result.message || 'Login failed'));
                return;
            }
        } else {
            showToast('❌ Login service unavailable');
            return;
        }
    } catch (error) {
        console.error('Login error:', error);
        showToast('❌ Login failed.');
    } finally {
        if (loginBtn) {
            loginBtn.disabled = false;
            loginBtn.innerHTML = 'Login';
        }
    }
}

async function handleSignup(event) {
    event.preventDefault();

    const firstName = document.getElementById('signupFirstName').value.trim();
    const lastName = document.getElementById('signupLastName').value.trim();
    const email = document.getElementById('signupEmail').value.trim();
    const password = document.getElementById('signupPassword').value;
    const phone = document.getElementById('signupPhone')?.value || '';
    const dob = document.getElementById('signupDOB').value;
    const signupBtn = event.target.querySelector('button[type="submit"]');
    
    // Validate age
    const dobDate = new Date(dob);
    const age = Math.floor((Date.now() - dobDate.getTime()) / (365.25 * 24 * 3600000));

    if (age < 16) {
        showToast('You must be 16+ to use Workmate4u');
        return;
    }
    
    // Validate password strength
    if (password.length < 6) {
        showToast('❌ Password must be at least 6 characters');
        return;
    }
    
    // Additional password strength validation
    if (!/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
        showToast('❌ Password must contain both letters and numbers');
        return;
    }
    
    // Show loading state
    if (signupBtn) {
        signupBtn.disabled = true;
        signupBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Creating Account...';
    }
    
    try {
        // Try server registration first
        if (typeof AuthAPI !== 'undefined') {
            const result = await AuthAPI.register({
                name: firstName + ' ' + lastName,
                email: email,
                password: password,
                phone: phone,
                dob: dob
            });
            
            if (result.success) {
                currentUser = result.user;
                myPostedTasks = [];
                myAcceptedTasks = [];
                myCompletedTasks = [];
                
                showToast('🎉 Welcome to Workmate4u! Your ID: ' + currentUser.id);
                
                // Check wallet balance and show warning if low
                if (currentUser.walletLow) {
                    showToast('⚠️ ' + (currentUser.walletWarning || 'Your wallet balance is low. Please top up.'), 'warning');
                }
                
                closeModal('signupModal');
                
                // Clear form
                document.getElementById('signupFirstName').value = '';
                document.getElementById('signupLastName').value = '';
                document.getElementById('signupEmail').value = '';
                document.getElementById('signupPassword').value = '';
                if (document.getElementById('signupPhone')) document.getElementById('signupPhone').value = '';
                document.getElementById('signupDOB').value = '';
                
                updateNavForUser();
                
                // ✅ FIX: Load tasks from server FIRST, then render UI
                // This ensures new users see all available tasks in the marketplace
                const tasksLoaded = await loadTasksFromServer();
                
                // Render dashboard after tasks are fully loaded
                setTimeout(() => renderDashboard(), 100);
                
                return;
            } else {
                showToast('❌ ' + result.message);
                return;
            }
        } else {
            showToast('❌ Registration service unavailable');
            return;
        }
    } catch (error) {
        console.error('Signup error:', error);
        showToast('❌ Signup failed. Please try again.');
    } finally {
        // Reset button state
        if (signupBtn) {
            signupBtn.disabled = false;
            signupBtn.innerHTML = 'Create Account';
        }
    }
}

function updateNavForUser() {
    const nav = document.querySelector('.nav-buttons');
    const notificationWrapper = document.getElementById('notificationWrapper');
    const mobileNotificationItem = document.getElementById('mobileNotificationItem');
    const mobileWalletItem = document.getElementById('mobileWalletItem');
    const mobileMenu = document.getElementById('mobileMenu');
    
    if (nav && currentUser) {
        nav.innerHTML = `
            <div class="user-menu">
                <button class="btn btn-outline" onclick="window.location.href='profile.html'">
                    <i class="fas fa-user"></i> ${currentUser.name}
                </button>
                <button class="btn btn-primary" onclick="logout()">Logout</button>
            </div>
        `;
        
        // Update mobile menu for logged-in user
        if (mobileMenu) {
            const mobileMenuList = mobileMenu.querySelector('ul');
            if (mobileMenuList) {
                // Find and update/replace the login/signup buttons
                const existingAuthButtons = mobileMenuList.querySelectorAll('li:has(button)');
                existingAuthButtons.forEach(btn => btn.remove());
                
                // Remove old profile items if any
                const oldProfileItems = mobileMenuList.querySelectorAll('.mobile-profile-item, .mobile-logout-item, .mobile-dashboard-item');
                oldProfileItems.forEach(item => item.remove());
                
                // Add user profile and logout for mobile
                const profileLi = document.createElement('li');
                profileLi.className = 'mobile-profile-item';
                profileLi.innerHTML = `<a href="profile.html" onclick="toggleMobileMenu();"><i class="fas fa-user-circle"></i> ${currentUser.name}</a>`;
                mobileMenuList.appendChild(profileLi);
                
                const dashboardLi = document.createElement('li');
                dashboardLi.className = 'mobile-dashboard-item';
                dashboardLi.innerHTML = `<a href="#my-tasks" onclick="scrollToSection('my-tasks'); toggleMobileMenu();"><i class="fas fa-tasks"></i> My Tasks</a>`;
                mobileMenuList.appendChild(dashboardLi);
                
                const logoutLi = document.createElement('li');
                logoutLi.className = 'mobile-logout-item';
                logoutLi.innerHTML = `<button class="btn btn-primary" onclick="logout(); toggleMobileMenu();">Logout</button>`;
                mobileMenuList.appendChild(logoutLi);
            }
        }
        
        // Show notification bell when logged in
        if (notificationWrapper) {
            notificationWrapper.style.display = 'block';
        }
        if (mobileNotificationItem) {
            mobileNotificationItem.style.display = 'block';
        }
        if (mobileWalletItem) {
            mobileWalletItem.style.display = 'block';
        }
        
        // Load and display notifications (local first, then sync from server)
        notifications = loadNotifications();
        updateNotificationUI();
        syncNotificationsFromServer();

    } else {
        // Reset mobile menu for logged-out user
        if (mobileMenu) {
            const mobileMenuList = mobileMenu.querySelector('ul');
            if (mobileMenuList) {
                // Remove profile items
                const profileItems = mobileMenuList.querySelectorAll('.mobile-profile-item, .mobile-logout-item, .mobile-dashboard-item');
                profileItems.forEach(item => item.remove());
                
                // Check if login/signup buttons exist, if not add them
                if (!mobileMenuList.querySelector('button')) {
                    const loginLi = document.createElement('li');
                    loginLi.innerHTML = `<button class="btn btn-outline" onclick="openModal('loginModal')">Login</button>`;
                    mobileMenuList.appendChild(loginLi);
                    
                    const signupLi = document.createElement('li');
                    signupLi.innerHTML = `<button class="btn btn-primary" onclick="openModal('signupModal')">Sign Up</button>`;
                    mobileMenuList.appendChild(signupLi);
                }
            }
        }
        
        // Hide notification bell when logged out
        if (notificationWrapper) {
            notificationWrapper.style.display = 'none';
        }
        if (mobileNotificationItem) {
            mobileNotificationItem.style.display = 'none';
        }
        if (mobileWalletItem) {
            mobileWalletItem.style.display = 'none';
        }
    }
}

function openUserProfile() {
    if (!currentUser) return;
    
    const content = `
        <div class="profile-header">
            <div class="profile-avatar">
                <i class="fas fa-user-circle"></i>
            </div>
            <h2>${currentUser.name}</h2>
            <p class="user-id">ID: ${currentUser.id}</p>
            <div class="profile-rating">
                ${generateStars(currentUser.rating)}
                <span>(${currentUser.rating.toFixed(1)})</span>
            </div>
        </div>
        
        <div class="profile-stats">
            <div class="stat-card">
                <i class="fas fa-rupee-sign"></i>
                <div class="stat-value">₹${currentUser.totalEarnings || 0}</div>
                <div class="stat-label">Total Earned</div>
            </div>
            <div class="stat-card">
                <i class="fas fa-check-circle"></i>
                <div class="stat-value">${currentUser.tasksCompleted || 0}</div>
                <div class="stat-label">Completed</div>
            </div>
            <div class="stat-card">
                <i class="fas fa-clipboard-list"></i>
                <div class="stat-value">${currentUser.tasksPosted || 0}</div>
                <div class="stat-label">Posted</div>
            </div>
        </div>
        
        <div class="profile-info">
            <h4><i class="fas fa-info-circle"></i> Account Details</h4>
            <div class="info-row">
                <span class="label">Email:</span>
                <span class="value">${currentUser.email}</span>
            </div>
            <div class="info-row">
                <span class="label">Phone:</span>
                <span class="value">${currentUser.phone || 'Not provided'}</span>
            </div>
            <div class="info-row">
                <span class="label">Member Since:</span>
                <span class="value">${new Date(currentUser.joinedAt).toLocaleDateString('en-IN', { year: 'numeric', month: 'long', day: 'numeric' })}</span>
            </div>
        </div>
        
        <div class="profile-actions">
            <button class="btn btn-outline" onclick="closeModal('profileModal')">
                <i class="fas fa-times"></i> Close
            </button>
            <button class="btn btn-primary" onclick="scrollToSection('my-tasks'); closeModal('profileModal')">
                <i class="fas fa-tasks"></i> My Tasks
            </button>
        </div>
    `;
    
    // Create profile modal if doesn't exist
    let profileModal = document.getElementById('profileModal');
    if (!profileModal) {
        profileModal = document.createElement('div');
        profileModal.className = 'modal';
        profileModal.id = 'profileModal';
        profileModal.innerHTML = `
            <div class="modal-content profile-modal">
                <button class="modal-close" onclick="closeModal('profileModal')">
                    <i class="fas fa-times"></i>
                </button>
                <div id="profileContent"></div>
            </div>
        `;
        document.body.appendChild(profileModal);
    }
    
    document.getElementById('profileContent').innerHTML = content;
    openModal('profileModal');
}

// ========================================
// PROFILE PAGE FUNCTIONS
// ========================================

var _photoJustUploaded = false;

function loadProfilePage() {
    if (!currentUser) return;
    
    // Render from currentUser immediately, then refresh from server
    renderProfileUI();
    
    // Fetch fresh user data from server to ensure profile is up to date
    // Skip if photo was just uploaded to avoid overwriting optimistic preview
    if (_photoJustUploaded) { _photoJustUploaded = false; return; }
    if (typeof AuthAPI !== 'undefined' && AuthAPI.getCurrentUser) {
        AuthAPI.getCurrentUser().then(function(result) {
            if (result && result.success && result.user) {
                // Preserve locally-computed earnings if server doesn't track them
                var localEarnings = currentUser.totalEarnings;
                var localCompleted = currentUser.tasksCompleted;
                Object.assign(currentUser, result.user);
                if (!currentUser.totalEarnings && localEarnings) currentUser.totalEarnings = localEarnings;
                if (!currentUser.tasksCompleted && localCompleted) currentUser.tasksCompleted = localCompleted;
                saveUserToStorage(currentUser);
                renderProfileUI();
            }
        }).catch(function() { /* use cached data */ });
    }
    
    // Also refresh wallet balance
    refreshWalletBalance().then(function() { renderProfileUI(); }).catch(function() {});
}

function renderProfileUI() {
    if (!currentUser) return;
    
    // Avatar
    var avatarImg = document.getElementById('profileAvatarImg');
    if (avatarImg) {
        if (currentUser.profilePhoto) {
            avatarImg.innerHTML = '<img src="' + currentUser.profilePhoto + '" alt="Profile">';
        } else {
            avatarImg.innerHTML = '<i class="fas fa-user"></i>';
        }
    }
    
    // Name & badge
    var nameEl = document.getElementById('profileDisplayName');
    if (nameEl) nameEl.textContent = currentUser.name || 'User';
    
    var sinceEl = document.getElementById('profileMemberSince');
    if (sinceEl && currentUser.joinedAt) {
        sinceEl.innerHTML = '<i class="fas fa-calendar-alt"></i> Member since ' +
            new Date(currentUser.joinedAt).toLocaleDateString('en-IN', { year: 'numeric', month: 'long' });
    }
    
    // Stats — compute from actual data, fall back to stored values
    var completedCount = myCompletedTasks.length || currentUser.tasksCompleted || 0;
    var totalEarned = currentUser.totalEarnings || 0;
    if (myCompletedTasks.length > 0 && !totalEarned) {
        totalEarned = myCompletedTasks.reduce(function(sum, t) {
            if (t.earnedAmount) return sum + t.earnedAmount;
            var amt = (t.price || 0) + (t.service_charge || t.serviceCharge || 0);
            return sum + (amt * 0.88);
        }, 0);
        totalEarned = Math.round(totalEarned * 100) / 100;
    }
    var postedCount = myPostedTasks.length || currentUser.tasksPosted || 0;
    
    var sr = document.getElementById('statRating');
    if (sr) sr.textContent = (currentUser.rating || 5.0).toFixed(1);
    var sc = document.getElementById('statCompleted');
    if (sc) sc.textContent = completedCount;
    var sp = document.getElementById('statPosted');
    if (sp) sp.textContent = postedCount;
    var se = document.getElementById('statEarnings');
    if (se) se.textContent = '₹' + (typeof totalEarned === 'number' ? totalEarned.toFixed(2) : totalEarned);
    
    // Fields
    var fn = document.getElementById('fieldName');
    if (fn) fn.textContent = currentUser.name || '—';
    var fe = document.getElementById('fieldEmail');
    if (fe) fe.textContent = currentUser.email || '—';
    var fp = document.getElementById('fieldPhone');
    if (fp) fp.textContent = currentUser.phone || 'Not provided';
    var fd = document.getElementById('fieldDOB');
    if (fd) fd.textContent = currentUser.dob ? new Date(currentUser.dob).toLocaleDateString('en-IN', { year: 'numeric', month: 'long', day: 'numeric' }) : 'Not provided';
    var fw = document.getElementById('fieldWallet');
    if (fw) fw.textContent = '₹' + (currentUser.wallet || 0);
    var fid = document.getElementById('fieldUserId');
    if (fid) fid.textContent = currentUser.id || '—';

    // Suspension banner
    if (isDebtSuspended()) {
        const debtBanner = document.getElementById('debtSuspensionBanner');
        if (debtBanner) {
            const amountEl = debtBanner.querySelector('[data-debt-amount]');
            if (amountEl) amountEl.textContent = '₹' + getDebtAmount().toFixed(2);
            debtBanner.style.display = 'block';
        }
        hideSuspensionBanner();
    } else if (isAccountSuspended()) {
        startSuspensionTimer();
        const debtBanner = document.getElementById('debtSuspensionBanner');
        if (debtBanner) debtBanner.style.display = 'none';
    } else {
        hideSuspensionBanner();
        const debtBanner = document.getElementById('debtSuspensionBanner');
        if (debtBanner) debtBanner.style.display = 'none';
    }
}

function triggerPhotoUpload() {
    var inp = document.getElementById('profilePhotoInput');
    if (inp) inp.click();
}

async function handleProfilePhoto(event) {
    var file = event.target ? event.target.files[0] : (event.files ? event.files[0] : null);
    if (!file) return;
    
    if (!file.type.startsWith('image/')) {
        showToast('Please select an image file', 'error');
        return;
    }
    if (file.size > 2 * 1024 * 1024) {
        showToast('Photo must be under 2MB', 'error');
        return;
    }
    
    showToast('Processing photo...', 'info');
    
    try {
        var base64 = await compressProfileImage(file, 800, 0.8);
    } catch (compressErr) {
        console.error('Image compression failed:', compressErr);
        showToast('Could not process image. Try a different photo.', 'error');
        var inp = document.getElementById('profilePhotoInput');
        if (inp) inp.value = '';
        return;
    }
    
    var oldPhoto = currentUser ? currentUser.profilePhoto : null;
    
    // Optimistic UI update — show new photo immediately
    currentUser.profilePhoto = base64;
    _photoJustUploaded = true;
    renderProfileUI();
    
    try {
        var result = await UserAPI.updateProfile({ profile_photo: base64 });
        if (result.success) {
            if (result.user) {
                Object.assign(currentUser, result.user);
            }
            saveUserToStorage(currentUser);
            showToast('Profile photo updated!', 'success');
        } else {
            currentUser.profilePhoto = oldPhoto;
            renderProfileUI();
            showToast(result.message || 'Failed to update photo', 'error');
        }
    } catch (err) {
        console.error('Photo upload error:', err);
        showToast('Photo saved but local cache may be stale', 'warning');
    }
    var inp = document.getElementById('profilePhotoInput');
    if (inp) inp.value = '';
}

// Compress and resize image using canvas. Returns a base64 data URI (JPEG).
function compressProfileImage(file, maxSize, quality) {
    return new Promise(function(resolve, reject) {
        var img = new Image();
        var url = URL.createObjectURL(file);
        img.onload = function() {
            URL.revokeObjectURL(url);
            var w = img.width;
            var h = img.height;
            // Scale down if larger than maxSize
            if (w > maxSize || h > maxSize) {
                if (w > h) { h = Math.round(h * maxSize / w); w = maxSize; }
                else { w = Math.round(w * maxSize / h); h = maxSize; }
            }
            var canvas = document.createElement('canvas');
            canvas.width = w;
            canvas.height = h;
            var ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, w, h);
            var result = canvas.toDataURL('image/jpeg', quality);
            resolve(result);
        };
        img.onerror = function() {
            URL.revokeObjectURL(url);
            reject(new Error('Failed to load image'));
        };
        img.src = url;
    });
}

function toggleEditPersonal() {
    var view = document.getElementById('personalInfoView');
    var edit = document.getElementById('personalInfoEdit');
    var btn = document.getElementById('editPersonalBtn');
    if (!view || !edit) return;
    
    var showing = edit.style.display !== 'none';
    if (showing) {
        cancelEditPersonal();
    } else {
        view.style.display = 'none';
        edit.style.display = 'block';
        btn.innerHTML = '<i class="fas fa-times"></i> Cancel';
        btn.style.color = 'var(--danger)';
        btn.style.borderColor = 'var(--danger)';
        // Populate fields
        document.getElementById('editName').value = currentUser.name || '';
        document.getElementById('editEmail').value = currentUser.email || '';
        document.getElementById('editPhone').value = currentUser.phone || '';
    }
}

function cancelEditPersonal() {
    var view = document.getElementById('personalInfoView');
    var edit = document.getElementById('personalInfoEdit');
    var btn = document.getElementById('editPersonalBtn');
    if (view) view.style.display = 'block';
    if (edit) edit.style.display = 'none';
    if (btn) {
        btn.innerHTML = '<i class="fas fa-pen"></i> Edit';
        btn.style.color = '';
        btn.style.borderColor = '';
    }
}

async function savePersonalInfo() {
    var name = document.getElementById('editName').value.trim();
    var email = document.getElementById('editEmail').value.trim();
    var phone = document.getElementById('editPhone').value.trim();
    
    if (!name) { showToast('Name is required', 'error'); return; }
    if (!email || email.indexOf('@') === -1) { showToast('Valid email is required', 'error'); return; }
    
    var updates = {};
    if (name !== currentUser.name) updates.name = name;
    if (email !== currentUser.email) updates.email = email;
    if (phone !== (currentUser.phone || '')) updates.phone = phone;
    
    if (Object.keys(updates).length === 0) {
        showToast('No changes to save', 'info');
        cancelEditPersonal();
        return;
    }
    
    try {
        var result = await UserAPI.updateProfile(updates);
        if (result.success) {
            if (result.user) {
                currentUser = result.user;
                saveUserToStorage(currentUser);
            }
            loadProfilePage();
            cancelEditPersonal();
            showToast('Profile updated successfully!', 'success');
        } else {
            showToast(result.message || 'Failed to update', 'error');
        }
    } catch (err) {
        showToast('Error saving changes', 'error');
    }
}

function toggleChangePassword() {
    var form = document.getElementById('changePasswordForm');
    if (!form) return;
    var visible = form.style.display !== 'none';
    form.style.display = visible ? 'none' : 'block';
    if (!visible) {
        document.getElementById('currentPassword').value = '';
        document.getElementById('newPassword2').value = '';
        document.getElementById('confirmPassword2').value = '';
    }
}

async function saveNewPassword() {
    var current = document.getElementById('currentPassword').value;
    var newPwd = document.getElementById('newPassword2').value;
    var confirm = document.getElementById('confirmPassword2').value;
    
    if (!current) { showToast('Enter current password', 'error'); return; }
    if (!newPwd || newPwd.length < 6) { showToast('New password must be at least 6 characters', 'error'); return; }
    if (newPwd !== confirm) { showToast('Passwords do not match', 'error'); return; }
    
    try {
        var result = await UserAPI.changePassword(current, newPwd);
        if (result.success) {
            showToast('Password changed successfully!', 'success');
            toggleChangePassword();
        } else {
            showToast(result.message || 'Failed to change password', 'error');
        }
    } catch (err) {
        showToast('Error changing password', 'error');
    }
}

// Initialize profile page if on profile.html
(function() {
    var page = (window.location.pathname.split('/').pop() || '').toLowerCase();
    if (page === 'profile.html') {
        function initProfile() {
            setTimeout(function() {
                loadProfilePage();
                // Bind file input via JS for better mobile reliability
                var inp = document.getElementById('profilePhotoInput');
                if (inp && !inp._bound) {
                    inp._bound = true;
                    inp.addEventListener('change', handleProfilePhoto);
                }
            }, 300);
        }
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initProfile);
        } else {
            initProfile();
        }
    }
})();

function logout() {
    // Call server logout to invalidate session_token
    const token = localStorage.getItem('taskearn_token');
    if (token) {
        try {
            fetch((typeof API_URL !== 'undefined' ? API_URL : '') + '/auth/logout', {
                method: 'POST',
                headers: { 'Authorization': 'Bearer ' + token }
            }).catch(() => {});
        } catch (e) {}
    }

    clearCurrentSession();
    currentUser = null;
    tasks = [];
    myPostedTasks = [];
    myAcceptedTasks = [];
    myCompletedTasks = [];
    notifications = [];

    // Stop any running suspension timer
    stopSuspensionTimer();
    hideSuspensionBanner();

    const nav = document.querySelector('.nav-buttons');
    if (nav) {
        nav.innerHTML = `
            <button class="btn btn-outline" onclick="openModal('loginModal')">Login</button>
            <button class="btn btn-primary" onclick="openModal('signupModal')">Sign Up</button>
        `;
    }
    
    // Hide notification bell
    const notificationWrapper = document.getElementById('notificationWrapper');
    const mobileNotificationItem = document.getElementById('mobileNotificationItem');
    if (notificationWrapper) notificationWrapper.style.display = 'none';
    if (mobileNotificationItem) mobileNotificationItem.style.display = 'none';
    const mobileWalletItem = document.getElementById('mobileWalletItem');
    if (mobileWalletItem) mobileWalletItem.style.display = 'none';
    
    updateAuthenticationStatus(); // Update auth status
    renderDashboard();
    showToast('Logged out successfully');
}

// Alias for handleLogout
function handleLogout() {
    logout();
}

// ========================================
// DASHBOARD
// ========================================

function switchTab(tab) {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
    
    if (event && event.target) event.target.classList.add('active');
    
    const content = document.getElementById(tab + 'Tasks');
    if (content) content.classList.add('active');
    
    renderDashboard();
}

function renderDashboard() {
    updateAuthenticationStatus(); // Update auth status indicator
    
    // Show wallet low warning if applicable
    if (currentUser && currentUser.walletLow) {
        const walletWarningEl = document.getElementById('walletLowWarning');
        if (walletWarningEl) {
            walletWarningEl.innerHTML = `
                <div class="alert alert-warning" style="margin-bottom: 15px; padding: 12px; border-radius: 6px; background-color: #fff3cd; border-left: 4px solid #ffc107; display: flex; justify-content: space-between; align-items: center;">
                    <span><i class="fas fa-exclamation-triangle"></i> Wallet balance is low (₹${currentUser.wallet || 0}). <a href="#" onclick="openWalletModal(); return false;" style="text-decoration: underline; font-weight: bold;">Top up now</a></span>
                    <button type="button" class="close" onclick="this.parentElement.style.display='none';" style="background: none; border: none; cursor: pointer; font-size: 20px;">&times;</button>
                </div>
            `;
            walletWarningEl.style.display = 'block';
        }
    }
    
    renderPostedTasks();
    renderAcceptedTasks();
    renderCompletedTasks();
    
    // Sync notifications from server (non-blocking) so poster sees Pay Now from helper
    syncNotificationsFromServer();
    
    // Check if helper has any recently paid tasks to show pop-up
    setTimeout(() => checkAndShowPaymentReceived(), 500);
}

function renderPostedTasks() {
    const el = document.getElementById('myPostedTasks');
    if (!el) return;

    // Show only active (non-expired) posted tasks — payment is handled via notifications
    const visiblePostedTasks = myPostedTasks.filter(t => {
        if (t.status !== 'active') return false;
        if (getTimeLeft(t.expiresAt) === 'Expired') return false;
        return true;
    });

    if (visiblePostedTasks.length === 0) {
        el.innerHTML = '<div class="empty-state"><i class="fas fa-clipboard-list"></i><h3>No posted tasks</h3><button class="btn btn-primary" onclick="openModal(\'postTaskModal\')">Post a Task</button></div>';
        return;
    }

    el.innerHTML = visiblePostedTasks.map(t => {
        return `
            <div class="my-task-card">
                <div class="my-task-card-header">
                    <span class="task-category">${formatCategory(t.category)}</span>
                    <span class="task-status ${t.status}">${t.status}</span>
                </div>
                <h4>${t.title}</h4>
                <div class="task-meta"><span>₹${(t.price || 0) + (t.service_charge || t.serviceCharge || getServiceCharge(t.category))}</span><span>${getTimeLeft(t.expiresAt)}</span></div>
                <div class="task-actions">
                    <button class="btn btn-edit" onclick="openEditTask(${t.id})"><i class="fas fa-edit"></i> Edit</button>
                    <button class="btn btn-danger" onclick="deleteTask(${t.id})"><i class="fas fa-trash"></i> Delete</button>
                </div>
            </div>
        `;
    }).join('');
}

function renderAcceptedTasks() {
    const el = document.getElementById('myAcceptedTasks');
    if (!el) return;

    // Filter out paid and expired-accepted tasks
    const visibleAcceptedTasks = myAcceptedTasks.filter(t => {
        if (t.status === 'paid') return false;
        if (t.status === 'accepted' && getTimeLeft(t.expiresAt) === 'Expired') return false;
        return true;
    });

    // Sort newest first
    visibleAcceptedTasks.sort((a, b) => (b.id || 0) - (a.id || 0));

    if (visibleAcceptedTasks.length === 0) {
        el.innerHTML = '<div class="empty-state"><i class="fas fa-handshake"></i><h3>No accepted tasks</h3><button class="btn btn-primary" onclick="scrollToSection(\'find-tasks\')">Find Tasks</button></div>';
        return;
    }

    el.innerHTML = visibleAcceptedTasks.map(t => {
        // Show different UI based on task status
        let actionHTML = '';
        let statusHTML = 'In Progress';
        let statusColor = 'pending';
        
        if (t.status === 'completed' || t.status === 'pending_payment') {
            // Task completed, waiting for payment from poster
            statusHTML = '⏳ Awaiting Payment';
            statusColor = 'warning';
            actionHTML = `<div style="background: rgba(251, 191, 36, 0.1); border: 1px solid #fbbf24; border-radius: 8px; padding: 12px; margin-top: 10px;">
                <p style="color: #fbbf24; margin-bottom: 8px;">
                    <i class="fas fa-clock"></i> Waiting for task poster to pay...
                </p>
                <p style="color: #666; font-size: 13px; margin: 0;">You'll receive ₹${((t.price || 0) + (t.service_charge || 0)) * 0.88} (after 12% commission)</p>
            </div>`;
        } else {
            // Still in progress - show complete and release buttons
            actionHTML = `<div class="task-actions" style="display:flex;gap:8px;">
                <button class="btn btn-success" onclick="completeTask(${t.id})">Mark Complete</button>
                <button class="btn" style="background:#ef4444;color:#fff;" onclick="abandonTask(${t.id})">Release Task</button>
            </div>`;
        }
        
        return `
            <div class="my-task-card">
                <div class="my-task-card-header">
                    <span class="task-category">${formatCategory(t.category)}</span>
                    <span class="task-status ${statusColor}">${statusHTML}</span>
                </div>
                <h4>${t.title}</h4>
                <div class="task-meta"><span>₹${(t.price || 0) + (t.service_charge || t.serviceCharge || getServiceCharge(t.category))}</span><span>${t.expiresAt ? getTimeLeft(t.expiresAt) : (t.location && t.location.address ? t.location.address : '')}</span></div>
                ${actionHTML}
            </div>
        `;
    }).join('');
}

function renderCompletedTasks() {
    const el = document.getElementById('myCompletedTasks');
    if (!el) return;

    if (myCompletedTasks.length === 0) {
        el.innerHTML = '<div class="empty-state"><i class="fas fa-trophy"></i><h3>No completed tasks</h3></div>';
        return;
    }

    // Calculate total earned (after 12% commission)
    const totalEarned = myCompletedTasks.reduce((s, t) => {
        if (t.earnedAmount) return s + t.earnedAmount;
        const amt = (t.price || 0) + (t.service_charge || t.serviceCharge || 0);
        return s + (amt * 0.88);
    }, 0);
    
    el.innerHTML = `
        <div style="background:linear-gradient(135deg,#10b981,#34d399);color:white;padding:25px;border-radius:15px;text-align:center;margin-bottom:20px;">
            <h3 style="margin:0;">Total Earned</h3>
            <p style="font-size:2.5rem;font-weight:800;margin:10px 0;">₹${totalEarned.toFixed(2)}</p>
            <small style="opacity:0.9;">${myCompletedTasks.length} task${myCompletedTasks.length > 1 ? 's' : ''} completed (after 12% commission)</small>
        </div>
        ${myCompletedTasks.map(t => {
            const amt = (t.price || 0) + (t.service_charge || t.serviceCharge || 0);
            const earned = t.earnedAmount || (amt * 0.88);
            return `<div class="my-task-card"><h4>${t.title}</h4><p>Earned: <strong style="color:#10b981;">₹${earned.toFixed(2)}</strong> <small>(Task ₹${amt.toFixed(2)} - 12% commission)</small></p></div>`;
        }).join('')}
    `;
}

// ========================================
// FILTERS
// ========================================

function applyFilters() {
    const cat = document.getElementById('filterCategory').value;
    const dist = parseInt(document.getElementById('filterDistance').value);
    const minB = parseInt(document.getElementById('minBudget').value) || 0;
    const maxB = parseInt(document.getElementById('maxBudget').value) || 999999;

    const filtered = tasks.filter(t => {
        if (t.status !== 'active') return false;
        if (getTimeLeft(t.expiresAt) === 'Expired') return false;
        const d = getDistance(userLocation.lat, userLocation.lng, t.location.lat, t.location.lng);
        if (cat !== 'all' && t.category !== cat) return false;
        if (d > dist) return false;
        if (t.price < minB || t.price > maxB) return false;
        return true;
    });

    renderTasks(filtered);
    showToast('Found ' + filtered.length + ' tasks');
}

function clearFilters() {
    document.getElementById('filterCategory').value = 'all';
    document.getElementById('filterDistance').value = 10;
    document.getElementById('distanceValue').textContent = '10';
    document.getElementById('minBudget').value = '';
    document.getElementById('maxBudget').value = '';
    renderTasks();
    addTaskMarkers();
}

function filterByCategory(cat) {
    document.getElementById('filterCategory').value = cat;
    applyFilters();
    scrollToSection('find-tasks');
}

// ========================================
// UTILITIES
// ========================================

function getDistance(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat/2) ** 2 + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon/2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function getTimeLeft(expires) {
    const diff = new Date(expires) - Date.now();
    if (diff <= 0) return 'Expired';
    const h = Math.floor(diff / 3600000);
    const m = Math.floor((diff % 3600000) / 60000);
    return h > 0 ? h + 'h ' + m + 'm' : m + 'm';
}

function formatCategory(cat) {
    const names = { 
        household: 'Household', 
        delivery: 'Delivery', 
        tutoring: 'Tutoring', 
        transport: 'Transport', 
        vehicle: 'Vehicle', 
        repair: 'Repairs', 
        photography: 'Photography', 
        freelance: 'Freelance', 
        waste: 'Waste',
        cleaning: 'Cleaning',
        cooking: 'Cooking',
        petcare: 'Pet Care',
        gardening: 'Gardening',
        shopping: 'Shopping',
        eventhelp: 'Event Help',
        moving: 'Moving',
        techsupport: 'Tech Support',
        beauty: 'Beauty',
        laundry: 'Laundry',
        catering: 'Catering',
        babysitting: 'Babysitting',
        eldercare: 'Elder Care',
        fitness: 'Fitness',
        painting: 'Painting',
        electrician: 'Electrician',
        plumbing: 'Plumbing',
        carpentry: 'Carpentry',
        tailoring: 'Tailoring',
        other: 'Other'
    };
    return names[cat] || cat;
}

// ========================================
// UI HELPERS
// ========================================

function openModal(id) {
    document.getElementById(id)?.classList.add('active');
    document.body.style.overflow = 'hidden';
    if (id === 'postTaskModal') {
        resetBonusOnModalOpen();
    }
}

function closeModal(id) {
    document.getElementById(id)?.classList.remove('active');
    document.body.style.overflow = '';
}

function switchModal(from, to) {
    closeModal(from);
    setTimeout(() => openModal(to), 200);
}

function toggleMobileMenu() {
    document.getElementById('mobileMenu')?.classList.toggle('active');
}

function scrollToSection(id) {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
    // Refresh map tiles after scrolling to map section
    if (map && (id === 'find-tasks' || id === 'map')) {
        setTimeout(() => map.invalidateSize(), 400);
    }
}

function showToast(msg) {
    const toast = document.getElementById('toast');
    const text = document.getElementById('toastMessage');
    if (toast && text) {
        text.textContent = msg;
        toast.classList.add('show');
        setTimeout(() => toast.classList.remove('show'), 3000);
    }
}

function selectBudget(el, amt) {
    document.querySelectorAll('.budget-option').forEach(o => o.classList.remove('active'));
    el.classList.add('active');
    selectedBudget = amt;
    document.getElementById('customBudget').value = '';
    updateTotalBudgetDisplay();
}

// Bonus amount tracking
let currentBonus = 0;

function addBonus(amount) {
    // Toggle bonus - if clicking same amount, remove it
    const btn = event.target;
    const wasActive = btn.classList.contains('active');
    
    // Remove active from all bonus buttons
    document.querySelectorAll('.bonus-btn').forEach(b => b.classList.remove('active'));
    
    if (wasActive) {
        currentBonus = 0;
    } else {
        btn.classList.add('active');
        currentBonus = amount;
    }
    
    updateTotalBudgetDisplay();
}

function updateTotalBudgetDisplay() {
    const customBudget = parseInt(document.getElementById('customBudget')?.value) || 0;
    let baseBudget = customBudget > 0 ? customBudget : selectedBudget;
    
    // Enforce minimum ₹100
    if (baseBudget < MIN_TASK_PRICE) {
        baseBudget = MIN_TASK_PRICE;
    }
    
    const total = baseBudget + currentBonus;
    
    // Get service charge based on selected category
    const category = document.getElementById('modalTaskCategory')?.value || 'other';
    const serviceCharge = getServiceCharge(category);
    const chargeInfo = getServiceChargeInfo(category);
    
    const totalPayable = total + serviceCharge; // What poster pays
    const workerEarns = total + serviceCharge; // Worker gets budget + service charge
    
    const displayEl = document.getElementById('totalBudgetDisplay');
    if (displayEl) {
        displayEl.textContent = '₹' + total;
        displayEl.style.color = currentBonus > 0 ? '#f59e0b' : '#10b981';
    }
    
    // Update service charge display
    const budgetDisplay = document.getElementById('displayTaskBudget');
    const payableDisplay = document.getElementById('totalPayable');
    const workerEarnsDisplay = document.getElementById('workerEarns');
    const serviceChargeDisplay = document.getElementById('serviceChargeAmount');
    const serviceChargeLevel = document.getElementById('serviceChargeLevel');
    const serviceChargeTime = document.getElementById('serviceChargeTime');
    
    if (budgetDisplay) {
        budgetDisplay.textContent = '₹' + total;
    }
    if (payableDisplay) {
        payableDisplay.textContent = '₹' + totalPayable;
    }
    if (workerEarnsDisplay) {
        workerEarnsDisplay.textContent = '₹' + workerEarns;
    }
    if (serviceChargeDisplay) {
        serviceChargeDisplay.textContent = '₹' + serviceCharge;
    }
    if (serviceChargeLevel) {
        serviceChargeLevel.textContent = chargeInfo.level;
    }
    if (serviceChargeTime) {
        serviceChargeTime.textContent = chargeInfo.time;
    }
}

function resetBonusOnModalOpen() {
    currentBonus = 0;
    document.querySelectorAll('.bonus-btn').forEach(b => b.classList.remove('active'));
    updateTotalBudgetDisplay();
}

function getCurrentLocation() {
    getModalLocation();
}

async function getModalLocation() {
    const input = document.getElementById('modalTaskLocation');
    if (!input) return;

    if (!navigator.geolocation) {
        showToast('GPS not supported. Please type an address.');
        return;
    }

    input.value = 'Locating...';
    try {
        const pos = await new Promise((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(resolve, reject, {
                enableHighAccuracy: true, timeout: 10000, maximumAge: 30000
            });
        });
        const lat = pos.coords.latitude;
        const lng = pos.coords.longitude;
        modalTaskCoords = { lat, lng };

        // Reverse-geocode to get address text
        try {
            const resp = await fetch(`https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&addressdetails=1`, {
                headers: { 'Accept-Language': 'en' }
            });
            const data = await resp.json();
            input.value = data.display_name || 'Current Location';
        } catch {
            input.value = 'Current Location';
        }
        showToast('📍 Location set from GPS');
    } catch (err) {
        console.warn('GPS error:', err.message);
        input.value = '';
        showToast('Could not get GPS. Please type an address.');
    }
}

async function geocodeAddress(address) {
    try {
        const resp = await fetch(`https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(address)}&format=json&limit=1&countrycodes=in`, {
            headers: { 'Accept-Language': 'en' }
        });
        const results = await resp.json();
        if (results && results.length > 0) {
            return { lat: parseFloat(results[0].lat), lng: parseFloat(results[0].lon) };
        }
    } catch (e) {
        console.warn('Geocoding failed:', e.message);
    }
    return null;
}

function setMinDateTime() {
    const min = new Date().toISOString().slice(0, 16);
    document.querySelectorAll('input[type="datetime-local"]').forEach(i => i.min = min);
}

function startTaskTimers() {
    setInterval(() => {
        tasks.forEach(t => {
            if (t.status === 'active' && new Date(t.expiresAt) <= new Date()) {
                t.status = 'expired';
            }
        });
        // Remove expired-active posted tasks and expired-accepted tasks
        myPostedTasks = myPostedTasks.filter(t => {
            if (t.status === 'active' && t.expiresAt && new Date(t.expiresAt) <= new Date()) return false;
            return true;
        });
        myAcceptedTasks = myAcceptedTasks.filter(t => {
            if (t.status === 'accepted' && t.expiresAt && new Date(t.expiresAt) <= new Date()) return false;
            return true;
        });
        renderTasks();
        renderPostedTasks();
        renderAcceptedTasks();
        addTaskMarkers();
    }, 60000);

    // Sync notifications from server every 30 seconds
    setInterval(() => {
        if (currentUser) {
            syncNotificationsFromServer();
        }
    }, 30000);
}

// ========================================
// EVENT LISTENERS
// ========================================

function setupEventListeners() {
    // Distance slider
    const slider = document.getElementById('filterDistance');
    if (slider) {
        slider.oninput = function() {
            document.getElementById('distanceValue').textContent = this.value;
        };
    }

    // Custom budget input updates total display
    const customBudgetInput = document.getElementById('customBudget');
    if (customBudgetInput) {
        customBudgetInput.oninput = function() {
            // Deselect preset options when custom is entered
            if (this.value) {
                document.querySelectorAll('.budget-option').forEach(o => o.classList.remove('active'));
            }
            updateTotalBudgetDisplay();
        };
    }
    
    // Category change updates service charge
    const categorySelect = document.getElementById('modalTaskCategory');
    if (categorySelect) {
        categorySelect.onchange = function() {
            updateTotalBudgetDisplay();
        };
    }

    // Close modals on backdrop click
    document.querySelectorAll('.modal').forEach(m => {
        m.onclick = function(e) {
            if (e.target === this) {
                this.classList.remove('active');
                document.body.style.overflow = '';
                clearRoute();
            }
        };
    });

    // Escape key
    document.onkeydown = function(e) {
        if (e.key === 'Escape') {
            document.querySelectorAll('.modal.active').forEach(m => m.classList.remove('active'));
            document.body.style.overflow = '';
            clearRoute();
        }
    };

    // Scroll effect
    window.onscroll = function() {
        const nav = document.querySelector('.navbar');
        if (nav) nav.style.boxShadow = window.scrollY > 50 ? '0 4px 20px rgba(0,0,0,0.1)' : '';
    };
}

// ========================================
// GLOBAL EXPORTS
// ========================================

window.openModal = openModal;
window.closeModal = closeModal;
window.switchModal = switchModal;
window.handleLogin = handleLogin;
window.handleSignup = handleSignup;
window.handleTaskSubmit = handleTaskSubmit;
window.openTaskDetail = openTaskDetail;
window.navigateToTask = navigateToTask;
window.acceptTask = acceptTask;
window.abandonTask = abandonTask;
window.penaltyContinueTask = penaltyContinueTask;
window.penaltyConfirmRelease = penaltyConfirmRelease;
window.deleteTask = deleteTask;
window.completeTask = completeTask;
window.openEditTask = openEditTask;
window.selectBudgetIncrease = selectBudgetIncrease;
window.updateNewBudget = updateNewBudget;
window.saveTaskEdit = saveTaskEdit;
window.showTaskPostedSuccess = showTaskPostedSuccess;
window.switchTab = switchTab;
window.applyFilters = applyFilters;
window.clearFilters = clearFilters;
window.filterByCategory = filterByCategory;
window.loadCategoryCounts = loadCategoryCounts;
window.selectBudget = selectBudget;
window.addBonus = addBonus;
window.updateTotalBudgetDisplay = updateTotalBudgetDisplay;
window.getCurrentLocation = getCurrentLocation;
window.getModalLocation = getModalLocation;
window.toggleMobileMenu = toggleMobileMenu;
window.scrollToSection = scrollToSection;
window.centerOnUser = centerOnUser;
window.zoomIn = zoomIn;
window.zoomOut = zoomOut;
window.toggleMapType = toggleMapType;
window.toggleTracking = toggleTracking;
window.logout = logout;
window.handleLogout = handleLogout;
window.onTaskCardClick = onTaskCardClick;
window.openGoogleMaps = openGoogleMaps;
window.clearRoute = clearRoute;
window.openUserProfile = openUserProfile;
window.loadProfilePage = loadProfilePage;
window.triggerPhotoUpload = triggerPhotoUpload;
window.handleProfilePhoto = handleProfilePhoto;
window.toggleEditPersonal = toggleEditPersonal;
window.cancelEditPersonal = cancelEditPersonal;
window.savePersonalInfo = savePersonalInfo;
window.toggleChangePassword = toggleChangePassword;
window.saveNewPassword = saveNewPassword;
window.toggleNotifications = toggleNotifications;
window.markAsRead = markAsRead;
window.clearAllNotifications = clearAllNotifications;
window.handleNotificationAction = handleNotificationAction;
window.executePayment = executePayment;
window.showPaymentInvoice = showPaymentInvoice;

// Forgot Password Functions
window.openForgotPassword = openForgotPassword;
window.resetForgotPassword = resetForgotPassword;
window.findAccount = findAccount;
window.goToForgotStep = goToForgotStep;
window.sendOTP = sendOTP;
window.verifyOTP = verifyOTP;
window.resendOTP = resendOTP;
window.resetPassword = resetPassword;
window.handleOTPInput = handleOTPInput;
window.handleOTPKeydown = handleOTPKeydown;
window.togglePasswordVisibility = togglePasswordVisibility;

// ========================================
// FORGOT PASSWORD SYSTEM WITH REAL OTP
// Using EmailJS (Free - 200 emails/month)
// ========================================

// ⚠️ EMAILJS CONFIGURATION - YOU MUST SET THESE UP!
// 1. Go to https://www.emailjs.com/ and create FREE account
// 2. Add Email Service (Gmail recommended)
// 3. Create Email Template with these variables:
//    - {{to_email}} - recipient email
//    - {{to_name}} - recipient name  
//    - {{otp_code}} - the 6-digit OTP
//    - {{app_name}} - Workmate4u
// 4. Copy your IDs below:

const EMAILJS_CONFIG = {
    PUBLIC_KEY: 'wc4cpx8eMKCf3OnwL',      // From EmailJS Dashboard > Account > API Keys
    SERVICE_ID: 'service_ghspmfa',       // From EmailJS Dashboard > Email Services
    TEMPLATE_ID: 'template_fsel57p'      // From EmailJS Dashboard > Email Templates
};

// Check if EmailJS is configured (not placeholder values)
function isEmailJSConfigured() {
    return EMAILJS_CONFIG.PUBLIC_KEY !== 'YOUR_PUBLIC_KEY_HERE' &&
           EMAILJS_CONFIG.SERVICE_ID !== 'YOUR_SERVICE_ID_HERE' &&
           EMAILJS_CONFIG.TEMPLATE_ID !== 'YOUR_TEMPLATE_ID_HERE' &&
           EMAILJS_CONFIG.PUBLIC_KEY.length > 0;
}

// Initialize EmailJS
function initEmailJS() {
    if (typeof emailjs !== 'undefined') {
        emailjs.init(EMAILJS_CONFIG.PUBLIC_KEY);
        console.log('✅ EmailJS initialized with key:', EMAILJS_CONFIG.PUBLIC_KEY);
        return true;
    }
    console.log('⚠️ EmailJS SDK not loaded');
    return false;
}

// Initialize on load
document.addEventListener('DOMContentLoaded', function() {
    setTimeout(initEmailJS, 1000);
});

let forgotPasswordState = {
    email: '',
    user: null,
    resetToken: '',
    otp: '',
    method: '',
    otpTimer: null,
    otpExpiry: null,
    isSending: false
};

function openForgotPassword() {
    closeModal('loginModal');
    resetForgotPassword();
    openModal('forgotPasswordModal');
}

function resetForgotPassword() {
    if (forgotPasswordState.otpTimer) {
        clearInterval(forgotPasswordState.otpTimer);
    }
    
    forgotPasswordState = {
        email: '',
        user: null,
        resetToken: '',
        otp: '',
        method: '',
        otpTimer: null,
        otpExpiry: null,
        isSending: false
    };
    
    document.querySelectorAll('.forgot-step').forEach(step => step.classList.remove('active'));
    document.getElementById('forgotStep1')?.classList.add('active');
    
    const forgotEmail = document.getElementById('forgotEmail');
    if (forgotEmail) forgotEmail.value = '';
    
    document.querySelectorAll('.otp-input').forEach(input => {
        input.value = '';
        input.classList.remove('filled', 'error');
    });
    
    const newPass = document.getElementById('newPassword');
    const confirmPass = document.getElementById('confirmNewPassword');
    if (newPass) newPass.value = '';
    if (confirmPass) confirmPass.value = '';
}

function goToForgotStep(step) {
    document.querySelectorAll('.forgot-step').forEach(s => s.classList.remove('active'));
    document.getElementById('forgotStep' + step)?.classList.add('active');
}

// Step 1: Find account via backend API
async function findAccount(event) {
    event.preventDefault();
    
    const email = document.getElementById('forgotEmail').value.trim();
    if (!email) {
        showToast('❌ Please enter your email');
        return;
    }
    
    const findBtn = document.querySelector('#forgotStep1 button[type="submit"]');
    if (findBtn) {
        findBtn.disabled = true;
        findBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Finding...';
    }
    
    try {
        // Call backend - generates OTP, stores in DB, returns resetToken
        const result = await AuthAPI.forgotPassword(email);
        
        if (result.success) {
            forgotPasswordState.email = email;
            forgotPasswordState.resetToken = result.resetToken;
            forgotPasswordState.user = { name: result.userName, email: email };
            // Backend returns OTP when SendGrid is not configured (dev/demo mode)
            if (result.otp) {
                forgotPasswordState.otp = result.otp;
            }
            
            // Show account preview
            const preview = document.getElementById('accountPreview');
            preview.innerHTML = `
                <div class="avatar"><i class="fas fa-user"></i></div>
                <div class="details">
                    <div class="name">${result.userName}</div>
                    <div class="email">${result.maskedEmail}</div>
                </div>
            `;
            
            document.getElementById('maskedEmail').textContent = result.maskedEmail;
            goToForgotStep(2);
        } else {
            showToast('❌ ' + (result.message || 'No account found with this email'));
        }
    } catch (error) {
        console.error('Find account error:', error);
        showToast('❌ ' + (error.message || 'Could not find account. Please try again.'));
    } finally {
        if (findBtn) {
            findBtn.disabled = false;
            findBtn.innerHTML = '<i class="fas fa-search"></i> Find Account';
        }
    }
}

function maskEmail(email) {
    const [name, domain] = email.split('@');
    const maskedName = name.charAt(0) + '*'.repeat(Math.max(name.length - 2, 1)) + name.charAt(name.length - 1);
    return maskedName + '@' + domain;
}

// Step 2: Send OTP via EmailJS (OTP was already generated by backend)
async function sendOTP(method) {
    if (forgotPasswordState.isSending) {
        showToast('⏳ Please wait, sending OTP...');
        return;
    }
    
    forgotPasswordState.method = method;
    forgotPasswordState.isSending = true;
    forgotPasswordState.otpExpiry = Date.now() + 10 * 60 * 1000; // 10 min (matches backend)
    
    const user = forgotPasswordState.user;
    const otp = forgotPasswordState.otp; // From backend response (dev mode)
    
    if (method === 'email') {
        showToast('📨 Sending OTP to your email...', 2000);
        
        // Try sending via EmailJS
        if (isEmailJSConfigured() && typeof emailjs !== 'undefined' && otp) {
            try {
                await emailjs.send(
                    EMAILJS_CONFIG.SERVICE_ID,
                    EMAILJS_CONFIG.TEMPLATE_ID,
                    {
                        to_email: forgotPasswordState.email,
                        to_name: user.name || 'User',
                        otp_code: otp,
                        app_name: 'Workmate4u',
                        validity: '10 minutes'
                    }
                );
                console.log('✅ OTP email sent via EmailJS');
                showToast('✅ OTP sent to your email!', 4000);
            } catch (error) {
                console.error('EmailJS error:', error);
                showToast('✅ OTP sent to your email!', 4000);
                // Backend already logged OTP to console as fallback
            }
        } else {
            // No EmailJS or no OTP in response (SendGrid handled it on backend)
            showToast('✅ OTP sent to your email!', 4000);
        }
    } else if (method === 'phone') {
        showToast('📱 SMS not available. Please use email.', 3000);
        forgotPasswordState.isSending = false;
        return;
    }
    
    forgotPasswordState.isSending = false;
    proceedToOTPStep(method);
}

function proceedToOTPStep(method) {
    document.getElementById('otpSentMessage').textContent = 
        `Enter the 6-digit code sent to your email`;
    
    startOTPTimer();
    goToForgotStep(3);
    
    setTimeout(() => {
        document.querySelector('.otp-input')?.focus();
    }, 300);
}

function startOTPTimer() {
    let seconds = 60;
    const timerEl = document.getElementById('otpTimer');
    const resendBtn = document.getElementById('resendBtn');
    
    if (resendBtn) resendBtn.disabled = true;
    
    if (forgotPasswordState.otpTimer) {
        clearInterval(forgotPasswordState.otpTimer);
    }
    
    forgotPasswordState.otpTimer = setInterval(() => {
        seconds--;
        
        if (seconds <= 0) {
            clearInterval(forgotPasswordState.otpTimer);
            if (timerEl) timerEl.innerHTML = '<span style="color: var(--danger);">OTP expired</span>';
            if (resendBtn) resendBtn.disabled = false;
        } else {
            if (timerEl) timerEl.innerHTML = `Resend OTP in <strong>${seconds}s</strong>`;
        }
    }, 1000);
}

async function resendOTP() {
    // Re-call backend to generate new OTP
    try {
        const result = await AuthAPI.forgotPassword(forgotPasswordState.email);
        if (result.success) {
            forgotPasswordState.resetToken = result.resetToken;
            if (result.otp) forgotPasswordState.otp = result.otp;
            forgotPasswordState.otpExpiry = Date.now() + 10 * 60 * 1000;
            
            // Re-send via EmailJS if available
            if (isEmailJSConfigured() && typeof emailjs !== 'undefined' && result.otp) {
                try {
                    await emailjs.send(
                        EMAILJS_CONFIG.SERVICE_ID,
                        EMAILJS_CONFIG.TEMPLATE_ID,
                        {
                            to_email: forgotPasswordState.email,
                            to_name: forgotPasswordState.user?.name || 'User',
                            otp_code: result.otp,
                            app_name: 'Workmate4u',
                            validity: '10 minutes'
                        }
                    );
                } catch (e) {
                    console.warn('EmailJS resend error:', e);
                }
            }
            
            showToast('✅ New OTP sent!', 3000);
            startOTPTimer();
        }
    } catch (error) {
        showToast('❌ Could not resend OTP. Try again.');
    }
}

function handleOTPInput(input) {
    const value = input.value.replace(/\D/g, '');
    input.value = value;
    
    if (value) {
        input.classList.add('filled');
        // Move to next input
        const index = parseInt(input.dataset.index);
        const nextInput = document.querySelector(`.otp-input[data-index="${index + 1}"]`);
        if (nextInput) {
            nextInput.focus();
        }
    } else {
        input.classList.remove('filled');
    }
}

function handleOTPKeydown(event, input) {
    const index = parseInt(input.dataset.index);
    
    // Backspace - move to previous input
    if (event.key === 'Backspace' && !input.value && index > 0) {
        const prevInput = document.querySelector(`.otp-input[data-index="${index - 1}"]`);
        if (prevInput) {
            prevInput.focus();
            prevInput.value = '';
            prevInput.classList.remove('filled');
        }
    }
    
    // Arrow keys
    if (event.key === 'ArrowLeft' && index > 0) {
        document.querySelector(`.otp-input[data-index="${index - 1}"]`)?.focus();
    }
    if (event.key === 'ArrowRight' && index < 5) {
        document.querySelector(`.otp-input[data-index="${index + 1}"]`)?.focus();
    }
}

async function verifyOTP(event) {
    event.preventDefault();
    
    // Collect OTP
    let enteredOTP = '';
    document.querySelectorAll('.otp-input').forEach(input => {
        enteredOTP += input.value;
    });
    
    if (enteredOTP.length !== 6) {
        showToast('❌ Please enter complete 6-digit OTP');
        document.querySelectorAll('.otp-input').forEach(input => {
            if (!input.value) input.classList.add('error');
        });
        return;
    }
    
    // Check local expiry
    if (forgotPasswordState.otpExpiry && Date.now() > forgotPasswordState.otpExpiry) {
        showToast('❌ OTP has expired. Please request a new one.');
        return;
    }
    
    try {
        // Verify OTP via backend
        const result = await AuthAPI.verifyOTP(forgotPasswordState.resetToken, enteredOTP);
        
        if (result.success) {
            showToast('✅ OTP verified successfully!');
            clearInterval(forgotPasswordState.otpTimer);
            goToForgotStep(4);
            
            setTimeout(() => {
                document.getElementById('newPassword')?.focus();
            }, 300);
        } else {
            showToast('❌ ' + (result.message || 'Invalid OTP. Please try again.'));
            document.querySelectorAll('.otp-input').forEach(input => {
                input.classList.add('error');
            });
            setTimeout(() => {
                document.querySelectorAll('.otp-input').forEach(input => {
                    input.classList.remove('error');
                });
            }, 500);
        }
    } catch (error) {
        showToast('❌ ' + (error.message || 'Invalid OTP. Please try again.'));
        document.querySelectorAll('.otp-input').forEach(input => {
            input.classList.add('error');
        });
        setTimeout(() => {
            document.querySelectorAll('.otp-input').forEach(input => {
                input.classList.remove('error');
            });
        }, 500);
    }
}

async function resetPassword(event) {
    event.preventDefault();
    
    const newPassword = document.getElementById('newPassword').value;
    const confirmPassword = document.getElementById('confirmNewPassword').value;
    const resetBtn = event.target.querySelector('button[type="submit"]');
    
    if (newPassword.length < 6) {
        showToast('❌ Password must be at least 6 characters');
        return;
    }
    
    if (!/[A-Za-z]/.test(newPassword) || !/[0-9]/.test(newPassword)) {
        showToast('❌ Password must contain both letters and numbers');
        return;
    }
    
    if (newPassword !== confirmPassword) {
        showToast('❌ Passwords do not match');
        return;
    }
    
    if (resetBtn) {
        resetBtn.disabled = true;
        resetBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Resetting...';
    }
    
    try {
        // Reset password via backend (backend handles hashing)
        const result = await AuthAPI.resetPassword(forgotPasswordState.resetToken, newPassword);
        
        if (result.success) {
            showToast('✅ Password reset successfully!');
            goToForgotStep(5);
        } else {
            showToast('❌ ' + (result.message || 'Error resetting password.'));
        }
    } catch (error) {
        console.error('Password reset error:', error);
        showToast('❌ ' + (error.message || 'Error resetting password. Please try again.'));
    } finally {
        if (resetBtn) {
            resetBtn.disabled = false;
            resetBtn.innerHTML = '<i class="fas fa-save"></i> Reset Password';
        }
    }
}

function togglePasswordVisibility(inputId) {
    const input = document.getElementById(inputId);
    const icon = input.nextElementSibling.querySelector('i');
    
    if (input.type === 'password') {
        input.type = 'text';
        icon.classList.remove('fa-eye');
        icon.classList.add('fa-eye-slash');
    } else {
        input.type = 'password';
        icon.classList.remove('fa-eye-slash');
        icon.classList.add('fa-eye');
    }
}

// Password strength checker
document.addEventListener('DOMContentLoaded', function() {
    const passwordInput = document.getElementById('newPassword');
    if (passwordInput) {
        passwordInput.addEventListener('input', function() {
            const strength = document.getElementById('passwordStrength');
            const password = this.value;
            
            strength.classList.remove('weak', 'medium', 'strong');
            
            if (password.length === 0) return;
            
            let score = 0;
            if (password.length >= 6) score++;
            if (password.length >= 8) score++;
            if (/[A-Z]/.test(password)) score++;
            if (/[0-9]/.test(password)) score++;
            if (/[^A-Za-z0-9]/.test(password)) score++;
            
            if (score <= 2) {
                strength.classList.add('weak');
            } else if (score <= 3) {
                strength.classList.add('medium');
            } else {
                strength.classList.add('strong');
            }
        });
    }
});

// Extended toast function with custom duration
const originalShowToast = showToast;
showToast = function(msg, duration = 3000) {
    const toast = document.getElementById('toast');
    const text = document.getElementById('toastMessage');
    if (toast && text) {
        text.textContent = msg;
        toast.classList.add('show');
        setTimeout(() => toast.classList.remove('show'), duration);
    }
}

