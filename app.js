// ========================================
// TaskEarn India - Task Marketplace
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
let selectedBudget = 50; // Default budget
const MIN_TASK_PRICE = 50; // Minimum ₹50 per task
let selectedTask = null;
let gpsWatchId = null;
let isGPSActive = false;

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
    CURRENT_USER: 'taskearn_current_user',
    USER_TASKS: 'taskearn_user_tasks'
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

// Initialize IndexedDB on load
initIndexedDB().then(dbAvailable => {
    if (!STORAGE_AVAILABLE && !dbAvailable) {
        alert('⚠️ Warning: Your browser cannot save data. Please:\n\n1. Use http://localhost:8080 (not file://)\n2. Disable private/incognito mode\n3. Allow cookies and site data\n\nYour account will NOT be saved!');
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
    if (users[userId]) {
        users[userId] = { ...users[userId], ...updates };
        await saveUsersAsync(users);
        
        // Update current user if logged in
        if (currentUser && currentUser.id === userId) {
            currentUser = users[userId];
            saveCurrentSession(currentUser);
        }
        return users[userId];
    }
    return null;
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

// Clear current session (logout only, keeps account data)
function clearCurrentSession() {
    if (!STORAGE_AVAILABLE) return;
    try {
        // Clear local session
        localStorage.removeItem(STORAGE_KEYS.CURRENT_USER);
        // Clear API session (token + user)
        localStorage.removeItem('taskearn_token');
        localStorage.removeItem('taskearn_user');
        console.log('✅ Session cleared (account data preserved)');
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

// Make debug functions available in console
window.resetUserPassword = resetUserPassword;
window.debugListUsers = debugListUsers;

// Serialize task for storage (convert dates to ISO strings, remove circular refs)
function serializeTask(task) {
    return {
        id: task.id,
        title: task.title,
        description: task.description,
        category: task.category,
        location: task.location,
        price: task.price,
        postedBy: task.postedBy ? {
            name: task.postedBy.name,
            rating: task.postedBy.rating,
            tasksPosted: task.postedBy.tasksPosted
        } : null,
        postedAt: task.postedAt instanceof Date ? task.postedAt.toISOString() : task.postedAt,
        expiresAt: task.expiresAt instanceof Date ? task.expiresAt.toISOString() : task.expiresAt,
        acceptedAt: task.acceptedAt || null,
        completedAt: task.completedAt || null,
        status: task.status
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
let notifications = [];

// ========================================
// NOTIFICATION SYSTEM
// ========================================

function loadNotifications() {
    if (!currentUser) return [];
    const saved = localStorage.getItem(`notifications_${currentUser.id}`);
    return saved ? JSON.parse(saved) : [];
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
            list.innerHTML = notifications.slice(0, 20).map(n => `
                <div class="notification-item ${n.read ? '' : 'unread'}" onclick="markAsRead(${n.id})">
                    <div class="notification-icon ${n.type || 'info'}">
                        <i class="fas ${getNotificationIcon(n.type)}"></i>
                    </div>
                    <div class="notification-content">
                        <h5>${escapeHtml(n.title)}</h5>
                        <p>${escapeHtml(n.message)}</p>
                        <span class="notification-time">${getTimeAgo(n.createdAt)}</span>
                    </div>
                </div>
            `).join('');
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
    if (dropdown) {
        dropdown.classList.toggle('active');
    }
}

function markAsRead(notifId) {
    const notif = notifications.find(n => n.id === notifId);
    if (notif) {
        notif.read = true;
        saveNotifications();
        updateNotificationUI();
    }
}

function clearAllNotifications() {
    notifications = [];
    saveNotifications();
    updateNotificationUI();
    showToast('All notifications cleared');
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
            app_name: 'TaskEarn',
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

// Update map markers when tasks change
function updateMapMarkers() {
    if (!map) return;
    
    // Clear existing markers
    taskMarkers.forEach(marker => marker.remove());
    taskMarkers = [];
    
    // Add markers for active tasks
    tasks.filter(t => t.status === 'active').forEach(task => {
        if (task.location && task.location.lat && task.location.lng) {
            const marker = L.marker([task.location.lat, task.location.lng], {
                icon: L.divIcon({
                    className: 'task-marker',
                    html: `<div class="marker-pin" style="background: var(--primary-gradient)"><i class="fas fa-tasks"></i></div>`,
                    iconSize: [30, 42],
                    iconAnchor: [15, 42]
                })
            }).addTo(map);
            
            marker.bindPopup(`
                <div class="task-popup">
                    <h4>${task.title}</h4>
                    <p>${task.description}</p>
                    <span class="task-price">₹${task.price}</span>
                </div>
            `);
            
            taskMarkers.push(marker);
        }
    });
}

// Load tasks from backend API (PRODUCTION ONLY - NO LOCAL FALLBACKS)
async function loadTasksFromServer() {
    try {
        console.log('📡 Loading tasks from production server...');
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
                
                console.log('✅ Loaded', serverTasks.length, 'tasks from production server');
                console.log('📋 Total tasks now:', tasks.length);
                renderTasks();
                updateMapMarkers();
                return true;
            } else {
                console.error('❌ PRODUCTION ERROR: Server returned success=false');
                console.error('Result:', result);
                showNotification('❌ Cannot load tasks from production server. Backend error.', 'error');
                tasks = [];
                renderTasks();
                return false;
            }
        } else {
            console.error('❌ PRODUCTION ERROR: TasksAPI not available');
            showNotification('❌ Production API not configured. Please contact support.', 'error');
            return false;
        }
    } catch (error) {
        console.error('❌ PRODUCTION ERROR - Cannot connect to backend:', error);
        showNotification('❌ Cannot connect to production server. Check your internet connection.', 'error');
        tasks = [];
        renderTasks();
        return false;
    }
}

document.addEventListener('DOMContentLoaded', async function() {
    console.log('🚀 TaskEarn Starting...');
    console.log('📦 localStorage available:', STORAGE_AVAILABLE);
    console.log('🔑 API Token:', localStorage.getItem('taskearn_token') ? 'EXISTS (✅)' : 'MISSING (❌)');
    console.log('🌐 Backend URL:', window.TASKEARN_API_URL);
    console.log('🔌 TasksAPI available:', typeof TasksAPI !== 'undefined' ? 'YES (✅)' : 'NO (❌)');
    console.log('🔌 AuthAPI available:', typeof AuthAPI !== 'undefined' ? 'YES (✅)' : 'NO (❌)');
    
    // Wait for IndexedDB to initialize
    await initIndexedDB();
    
    // Initialize Push Notifications
    initPushNotifications();
    
    // Debug: Show all stored users (using async version for full support)
    const allUsers = await getStoredUsersAsync();
    console.log('👥 Registered users:', Object.keys(allUsers).length);
    
    // List registered user emails for debugging
    if (Object.keys(allUsers).length > 0) {
        console.log('📧 Registered emails:', Object.values(allUsers).map(u => u.email));
    }
    
    // Check for existing session (using async version)
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
                const banner = document.getElementById('migrationWarningBanner');
                if (banner) {
                    banner.style.display = 'block';
                }
                console.warn('📢 User needs to re-login to migrate to backend');
            }, 2000);
        }
        
        setTimeout(() => {
            updateNavForUser();
            renderDashboard();
        }, 100);
    } else {
        console.log('👤 No active session - user needs to login');
    }
    
    // Initialize map first
    initializeMap();
    
    // Setup UI
    setupEventListeners();
    setMinDateTime();
    
    // Load tasks from server (replaces demo tasks)
    await loadTasksFromServer();
    
    // Fallback render if server load failed
    renderTasks();
    startTaskTimers();
    
    // Refresh tasks from server every 30 seconds
    setInterval(loadTasksFromServer, 30000);
    
    console.log('✅ TaskEarn Ready!');
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
                showLocalNotification('TaskEarn', 'Notifications enabled! You\'ll be notified about task updates.');
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

// Notification helpers for different events
function notifyTaskAccepted(task, helperName) {
    showLocalNotification(
        '🎉 Task Accepted!',
        `${helperName} has accepted your task: ${task.title}`,
        { tag: 'task-accepted', url: `chat.html?task=${task.id}` }
    );
}

function notifyNewMessage(senderName, taskTitle) {
    showLocalNotification(
        '💬 New Message',
        `${senderName}: New message about ${taskTitle}`,
        { tag: 'new-message', url: 'chat.html' }
    );
}

function notifyTaskCompleted(task) {
    showLocalNotification(
        '✅ Task Completed!',
        `Your task "${task.title}" has been completed. Please rate the helper.`,
        { tag: 'task-completed' }
    );
}

function notifyNearbyTask(task, distance) {
    showLocalNotification(
        '📍 New Task Nearby!',
        `${task.title} - ₹${task.price} (${distance}km away)`,
        { tag: 'nearby-task-' + task.id }
    );
}

function notifyPaymentReceived(amount, taskTitle) {
    showLocalNotification(
        '💰 Payment Received!',
        `₹${amount} added to your wallet for: ${taskTitle}`,
        { tag: 'payment-received', url: 'wallet.html' }
    );
}

// ========================================
// MAP INITIALIZATION
// ========================================

function initializeMap() {
    try {
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

        console.log('✅ Map initialized');

        // Add task markers
        addTaskMarkers();

        // Try to get user location
        getUserLocation();

    } catch (error) {
        console.error('❌ Map error:', error);
        showToast('Map loading error. Please refresh.');
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
    const isSecure = location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1';
    
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
    // Clear old markers
    taskMarkers.forEach(m => {
        if (map.hasLayer(m)) map.removeLayer(m);
    });
    taskMarkers = [];

    // Add markers for active tasks
    tasks.filter(t => t.status === 'active').forEach(task => {
        const icon = getTaskIcon(task.category);
        const marker = L.marker([task.location.lat, task.location.lng], { icon }).addTo(map);

        // Popup content
        const dist = getDistance(userLocation.lat, userLocation.lng, task.location.lat, task.location.lng);
        const timeLeft = getTimeLeft(task.expiresAt);

        marker.bindPopup(`
            <div style="min-width:200px;padding:5px;">
                <h4 style="margin:0 0 8px 0;font-size:14px;">${task.title}</h4>
                <p style="margin:0 0 10px 0;font-size:12px;color:#666;">${task.description.substring(0, 60)}...</p>
                <div style="display:flex;justify-content:space-between;margin-bottom:8px;">
                    <span style="color:#10b981;font-weight:700;">₹${task.price}</span>
                    <span style="color:#666;font-size:12px;">📍 ${dist.toFixed(1)} km</span>
                </div>
                <div style="color:#f59e0b;font-size:12px;margin-bottom:10px;">⏱️ ${timeLeft} left</div>
                <button onclick="openTaskDetail(${task.id})" style="width:100%;padding:8px;background:linear-gradient(135deg,#6366f1,#0ea5e9);color:white;border:none;border-radius:6px;cursor:pointer;font-weight:600;">View Details</button>
            </div>
        `, { maxWidth: 280 });

        marker.on('click', function() {
            selectedTask = task;
            highlightTaskCard(task.id);
            showRouteTo(task);
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
    const serviceCharge = getServiceCharge(task.category);
    const totalEarnings = task.price + serviceCharge;
    const chargeInfo = getServiceChargeInfo(task.category);
    
    if (panel) {
        panel.innerHTML = `
            <h4>📍 Distance & Earnings</h4>
            <div class="distance-value">${km} km</div>
            <div class="eta">~${mins} min drive</div>
            <div class="price-info">
                <div class="total-price">Earn: <strong>₹${totalEarnings}</strong></div>
                <small style="color:#10b981;">₹${task.price} + ₹${serviceCharge} (${chargeInfo.level})</small>
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

function renderTasks(filtered = null) {
    const container = document.getElementById('tasksList');
    if (!container) return;

    // Filter: Show only active tasks (hide completed, paid, cancelled)
    let list = filtered || tasks.filter(t => {
        return t.status === 'active' || t.status === 'pending_payment';
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
                <p>Try adjusting your filters</p>
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
    const task = tasks.find(t => t.id === taskId);
    if (!task || !map) return;

    highlightTaskCard(taskId);
    map.setView([task.location.lat, task.location.lng], 15);

    // Open popup
    const idx = tasks.filter(t => t.status === 'active').findIndex(t => t.id === taskId);
    if (idx >= 0 && taskMarkers[idx]) {
        taskMarkers[idx].openPopup();
    }

    selectedTask = task;
    showRouteTo(task);
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
    const task = tasks.find(t => t.id === taskId);
    if (!task) return;

    const dist = getDistance(userLocation.lat, userLocation.lng, task.location.lat, task.location.lng);
    const timeLeft = getTimeLeft(task.expiresAt);
    
    // Check if current user is the task owner
    const isOwner = currentUser && task.postedBy && task.postedBy.id === currentUser.id;

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
            <button class="btn btn-outline" onclick="closeModal('taskDetailModal'); clearRoute();">
                <i class="fas fa-times"></i> Close
            </button>
            ${!isOwner ? `
            <button class="btn btn-secondary" style="background: #0ea5e9; border: none;" onclick="contactTaskProvider(${task.id}, '${task.postedBy.name.replace(/'/g, "\\'")}')" title="Message the task provider">
                <i class="fas fa-comment-dots"></i> Contact Provider
            </button>
            <button class="btn btn-primary" onclick="acceptTask(${task.id})">
                <i class="fas fa-check"></i> Accept Task
            </button>
            ` : ''}
        </div>
    `;

    document.getElementById('taskDetailContent').innerHTML = content;
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

// ========================================
// TASK ACTIONS
// ========================================

function acceptTask(taskId) {
    if (!currentUser) {
        showToast('Please login first');
        closeModal('taskDetailModal');
        openModal('loginModal');
        return;
    }

    const task = tasks.find(t => t.id === taskId);
    if (task && currentUser) {
        task.status = 'accepted';
        task.acceptedBy = currentUser;
        task.acceptedAt = new Date().toISOString();
        myAcceptedTasks.push(task);

        // Save to user storage (serialize for localStorage)
        updateUserData(currentUser.id, {
            acceptedTasks: serializeTasks(myAcceptedTasks)
        });

        // 🔔 Notify the task poster (in-app + email)
        notifyTaskPoster(task, currentUser);

        showToast('✅ Task accepted: ' + task.title);
        closeModal('taskDetailModal');
        clearRoute();
        renderTasks();
        addTaskMarkers();
        
        // ✅ FIX: Update profile display after task acceptance
        setTimeout(() => {
            renderDashboard();
            if (currentUser) {
                openUserProfile();
            }
        }, 300);
    }
}

function contactTaskProvider(taskId, providerName) {
    if (!currentUser) {
        showToast('Please login first to contact provider');
        closeModal('taskDetailModal');
        openModal('loginModal');
        return;
    }

    const task = tasks.find(t => t.id === taskId);
    if (task && task.postedBy) {
        // Redirect to chat page with provider ID
        const providerId = task.postedBy.id;
        window.location.href = `chat.html?provider=${providerId}&task=${taskId}&taskTitle=${encodeURIComponent(task.title)}`;
    }
}

function cancelTask(taskId) {
    const idx = myPostedTasks.findIndex(t => t.id === taskId);
    if (idx >= 0 && currentUser) {
        myPostedTasks[idx].status = 'cancelled';
        tasks = tasks.filter(t => t.id !== taskId);
        myPostedTasks = myPostedTasks.filter(t => t.id !== taskId);

        // Update storage
        updateUserData(currentUser.id, {
            postedTasks: serializeTasks(myPostedTasks)
        });

        showToast('Task cancelled');
        renderTasks();
        addTaskMarkers();
        renderDashboard();
    }
}

function deleteTask(taskId) {
    if (confirm('Delete this task?') && currentUser) {
        tasks = tasks.filter(t => t.id !== taskId);
        myPostedTasks = myPostedTasks.filter(t => t.id !== taskId);

        // Update storage
        updateUserData(currentUser.id, {
            postedTasks: serializeTasks(myPostedTasks)
        });

        showToast('Task deleted');
        closeModal('taskDetailModal');
        renderTasks();
        addTaskMarkers();
        renderDashboard();
    }
}

// Edit Task Functions
let editTaskState = {
    taskId: null,
    originalBudget: 0,
    budgetIncrease: 0
};

function openEditTask(taskId) {
    // Search in both tasks array and myPostedTasks
    let task = tasks.find(t => t.id === taskId);
    if (!task) {
        task = myPostedTasks.find(t => t.id === taskId);
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

function saveTaskEdit(event) {
    event.preventDefault();
    
    const taskId = parseInt(document.getElementById('editTaskId').value);
    
    // Search in both arrays
    let task = tasks.find(t => t.id === taskId);
    if (!task) {
        task = myPostedTasks.find(t => t.id === taskId);
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
    
    // Update in main tasks array
    const mainTask = tasks.find(t => t.id === taskId);
    if (mainTask) {
        mainTask.title = newTitle;
        mainTask.category = newCategory;
        mainTask.description = newDescription;
        mainTask.location.address = newLocation;
        mainTask.price = newPrice;
    }
    
    // Update in myPostedTasks array
    const postedTask = myPostedTasks.find(t => t.id === taskId);
    if (postedTask) {
        postedTask.title = newTitle;
        postedTask.category = newCategory;
        postedTask.description = newDescription;
        postedTask.location.address = newLocation;
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

function completeTask(taskId) {
    const task = myAcceptedTasks.find(t => t.id === taskId);
    if (task && currentUser) {
        // Mark task as pending payment (helper completed, waiting for poster to pay)
        task.status = 'pending_payment';
        task.completedAt = new Date().toISOString();
        task.helperId = currentUser.id;
        task.helperName = currentUser.name;
        
        // Update task in accepted tasks
        updateUserData(currentUser.id, {
            acceptedTasks: serializeTasks(myAcceptedTasks)
        });
        
        // Notify task poster to pay
        showToast('✅ Task marked complete! Waiting for payment from task poster.');
        
        // Show completion modal with payment info
        showTaskCompletionModal(task);
        
        renderDashboard();
        
        // ✅ FIX: Update profile after completing task
        setTimeout(() => {
            if (currentUser) {
                openUserProfile();
            }
        }, 500);
    }
}

// Show task completion modal
function showTaskCompletionModal(task) {
    const platformFee = Math.ceil(task.price * 0.10); // 10% platform fee
    const totalPayable = task.price + platformFee;
    
    const content = `
        <div style="text-align: center; padding: 20px;">
            <div style="font-size: 60px; margin-bottom: 20px;">🎉</div>
            <h2 style="color: #4ade80; margin-bottom: 15px;">Task Completed!</h2>
            <p style="margin-bottom: 20px;">Your task completion has been submitted.</p>
            
            <div style="background: rgba(74, 222, 128, 0.1); border-radius: 12px; padding: 20px; margin-bottom: 20px;">
                <h3 style="margin-bottom: 15px;">${task.title}</h3>
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px;">
                    <span>Task Amount:</span>
                    <span>₹${task.price}</span>
                </div>
                <hr style="border-color: rgba(255,255,255,0.1); margin: 10px 0;">
                <div style="display: flex; justify-content: space-between; font-size: 18px; font-weight: 600;">
                    <span>You'll Receive:</span>
                    <span style="color: #4ade80;">₹${task.price}</span>
                </div>
            </div>
            
            <p style="color: #888; font-size: 14px;">
                The task poster will be notified to complete the payment.<br>
                You'll receive the amount in your wallet once payment is confirmed.
            </p>
        </div>
    `;
    
    document.getElementById('taskSuccessContent').innerHTML = content;
    openModal('taskSuccessModal');
}

// Process payment for completed task (called by task poster)
async function payForCompletedTask(taskId) {
    const task = myPostedTasks.find(t => t.id === taskId);
    if (!task || !currentUser) {
        showToast('❌ Task not found');
        return;
    }
    
    // Use new real-time payment modal for better experience
    openPaymentModal(taskId, task.postedBy?.id || task.helperId);
}

// Initiate Razorpay payment for task
function initiateTaskPayment(task, totalPayable, platformFee) {
    const userStr = localStorage.getItem('taskearn_user') || localStorage.getItem('taskearn_current_user');
    if (!userStr) {
        showToast('❌ Please login first');
        return;
    }
    
    const user = JSON.parse(userStr);
    const RAZORPAY_KEY = 'rzp_live_Rz0lerO1zBlLgQ';
    
    const options = {
        key: RAZORPAY_KEY,
        amount: totalPayable * 100, // Razorpay expects paise
        currency: 'INR',
        name: 'TaskEarn',
        description: `Payment for: ${task.title}`,
        handler: function(response) {
            // Payment successful
            console.log('Payment successful:', response);
            completeTaskPayment(task, totalPayable, platformFee, response.razorpay_payment_id);
        },
        prefill: {
            name: user.name || '',
            email: user.email || '',
            contact: user.phone || ''
        },
        notes: {
            task_id: task.id,
            task_title: task.title,
            helper_id: task.helperId,
            platform_fee: platformFee
        },
        theme: {
            color: '#667eea'
        },
        modal: {
            ondismiss: function() {
                showToast('Payment cancelled');
            }
        }
    };
    
    const razorpay = new Razorpay(options);
    razorpay.on('payment.failed', function(response) {
        showToast('❌ Payment failed: ' + response.error.description);
    });
    razorpay.open();
}

// Complete task payment and transfer to helper
function completeTaskPayment(task, totalPayable, platformFee, paymentId) {
    // Update task status
    task.status = 'paid';
    task.paidAt = new Date().toISOString();
    task.paymentId = paymentId;
    task.platformFee = platformFee;
    
    // Move to completed tasks for poster
    myCompletedTasks.push(task);
    myPostedTasks = myPostedTasks.filter(t => t.id !== task.id);
    
    // Update poster's data
    updateUserData(currentUser.id, {
        postedTasks: serializeTasks(myPostedTasks),
        completedTasks: serializeTasks(myCompletedTasks)
    });
    
    // Credit helper's wallet (in local storage for demo)
    creditHelperWallet(task.helperId, task.price, task);
    
    showToast('✅ Payment of ₹' + totalPayable + ' successful! (₹' + task.price + ' to helper + ₹' + platformFee + ' platform fee)');
    renderDashboard();
    
    // Show success modal
    showPaymentSuccessModal(task, totalPayable, platformFee);
}

// Process payment locally (without Razorpay)
function processTaskPaymentLocal(task, totalPayable, platformFee) {
    // Check wallet balance
    const walletStr = localStorage.getItem('taskearn_local_wallet');
    const wallet = walletStr ? JSON.parse(walletStr) : { balance: 0 };
    
    if (wallet.balance < totalPayable) {
        showToast('❌ Insufficient wallet balance. Please add ₹' + (totalPayable - wallet.balance) + ' to your wallet.');
        window.location.href = 'wallet.html';
        return;
    }
    
    // Deduct from wallet
    wallet.balance -= totalPayable;
    wallet.transactions = wallet.transactions || [];
    wallet.transactions.unshift({
        id: Date.now(),
        type: 'debit',
        amount: totalPayable,
        description: `Payment for task: ${task.title}`,
        date: new Date().toISOString()
    });
    localStorage.setItem('taskearn_local_wallet', JSON.stringify(wallet));
    
    // Complete payment
    completeTaskPayment(task, totalPayable, platformFee, 'local_' + Date.now());
}

// Credit helper's wallet
function creditHelperWallet(helperId, amount, task) {
    // For demo, we'll store in a shared wallet system
    const helperWalletsStr = localStorage.getItem('taskearn_helper_wallets') || '{}';
    const helperWallets = JSON.parse(helperWalletsStr);
    
    if (!helperWallets[helperId]) {
        helperWallets[helperId] = { balance: 0, transactions: [] };
    }
    
    helperWallets[helperId].balance += amount;
    helperWallets[helperId].transactions.unshift({
        id: Date.now(),
        type: 'credit',
        amount: amount,
        description: `Earned from task: ${task.title}`,
        date: new Date().toISOString()
    });
    
    localStorage.setItem('taskearn_helper_wallets', JSON.stringify(helperWallets));
    
    // Also update the current user's wallet if they're the helper
    const currentUserStr = localStorage.getItem('taskearn_current_user') || localStorage.getItem('taskearn_user');
    if (currentUserStr) {
        const currentUserData = JSON.parse(currentUserStr);
        if (currentUserData.id === helperId) {
            const localWalletStr = localStorage.getItem('taskearn_local_wallet');
            const localWallet = localWalletStr ? JSON.parse(localWalletStr) : { balance: 0, transactions: [], totalEarned: 0 };
            localWallet.balance += amount;
            localWallet.totalEarned = (localWallet.totalEarned || 0) + amount;
            localWallet.transactions.unshift({
                id: Date.now(),
                type: 'earned',
                amount: amount,
                description: `Earned from task: ${task.title}`,
                date: new Date().toISOString()
            });
            localStorage.setItem('taskearn_local_wallet', JSON.stringify(localWallet));
        }
    }
}

// Show payment success modal
function showPaymentSuccessModal(task, totalPayable, platformFee) {
    const content = `
        <div style="text-align: center; padding: 20px;">
            <div style="font-size: 60px; margin-bottom: 20px;">💰</div>
            <h2 style="color: #4ade80; margin-bottom: 15px;">Payment Successful!</h2>
            
            <div style="background: rgba(74, 222, 128, 0.1); border-radius: 12px; padding: 20px; margin-bottom: 20px;">
                <h3 style="margin-bottom: 15px;">${task.title}</h3>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                    <span>Task Amount:</span>
                    <span>₹${task.price}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                    <span>Platform Fee (10%):</span>
                    <span>₹${platformFee}</span>
                </div>
                <hr style="border-color: rgba(255,255,255,0.1); margin: 10px 0;">
                <div style="display: flex; justify-content: space-between; font-size: 18px; font-weight: 600;">
                    <span>Total Paid:</span>
                    <span style="color: #4ade80;">₹${totalPayable}</span>
                </div>
            </div>
            
            <p style="color: #4ade80; font-size: 14px;">
                ✅ ₹${task.price} has been credited to ${task.helperName || 'the helper'}'s wallet
            </p>
        </div>
    `;
    
    document.getElementById('taskSuccessContent').innerHTML = content;
    openModal('taskSuccessModal');
}

/**
 * Pay for a completed task using Razorpay
 * Called when task poster clicks "Pay Now" on completed task
 */
function payForCompletedTask(taskId) {
    const task = myPostedTasks.find(t => t.id === taskId);
    
    if (!task || task.status !== 'pending_payment') {
        showToast('❌ Task not ready for payment');
        return;
    }
    
    // Confirm payment dialog
    if (!confirm(`Confirm payment of ₹${task.price + Math.ceil(task.price * 0.10)} for task: "${task.title}"?\n\n✓ Helper will receive: ₹${task.price}\n✓ Platform fee (10%): ₹${Math.ceil(task.price * 0.10)}`)) {
        return;
    }
    
    // Initiate Razorpay payment
    initiateRazorpayPayment(task);
}

// ========================================
// RAZORPAY PAYMENT INTEGRATION
// ========================================

/**
 * Initiate Razorpay payment for task (Task Poster pays)
 * Called when posting a task or making payment
 */
async function initiateRazorpayPayment(task) {
    if (!task || task.status !== 'pending_payment') {
        showToast('❌ Task not ready for payment');
        return;
    }

    // Amount in paise (multiply rupees by 100)
    const amount = Math.ceil(task.price * 100);
    const platforFee = Math.ceil(task.price * 10);  // 10% commission
    const totalAmount = amount + (platforFee * 100);

    try {
        // Step 1: Create payment order on backend
        const orderResponse = await fetch('/api/payments/create-order', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
            },
            body: JSON.stringify({
                taskId: task.id,
                amount: totalAmount,
                helperId: task.acceptedBy?.id,
                description: `Payment for task: ${task.title}`
            })
        });

        if (!orderResponse.ok) {
            showToast('❌ Failed to create payment order');
            return;
        }

        const orderData = await orderResponse.json();
        
        if (!orderData.success) {
            showToast('❌ ' + orderData.message);
            return;
        }

        // Step 2: Open Razorpay payment window
        const options = {
            key: orderData.key,  // Razorpay Key ID
            amount: totalAmount,
            currency: 'INR',
            order_id: orderData.orderId,
            name: 'TaskEarn',
            description: task.title,
            image: 'https://taskearn.app/logo.png',
            
            handler: async function(response) {
                // Step 3: Verify payment on backend
                paymentSuccessHandler(task, response);
            },
            
            prefill: {
                name: currentUser?.name || '',
                email: currentUser?.email || '',
                contact: currentUser?.phone || ''
            },
            
            notes: {
                taskId: task.id,
                taskTitle: task.title,
                Platform: 'TaskEarn'
            },
            
            theme: {
                color: '#6366f1'  // Indigo color
            },
            
            modal: {
                ondismiss: function() {
                    showToast('⚠️ Payment cancelled');
                }
            }
        };

        // Open Razorpay
        const rzp = new Razorpay(options);
        rzp.open();

    } catch (error) {
        console.error('Payment error:', error);
        showToast('❌ Payment error: ' + error.message);
    }
}

/**
 * Handle successful Razorpay payment
 */
async function paymentSuccessHandler(task, response) {
    try {
        showToast('⏳ Verifying payment...');

        // Verify payment signature on backend
        const verifyResponse = await fetch('/api/payments/verify', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
            },
            body: JSON.stringify({
                razorpayPaymentId: response.razorpay_payment_id,
                razorpayOrderId: response.razorpay_order_id,
                razorpaySignature: response.razorpay_signature,
                taskId: task.id,
                helperId: task.acceptedBy?.id
            })
        });

        const verifyData = await verifyResponse.json();

        if (!verifyData.success) {
            showToast('❌ Payment verification failed: ' + verifyData.message);
            return;
        }

        // Update task status locally
        task.status = 'paid';
        task.paidAt = new Date().toISOString();
        task.razorpayPaymentId = response.razorpay_payment_id;

        // Update myPostedTasks
        updateUserData(currentUser.id, {
            postedTasks: serializeTasks(myPostedTasks)
        });

        // Show success modal
        showPaymentSuccessModal(task, verifyData);

        // Refresh dashboard
        renderDashboard();

        showToast('✅ Payment successful! ' + verifyData.message);

    } catch (error) {
        console.error('Verification error:', error);
        showToast('❌ Error verifying payment: ' + error.message);
    }
}

/**
 * Show payment success modal
 */
function showPaymentSuccessModal(task, verifyData) {
    const content = `
        <div style="text-align: center; padding: 30px;">
            <div style="font-size: 60px; margin-bottom: 20px;">✅</div>
            <h2 style="color: #4ade80; margin-bottom: 20px;">Payment Successful!</h2>
            
            <div style="background: linear-gradient(135deg, rgba(74, 222, 128, 0.1), rgba(52, 211, 153, 0.1)); border-radius: 15px; padding: 25px; margin-bottom: 20px; text-align: left; color: #fff;">
                <h3>${task.title}</h3>
                
                <div style="background: rgba(50, 50, 60, 0.8); border-radius: 10px; padding: 15px; margin-top: 15px;">
                    <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding: 8px 0; border-bottom: 1px solid rgba(255,255,255,0.1);">
                        <span>Task Amount</span>
                        <span style="font-weight: 600;">₹${task.price}</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding: 8px 0;">
                        <span>Platform Commission (10%)</span>
                        <span style="color: #fbbf24;">₹${Math.ceil(task.price * 10)}</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; padding: 8px 0; font-size: 16px; font-weight: 700; border-top: 2px solid rgba(255,255,255,0.1); margin-top: 8px;">
                        <span>Total Paid</span>
                        <span style="color: #4ade80;">₹${task.price + Math.ceil(task.price * 10)}</span>
                    </div>
                </div>

                <div style="background: rgba(74, 222, 128, 0.1); border-left: 4px solid #4ade80; border-radius: 5px; padding: 12px; margin-top: 15px; font-size: 13px;">
                    <strong>✓ Helper receives: ₹${verifyData.helperCredit}</strong><br>
                    <small style="opacity: 0.8;">Payment will be credited to helper's wallet immediately</small>
                </div>
            </div>

            <button class="btn btn-primary" style="width: 100%; padding: 12px; font-size: 15px; border-radius: 8px;" 
                onclick="closeModal('taskSuccessModal'); renderDashboard()">
                <i class="fas fa-arrow-left"></i> Back to Dashboard
            </button>
        </div>
    `;

    document.getElementById('taskSuccessContent').innerHTML = content;
    openModal('taskSuccessModal');
}

// ========================================
// PAYMENT RECEPTION (For Helpers to Receive Payment)
// ========================================

/**
 * Open payment reception modal for a completed task
 * Called when helper clicks "Receive Payment" on a completed task
 */
function openPaymentReceptionModal(taskId) {
    const task = myAcceptedTasks.find(t => t.id === taskId);
    if (!task || task.status !== 'pending_payment') {
        showToast('❌ Task not found or not ready for payment');
        return;
    }

    const helperEarnings = task.price; // Helper gets 100% of task price (commission deducted from poster)
    const platformFee = Math.ceil(task.price * 0.10); // 10% platform commission
    const totalFromPoster = task.price + platformFee; // What poster pays
    const helperReceives = task.price; // What helper gets

    const content = `
        <div style="padding: 20px;">
            <div style="background: linear-gradient(135deg, #4ade80, #22c55e); border-radius: 15px; padding: 25px; text-align: center; margin-bottom: 25px; color: white;">
                <h3 style="margin: 0 0 10px 0; font-size: 18px;">Task Payment Ready</h3>
                <div style="font-size: 2.5rem; font-weight: 800; margin: 15px 0;">₹${helperReceives}</div>
                <p style="margin: 10px 0 0 0; opacity: 0.95;">Amount to Receive</p>
            </div>

            <div style="background: rgba(30, 30, 40, 0.9); border: 2px solid rgba(139, 92, 246, 0.3); border-radius: 12px; padding: 15px; margin-bottom: 20px; color: #fff;">
                <h4 style="margin-top: 0; color: #fff;">📋 Payment Breakdown</h4>
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding: 8px 0; border-bottom: 1px solid rgba(255,255,255,0.1);">
                    <span>Task Amount</span>
                    <span style="font-weight: 600; color: #fff;">₹${task.price}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding: 8px 0;">
                    <span style="color: #fff;">Platform Commission (10%)</span>
                    <span style="color: #fbbf24; font-weight: 600;">-₹${platformFee}</span>
                </div>
                <div style="display: flex; justify-content: space-between; padding: 8px 0; border-top: 2px solid rgba(255,255,255,0.2); font-weight: 700; font-size: 16px;">
                    <span style="color: #fff;">You Receive</span>
                    <span style="color: #4ade80;">₹${helperReceives}</span>
                </div>
            </div>

            <div style="background: rgba(251, 191, 36, 0.1); border: 1px solid rgba(251, 191, 36, 0.3); border-radius: 10px; padding: 15px; margin-bottom: 20px;">
                <h4 style="margin-top: 0; color: #fbbf24;"><i class="fas fa-info-circle"></i> Payment Methods</h4>
                <p style="font-size: 14px; margin: 10px 0 0 0; opacity: 0.9;">Choose how you want to receive your payment. Commission will be deducted in both cases.</p>
            </div>

            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
                <button class="btn btn-success" style="width: 100%; padding: 15px; font-size: 15px; border-radius: 10px;" 
                    onclick="initiatePaymentReception(${taskId}, 'digital')">
                    <i class="fas fa-credit-card"></i><br>Digital Payment<br><small>UPI/Bank Transfer</small>
                </button>
                <button class="btn btn-secondary" style="width: 100%; padding: 15px; font-size: 15px; border-radius: 10px; background: #0ea5e9;" 
                    onclick="initiatePaymentReception(${taskId}, 'cash')">
                    <i class="fas fa-money-bill"></i><br>Cash Payment<br><small>Direct Settlement</small>
                </button>
            </div>

            <div style="background: rgba(74, 222, 128, 0.05); border-left: 4px solid #4ade80; border-radius: 5px; padding: 12px; margin-top: 15px; font-size: 13px;">
                <i class="fas fa-check-circle" style="color: #4ade80;"></i> <strong>Note:</strong> Payment is processed through the task poster's payment. Your ₹${helperReceives} will be added to your wallet upon confirmation.
            </div>
        </div>
    `;

    document.getElementById('paymentReceptionContent').innerHTML = content;
    openModal('receivePaymentModal');
}

/**
 * Initiate payment reception by helper
 * @param {number} taskId - Task ID
 * @param {string} method - Payment method ('digital' or 'cash')
 */
function initiatePaymentReception(taskId, method) {
    const task = myAcceptedTasks.find(t => t.id === taskId);
    if (!task) {
        showToast('❌ Task not found');
        return;
    }

    const helperReceives = task.price;
    const platformFee = Math.ceil(task.price * 0.10);

    if (method === 'digital') {
        showDigitalPaymentOptions(task, helperReceives, platformFee);
    } else if (method === 'cash') {
        showCashPaymentOptions(task, helperReceives, platformFee);
    }
}

/**
 * Show digital payment options (UPI, Bank Transfer, Wallet)
 */
function showDigitalPaymentOptions(task, helperReceives, platformFee) {
    const content = `
        <div style="padding: 20px;">
            <h3 style="color: #fff;"><i class="fas fa-arrow-left" style="cursor: pointer; opacity: 0.6;" onclick="openPaymentReceptionModal(${task.id})"></i> Digital Payment Methods</h3>

            <div style="background: rgba(30, 30, 40, 0.9); border: 2px solid rgba(139, 92, 246, 0.3); border-radius: 12px; padding: 15px; margin-bottom: 15px; color: #fff;">
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px;">
                    <span style="color: #fff;">Amount to Receive</span>
                    <span style="font-weight: 700; color: #4ade80;">₹${helperReceives}</span>
                </div>
                <div style="display: flex; justify-content: space-between; opacity: 0.8;">
                    <span style="font-size: 12px; color: #fff;">Platform Commission (10%)</span>
                    <span style="font-size: 12px; color: #fbbf24;">-₹${platformFee}</span>
                </div>
            </div>

            <div style="display: flex; flex-direction: column; gap: 10px;">
                <button class="payment-option-btn" onclick="selectDigitalPaymentMethod('upi', ${task.id}, ${helperReceives}, ${platformFee})">
                    <div style="display: flex; align-items: center; justify-content: space-between; width: 100%;">
                        <div style="display: flex; align-items: center; gap: 12px;">
                            <i class="fas fa-mobile-alt" style="font-size: 24px; color: #667eea;"></i>
                            <div style="text-align: left;">
                                <div style="font-weight: 600; color: #fff;">UPI Transfer</div>
                                <div style="font-size: 12px; opacity: 0.8; color: #ccc;">Fast and instant transfer</div>
                            </div>
                        </div>
                        <i class="fas fa-chevron-right" style="opacity: 0.6; color: #fff;"></i>
                    </div>
                </button>

                <button class="payment-option-btn" onclick="selectDigitalPaymentMethod('bank', ${task.id}, ${helperReceives}, ${platformFee})">
                    <div style="display: flex; align-items: center; justify-content: space-between; width: 100%;">
                        <div style="display: flex; align-items: center; gap: 12px;">
                            <i class="fas fa-university" style="font-size: 24px; color: #10b981;"></i>
                            <div style="text-align: left;">
                                <div style="font-weight: 600; color: #fff;">Bank Transfer</div>
                                <div style="font-size: 12px; opacity: 0.8; color: #ccc;">Direct to your bank account</div>
                            </div>
                        </div>
                        <i class="fas fa-chevron-right" style="opacity: 0.6; color: #fff;"></i>
                    </div>
                </button>

                <button class="payment-option-btn" onclick="selectDigitalPaymentMethod('wallet', ${task.id}, ${helperReceives}, ${platformFee})">
                    <div style="display: flex; align-items: center; justify-content: space-between; width: 100%;">
                        <div style="display: flex; align-items: center; gap: 12px;">
                            <i class="fas fa-wallet" style="font-size: 24px; color: #f59e0b;"></i>
                            <div style="text-align: left;">
                                <div style="font-weight: 600; color: #fff;">Add to Wallet</div>
                                <div style="font-size: 12px; opacity: 0.8; color: #ccc;">Instant credit to your wallet</div>
                            </div>
                        </div>
                        <i class="fas fa-chevron-right" style="opacity: 0.6; color: #fff;"></i>
                    </div>
                </button>
            </div>

            <style>
                .payment-option-btn {
                    background: rgba(30, 30, 40, 0.9);
                    border: 2px solid rgba(139, 92, 246, 0.5);
                    padding: 15px;
                    border-radius: 10px;
                    color: #fff;
                    cursor: pointer;
                    transition: all 0.3s;
                    text-align: left;
                    width: 100%;
                    font-family: inherit;
                    font-size: 14px;
                }
                .payment-option-btn:hover {
                    background: rgba(30, 30, 40, 1);
                    border-color: rgba(139, 92, 246, 0.8);
                    transform: translateX(5px);
                    box-shadow: 0 0 15px rgba(139, 92, 246, 0.3);
                }
            </style>
        </div>
    `;

    document.getElementById('paymentReceptionContent').innerHTML = content;
}

/**
 * Process digital payment method selection
 */
function selectDigitalPaymentMethod(method, taskId, helperReceives, platformFee) {
    const task = myAcceptedTasks.find(t => t.id === taskId);
    if (!task) return;

    if (method === 'wallet') {
        // Direct wallet credit
        completePaymentReception(task, helperReceives, platformFee, 'wallet');
    } else if (method === 'upi' || method === 'bank') {
        // Show payment collection form
        showPaymentDetailsForm(task, helperReceives, platformFee, method);
    }
}

/**
 * Show form to collect payment details
 */
function showPaymentDetailsForm(task, helperReceives, platformFee, method) {
    const methodTitle = method === 'upi' ? 'UPI ID' : 'Bank Account';
    const methodPlaceholder = method === 'upi' ? 'example@upi' : 'Account number';

    const content = `
        <div style="padding: 20px;">
            <h3 style="color: #fff;"><i class="fas fa-arrow-left" style="cursor: pointer; opacity: 0.6;" onclick="initiatePaymentReception(${task.id}, 'digital')"></i> ${methodTitle} Details</h3>

            <div style="background: rgba(30, 30, 40, 0.9); border: 2px solid rgba(139, 92, 246, 0.3); border-radius: 10px; padding: 15px; margin-bottom: 20px; color: #fff;">
                <div style="display: flex; justify-content: space-between;">
                    <span style="color: #fff;">Amount to Receive</span>
                    <span style="font-weight: 700; color: #4ade80;">₹${helperReceives}</span>
                </div>
            </div>

            <form onsubmit="processPaymentDetails(event, ${task.id}, ${helperReceives}, ${platformFee}, '${method}')">
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 8px; font-weight: 500; color: #fff;">
                        ${methodTitle}
                        <span style="color: #ef4444;">*</span>
                    </label>
                    <input type="text" placeholder="${methodPlaceholder}" required 
                        style="width: 100%; padding: 12px; background: rgba(50, 50, 60, 0.95); border: 2px solid rgba(139, 92, 246, 0.4); border-radius: 8px; color: #fff; font-size: 14px;"
                        id="paymentDetail">
                </div>

                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 8px; font-weight: 500; color: #fff;">
                        Account Holder Name
                        <span style="color: #ef4444;">*</span>
                    </label>
                    <input type="text" placeholder="Your full name" required 
                        style="width: 100%; padding: 12px; background: rgba(50, 50, 60, 0.95); border: 2px solid rgba(139, 92, 246, 0.4); border-radius: 8px; color: #fff; font-size: 14px;"
                        id="accountHolderName" value="${currentUser ? currentUser.name : ''}">
                </div>

                <button type="submit" class="btn btn-success" style="width: 100%; padding: 12px; font-size: 15px; border-radius: 8px;">
                    <i class="fas fa-check-circle"></i> Confirm Payment Details
                </button>
            </form>
        </div>
    `;

    document.getElementById('paymentReceptionContent').innerHTML = content;
}

/**
 * Process payment details form submission
 */
function processPaymentDetails(event, taskId, helperReceives, platformFee, method) {
    event.preventDefault();
    
    const paymentDetail = document.getElementById('paymentDetail').value;
    const accountHolderName = document.getElementById('accountHolderName').value;

    if (!paymentDetail || !accountHolderName) {
        showToast('❌ Please fill in all fields');
        return;
    }

    // In production, this would be validated server-side
    const task = myAcceptedTasks.find(t => t.id === taskId);
    if (task) {
        completePaymentReception(task, helperReceives, platformFee, method, {
            detail: paymentDetail,
            accountHolder: accountHolderName
        });
    }
}

/**
 * Show cash payment settlement options
 */
function showCashPaymentOptions(task, helperReceives, platformFee) {
    const content = `
        <div style="padding: 20px;">
            <h3 style="color: #fff;">💵 Cash Payment Settlement</h3>

            <div style="background: rgba(30, 30, 40, 0.9); border: 2px solid rgba(251, 191, 36, 0.5); border-radius: 10px; padding: 15px; margin-bottom: 20px;">
                <h4 style="margin-top: 0; color: #fbbf24;"><i class="fas fa-warning-circle"></i> Important</h4>
                <p style="font-size: 14px; margin: 10px 0 0 0; color: #fff;">For cash payments, you will receive:</p>
                <div style="background: rgba(50, 50, 60, 0.8); border-radius: 8px; padding: 12px; margin-top: 10px; border: 1px solid rgba(255,255,255,0.1);">
                    <div style="display: flex; justify-content: space-between;">
                        <span style="color: #fff;">Cash Amount</span>
                        <span style="font-weight: 700; color: #fff;">₹${helperReceives}</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; opacity: 0.9; font-size: 12px; margin-top: 5px;">
                        <span style="color: #ccc;">Platform Commission (10%)</span>
                        <span style="color: #fbbf24;">-₹${platformFee} (to company)</span>
                    </div>
                </div>
            </div>

            <div style="background: rgba(30, 30, 40, 0.9); border: 2px solid rgba(52, 211, 153, 0.5); border-radius: 10px; padding: 15px; margin-bottom: 20px; color: #fff;">
                <h4 style="margin-top: 0; color: #4ade80;"><i class="fas fa-handshake"></i> Settlement with ${task.postedBy ? task.postedBy.name : 'Task Poster'}</h4>
                <p style="font-size: 14px; margin: 10px 0 0 0; color: #fff;">
                    You will meet with the task poster and settle ₹${helperReceives} in cash. 
                    The 10% platform commission (₹${platformFee}) will be collected separately.
                </p>
            </div>

            <button class="btn btn-primary" style="width: 100%; padding: 12px; font-size: 15px; border-radius: 8px; margin-bottom: 10px;"
                onclick="processChargeVerification(${task.id}, 'cash', ${helperReceives}, ${platformFee})">
                <i class="fas fa-phone"></i> Get Contact Details
            </button>

            <button class="btn btn-secondary" style="width: 100%; padding: 12px; font-size: 15px; border-radius: 8px; background: #666;"
                onclick="initiatePaymentReception(${task.id}, 'digital')">
                <i class="fas fa-arrow-left"></i> Back
            </button>
        </div>
    `;

    document.getElementById('paymentReceptionContent').innerHTML = content;
}

/**
 * Verify and display task poster's contact for cash settlement
 */
function processChargeVerification(taskId, method, helperReceives, platformFee) {
    const task = myAcceptedTasks.find(t => t.id === taskId);
    if (!task || !task.postedBy) {
        showToast('❌ Task poster information not found');
        return;
    }

    const content = `
        <div style="padding: 20px;">
            <h3 style="text-align: center; color: #fff;"><i class="fas fa-check-circle" style="color: #4ade80;"></i> Contact Details</h3>

            <div style="background: rgba(30, 30, 40, 0.95); border: 2px solid rgba(52, 211, 153, 0.5); border-radius: 15px; padding: 20px; margin-bottom: 20px; color: #fff;">
                <h4 style="margin-top: 0; text-align: center; color: #4ade80;">${task.postedBy.name}</h4>
                <div style="text-align: center; margin-bottom: 15px;">
                    <i class="fas fa-phone" style="font-size: 30px; color: #4ade80;"></i>
                </div>
                <div style="background: rgba(50, 50, 60, 0.8); border-radius: 10px; padding: 12px; margin-bottom: 10px; border: 1px solid rgba(255,255,255,0.1);">
                    <div style="font-size: 12px; opacity: 0.8; color: #ccc;">Phone Number</div>
                    <div style="font-size: 16px; font-weight: 700; font-family: monospace; color: #fff;">${task.postedBy.phone || '+91-XXXXXXXXXX'}</div>
                </div>
                <div style="background: rgba(50, 50, 60, 0.8); border-radius: 10px; padding: 12px; border: 1px solid rgba(255,255,255,0.1);">
                    <div style="font-size: 12px; opacity: 0.8; color: #ccc;">Location</div>
                    <div style="font-size: 14px; color: #fff;">${task.location.address}</div>
                </div>
            </div>

            <div style="background: rgba(30, 30, 40, 0.9); border: 2px solid rgba(251, 191, 36, 0.5); border-radius: 10px; padding: 15px; margin-bottom: 20px;">
                <h4 style="margin-top: 0; color: #fbbf24;"><i class="fas fa-info-circle"></i> Settlement Instructions</h4>
                <ol style="margin: 10px 0 0 0; padding-left: 20px; font-size: 14px; color: #fff;">
                    <li>Contact the task poster using the number above</li>
                    <li>Arrange cash payment of ₹${helperReceives}</li>
                    <li>After settlement, confirm payment in the app</li>
                    <li>Amount will be added to your wallet (10% commission deducted)</li>
                </ol>
            </div>

            <button class="btn btn-success" style="width: 100%; padding: 12px; font-size: 15px; border-radius: 8px; margin-bottom: 10px;"
                onclick="completePaymentReception(${task.id}, ${helperReceives}, ${platformFee}, 'cash')">
                <i class="fas fa-check-circle"></i> Confirm Cash Settlement
            </button>

            <button class="btn btn-secondary" style="width: 100%; padding: 12px; font-size: 15px; border-radius: 8px; background: #666;"
                onclick="showCashPaymentOptions(JSON.parse('${JSON.stringify(task).replace(/'/g, "\\'")}'), ${helperReceives}, ${platformFee})">
                <i class="fas fa-arrow-left"></i> Back
            </button>
        </div>
    `;

    document.getElementById('paymentReceptionContent').innerHTML = content;
}

/**
 * Complete payment reception process
 * Updates task status to 'paid' and adds earnings to wallet
 */
function completePaymentReception(task, helperReceives, platformFee, method, paymentDetails = {}) {
    if (!task || !currentUser) {
        showToast('❌ Error processing payment');
        return;
    }

    // Update task status to paid
    task.status = 'paid';
    task.paidAt = new Date().toISOString();
    task.paymentMethod = method;
    task.platformFeeDeducted = platformFee;
    task.paymentDetails = paymentDetails;

    // Update myAcceptedTasks
    updateUserData(currentUser.id, {
        acceptedTasks: serializeTasks(myAcceptedTasks)
    });

    // Add earnings to local wallet (in production, this would be server-side)
    addEarningsToWallet(currentUser.id, helperReceives, platformFee, task);

    // Track company commission
    trackCompanyCommission(task.id, platformFee, currentUser.name, method);

    // Show success message
    closeModal('receivePaymentModal');
    showPaymentReceptionSuccessModal(task, helperReceives, platformFee, method);

    // Update dashboard
    renderDashboard();
}

/**
 * Add earnings to helper's wallet
 */
function addEarningsToWallet(userId, earnings, platformFee, task) {
    const walletStr = localStorage.getItem('taskearn_local_wallet');
    const wallet = walletStr ? JSON.parse(walletStr) : { balance: 0, transactions: [], totalEarned: 0 };

    wallet.balance += earnings;
    wallet.totalEarned = (wallet.totalEarned || 0) + earnings;
    wallet.transactions = wallet.transactions || [];
    wallet.transactions.unshift({
        id: Date.now(),
        type: 'earned',
        amount: earnings,
        platformFee: platformFee,
        gross: earnings + platformFee,
        description: `Payment received for task: ${task.title}`,
        paymentMethod: task.paymentMethod,
        date: new Date().toISOString()
    });

    localStorage.setItem('taskearn_local_wallet', JSON.stringify(wallet));

    console.log('✅ Wallet updated:', {
        newBalance: wallet.balance,
        earnedAmount: earnings,
        platformCommission: platformFee
    });
}

/**
 * Show payment reception success modal
 */
function showPaymentReceptionSuccessModal(task, helperReceives, platformFee, method) {
    const methodLabel = method === 'wallet' ? '💳 Wallet Credit' : method === 'upi' ? '📱 UPI Transfer' : method === 'bank' ? '🏦 Bank Transfer' : '💵 Cash Payment';

    const content = `
        <div style="text-align: center; padding: 20px;">
            <div style="font-size: 60px; margin-bottom: 20px;">✅</div>
            <h2 style="color: #4ade80; margin-bottom: 15px;">Payment Received!</h2>
            
            <div style="background: linear-gradient(135deg, rgba(74, 222, 128, 0.1), rgba(52, 211, 153, 0.1)); border-radius: 15px; padding: 25px; margin-bottom: 20px;">
                <div style="font-size: 2rem; font-weight: 800; color: #4ade80; margin-bottom: 10px;">₹${helperReceives}</div>
                <p style="margin: 10px 0 0 0; opacity: 0.9;">Added to Your Wallet</p>
            </div>

            <div style="background: rgba(255, 255, 255, 0.05); border-radius: 12px; padding: 15px; margin-bottom: 20px; text-align: left;">
                <h4 style="margin: 0 0 12px 0;">Transaction Details</h4>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px; padding: 6px 0;">
                    <span>Task</span>
                    <span style="font-weight: 600;">${task.title}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px; padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.1);">
                    <span>Payment Method</span>
                    <span style="color: #0ea5e9;">${methodLabel}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px; padding: 6px 0;">
                    <span>Gross Amount</span>
                    <span>₹${helperReceives + platformFee}</span>
                </div>
                <div style="display: flex; justify-content: space-between; margin-bottom: 8px; padding: 6px 0;">
                    <span style="opacity: 0.7;">Platform Commission (10%)</span>
                    <span style="color: #fbbf24; opacity: 0.7;">-₹${platformFee}</span>
                </div>
                <div style="display: flex; justify-content: space-between; padding: 8px 0; font-size: 16px; font-weight: 700; border-top: 2px solid rgba(255,255,255,0.1); margin-top: 8px;">
                    <span>You Received</span>
                    <span style="color: #4ade80;">₹${helperReceives}</span>
                </div>
            </div>

            <button class="btn btn-primary" style="width: 100%; padding: 12px; font-size: 15px; border-radius: 8px;" 
                onclick="closeModal('taskSuccessModal'); scrollToSection('my-tasks')">
                <i class="fas fa-arrow-left"></i> Back to Tasks
            </button>
        </div>
    `;

    document.getElementById('taskSuccessContent').innerHTML = content;
    openModal('taskSuccessModal');
}

/**
 * Track company commission from payment
 * Stores commission in localStorage for accounting purposes
 */
function trackCompanyCommission(taskId, amount, helperName, method = 'digital') {
    const commissionStr = localStorage.getItem('taskearn_company_commissions');
    const commissions = commissionStr ? JSON.parse(commissionStr) : {
        transactions: [],
        totalCommission: 0,
        lastUpdated: null
    };

    const commission = {
        id: `commission-${Date.now()}`,
        taskId: taskId,
        amount: amount,
        helperName: helperName,
        paymentMethod: method,
        date: new Date().toISOString(),
        status: 'received'
    };

    commissions.transactions.unshift(commission);
    commissions.totalCommission += amount;
    commissions.lastUpdated = new Date().toISOString();

    localStorage.setItem('taskearn_company_commissions', JSON.stringify(commissions));
    
    console.log('📊 Company Commission Tracked:', {
        commission: amount,
        helper: helperName,
        totalCommissions: commissions.totalCommission,
        transactionCount: commissions.transactions.length
    });

    return commissions;
}

/**
 * Get company commission summary
 */
function getCompanyCommissionSummary() {
    const commissionStr = localStorage.getItem('taskearn_company_commissions');
    return commissionStr ? JSON.parse(commissionStr) : {
        transactions: [],
        totalCommission: 0,
        lastUpdated: null
    };
}

/**
 * Get this month's commission
 */
function getCurrentMonthCommission() {
    const now = new Date();
    const firstDay = new Date(now.getFullYear(), now.getMonth(), 1);
    const commissionStr = localStorage.getItem('taskearn_company_commissions');
    
    if (!commissionStr) return 0;
    
    const commissions = JSON.parse(commissionStr);
    return commissions.transactions
        .filter(t => new Date(t.date) >= firstDay && new Date(t.date) <= now)
        .reduce((sum, t) => sum + t.amount, 0);
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
    
    // Enforce minimum ₹50
    if (baseBudget < MIN_TASK_PRICE) {
        baseBudget = MIN_TASK_PRICE;
        showToast('⚠️ Minimum task budget is ₹' + MIN_TASK_PRICE);
    }
    
    const totalPrice = baseBudget + currentBonus;
    const category = document.getElementById('modalTaskCategory').value;
    const serviceCharge = getServiceCharge(category);
    const totalPayable = totalPrice + serviceCharge;

    const taskData = {
        title: document.getElementById('modalTaskTitle').value,
        category: category,
        description: document.getElementById('modalTaskDescription').value,
        location: {
            lat: userLocation.lat + (Math.random() - 0.5) * 0.02,
            lng: userLocation.lng + (Math.random() - 0.5) * 0.02,
            address: document.getElementById('modalTaskLocation').value
        },
        price: totalPrice,
        serviceCharge: serviceCharge,
        totalPaid: totalPayable
    };

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
                console.error('⚠️ Server save failed:', result.message);
                if (result.message && result.message.includes('token')) {
                    showToast('❌ Session expired. Please login again.');
                    setTimeout(() => {
                        handleLogout();
                        openModal('loginModal');
                    }, 2000);
                    return;
                } else {
                    showToast('❌ Failed to post task: ' + result.message);
                    return;
                }
            }
        } else {
            showToast('❌ Backend API not available. Please try again later.');
            return;
        }
    } catch (error) {
        console.error('❌ Error saving task to server:', error);
        showToast('❌ Network error. Please check your connection and try again.');
        return;
    }

    // Only create task if server save was successful
    if (!serverTaskId) {
        showToast('❌ Failed to post task. Please try again.');
        return;
    }

    const newTask = {
        id: serverTaskId,
        ...taskData,
        postedBy: currentUser,
        postedAt: new Date(),
        expiresAt: new Date(Date.now() + 12 * 3600000),
        status: 'active'
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
    setTimeout(() => loadTasksFromServer(), 1000);
    
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
                closeModal('loginModal');
                document.getElementById('loginEmail').value = '';
                document.getElementById('loginPassword').value = '';
                
                updateNavForUser();
                renderDashboard();
                loadTasksFromServer();
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
        showToast('You must be 16+ to use TaskEarn');
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
                
                showToast('🎉 Welcome to TaskEarn! Your ID: ' + currentUser.id);
                closeModal('signupModal');
                
                // Clear form
                document.getElementById('signupFirstName').value = '';
                document.getElementById('signupLastName').value = '';
                document.getElementById('signupEmail').value = '';
                document.getElementById('signupPassword').value = '';
                if (document.getElementById('signupPhone')) document.getElementById('signupPhone').value = '';
                document.getElementById('signupDOB').value = '';
                
                updateNavForUser();
                renderDashboard();
                loadTasksFromServer();
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
    const mobileMenu = document.getElementById('mobileMenu');
    
    if (nav && currentUser) {
        nav.innerHTML = `
            <div class="user-menu">
                <button class="btn btn-outline" onclick="openUserProfile()">
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
                profileLi.innerHTML = `<a href="#" onclick="openUserProfile(); toggleMobileMenu();"><i class="fas fa-user-circle"></i> ${currentUser.name}</a>`;
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
        
        // Load and display notifications
        notifications = loadNotifications();
        updateNotificationUI();
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

function logout() {
    clearCurrentSession();
    currentUser = null;
    myPostedTasks = [];
    myAcceptedTasks = [];
    myCompletedTasks = [];
    notifications = [];

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
    renderAvailableTasks();
    renderPostedTasks();
    renderAcceptedTasks();
    renderCompletedTasks();
}

function renderAvailableTasks() {
    const el = document.getElementById('availableTasks');
    if (!el) return;

    // Get available tasks (not posted by current user and not already accepted by them)
    const availableTasksList = tasks.filter(t => 
        t.status === 'active' && 
        (!currentUser || t.postedBy.id !== currentUser.id) &&
        (!myAcceptedTasks.find(at => at.id === t.id))
    ).sort((a, b) => {
        // Sort by distance (closest first)
        const distA = getDistance(userLocation.lat, userLocation.lng, a.location.lat, a.location.lng);
        const distB = getDistance(userLocation.lat, userLocation.lng, b.location.lat, b.location.lng);
        return distA - distB;
    });

    if (availableTasksList.length === 0) {
        el.innerHTML = `
            <div class="empty-state">
                <i class="fas fa-inbox"></i>
                <h3>No available tasks</h3>
                <p style="color: #666; font-size: 14px; margin-bottom: 15px;">Check back soon for new tasks in your area!</p>
                <button class="btn btn-primary" onclick="setTimeout(() => location.reload(), 500)">
                    <i class="fas fa-sync-alt"></i> Refresh
                </button>
            </div>
        `;
        return;
    }

    el.innerHTML = availableTasksList.slice(0, 10).map(t => {
        const dist = getDistance(userLocation.lat, userLocation.lng, t.location.lat, t.location.lng);
        const serviceCharge = getServiceCharge(t.category);
        const totalEarnings = t.price + serviceCharge;
        return `
            <div class="available-task-card">
                <div class="available-task-header">
                    <span class="task-category">${formatCategory(t.category)}</span>
                    <span class="task-distance"><i class="fas fa-map-marker-alt"></i> ${dist.toFixed(1)} km</span>
                </div>
                <h4 class="available-task-title">${t.title}</h4>
                <p class="available-task-description">${t.description.substring(0, 100)}...</p>
                <div class="available-task-meta">
                    <span><i class="fas fa-map-pin"></i> ${t.location.address.split(',')[0]}</span>
                    <span><i class="fas fa-clock"></i> ${getTimeLeft(t.expiresAt)} left</span>
                </div>
                <div class="available-task-footer">
                    <div class="available-task-poster">
                        <div class="poster-avatar-small"><i class="fas fa-user"></i></div>
                        <div class="poster-info-small">
                            <p>${t.postedBy.name}</p>
                            <span>${generateStars(t.postedBy.rating)} ${t.postedBy.rating}</span>
                        </div>
                    </div>
                    <span class="available-task-price">₹${totalEarnings}</span>
                </div>
                <div class="available-task-actions">
                    <button class="btn btn-secondary" style="flex: 1; background: #0ea5e9; border: none; font-size: 13px;" onclick="contactTaskProvider(${t.id}, '${t.postedBy.name.replace(/'/g, "\\'")}')" title="Message provider for details">
                        <i class="fas fa-comment-dots"></i> Contact
                    </button>
                    <button class="btn btn-primary" style="flex: 1; font-size: 13px;" onclick="acceptTaskFromBrowse(${t.id})">
                        <i class="fas fa-check"></i> Accept
                    </button>
                </div>
            </div>
        `;
    }).join('');
}

function acceptTaskFromBrowse(taskId) {
    if (!currentUser) {
        showToast('Please login first');
        openModal('loginModal');
        return;
    }
    acceptTask(taskId);
    showToast('✅ Task accepted! Check your Accepted Tasks tab.');
}

function renderPostedTasks() {
    const el = document.getElementById('myPostedTasks');
    if (!el) return;

    if (myPostedTasks.length === 0) {
        el.innerHTML = '<div class="empty-state"><i class="fas fa-clipboard-list"></i><h3>No posted tasks</h3><button class="btn btn-primary" onclick="openModal(\'postTaskModal\')">Post a Task</button></div>';
        return;
    }

    el.innerHTML = myPostedTasks.map(t => {
        // Payment system: Poster pays full amount, 90% goes to helper, 10% to company
        const taskAmount = t.price;
        const helperAmount = Math.floor(taskAmount * 0.9);
        const companyAmount = taskAmount - helperAmount;
        
        let actionButtons = '';
        if (t.status === 'active') {
            actionButtons = `<div class="task-actions"><button class="btn btn-edit" onclick="openEditTask(${t.id})"><i class="fas fa-edit"></i> Edit</button><button class="btn btn-danger" onclick="deleteTask(${t.id})"><i class="fas fa-trash"></i> Delete</button></div>`;
        } else if (t.status === 'pending_payment') {
            actionButtons = `
                <div style="background: rgba(251, 191, 36, 0.1); border: 1px solid #fbbf24; border-radius: 8px; padding: 12px; margin-top: 10px;">
                    <p style="color: #fbbf24; margin-bottom: 8px; font-size: 14px;">
                        <i class="fas fa-check-circle"></i> ${t.helperName || 'Helper'} completed this task!
                    </p>
                    <div style="display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 13px;">
                        <span>Task Amount:</span><span>₹${taskAmount}</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 13px; color: #888;">
                        <span>Helper receives (90%):</span><span>₹${helperAmount}</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; margin-bottom: 8px; font-size: 13px; color: #888;">
                        <span>Platform (10%):</span><span>₹${companyAmount}</span>
                    </div>
                    <button class="btn btn-success" style="width: 100%; margin-top: 12px;" onclick="payForCompletedTask(${t.id})" title="Open real-time payment modal">
                        <i class="fas fa-credit-card"></i> Pay ₹${taskAmount} Now
                    </button>
                </div>
            `;
        } else if (t.status === 'paid') {
            actionButtons = `
                <div style="background: rgba(74, 222, 128, 0.1); border: 1px solid #4ade80; border-radius: 8px; padding: 12px; margin-top: 10px;">
                    <p style="color: #4ade80; margin: 0;">
                        <i class="fas fa-check-circle"></i> Payment completed - ₹${taskAmount} sent to ${t.helperName || 'helper'}
                    </p>
                </div>
            `;
        }
        
        const statusColor = t.status === 'pending_payment' ? 'style="background: #fbbf24; color: #000;"' : 
                           t.status === 'paid' ? 'style="background: #4ade80; color: #000;"' : '';
        const statusText = t.status === 'pending_payment' ? '⏳ Awaiting Payment' : 
                          t.status === 'paid' ? '✅ Paid' : t.status;
        
        return `
            <div class="my-task-card">
                <div class="my-task-card-header">
                    <span class="task-category">${formatCategory(t.category)}</span>
                    <span class="task-status ${t.status}" ${statusColor}>${statusText}</span>
                </div>
                <h4>${t.title}</h4>
                <div class="task-meta"><span>₹${t.price}</span><span>${getTimeLeft(t.expiresAt)}</span></div>
                ${actionButtons}
            </div>
        `;
    }).join('');
}

function renderAcceptedTasks() {
    const el = document.getElementById('myAcceptedTasks');
    if (!el) return;

    if (myAcceptedTasks.length === 0) {
        el.innerHTML = '<div class="empty-state"><i class="fas fa-handshake"></i><h3>No accepted tasks</h3><button class="btn btn-primary" onclick="scrollToSection(\'find-tasks\')">Find Tasks</button></div>';
        return;
    }

    el.innerHTML = myAcceptedTasks.map(t => {
        // ✅ Show different UI based on task status
        let actionHTML = '';
        let statusHTML = 'In Progress';
        let statusColor = 'pending';
        
        if (t.status === 'pending_payment') {
            // Task completed, waiting for payment from poster
            statusHTML = '⏳ Awaiting Payment';
            statusColor = 'warning';
            actionHTML = `<div class="task-actions">
                <button class="btn btn-success" onclick="openPaymentReceptionModal(${t.id})" title="Receive payment for completed task">
                    <i class="fas fa-wallet"></i> Receive Payment
                </button>
            </div>`;
        } else if (t.status === 'paid') {
            // Payment received
            statusHTML = '✅ Paid';
            statusColor = 'success';
            actionHTML = `<div style="background: rgba(74, 222, 128, 0.1); border-radius: 8px; padding: 12px; margin-top: 10px;">
                <p style="color: #4ade80; margin: 0;">
                    <i class="fas fa-check-circle"></i> Payment received - ₹${t.price} added to your wallet
                </p>
            </div>`;
        } else {
            // Still in progress
            actionHTML = `<div class="task-actions"><button class="btn btn-success" onclick="completeTask(${t.id})">Mark Complete</button></div>`;
        }
        
        return `
            <div class="my-task-card">
                <div class="my-task-card-header">
                    <span class="task-category">${formatCategory(t.category)}</span>
                    <span class="task-status ${statusColor}">${statusHTML}</span>
                </div>
                <h4>${t.title}</h4>
                <div class="task-meta"><span>₹${t.price}</span><span>${t.location.address}</span></div>
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

    // Calculate total with service charges based on category
    const totalWithCharges = myCompletedTasks.reduce((s, t) => s + t.price + getServiceCharge(t.category), 0);
    el.innerHTML = `
        <div style="background:linear-gradient(135deg,#10b981,#34d399);color:white;padding:25px;border-radius:15px;text-align:center;margin-bottom:20px;">
            <h3 style="margin:0;">Total Earned</h3>
            <p style="font-size:2.5rem;font-weight:800;margin:10px 0;">₹${totalWithCharges}</p>
            <small style="opacity:0.9;">Includes service charges per task</small>
        </div>
        ${myCompletedTasks.map(t => {
            const sc = getServiceCharge(t.category);
            return `<div class="my-task-card"><h4>${t.title}</h4><p>Earned: <strong style="color:#10b981;">₹${t.price + sc}</strong> <small>(₹${t.price} + ₹${sc} service)</small></p></div>`;
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
    
    // Enforce minimum ₹50
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
    document.getElementById('taskLocation').value = 'Current Location';
    showToast('Location set');
}

function getModalLocation() {
    document.getElementById('modalTaskLocation').value = 'Current Location';
    showToast('Location set');
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
        renderTasks();
        addTaskMarkers();
    }, 60000);
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

    // Upload form
    const uploadForm = document.getElementById('taskUploadForm');
    if (uploadForm) {
        uploadForm.onsubmit = function(e) {
            e.preventDefault();
            if (!currentUser) {
                showToast('Please login');
                openModal('loginModal');
                return;
            }

            const newTask = {
                id: Date.now(),
                title: document.getElementById('taskTitle').value,
                category: document.getElementById('taskCategory').value,
                description: document.getElementById('taskDescription').value,
                location: {
                    lat: userLocation.lat + (Math.random() - 0.5) * 0.02,
                    lng: userLocation.lng + (Math.random() - 0.5) * 0.02,
                    address: document.getElementById('taskLocation').value
                },
                price: parseInt(document.getElementById('taskBudget').value),
                postedBy: currentUser,
                postedAt: new Date(),
                expiresAt: new Date(Date.now() + 12 * 3600000),
                status: 'active'
            };

            tasks.unshift(newTask);
            myPostedTasks.unshift(newTask);
            showToast('Task posted!');
            this.reset();
            renderTasks();
            addTaskMarkers();
            renderDashboard();
        };
    }

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
window.acceptTask = acceptTask;
window.cancelTask = cancelTask;
window.deleteTask = deleteTask;
window.completeTask = completeTask;
window.payForCompletedTask = payForCompletedTask;
window.initiateTaskPayment = initiateTaskPayment;
window.openEditTask = openEditTask;
window.selectBudgetIncrease = selectBudgetIncrease;
window.updateNewBudget = updateNewBudget;
window.saveTaskEdit = saveTaskEdit;
window.showTaskPostedSuccess = showTaskPostedSuccess;
window.switchTab = switchTab;
window.applyFilters = applyFilters;
window.clearFilters = clearFilters;
window.filterByCategory = filterByCategory;
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
window.onTaskCardClick = onTaskCardClick;
window.openGoogleMaps = openGoogleMaps;
window.clearRoute = clearRoute;
window.openUserProfile = openUserProfile;
window.toggleNotifications = toggleNotifications;
window.markAsRead = markAsRead;
window.clearAllNotifications = clearAllNotifications;

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
//    - {{app_name}} - TaskEarn
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
    // Clear timer first
    if (forgotPasswordState.otpTimer) {
        clearInterval(forgotPasswordState.otpTimer);
    }
    
    forgotPasswordState = {
        email: '',
        user: null,
        otp: '',
        method: '',
        otpTimer: null,
        otpExpiry: null,
        isSending: false
    };
    
    // Reset to step 1
    document.querySelectorAll('.forgot-step').forEach(step => step.classList.remove('active'));
    document.getElementById('forgotStep1')?.classList.add('active');
    
    // Clear inputs
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

function findAccount(event) {
    event.preventDefault();
    
    const email = document.getElementById('forgotEmail').value.trim();
    const user = getUserByEmail(email);
    
    if (!user) {
        showToast('❌ No account found with this email');
        return;
    }
    
    forgotPasswordState.email = email;
    forgotPasswordState.user = user;
    
    // Show account preview
    const preview = document.getElementById('accountPreview');
    preview.innerHTML = `
        <div class="avatar"><i class="fas fa-user"></i></div>
        <div class="details">
            <div class="name">${user.name}</div>
            <div class="user-id">ID: ${user.id}</div>
        </div>
    `;
    
    // Mask email
    const maskedEmail = maskEmail(user.email);
    
    document.getElementById('maskedEmail').textContent = maskedEmail;
    
    goToForgotStep(2);
}

function maskEmail(email) {
    const [name, domain] = email.split('@');
    const maskedName = name.charAt(0) + '*'.repeat(Math.max(name.length - 2, 1)) + name.charAt(name.length - 1);
    return maskedName + '@' + domain;
}

// Generate secure OTP
function generateOTP() {
    return Math.floor(100000 + Math.random() * 900000).toString();
}

// Send OTP via selected method
async function sendOTP(method) {
    if (forgotPasswordState.isSending) {
        showToast('⏳ Please wait, sending OTP...');
        return;
    }
    
    forgotPasswordState.method = method;
    forgotPasswordState.isSending = true;
    
    // Generate 6-digit OTP
    const otp = generateOTP();
    forgotPasswordState.otp = otp;
    forgotPasswordState.otpExpiry = Date.now() + 5 * 60 * 1000; // 5 minutes
    
    const user = forgotPasswordState.user;
    
    if (method === 'email') {
        // Send via EmailJS
        await sendEmailOTP(user.email, user.name, otp);
    } else if (method === 'phone') {
        // SMS requires backend - show instructions
        await sendSMSOTP(user.phone, otp);
    }
    
    forgotPasswordState.isSending = false;
}

// Send OTP via Email using EmailJS
async function sendEmailOTP(email, name, otp) {
    showToast('📨 Sending OTP to your email...', 2000);
    
    // Check if EmailJS is configured
    if (!isEmailJSConfigured()) {
        // EmailJS not configured - use demo mode
        console.log('⚠️ EmailJS not configured - using demo mode');
        showToast('⚠️ Email service not configured. Using demo mode.', 4000);
        
        setTimeout(() => {
            showToast(`🔐 Demo OTP: ${otp}`, 10000);
            showDemoSetupInstructions();
        }, 1500);
        
        proceedToOTPStep('email');
        return;
    }
    
    try {
        // Send real email via EmailJS
        const response = await emailjs.send(
            EMAILJS_CONFIG.SERVICE_ID,
            EMAILJS_CONFIG.TEMPLATE_ID,
            {
                to_email: email,
                to_name: name || 'User',
                otp_code: otp,
                app_name: 'TaskEarn India',
                validity: '5 minutes'
            }
        );
        
        console.log('✅ Email sent:', response);
        showToast('✅ OTP sent to ' + maskEmail(email), 4000);
        proceedToOTPStep('email');
        
    } catch (error) {
        console.error('❌ EmailJS Error:', error);
        
        // Show error but allow demo mode
        showToast('❌ Email sending failed. Using demo mode.', 4000);
        setTimeout(() => {
            showToast(`🔐 Demo OTP: ${otp}`, 10000);
        }, 1500);
        
        proceedToOTPStep('email');
    }
}

// Send OTP via SMS (requires backend integration)
async function sendSMSOTP(phone, otp) {
    showToast('📱 Sending OTP to your phone...', 2000);
    
    // SMS requires backend service (Twilio, MSG91, etc.)
    // For now, show demo mode with instructions
    
    setTimeout(() => {
        showToast('⚠️ SMS requires backend integration.', 4000);
    }, 1000);
    
    setTimeout(() => {
        showToast(`🔐 Demo OTP: ${otp}`, 10000);
    }, 2500);
    
    // Store OTP for verification
    forgotPasswordState.otp = otp;
    
    proceedToOTPStep('phone');
}

// Proceed to OTP entry step
function proceedToOTPStep(method) {
    const methodText = method === 'email' ? 'email' : 'phone';
    
    // Update step 3 message
    document.getElementById('otpSentMessage').textContent = 
        `Enter the 6-digit code sent to your ${methodText}`;
    
    // Start timer
    startOTPTimer();
    
    goToForgotStep(3);
    
    // Focus first OTP input
    setTimeout(() => {
        document.querySelector('.otp-input')?.focus();
    }, 300);
}

// Show setup instructions for EmailJS
function showDemoSetupInstructions() {
    console.log(`
╔══════════════════════════════════════════════════════════════╗
║         📧 SETUP REAL EMAIL OTP - FREE!                      ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  1. Go to: https://www.emailjs.com/                         ║
║  2. Sign up for FREE account (200 emails/month)             ║
║  3. Add Email Service:                                       ║
║     - Click "Email Services" → "Add New Service"            ║
║     - Choose Gmail → Connect your Gmail account             ║
║  4. Create Email Template:                                   ║
║     - Click "Email Templates" → "Create New Template"       ║
║     - Subject: "TaskEarn OTP: {{otp_code}}"                 ║
║     - Content:                                               ║
║       "Hi {{to_name}},                                      ║
║        Your OTP for TaskEarn password reset is:             ║
║        {{otp_code}}                                         ║
║        Valid for {{validity}}.                              ║
║        - {{app_name}} Team"                                 ║
║  5. Copy your IDs to app.js:                                ║
║     - PUBLIC_KEY: Account → API Keys                        ║
║     - SERVICE_ID: Email Services → Your Service             ║
║     - TEMPLATE_ID: Email Templates → Your Template          ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
    `);
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

function resendOTP() {
    sendOTP(forgotPasswordState.method);
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

function verifyOTP(event) {
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
    
    // Check expiry
    if (Date.now() > forgotPasswordState.otpExpiry) {
        showToast('❌ OTP has expired. Please request a new one.');
        return;
    }
    
    // Verify OTP
    if (enteredOTP === forgotPasswordState.otp) {
        showToast('✅ OTP verified successfully!');
        clearInterval(forgotPasswordState.otpTimer);
        goToForgotStep(4);
        
        // Focus password input
        setTimeout(() => {
            document.getElementById('newPassword')?.focus();
        }, 300);
    } else {
        showToast('❌ Invalid OTP. Please try again.');
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
    
    // Validate password length
    if (newPassword.length < 6) {
        showToast('❌ Password must be at least 6 characters');
        return;
    }
    
    // Validate password strength
    if (!/[A-Za-z]/.test(newPassword) || !/[0-9]/.test(newPassword)) {
        showToast('❌ Password must contain both letters and numbers');
        return;
    }
    
    if (newPassword !== confirmPassword) {
        showToast('❌ Passwords do not match');
        return;
    }
    
    // Show loading state
    if (resetBtn) {
        resetBtn.disabled = true;
        resetBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Resetting...';
    }
    
    try {
        // Hash the new password
        const { salt, hash } = await createPasswordHash(newPassword);
        
        // Update password in storage
        const users = getStoredUsers();
        if (users[forgotPasswordState.user.id]) {
            users[forgotPasswordState.user.id].passwordHash = hash;
            users[forgotPasswordState.user.id].passwordSalt = salt;
            users[forgotPasswordState.user.id].sessionToken = generateSessionToken();
            delete users[forgotPasswordState.user.id].password; // Remove any legacy plain password
            saveUsers(users);
            
            showToast('✅ Password reset successfully!');
            goToForgotStep(5);
        } else {
            showToast('❌ Error resetting password. Please try again.');
        }
    } catch (error) {
        console.error('Password reset error:', error);
        showToast('❌ Error resetting password. Please try again.');
    } finally {
        // Reset button state
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

// ========================================
// PRODUCTION PAYMENT SYSTEM
// ========================================

let currentPaymentData = {
    taskId: null,
    taskTitle: '',
    helperName: '',
    amount: 0,
    helperShare: 0,
    companyShare: 0,
    paymentMethod: 'wallet',
    orderId: null,
    transactionId: null
};

// Open payment modal (called when task marked as completed)
function openPaymentModal(taskId, helperId) {
    const task = tasks.find(t => t.id === taskId);
    if (!task || !currentUser) return;
    
    // If not found in tasks, try myPostedTasks
    const taskToUse = task || myPostedTasks.find(t => t.id === taskId);
    if (!taskToUse) return;
    
    // Calculate amounts
    const amount = taskToUse.price;
    const helperShare = Math.floor(amount * 0.9); // 90% to helper
    const companyShare = amount - helperShare; // 10% to company
    
    // Store payment data
    currentPaymentData = {
        taskId: taskId,
        taskTitle: taskToUse.title || 'Task',
        helperName: taskToUse.helperName || taskToUse.postedBy?.name || 'Helper',
        helperId: helperId || taskToUse.helperId || taskToUse.postedBy?.id,
        amount: amount,
        helperShare: helperShare,
        companyShare: companyShare,
        paymentMethod: 'wallet'
    };
    
    // Validate helperId
    if (!currentPaymentData.helperId) {
        showToast('❌ Helper ID not found. Please refresh and try again.');
        return;
    }
    
    // Update UI
    document.getElementById('paymentTaskTitle').textContent = currentPaymentData.taskTitle;
    document.getElementById('paymentHelperName').textContent = currentPaymentData.helperName;
    document.getElementById('paymentAmount').textContent = `₹${currentPaymentData.amount}`;
    document.getElementById('helperShare').textContent = `₹${currentPaymentData.helperShare}`;
    document.getElementById('companyShare').textContent = `₹${currentPaymentData.companyShare}`;
    document.getElementById('totalPaymentAmount').textContent = `₹${currentPaymentData.amount}`;
    
    // Update wallet balance
    const userWallet = currentUser.wallet || 0;
    document.getElementById('walletBalanceDisplay').innerHTML = `Balance: <strong>₹${userWallet}</strong>`;
    
    if (userWallet < currentPaymentData.amount) {
        document.getElementById('walletStatus').textContent = 'Insufficient Balance';
        document.getElementById('walletStatus').style.color = '#ef4444';
    } else {
        document.getElementById('walletStatus').textContent = 'Available';
        document.getElementById('walletStatus').style.color = '#10b981';
    }
    
    // Reset to step 1
    goToPaymentStep(1);
    openModal('makePaymentModal');
}

// Select payment method
function selectPaymentMethod(element, method) {
    document.querySelectorAll('.payment-option').forEach(opt => opt.classList.remove('active'));
    element.closest('.payment-option').classList.add('active');
    currentPaymentData.paymentMethod = method;
    console.log(`Payment method selected: ${method}`);
}

// Proceed to payment
function proceedToPayment() {
    const method = currentPaymentData.paymentMethod;
    
    if (method === 'wallet') {
        goToPaymentStep(2); // Wallet confirmation
    } else if (method === 'razorpay') {
        initRazorpayPayment();
    } else if (method === 'upi') {
        showUPIOptions();
    }
}

// Wallet payment - Step 2
function goToPaymentStep(step) {
    document.querySelectorAll('.payment-step').forEach(s => s.classList.remove('active'));
    const stepElement = document.getElementById(`paymentStep${step}`);
    if (stepElement) {
        stepElement.classList.add('active');
        
        // Update wallet details for step 2
        if (step === 2) {
            const userWallet = currentUser?.wallet || 0;
            document.getElementById('currentWalletBalance').textContent = `₹${userWallet}`;
            document.getElementById('walletPaymentAmount').textContent = `₹${currentPaymentData.amount}`;
            document.getElementById('remainingBalance').textContent = `₹${Math.max(0, userWallet - currentPaymentData.amount)}`;
        }
    }
}

// Process wallet payment
function processWalletPayment() {
    const userWallet = currentUser?.wallet || 0;
    
    // Check balance
    if (userWallet < currentPaymentData.amount) {
        showPaymentError('Insufficient wallet balance. Please add funds to your wallet.');
        return;
    }
    
    // Show processing
    goToPaymentStep(3);
    
    // Simulate processing
    let progress = 0;
    const interval = setInterval(() => {
        progress += Math.random() * 30;
        if (progress > 100) progress = 100;
        document.getElementById('paymentProgress').style.width = progress + '%';
        
        if (progress >= 100) {
            clearInterval(interval);
            setTimeout(() => completeWalletPayment(), 500);
        }
    }, 300);
}

// Complete wallet payment
function completeWalletPayment() {
    // Verify we have auth token
    const token = localStorage.getItem('taskearn_token');
    if (!token) {
        showPaymentError('Authentication required. Please login again.');
        return;
    }
    
    // Verify helperId exists
    if (!currentPaymentData.helperId) {
        showPaymentError('Helper information missing. Please refresh and try again.');
        return;
    }
    
    console.log('[PAYMENT] Starting wallet payment:', {
        taskId: currentPaymentData.taskId,
        amount: currentPaymentData.amount,
        helperId: currentPaymentData.helperId,
        timestamp: new Date().toISOString()
    });
    
    // Call backend to process wallet payment
    fetch('https://taskearn-production-production.up.railway.app/api/payments/wallet-pay', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
            taskId: currentPaymentData.taskId,
            amount: currentPaymentData.amount,
            helperId: currentPaymentData.helperId
        })
    })
    .then(res => {
        console.log('[PAYMENT] Backend response status:', res.status);
        if (res.status === 401) {
            throw new Error('Authentication failed. Please login again.');
        }
        return res.json();
    })
    .then(data => {
        console.log('[PAYMENT] Backend response data:', data);
        
        if (data.success) {
            // Update local wallet immediately for real-time feedback
            currentUser.wallet = (currentUser.wallet || 0) - currentPaymentData.amount;
            updateUserData(currentUser.id, { wallet: currentUser.wallet });
            
            // Store transaction data
            currentPaymentData.transactionId = data.transactionId;
            
            // Show success
            goToPaymentStep(4);
            document.getElementById('transactionId').textContent = currentPaymentData.transactionId || 'TXN-' + Date.now();
            document.getElementById('amountPaid').textContent = `₹${currentPaymentData.amount}`;
            document.getElementById('helperEarned').textContent = `₹${currentPaymentData.helperShare}`;
            
            showToast('✅ Payment successful! Wallet updated in real-time.');
            console.log('[PAYMENT] Wallet payment completed successfully');
            
            // Refresh dashboard after 2 seconds
            setTimeout(() => {
                renderDashboard();
            }, 2000);
        } else {
            showPaymentError(data.message || 'Payment failed. Please try again.');
            console.error('[PAYMENT] Backend returned error:', data);
        }
    })
    .catch(err => {
        console.error('[PAYMENT] Error processing payment:', err);
        
        let errorMsg = 'Network error. Please check your connection.';
        if (err.message.includes('Authentication')) {
            errorMsg = err.message;
        }
        
        showPaymentError(errorMsg);
    });
}

// Show payment error
function showPaymentError(message) {
    goToPaymentStep(5);
    document.getElementById('errorMessage').textContent = message;
}

// Retry payment
function retryPayment() {
    goToPaymentStep(1);
    currentPaymentData.paymentMethod = 'wallet';
    document.querySelectorAll('.payment-option').forEach(opt => opt.classList.remove('active'));
    document.querySelectorAll('.payment-option')[0].classList.add('active');
}

// Initialize Razorpay payment
function initRazorpayPayment() {
    goToPaymentStep(3);
    
    // Call Razorpay API to create order
    fetch('https://taskearn-production-production.up.railway.app/api/payments/create-order', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
        },
        body: JSON.stringify({
            amount: currentPaymentData.amount,
            taskId: currentPaymentData.taskId
        })
    })
    .then(res => res.json())
    .then(data => {
        if (data.success && data.orderId) {
            currentPaymentData.orderId = data.orderId;
            openRazorpayCheckout(data.orderId);
        } else {
            showPaymentError('Failed to create payment order. Please try again.');
        }
    })
    .catch(err => {
        console.error('Error creating order:', err);
        showPaymentError('Network error. Please try again.');
    });
}

// Open Razorpay checkout
function openRazorpayCheckout(orderId) {
    const options = {
        key: 'rzp_live_SRt7rogPTT3FuK',
        amount: currentPaymentData.amount * 100,
        currency: 'INR',
        order_id: orderId,
        name: 'Workmate4u',
        description: currentPaymentData.taskTitle,
        handler: function(response) {
            verifyRazorpayPayment(response);
        },
        prefill: {
            name: currentUser.name,
            email: currentUser.email,
            contact: currentUser.phone
        },
        theme: {
            color: '#6366f1'
        }
    };
    
    const rzp = new Razorpay(options);
    rzp.open();
}

// Verify Razorpay payment
function verifyRazorpayPayment(response) {
    fetch('https://taskearn-production-production.up.railway.app/api/payments/verify', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
        },
        body: JSON.stringify({
            orderId: currentPaymentData.orderId,
            paymentId: response.razorpay_payment_id,
            signature: response.razorpay_signature
        })
    })
    .then(res => res.json())
    .then(data => {
        if (data.success) {
            currentPaymentData.transactionId = response.razorpay_payment_id;
            goToPaymentStep(4);
            document.getElementById('transactionId').textContent = currentPaymentData.transactionId;
            document.getElementById('amountPaid').textContent = `₹${currentPaymentData.amount}`;
            document.getElementById('helperEarned').textContent = `₹${currentPaymentData.helperShare}`;
        } else {
            showPaymentError(data.message || 'Payment verification failed');
        }
    })
    .catch(err => {
        console.error('Error verifying payment:', err);
        showPaymentError('Failed to verify payment');
    });
}

// Show UPI payment options
function showUPIOptions() {
    const upiString = `upi://pay?pa=workmate4u@bankname&pn=Workmate4u&am=${currentPaymentData.amount}&tr=${Date.now()}&tn=Task%20Payment`;
    
    alert(`UPI Payment Link:\n\nCopy this and paste in your UPI app:\n\n${upiString}\n\nYou can also use:\n1. Google Pay\n2. PhonePe\n3. BHIM\n4. Your Bank's UPI App`);
    
    // Open default UPI handler
    window.location.href = `upi://pay?pa=workmate4u@paytm&pn=Workmate4u&am=${currentPaymentData.amount}&tn=Task`;
}

// Save transaction to backend
function saveTransaction(transaction) {
    fetch('https://taskearn-production-production.up.railway.app/api/wallet/transaction', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
        },
        body: JSON.stringify({
            taskId: transaction.taskId,
            amount: transaction.amount,
            type: transaction.type,
            transactionId: transaction.id,
            status: transaction.status
        })
    })
    .then(res => res.json())
    .then(data => {
        console.log('Transaction saved:', data);
    })
    .catch(err => {
        console.error('Error saving transaction:', err);
    });
}
    }
};
