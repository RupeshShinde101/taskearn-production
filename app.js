// ========================================
// Workmate4u India - Task Marketplace
// Using Leaflet + OpenStreetMap (100% Free)
// Robust GPS with Fallback System
// ========================================

// Production: suppress debug logs
(function() {
    if (location.hostname !== 'localhost' && location.hostname !== '127.0.0.1') {
        const noop = function() {};
        console.log = noop;
        console.debug = noop;
        console.info = noop;
    }
})();

// Dark mode initialization — runs before paint
(function() {
    var t = localStorage.getItem('theme');
    if (t === 'dark' || (!t && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
        document.documentElement.setAttribute('data-theme', 'dark');
    }
})();

function toggleDarkMode() {
    var isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    document.documentElement.setAttribute('data-theme', isDark ? 'light' : 'dark');
    localStorage.setItem('theme', isDark ? 'light' : 'dark');
    var icons = document.querySelectorAll('.dark-mode-toggle i');
    icons.forEach(function(ic) { ic.className = isDark ? 'fas fa-moon' : 'fas fa-sun'; });
    if (typeof updateThemeButtons === 'function') updateThemeButtons();
}

// Explicit setter used by the Appearance card on profile.html
function setTheme(mode) {
    if (mode !== 'light' && mode !== 'dark') return;
    document.documentElement.setAttribute('data-theme', mode);
    localStorage.setItem('theme', mode);
    updateThemeButtons();
}

function updateThemeButtons() {
    var current = document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
    var lb = document.getElementById('themeBtnLight');
    var db = document.getElementById('themeBtnDark');
    if (lb) {
        lb.style.outline = current === 'light' ? '2px solid #3b82f6' : 'none';
        lb.style.outlineOffset = '2px';
    }
    if (db) {
        db.style.outline = current === 'dark' ? '2px solid #60a5fa' : 'none';
        db.style.outlineOffset = '2px';
    }
}
document.addEventListener('DOMContentLoaded', function(){ try { updateThemeButtons(); } catch(_){} });
window.setTheme = setTheme;

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

// Categories that carry a distance-based service charge (Delivery / Pick&Drop).
// All other categories have NO service charge. Commission: 15% delivery/pickup, 17% others.
const DELIVERY_CATEGORIES = new Set(['delivery', 'pickup', 'transport', 'moving']);

// Service Charge based on task category (importance & time)
const SERVICE_CHARGES = {
    // Distance-based categories (Delivery / Moving / Pick&Drop): ₹10–₹40 scaled by km.
    'delivery':  { charge: 15, time: '15-30 mins', level: 'Quick',  distance: true },
    'pickup':    { charge: 15, time: '15-30 mins', level: 'Quick',  distance: true },
    'transport': { charge: 15, time: '10-30 mins', level: 'Quick',  distance: true },
    'document':  { charge: 15, time: '15-30 mins', level: 'Quick' },
    'errand':    { charge: 20, time: '30-45 mins', level: 'Quick' },
    'moving':    { charge: 40, time: '2-6 hours',  level: 'Heavy',  distance: true },
    
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
    'eldercare': { charge: 80, time: '4-8 hours', level: 'Expert' },
    
    // Professional/High-skill tasks - ₹90-100
    'carpentry': { charge: 90, time: '3-6 hours', level: 'Professional' },
    'electrician': { charge: 100, time: '1-4 hours', level: 'Professional' },
    'plumbing': { charge: 100, time: '1-4 hours', level: 'Professional' },
    
    // Default
    'other': { charge: 50, time: '1-3 hours', level: 'Medium' }
};

function getServiceCharge(category, distanceKm) {
    // Service charge ONLY for Delivery/Pick&Drop categories.
    if (!DELIVERY_CATEGORIES.has(category)) return 0;
    const info = SERVICE_CHARGES[category];
    // Distance-based: ₹10–₹40 scaled by km when known.
    if (info && info.distance) {
        if (typeof distanceKm === 'number' && distanceKm > 0) {
            const base = category === 'moving' ? 20 : 10;
            const perKm = category === 'moving' ? 2.5 : 1.5;
            return Math.max(10, Math.min(40, Math.round(base + perKm * distanceKm)));
        }
        return info.charge;
    }
    return info?.charge || 0;
}

function getServiceChargeInfo(category) {
    return SERVICE_CHARGES[category] || SERVICE_CHARGES['other'];
}

// Returns the per-category service charge for a task object.
// Service charge ONLY applies to Delivery/Pick&Drop categories.
// All other categories return 0 regardless of any stored value.
function getTaskServiceCharge(task) {
    if (!task) return 0;
    // Non-delivery categories: always 0 (override any legacy stored value)
    if (!DELIVERY_CATEGORIES.has(task.category)) return 0;
    if (task.service_charge !== undefined && task.service_charge !== null && task.service_charge !== '') {
        return parseFloat(task.service_charge) || 0;
    }
    if (task.serviceCharge !== undefined && task.serviceCharge !== null) {
        return parseFloat(task.serviceCharge) || 0;
    }
    return getServiceCharge(task.category);
}

// Backward-compat alias (older code path used getTaskPostingFee for the per-category charge)
function getTaskPostingFee(task) { return getTaskServiceCharge(task); }

// Check if current user has already rated a specific task (localStorage + server-synced list).
function hasRatedTask(taskId) {
    try {
        var ratedKey = 'rated_tasks_' + (currentUser && currentUser.id ? currentUser.id : 'anon');
        var rated = JSON.parse(localStorage.getItem(ratedKey) || '[]');
        return rated.indexOf(String(taskId)) !== -1;
    } catch(e) { return false; }
}

// Sync server-side rated task IDs into localStorage for accurate UI state.
function syncRatedTaskIds(ids) {
    if (!currentUser || !Array.isArray(ids)) return;
    try {
        var ratedKey = 'rated_tasks_' + currentUser.id;
        var existing = JSON.parse(localStorage.getItem(ratedKey) || '[]');
        ids.forEach(function(id) {
            if (existing.indexOf(String(id)) === -1) existing.push(String(id));
        });
        localStorage.setItem(ratedKey, JSON.stringify(existing));
    } catch(e) {}
}

// Task Posting Fee: DISABLED. Previously 5% platform fee — commented out for future use.
// function getTaskPlatformFee(task) {
//     if (!task) return 0;
//     const price = parseFloat(task.price || task.amount || 0) || 0;
//     const sc = getTaskServiceCharge(task);
//     return Math.round((price + sc) * 0.05 * 100) / 100;
// }
function getTaskPlatformFee(task) { return 0; } // DISABLED — no posting fee

// Returns the final task value the poster pays = price + service charge (no posting fee).
function getTaskFinalValue(task) {
    if (!task) return 0;
    const price = parseFloat(task.price || task.amount || 0) || 0;
    return price + getTaskServiceCharge(task);
}

// Commission rates: Delivery/Pickup/Transport/Moving = 15%, all others = 17%.
const DELIVERY_COMMISSION_CATS = new Set(['delivery', 'pickup', 'transport', 'moving']);
function getCommissionRate(category) {
    return DELIVERY_COMMISSION_CATS.has(category) ? 0.15 : 0.17;
}

// Returns what the helper actually receives after platform commission.
// Commission: 15% for delivery/pickup/transport/moving, 17% for all others.
function getHelperEarnings(task) {
    if (!task) return 0;
    const price = parseFloat(task.price || task.amount || 0) || 0;
    const sc = parseFloat(task.service_charge != null ? task.service_charge :
                          task.serviceCharge != null ? task.serviceCharge : getTaskServiceCharge(task)) || 0;
    const rate = getCommissionRate(task.category || 'other');
    return Math.round((price + sc) * (1 - rate) * 100) / 100;
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
    // Vibrate on mobile for important notifications
    if (navigator.vibrate && (type === 'success' || type === 'error')) {
        navigator.vibrate(type === 'error' ? [100, 50, 100] : [80]);
    }

    // Play notification sound using Web Audio API (only after user gesture)
    try {
        if (window._userHasInteracted) {
            var ac = window._notifAudioCtx || (window._notifAudioCtx = new (window.AudioContext || window.webkitAudioContext)());
            if (ac.state === 'suspended') ac.resume();
            var osc = ac.createOscillator();
            var gain = ac.createGain();
            osc.connect(gain);
            gain.connect(ac.destination);
            gain.gain.value = 0.08;
            osc.frequency.value = type === 'error' ? 300 : type === 'success' ? 800 : 600;
            osc.type = 'sine';
            osc.start();
            osc.stop(ac.currentTime + 0.15);
        }
    } catch (e) {}

    // Create notification container if it doesn't exist
    let container = document.getElementById('notification-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'notification-container';
        container.style.cssText = [
            'position:fixed',
            'bottom:24px',
            'left:50%',
            'transform:translateX(-50%)',
            'z-index:10000',
            'display:flex',
            'flex-direction:column',
            'align-items:center',
            'gap:10px',
            'pointer-events:none',
            'width:max-content',
            'max-width:calc(100vw - 32px)'
        ].join(';');
        document.body.appendChild(container);
    }

    // Icon + colours per type
    const META = {
        success: { icon: 'fa-circle-check',     bg: '#10b981', border: '#059669' },
        error:   { icon: 'fa-circle-xmark',      bg: '#ef4444', border: '#dc2626' },
        warning: { icon: 'fa-triangle-exclamation', bg: '#f59e0b', border: '#d97706' },
        offline: { icon: 'fa-wifi-slash',         bg: '#64748b', border: '#475569' },
        info:    { icon: 'fa-circle-info',        bg: '#6366f1', border: '#4f46e5' },
    };
    const m = META[type] || META.info;

    // Create notification element
    const notification = document.createElement('div');
    notification.style.cssText = [
        `background:${m.bg}`,
        `border:1.5px solid ${m.border}`,
        'color:#fff',
        'padding:11px 16px 11px 14px',
        'border-radius:12px',
        'box-shadow:0 8px 24px rgba(0,0,0,0.18)',
        'animation:toastIn 0.28s cubic-bezier(0.34,1.56,0.64,1) forwards',
        'font-size:14px',
        'line-height:1.4',
        'display:flex',
        'align-items:center',
        'gap:10px',
        'pointer-events:all',
        'cursor:pointer',
        'max-width:360px',
        'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif'
    ].join(';');

    const safeMsg = message.replace(/</g, '&lt;').replace(/>/g, '&gt;');
    notification.innerHTML = `
        <i class="fas ${m.icon}" style="font-size:16px;flex-shrink:0;"></i>
        <span style="flex:1;">${safeMsg}</span>
        <button aria-label="Dismiss" style="background:none;border:none;color:#fff;opacity:0.7;cursor:pointer;padding:0 0 0 6px;font-size:16px;line-height:1;flex-shrink:0;" onclick="this.closest('[id]').remove ? this.closest('div').remove() : null">&times;</button>
    `;
    container.appendChild(notification);
    
    // Add animation keyframes if not present
    if (!document.getElementById('notification-styles')) {
        const style = document.createElement('style');
        style.id = 'notification-styles';
        style.textContent = `
            @keyframes toastIn {
                from { opacity: 0; transform: translateY(16px) scale(0.95); }
                to   { opacity: 1; transform: translateY(0)   scale(1);    }
            }
            @keyframes toastOut {
                from { opacity: 1; transform: translateY(0)   scale(1);    }
                to   { opacity: 0; transform: translateY(12px) scale(0.95); }
            }
        `;
        document.head.appendChild(style);
    }

    container.appendChild(notification);

    // Progress bar for auto-dismiss
    const bar = document.createElement('div');
    bar.style.cssText = [
        'position:absolute',
        'bottom:0',
        'left:0',
        `width:100%`,
        'height:3px',
        'background:rgba(255,255,255,0.4)',
        'border-radius:0 0 12px 12px',
        `transition:width ${duration}ms linear`
    ].join(';');
    notification.style.position = 'relative';
    notification.style.overflow = 'hidden';
    notification.appendChild(bar);
    requestAnimationFrame(() => requestAnimationFrame(() => { bar.style.width = '0%'; }));

    // Remove after duration
    const timeout = setTimeout(() => {
        notification.style.animation = 'toastOut 0.25s ease-in forwards';
        setTimeout(() => notification.remove(), 250);
    }, duration);

    // Click dismiss
    notification.addEventListener('click', () => {
        clearTimeout(timeout);
        notification.style.animation = 'toastOut 0.25s ease-in forwards';
        setTimeout(() => notification.remove(), 250);
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
        Object.assign(currentUser, Object.fromEntries(
            Object.entries(updates).filter(([k]) => !k.startsWith('__'))
        ));
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
                // Verify token is still valid with the backend
                if (typeof AuthAPI !== 'undefined' && AuthAPI.getCurrentUser) {
                    try {
                        const verifyResult = await AuthAPI.getCurrentUser();
                        if (!verifyResult || !verifyResult.success || !verifyResult.user) {
                            console.warn('⚠️ API token invalid or expired — clearing session');
                            clearCurrentSession();
                            return null;
                        }
                        console.log('✅ API token verified with backend');
                        // Merge locally-cached task data into fresh server profile so tasks
                        // show immediately on the first render (before syncUserTasksFromServer).
                        return {
                            ...verifyResult.user,
                            acceptedTasks:  apiUser.acceptedTasks  || verifyResult.user.acceptedTasks,
                            postedTasks:    apiUser.postedTasks    || verifyResult.user.postedTasks,
                            completedTasks: apiUser.completedTasks || verifyResult.user.completedTasks,
                            totalEarnings:  apiUser.totalEarnings  != null ? apiUser.totalEarnings  : verifyResult.user.totalEarnings,
                            tasksCompleted: apiUser.tasksCompleted != null ? apiUser.tasksCompleted : verifyResult.user.tasksCompleted
                        };
                    } catch (verifyErr) {
                        // Network error — fall back to cached user so offline usage still works
                        console.warn('⚠️ Could not verify token with server (offline?), using cached session:', verifyErr.message);
                        return apiUser;
                    }
                }
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
        localOnly: task.localOnly || false,
        accepted_by: task.accepted_by || task.acceptedBy || null,
        helper_name: task.helper_name || null,
        helper_phone: task.helper_phone || null,
        helper_rating: task.helper_rating || null,
        helper_tasks_completed: task.helper_tasks_completed || null
    };
}

// Deserialize task from storage (convert ISO strings back to dates)
function deserializeTask(task) {
    return {
        ...task,
        postedAt: task.postedAt ? new Date(task.postedAt) : new Date(),
        expiresAt: task.expiresAt ? new Date(task.expiresAt) : new Date(Date.now() + 24 * 3600000)
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
let myPaidPostedTasks = []; // Poster's paid/completed task history (for rating helper)

// ========================================
// LIVE CATEGORY COUNTS
// ========================================

// ========================================
// AI-MATCHED RECOMMENDED TASKS
// ========================================

async function loadRecommendedTasks() {
    const container = document.getElementById('recommendedTasksList');
    const section   = document.getElementById('recommendedSection');
    if (!container || !section) return;
    if (!currentUser) { section.style.display = 'none'; return; }

    try {
        if (typeof TasksAPI === 'undefined' || !TasksAPI.getRecommended) return;

        const lat = userLocation ? userLocation.lat : null;
        const lng = userLocation ? userLocation.lng : null;
        if (!lat || !lng) return;

        const result = await TasksAPI.getRecommended(lat, lng);
        if (!result || !result.success || !result.tasks || result.tasks.length === 0) {
            section.style.display = 'none';
            return;
        }

        section.style.display = 'block';
        container.innerHTML = result.tasks.map(t => {
            const distText = t.distanceKm != null ? `${t.distanceKm.toFixed(1)} km` : '?';
            const total = Math.round((parseFloat(t.price)||0) + (parseFloat(t.service_charge)||0));
            const catLabel = formatCategory ? formatCategory(t.category) : t.category;
            return `
            <div class="task-card recommended-task-card" onclick="openTaskDetail(${t.id})">
                <div class="task-card-top">
                    <span class="task-category-badge">${catLabel}</span>
                    <span class="task-price-badge">₹${total}</span>
                </div>
                <h4 class="task-title">${t.title}</h4>
                <p class="task-desc">${(t.description || '').slice(0, 80)}${t.description && t.description.length > 80 ? '…' : ''}</p>
                <div class="task-meta">
                    <span>📍 ${distText}</span>
                    <span>⏱️ ${getTimeLeft ? getTimeLeft(t.expiresAt) : ''}</span>
                </div>
            </div>`;
        }).join('');
    } catch (err) {
        console.log('Recommended tasks unavailable:', err.message);
        if (section) section.style.display = 'none';
    }
}

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
/** Map a raw server notification row to the UI shape */
function _mapServerNotification(n) {
    let action = null;
    try {
        if (n.data && typeof n.data === 'string') action = JSON.parse(n.data);
        else if (n.data && typeof n.data === 'object') action = n.data;
    } catch (e) {}

    const typeMap = {
        task_completed: 'warning', task_accepted: 'success', task_assigned: 'success',
        task_completed_helper: 'success', task_posted: 'info', task_released: 'warning',
        task_expired: 'warning', payment_received: 'success', payment_done: 'success',
        payment_completed: 'warning', wallet_topup: 'success', withdrawal_requested: 'info',
        account_suspended: 'error', account_restored: 'success', account_banned: 'error'
    };
    return {
        id: n.id,
        type: typeMap[n.notification_type] || 'info',
        title: n.title || 'Notification',
        message: n.message || '',
        taskId: n.task_id,
        read: n.status === 'read',
        createdAt: n.created_at,
        action
    };
}

async function syncNotificationsFromServer() {
    if (!currentUser) return [];

    try {
        const r = await apiRequest('/notifications', { method: 'GET' });
        const result = (r.data) || {};

        if (r.success && result.success && Array.isArray(result.notifications)) {
            const serverNotifications = result.notifications.map(_mapServerNotification);

            // Keep any local-only notifications (client-side ones with timestamp IDs)
            const localNotifications = loadNotifications();
            const serverIds = new Set(serverNotifications.map(n => n.id));
            const localOnly = localNotifications.filter(n => !serverIds.has(n.id));
            const merged = [...serverNotifications, ...localOnly];

            localStorage.setItem(`notifications_${currentUser.id}`, JSON.stringify(merged));
            notifications = merged;
            updateNotificationUI();
            return merged;
        }
    } catch (error) {
        console.warn('Could not sync notifications from server:', error.message);
    }

    // Fallback: always ensure in-memory array matches localStorage
    const local = loadNotifications();
    if (local.length > 0) {
        notifications = local;
        updateNotificationUI();
    }
    return local;
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
                const hasActions = n.action && (n.action.type === 'payment' || n.action.type === 'task' || n.action.type === 'verify_and_pay' || n.action.type === 'mark_complete');
                const actionButton = hasActions ? `
                    <button class="notification-action-btn" onclick="event.stopPropagation(); handleNotificationAction(${n.id}, '${n.action.type}', ${n.taskId || 'null'})">
                        ${n.action.label || (n.action.type === 'payment' ? 'Pay Now' : 'View')}
                    </button>
                ` : '';
                
                return `
                    <div class="notification-item ${n.read ? '' : 'unread'}" onclick="markAsRead(${n.id}); window.location.href='notifications.html';">
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
        case 'warning': return 'fa-exclamation-triangle';
        case 'error': return 'fa-times-circle';
        case 'task': return 'fa-tasks';
        case 'payment': return 'fa-rupee-sign';
        case 'info': return 'fa-info-circle';
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
    if (text == null) return '';
    const div = document.createElement('div');
    div.textContent = String(text);
    return div.innerHTML;
}

// Detect a "Required vehicle: <Label>" prefix in a task description and
// return a small descriptor for badge rendering, or null if absent.
function getRequiredVehicle(text) {
    if (!text) return null;
    const m = String(text).match(/Required vehicle:\s*([^\n—\-]+)/i);
    if (!m) return null;
    const label = m[1].trim();
    let key = null;
    if (/bike/i.test(label)) key = 'bike';
    else if (/auto/i.test(label)) key = 'auto';
    else if (/mini/i.test(label)) key = 'mini';
    else if (/sedan/i.test(label)) key = 'sedan';
    return { key, label };
}

// Render task description. Detects the Q&A template format produced by
// category-picker.js and renders questions/answers as readable cards.
// opts.compact: card-list mode → show only the answers as a short summary.
function formatTaskDescription(text, opts) {
    opts = opts || {};
    if (text == null) return '';
    let raw = String(text).trim();
    if (!raw) return '';
    // Strip the "Required vehicle:" prefix line — it's surfaced as a
    // separate badge on the card; keep the description focused on the task.
    raw = raw.replace(/^[^\n]*Required vehicle:[^\n]*\n+/i, '').trim();
    const hasQA = /^Q\d+\./m.test(raw);
    if (!hasQA) {
        return escapeHtml(raw).replace(/\n/g, '<br>');
    }
    const lines = raw.split('\n');
    const blocks = [];
    let curQ = null, curA = [];
    let extra = [], inExtra = false;
    for (const line of lines) {
        const qm = line.match(/^Q(\d+)\.\s*(.*)$/);
        const am = line.match(/^A:\s*(.*)$/);
        const exm = line.match(/^Additional details[^:]*:\s*(.*)$/i);
        if (qm) {
            if (curQ !== null) blocks.push({ q: curQ, a: curA.join('\n').trim() });
            curQ = qm[2].trim(); curA = []; inExtra = false;
        } else if (am) {
            curA.push(am[1]);
        } else if (exm) {
            if (curQ !== null) { blocks.push({ q: curQ, a: curA.join('\n').trim() }); curQ = null; }
            inExtra = true;
            if (exm[1]) extra.push(exm[1]);
        } else if (inExtra) {
            extra.push(line);
        } else if (curQ !== null) {
            if (line.trim()) curA.push(line);
        }
    }
    if (curQ !== null) blocks.push({ q: curQ, a: curA.join('\n').trim() });
    const extraText = extra.join('\n').trim();

    if (opts.compact) {
        const parts = blocks.map(b => b.a).filter(Boolean);
        if (extraText) parts.push(extraText);
        return escapeHtml(parts.join(' • '));
    }
    let html = '<div class="task-qa">';
    for (const b of blocks) {
        const ans = b.a
            ? escapeHtml(b.a).replace(/\n/g, '<br>')
            : '<em class="qa-empty">(not answered)</em>';
        html += `<div class="qa-item"><div class="qa-q">${escapeHtml(b.q)}</div><div class="qa-a">${ans}</div></div>`;
    }
    html += '</div>';
    if (extraText) {
        html += `<div class="qa-extra"><strong>Additional details</strong><div>${escapeHtml(extraText).replace(/\n/g, '<br>')}</div></div>`;
    }
    return html;
}

// ========================================
// ACCOUNT DELETION
// ========================================
function confirmDeleteAccount() {
    const pwd = prompt('This action is PERMANENT. Type your password to confirm:');
    if (!pwd) return;
    if (!confirm('Are you absolutely sure? All your data will be permanently deleted.')) return;
    
    apiRequest('/user/delete-account', {
        method: 'POST',
        body: JSON.stringify({ password: pwd })
    })
    .then(r => {
        const data = r.data || {};
        if (data.success) {
            alert('Account deleted. We\'re sorry to see you go.');
            localStorage.clear();
            window.location.reload();
        } else {
            alert(data.message || 'Failed to delete account');
        }
    })
    .catch(() => alert('Could not reach the server. Please check your connection and try again.'));
}

// ========================================
// DISPUTE / REPORT
// ========================================
function openDisputeModal(taskId) {
    closeModal('taskDetailModal');
    const reasons = ['Task description misleading', 'Inappropriate content', 'Suspected scam', 'Payment issue', 'Other'];
    const optionsHtml = reasons.map(r => `<option value="${r}">${r}</option>`).join('');
    
    const html = `
        <div style="padding:20px;">
            <h3 style="margin-bottom:15px;"><i class="fas fa-flag" style="color:#ef4444;"></i> Report / Dispute Task #${taskId}</h3>
            <label style="font-weight:600;display:block;margin-bottom:5px;">Reason</label>
            <select id="disputeReason" style="width:100%;padding:10px;border:1px solid var(--border,#e2e8f0);border-radius:8px;margin-bottom:12px;font-size:14px;">
                <option value="">-- Select reason --</option>
                ${optionsHtml}
            </select>
            <label style="font-weight:600;display:block;margin-bottom:5px;">Details (optional)</label>
            <textarea id="disputeDetails" maxlength="500" rows="3" style="width:100%;padding:10px;border:1px solid var(--border,#e2e8f0);border-radius:8px;resize:vertical;font-size:14px;" placeholder="Describe the issue..."></textarea>
            <div style="display:flex;gap:10px;margin-top:15px;">
                <button class="btn btn-outline" onclick="closeModal('disputeModal')" style="flex:1;padding:10px;">Cancel</button>
                <button class="btn" onclick="submitDispute(${taskId})" style="flex:1;padding:10px;background:#ef4444;color:white;border:none;border-radius:8px;cursor:pointer;font-weight:600;">Submit Report</button>
            </div>
        </div>
    `;
    
    let modal = document.getElementById('disputeModal');
    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'disputeModal';
        modal.className = 'modal';
        modal.innerHTML = `<div class="modal-content" style="max-width:450px;">${html}</div>`;
        document.body.appendChild(modal);
    } else {
        modal.querySelector('.modal-content').innerHTML = html;
    }
    openModal('disputeModal');
}

function submitDispute(taskId) {
    const reason = document.getElementById('disputeReason').value;
    const details = document.getElementById('disputeDetails').value;
    if (!reason) { alert('Please select a reason'); return; }
    
    apiRequest('/tasks/' + taskId + '/dispute', {
        method: 'POST',
        body: JSON.stringify({ reason, details })
    })
    .then(r => {
        const data = r.data || {};
        closeModal('disputeModal');
        alert(data.message || (data.success ? 'Dispute filed!' : 'Failed'));
    })
    .catch(() => alert('Could not reach the server. Please check your connection and try again.'));
}

// ========================================
// BOOKMARKS
// ========================================
function toggleBookmark(taskId, el) {
    apiRequest('/tasks/' + taskId + '/bookmark', {
        method: 'POST'
    })
    .then(r => {
        const data = r.data || {};
        if (data.success) {
            const icon = el.querySelector('i');
            if (data.bookmarked) {
                icon.className = 'fas fa-bookmark';
                el.style.color = '#667eea';
            } else {
                icon.className = 'far fa-bookmark';
                el.style.color = '#94a3b8';
            }
        }
    })
    .catch(() => {});
}

// ========================================
// TRANSACTION EXPORT
// ========================================
function exportTransactionsCSV() {
    const token = localStorage.getItem('taskearn_token');
    const headers = token ? { 'Authorization': 'Bearer ' + token } : {};
    // Try direct first, then proxy fallback for ISP-blocked carriers
    fetch(API_BASE_URL + '/wallet/export', { headers })
        .then(r => { if (!r.ok) throw new Error('Failed'); return r.blob(); })
        .catch(() => fetch('/.netlify/functions/api-proxy/api/wallet/export', { headers }).then(r => { if (!r.ok) throw new Error('Failed'); return r.blob(); }))
    .then(blob => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'transactions.csv';
        a.click();
        URL.revokeObjectURL(url);
    })
    .catch(() => alert('Failed to export. Try again.'));
}

function toggleNotifications() {
    const dropdown = document.getElementById('notificationDropdown');
    if (!dropdown) return;

    // Move dropdown to body once so it escapes any stacking context / overflow:hidden parents
    if (!dropdown.dataset.movedToBody) {
        document.body.appendChild(dropdown);
        dropdown.dataset.movedToBody = 'true';
    }

    const isOpen = dropdown.classList.toggle('active');

    if (isOpen) {
        // Position near bell on desktop
        const bell = document.querySelector('.notification-bell');
        if (bell && window.innerWidth > 768) {
            const rect = bell.getBoundingClientRect();
            dropdown.style.top = (rect.bottom + 8) + 'px';
            dropdown.style.right = (window.innerWidth - rect.right) + 'px';
            dropdown.style.left = 'auto';
            dropdown.style.transform = 'none';
        }

        // Immediately render whatever we have in memory (fast, may be stale)
        updateNotificationUI();

        // Then fetch fresh from server and re-render
        _fetchAndRenderNotifications();
    }

    // Manage backdrop overlay
    let overlay = document.getElementById('notificationOverlay');
    if (isOpen) {
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'notificationOverlay';
            overlay.className = 'notification-overlay';
            document.body.appendChild(overlay);
        }
        overlay.classList.add('active');
        overlay.ontouchend = function(e) {
            if (e.target === overlay) { e.preventDefault(); e.stopPropagation(); toggleNotifications(); }
        };
        overlay.onmousedown = function(e) {
            e.preventDefault(); e.stopPropagation(); toggleNotifications();
        };
    } else if (overlay) {
        overlay.classList.remove('active');
    }
}

/** Fetch notifications from server, update in-memory array, and re-render dropdown list */
async function _fetchAndRenderNotifications() {
    if (!currentUser) return;
    const list = document.getElementById('notificationList');

    // Show loading skeleton inside the list while fetching
    if (list && (!notifications || notifications.length === 0)) {
        list.innerHTML = '<div style="padding:20px;text-align:center;color:#94a3b8;"><i class="fas fa-spinner fa-spin" style="font-size:1.4rem;"></i></div>';
    }

    try {
        const r = await apiRequest('/notifications', { method: 'GET' });
        const result = (r && r.data) || {};

        if (r && r.success && result.success && Array.isArray(result.notifications)) {
            const serverNotifications = result.notifications.map(_mapServerNotification);
            const localNotifications = loadNotifications();
            const serverIds = new Set(serverNotifications.map(n => n.id));
            const localOnly = localNotifications.filter(n => !serverIds.has(n.id));
            const merged = [...serverNotifications, ...localOnly];

            localStorage.setItem(`notifications_${currentUser.id}`, JSON.stringify(merged));
            notifications = merged;
        } else if (!notifications || notifications.length === 0) {
            // Server failed — fall back to localStorage
            const local = loadNotifications();
            if (local.length > 0) notifications = local;
        }
    } catch (e) {
        // Network error — use localStorage if in-memory is empty
        if (!notifications || notifications.length === 0) {
            const local = loadNotifications();
            if (local.length > 0) notifications = local;
        }
    }

    // Re-render (dropdown may still be open)
    const dropdown = document.getElementById('notificationDropdown');
    if (dropdown && dropdown.classList.contains('active')) {
        updateNotificationUI();
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
    } else if (actionType === 'verify_and_pay' && taskId) {
        console.log(`✅ Verify & Pay for task ${taskId} from notification`);
        closeNotifDropdown();
        await showPaymentInvoice(taskId);
    } else if (actionType === 'mark_complete' && taskId) {
        console.log(`🎉 Mark completed for task ${taskId} from notification`);
        closeNotifDropdown();
        await markTaskCompleted(taskId);
    } else if (actionType === 'task' && taskId) {
        console.log(`📋 Opening task ${taskId}`);
        closeNotifDropdown();
        // Navigate to posted tasks page so poster can see helper info
        if (window.location.pathname.includes('posted.html')) {
            // Already on posted page, just scroll to the task
            const taskElement = document.querySelector(`[data-task-id="${taskId}"]`);
            if (taskElement) {
                taskElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
                taskElement.style.boxShadow = '0 0 0 3px #4ade80';
                setTimeout(() => { taskElement.style.boxShadow = ''; }, 3000);
            }
        } else {
            window.location.href = 'posted.html?highlight=' + taskId;
        }
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

// Standalone sync of the current user's posted/accepted/completed tasks from the server.
// Called independently of TasksAPI.getAll() so tasks always appear even if the
// global task list endpoint fails.
async function syncUserTasksFromServer() {
    if (!currentUser) return;
    try {
        const userTasksResult = await UserAPI.getTasks();
        if (!userTasksResult || !userTasksResult.success) {
            console.warn('syncUserTasksFromServer: API returned failure', userTasksResult);
            return;
        }

        const cutoff48h = Date.now() - (48 * 3600 * 1000);

        // ── Sync posted tasks ──────────────────────────────────────────────
        if (userTasksResult.postedTasks && userTasksResult.postedTasks.length > 0) {
            const dbPosted = userTasksResult.postedTasks;
            const dbPostedMap = {};
            dbPosted.forEach(t => { dbPostedMap[t.id] = t; });

            // Update existing local tasks with fresh DB statuses
            myPostedTasks = myPostedTasks.map(pt => {
                const dbTask = dbPostedMap[pt.id];
                if (!dbTask) return pt;
                return {
                    ...pt,
                    status: dbTask.status,
                    acceptedBy: dbTask.accepted_by || pt.acceptedBy,
                    accepted_by: dbTask.accepted_by || pt.accepted_by,
                    completedAt: dbTask.completed_at || pt.completedAt,
                    price: parseFloat(dbTask.price) || pt.price,
                    service_charge: parseFloat(dbTask.service_charge || 0),
                    helper_name: dbTask.helper_name || pt.helper_name,
                    helper_phone: dbTask.helper_phone || pt.helper_phone,
                    helper_rating: dbTask.helper_rating || pt.helper_rating,
                    helper_tasks_completed: dbTask.helper_tasks_completed || pt.helper_tasks_completed
                };
            });

            // Move any already-local tasks now marked paid/completed into history
            // (handles login case where postedTasks from API includes all statuses)
            myPostedTasks.forEach(pt => {
                if (pt.status === 'paid' || pt.status === 'payment_released' || pt.status === 'completed') {
                    if (!myPaidPostedTasks.find(p => p.id === pt.id)) {
                        myPaidPostedTasks.push({
                            id: pt.id, title: pt.title, category: pt.category,
                            price: pt.price, service_charge: pt.service_charge || 0,
                            status: pt.status, accepted_by: pt.accepted_by || pt.acceptedBy,
                            helper_name: pt.helper_name || 'Helper', postedAt: pt.postedAt
                        });
                    }
                }
            });

            // Add DB tasks not yet in local list
            dbPosted.forEach(dbTask => {
                if (dbTask.status === 'active' && new Date(dbTask.expires_at) <= new Date()) return;
                if (dbTask.status === 'paid' || dbTask.status === 'payment_released' || dbTask.status === 'completed') {
                    // Add to paid/released/completed history (task done — move out of active section)
                    if (!myPaidPostedTasks.find(pt => pt.id === dbTask.id)) {
                        myPaidPostedTasks.push({
                            id: dbTask.id, title: dbTask.title, category: dbTask.category,
                            price: parseFloat(dbTask.price),
                            service_charge: parseFloat(dbTask.service_charge || 0),
                            status: dbTask.status, accepted_by: dbTask.accepted_by,
                            helper_name: dbTask.helper_name || 'Helper', postedAt: dbTask.posted_at
                        });
                    }
                    return;
                }
                if (!myPostedTasks.find(pt => pt.id === dbTask.id)) {
                    myPostedTasks.push({
                        id: dbTask.id, title: dbTask.title, description: dbTask.description,
                        category: dbTask.category, price: parseFloat(dbTask.price),
                        service_charge: parseFloat(dbTask.service_charge || 0),
                        status: dbTask.status,
                        postedAt: new Date(dbTask.posted_at),
                        expiresAt: dbTask.expires_at ? new Date(dbTask.expires_at) : new Date(Date.now() + 24 * 3600000),
                        acceptedBy: dbTask.accepted_by, accepted_by: dbTask.accepted_by,
                        completedAt: dbTask.completed_at,
                        helper_name: dbTask.helper_name, helper_phone: dbTask.helper_phone,
                        helper_rating: dbTask.helper_rating,
                        helper_tasks_completed: dbTask.helper_tasks_completed,
                        postedBy: { id: currentUser.id, name: currentUser.name },
                        location: { lat: dbTask.location_lat, lng: dbTask.location_lng, address: dbTask.location_address }
                    });
                }
            });

            // Remove completed, paid, payment_released, and expired-active tasks
            myPostedTasks = myPostedTasks.filter(t => {
                if (t.status === 'paid' || t.status === 'payment_released' || t.status === 'completed') return false;
                if (t.status === 'active' && t.expiresAt && new Date(t.expiresAt) <= new Date()) return false;
                return true;
            });
        }

        // ── Sync accepted tasks ────────────────────────────────────────────
        if (Array.isArray(userTasksResult.acceptedTasks)) {
            const dbAccepted = userTasksResult.acceptedTasks;
            const dbAcceptedMap = {};
            dbAccepted.forEach(t => { dbAcceptedMap[t.id] = t; });

            // Only remove local tasks when DB returned a non-empty list (authoritative).
            // An empty list from the DB is trusted — user has no accepted tasks.
            myAcceptedTasks = myAcceptedTasks.filter(at => !!dbAcceptedMap[at.id]);

            // Update remaining local tasks with DB data
            myAcceptedTasks = myAcceptedTasks.map(at => {
                const dbTask = dbAcceptedMap[at.id];
                if (!dbTask) return at;
                return {
                    ...at, status: dbTask.status,
                    completedAt: dbTask.completed_at || at.completedAt,
                    price: parseFloat(dbTask.price) || at.price,
                    service_charge: parseFloat(dbTask.service_charge || 0),
                    poster_name: dbTask.poster_name || at.poster_name,
                    poster_phone: dbTask.poster_phone || at.poster_phone,
                    poster_email: dbTask.poster_email || at.poster_email
                };
            });

            // Add DB tasks not in local list
            dbAccepted.forEach(dbTask => {
                // Note: do NOT skip based on expiry — accepted tasks should always show
                // regardless of the original posting expiry window
                if (myAcceptedTasks.find(at => at.id == dbTask.id)) return;
                const taskObj = {
                    id: dbTask.id, title: dbTask.title, description: dbTask.description,
                    category: dbTask.category, price: parseFloat(dbTask.price),
                    service_charge: parseFloat(dbTask.service_charge || 0),
                    status: dbTask.status,
                    postedAt: new Date(dbTask.posted_at),
                    expiresAt: dbTask.expires_at ? new Date(dbTask.expires_at) : new Date(Date.now() + 24 * 3600000),
                    completedAt: dbTask.completed_at,
                    postedBy: { id: dbTask.posted_by, name: dbTask.poster_name || 'Poster' },
                    poster_name: dbTask.poster_name || 'Poster',
                    poster_phone: dbTask.poster_phone || '',
                    poster_email: dbTask.poster_email || '',
                    poster_user_id: dbTask.poster_user_id || dbTask.posted_by || '',
                    location: { lat: dbTask.location_lat, lng: dbTask.location_lng, address: dbTask.location_address || '' }
                };
                if (dbTask.status === 'paid' || dbTask.status === 'completed') {
                    if (!myCompletedTasks.find(ct => ct.id == dbTask.id)) {
                        taskObj.earnedAmount = getHelperEarnings(taskObj);
                        taskObj.paidAt = dbTask.paid_at || dbTask.helper_final_completed_at || dbTask.completed_at || new Date().toISOString();
                        myCompletedTasks.push(taskObj);
                    }
                } else {
                    myAcceptedTasks.push(taskObj);
                }
            });

            // Move newly-paid/completed items from myAcceptedTasks to myCompletedTasks
            myAcceptedTasks.filter(t => t.status === 'paid' || t.status === 'completed').forEach(pt => {
                if (!myCompletedTasks.find(ct => ct.id == pt.id)) {
                    pt.earnedAmount = getHelperEarnings(pt);
                    pt.paidAt = pt.paidAt || pt.paid_at || pt.helper_final_completed_at || new Date().toISOString();
                    myCompletedTasks.push(pt);
                    currentUser.tasksCompleted = (currentUser.tasksCompleted || 0) + 1;
                    currentUser.totalEarnings = Math.round(
                        (parseFloat(currentUser.totalEarnings || 0) + pt.earnedAmount) * 100) / 100;
                }
            });

            // Remove only paid/completed from myAcceptedTasks
            // Do NOT filter by expiry — accepted tasks stay visible until paid/completed
            myAcceptedTasks = myAcceptedTasks.filter(t => {
                if (t.status === 'paid' || t.status === 'completed') return false;
                return true;
            });

            // Remove completed tasks older than 48h from myCompletedTasks
            myCompletedTasks = myCompletedTasks.filter(t =>
                !t.paidAt || new Date(t.paidAt).getTime() > cutoff48h
            );
        }

        // ── Sync rated task IDs ────────────────────────────────────────────
        if (userTasksResult.ratedTaskIds) {
            syncRatedTaskIds(userTasksResult.ratedTaskIds);
        }

        // Persist to localStorage
        updateUserData(currentUser.id, {
            postedTasks: serializeTasks(myPostedTasks),
            acceptedTasks: serializeTasks(myAcceptedTasks),
            completedTasks: serializeTasks(myCompletedTasks),
            tasksCompleted: currentUser.tasksCompleted,
            totalEarnings: currentUser.totalEarnings
        });

        // Notify poster of tasks awaiting payment
        const awaitingPayment = myPostedTasks.filter(t => t.status === 'completed');
        if (awaitingPayment.length > 0) {
            showToast(`💰 ${awaitingPayment.length} task(s) completed and awaiting your payment!`, 5000);
        }

    } catch (e) {
        console.warn('syncUserTasksFromServer failed:', e.message);
    }
}

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
                
                // ✅ Sync myPostedTasks and myAcceptedTasks with REAL DB statuses.
                // Delegates to the standalone syncUserTasksFromServer() function.
                if (currentUser) {
                    try {
                        await syncUserTasksFromServer();
                    } catch (e) {
                        console.warn('Could not sync user tasks from DB:', e.message);
                    }
                }
                
                console.log('✅ Loaded', serverTasks.length, 'tasks from server');
                console.log('📋 Total tasks now:', tasks.length);
                renderTasks();
                renderDashboard();
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
                                showNotification('Offline mode — showing cached tasks.', 'offline');
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
                        showNotification('Cannot reach server. No cached data found.', 'offline');
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
                    showNotification('Working offline — some features limited.', 'offline');
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
                        showNotification('Backend unavailable — showing cached tasks.', 'offline');
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
                showNotification('Backend unavailable — showing offline mode.', 'offline', 7000);
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
                } else if (walletData.balance < 0) {
                    setDebtSuspension(Math.abs(walletData.balance));
                }

                // Mark walletLow on currentUser so dashboard banner shows
                currentUser.walletLow = walletData.balance < 100;
                
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
        // Check trial status — show closed overlay if trial is full or expired
        (async function checkTrialStatus() {
            try {
                var apiBase = (typeof API_BASE_URL !== 'undefined' && API_BASE_URL) ||
                    (typeof window.TASKEARN_API_URL !== 'undefined' && window.TASKEARN_API_URL) ||
                    'https://taskearn-production-production.up.railway.app/api';
                var resp = await fetch(apiBase + '/trial/status');
                if (!resp.ok) return; // trial endpoint missing → trial not active
                var data = await resp.json();
                if (!data.trial) return; // trial mode disabled by admin

                // Show centred popup card with slots remaining — dismissible
                if (data.active && !document.getElementById('trial-slots-banner') && !sessionStorage.getItem('trial-banner-dismissed')) {
                    var overlay = document.createElement('div');
                    overlay.id = 'trial-slots-banner';
                    overlay.style.cssText = 'position:fixed;inset:0;z-index:89999;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,0.45);backdrop-filter:blur(3px);';
                    overlay.innerHTML = '<div style="position:relative;background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;border-radius:18px;padding:28px 32px 24px;max-width:320px;width:90%;text-align:center;box-shadow:0 12px 40px rgba(0,0,0,0.35);">' +
                        '<button onclick="sessionStorage.setItem(\'trial-banner-dismissed\',\'1\');document.getElementById(\'trial-slots-banner\').remove()" style="position:absolute;top:12px;right:14px;background:rgba(255,255,255,0.2);border:none;color:#fff;width:28px;height:28px;border-radius:50%;cursor:pointer;font-size:16px;line-height:1;display:flex;align-items:center;justify-content:center;" aria-label="Dismiss">&times;</button>' +
                        '<div style="font-size:38px;margin-bottom:10px;">🚀</div>' +
                        '<div style="font-size:17px;font-weight:700;margin-bottom:6px;">Closed Beta Trial</div>' +
                        '<div style="font-size:28px;font-weight:800;margin:8px 0;"><strong>' + data.slotsRemaining + '</strong> <span style="font-size:15px;font-weight:500;">of ' + data.maxUsers + ' spots left</span></div>' +
                        '<div style="font-size:13px;opacity:0.85;margin-bottom:18px;">Closes on <strong>' + data.endDate + '</strong></div>' +
                        '<button onclick="sessionStorage.setItem(\'trial-banner-dismissed\',\'1\');document.getElementById(\'trial-slots-banner\').remove()" style="background:#fff;color:#6366f1;border:none;padding:10px 28px;border-radius:999px;font-weight:700;font-size:14px;cursor:pointer;">Got it!</button>' +
                    '</div>';
                    overlay.addEventListener('click', function(e) {
                        if (e.target === overlay) { sessionStorage.setItem('trial-banner-dismissed','1'); overlay.remove(); }
                    });
                    document.body.appendChild(overlay);
                }

                // Full or expired — block new signups with overlay
                if (!data.active) {
                    var msg = data.expired
                        ? 'The 30-day beta trial has ended.'
                        : 'All 100 beta spots have been taken.';
                    // Disable all signup buttons & forms instead of a hard block overlay
                    document.querySelectorAll('#signupModal, [onclick*="signupModal"], [data-modal="signupModal"]').forEach(function(el) {
                        el.style.pointerEvents = 'none'; el.style.opacity = '0.5';
                    });
                    // Show closed banner at bottom
                    var closedBar = document.createElement('div');
                    closedBar.id = 'trial-closed-banner';
                    closedBar.style.cssText = 'position:fixed;bottom:0;left:0;right:0;z-index:89999;background:#dc2626;color:#fff;text-align:center;font-size:13px;font-weight:600;padding:8px 16px;box-shadow:0 -2px 10px rgba(0,0,0,0.18);';
                    closedBar.innerHTML = '🔒 Trial Closed &mdash; ' + msg + ' Public launch coming soon!';
                    document.body.appendChild(closedBar);
                }
            } catch (e) { /* silently ignore — trial status fetch is non-critical */ }
        })();

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
        // PUSH NOTIFICATION FEATURE REMOVED
        
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

                // If on profile.html, load profile immediately now that currentUser is set
                try {
                    var _profilePage = (window.location.pathname.split('/').pop() || '').toLowerCase();
                    if (_profilePage === 'profile.html') { loadProfilePage(); }
                } catch (e) {}

                // Prompt Google users to complete profile if phone/DOB missing
                if (currentUser.authProvider === 'google' && (!currentUser.phone || !currentUser.dob)) {
                    setTimeout(() => showCompleteProfileModal(), 1500);
                }

                // Subscribe to push notifications (non-blocking, after a short delay)
                setTimeout(() => { try { initPushNotifications(); } catch (_) {} }, 3000);
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
        
        // Sync user tasks independently so they load even if getAll fails
        if (currentUser) {
            try {
                await syncUserTasksFromServer();
                renderDashboard();
            } catch (e) {
                console.warn('⚠️ Initial user task sync failed:', e.message);
            }
        }

        // Load tasks and category counts in PARALLEL (not serial)
        try {
            await Promise.all([
                loadTasksFromServer().catch(e => console.warn('⚠️ Could not load tasks from server:', e.message)),
                loadCategoryCounts().catch(e => console.warn('⚠️ Category counts failed:', e.message))
            ]);
        } catch (e) {
            console.warn('⚠️ Parallel load failed:', e.message);
        }

        // Load AI recommended tasks (after main tasks so userLocation is set)
        loadRecommendedTasks().catch(e => console.log('Recommendations unavailable:', e.message));

        // Re-render all views with fresh server data
        try {
            renderTasks();
            renderDashboard();
            startTaskTimers();
        } catch (e) {
            console.warn('⚠️ Task rendering failed:', e.message);
        }

        // Auto-open payment invoice if ?pay=TASK_ID is in URL (from email Pay Now button)
        try {
            const payTaskId = new URLSearchParams(window.location.search).get('pay');
            if (payTaskId && currentUser) {
                // Clean URL without reloading
                window.history.replaceState({}, '', window.location.pathname);
                setTimeout(() => showPaymentInvoice(parseInt(payTaskId, 10)), 800);
            }
        } catch (e) {
            console.warn('⚠️ Auto-pay URL handler failed:', e.message);
        }
        
        // Refresh tasks from server every 60 seconds (was 30s — reduced for performance)
        setInterval(() => {
            if (document.hidden) return; // Skip refresh when tab is not visible
            try {
                Promise.all([
                    loadTasksFromServer().catch(e => console.warn('⚠️ Auto-refresh failed:', e.message)),
                    loadCategoryCounts().catch(e => console.warn('⚠️ Category count refresh failed:', e.message)),
                    refreshWalletBalance().catch(e => console.warn('⚠️ Wallet refresh failed:', e.message))
                ]);
            } catch (e) {
                console.warn('⚠️ Task refresh failed:', e.message);
            }
        }, 60000);
        
        // Event delegation for Accept Task buttons (more reliable than inline onclick)
        document.addEventListener('click', function(e) {
            var btn = e.target.closest('.task-card-accept-btn');
            if (btn) {
                e.stopPropagation();
                e.preventDefault();
                var card = btn.closest('.task-card');
                var taskId = card ? card.getAttribute('data-task-id') : null;
                if (taskId) {
                    console.log('🖱️ Accept button clicked via delegation, taskId:', taskId);
                    acceptTask(parseInt(taskId, 10));
                }
                return;
            }
        });

        console.log('✅ Workmate4u Ready!');
        
        // Initialize Google Sign-In (if GIS loaded before app.js)
        setTimeout(() => initGoogleSignIn(), 500);
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
// IN-APP PUSH BANNER (foreground notifications like WhatsApp)
// ========================================
// PUSH NOTIFICATION FEATURE REMOVED

// PUSH NOTIFICATIONS feature removed


// ========================================
// MAP INITIALIZATION
// ========================================

function initializeMap() {
    try {
        const container = document.getElementById('map');
        if (!container) {
            console.log('ℹ️ No #map container on this page, skipping map init');
            // Still resolve the user's GPS location so distance calculations
            // on task cards (home page, etc.) are accurate instead of
            // defaulting to Delhi.
            try { getUserLocation(); } catch (e) { console.warn('GPS bootstrap failed:', e.message); }
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
        setTimeout(() => { if (map) try { map.invalidateSize(); } catch(_){} }, 1000);
        // Re-flow tiles on viewport changes (mobile rotation, resize)
        window.addEventListener('resize', () => { if (map) try { map.invalidateSize(); } catch(_){} });

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
            if (typeof map !== 'undefined' && map) {
                map.setView([userLocation.lat, userLocation.lng], 14);
            }
            try { renderTasks(); } catch (e) {}
            
            // Start watching position (only meaningful when a map exists)
            if (typeof map !== 'undefined' && map) {
                startLocationWatch();
            }
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
    // No-op when there is no map on the current page (e.g. home page)
    if (typeof map === 'undefined' || !map) return;
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
    const serviceCharge = getTaskPostingFee(task);
    const helperEarns = getHelperEarnings(task);
    const chargeInfo = getServiceChargeInfo(task.category);
    
    if (panel) {
        panel.innerHTML = `
            <h4>📍 Distance & Earnings</h4>
            <div class="distance-value">${km} km</div>
            <div class="eta">~${mins} min drive</div>
            <div class="price-info">
                <div class="total-price">Earn: <strong>₹${helperEarns.toFixed(0)}</strong></div>
                <small style="color:#10b981;">${DELIVERY_COMMISSION_CATS.has(task.category) ? '₹' + parseFloat(task.price).toFixed(0) + ' + ₹' + serviceCharge.toFixed(0) + ' (' + chargeInfo.level + ')' : '₹' + parseFloat(task.price).toFixed(0)}</small>
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

    // Sticky filter: when called with no explicit list, honor the
    // current Category dropdown. This prevents auto-refreshes
    // (every 60s) from wiping the filter the user (or a ?category=
    // URL param) just applied — fixes "every category page shows
    // the same task" bug on browse.html.
    if (!filtered) {
        try {
            const sel = document.getElementById('filterCategory');
            if (sel && sel.value && sel.value !== 'all'
                && typeof window.applyFilters === 'function'
                && Array.isArray(tasks) && tasks.length > 0) {
                window.applyFilters();
                return;
            }
        } catch (e) { /* fall through to default render */ }
    }

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
        const _allActiveTasks = tasks.filter(t => t.status === 'active' && getTimeLeft(t.expiresAt) !== 'Expired');
        const _hasTasksBeyondRadius = _allActiveTasks.length > 0 && _allActiveTasks.length > list.length;
        container.innerHTML = `
            <div class="empty-state">
                <div class="empty-state-icon"><i class="fas fa-magnifying-glass"></i></div>
                <h3>No tasks found nearby</h3>
                <p>${_hasTasksBeyondRadius ? 'There are <strong>' + _allActiveTasks.length + ' tasks</strong> available — try expanding your radius.' : 'No nearby tasks match your filters right now. Try widening your search or check back later.'}</p>
                <div class="empty-state-tips">
                    <button class="empty-state-tip-btn" onclick="document.getElementById('filterDistance').value=50; document.getElementById('distanceValue').textContent='50'; applyFilters();"><i class="fas fa-location-dot"></i> Expand to 50 km</button>
                    <button class="empty-state-tip-btn" onclick="document.getElementById('minBudget').value=''; document.getElementById('maxBudget').value=''; applyFilters();"><i class="fas fa-indian-rupee-sign"></i> Clear budget</button>
                    <button class="empty-state-tip-btn" onclick="loadTasksFromServer();"><i class="fas fa-rotate-right"></i> Refresh</button>
                </div>
                <button class="btn btn-outline empty-state-reset" onclick="clearFilters()"><i class="fas fa-times-circle"></i> Clear All Filters</button>
            </div>
        `;
        return;
        return;
    }

    const INITIAL_SHOW = 6;
    const showAll = container.dataset.showAll === 'true';
    const displayList = showAll ? list : list.slice(0, INITIAL_SHOW);
    const hasMore = list.length > INITIAL_SHOW;

    // Update (or inject) the toolbar above the card grid
    let toolbar = document.getElementById('tasksToolbar');
    if (!toolbar) {
        toolbar = document.createElement('div');
        toolbar.id = 'tasksToolbar';
        toolbar.className = 'tasks-toolbar';
        container.parentNode.insertBefore(toolbar, container);
    }
    const sortVal = container.dataset.sort || 'distance';
    toolbar.innerHTML = `
        <div class="tt-left">
            <span class="tt-count"><i class="fas fa-bolt" style="color:#6366f1;"></i> <strong>${list.length}</strong> tasks available</span>
        </div>
        <div class="tt-right">
            <label class="tt-sort-label" for="taskSortSelect"><i class="fas fa-sort"></i> Sort:</label>
            <select id="taskSortSelect" class="tt-sort-select" onchange="window._sortTasks(this.value)">
                <option value="distance" ${sortVal==='distance'?'selected':''}>Nearest</option>
                <option value="earn_desc" ${sortVal==='earn_desc'?'selected':''}>Highest Earn</option>
                <option value="earn_asc" ${sortVal==='earn_asc'?'selected':''}>Lowest Earn</option>
                <option value="time" ${sortVal==='time'?'selected':''}>Expiring Soon</option>
            </select>
        </div>
    `;

    // Sort helper
    window._sortTasks = function(by) {
        const c = document.getElementById('tasksList');
        if (c) c.dataset.sort = by;
        let sorted = [...list];
        if (by === 'earn_desc') sorted.sort((a,b) => getHelperEarnings(b) - getHelperEarnings(a));
        else if (by === 'earn_asc') sorted.sort((a,b) => getHelperEarnings(a) - getHelperEarnings(b));
        else if (by === 'time') sorted.sort((a,b) => new Date(a.expiresAt) - new Date(b.expiresAt));
        else sorted.sort((a,b) => {
            const dA = getDistance(userLocation.lat, userLocation.lng, a.location.lat, a.location.lng);
            const dB = getDistance(userLocation.lat, userLocation.lng, b.location.lat, b.location.lng);
            return dA - dB;
        });
        renderTasks(sorted);
    };

    const isHelper = currentUser && currentUser.id;
    container.innerHTML = displayList.map(task => {
        const dist = getDistance(userLocation.lat, userLocation.lng, task.location.lat, task.location.lng);
        const timeLeft = getTimeLeft(task.expiresAt);
        const rating = task.postedBy && task.postedBy.rating ? task.postedBy.rating : null;
        const isOwn = isHelper && task.postedBy && task.postedBy.id === currentUser.id;

        const _veh = getRequiredVehicle(task.description);
        const _vehBadge = _veh ? `<span class="task-vehicle-badge" title="Required vehicle">${escapeHtml(_veh.label)}</span>` : '';

        const posterName = (task.postedBy && task.postedBy.name) ? task.postedBy.name : 'Poster';
        const posterInitial = posterName.charAt(0).toUpperCase();
        const posterFirstName = escapeHtml(posterName.split(' ')[0]);
        const timerClass = getTimerUrgencyClass(timeLeft);
        const taskValue = Math.round(parseFloat(task.price || 0) + getTaskServiceCharge(task));
        const earnAmount = Math.round(getHelperEarnings(task));

        return `
            <div class="task-card task-card-v2" data-task-id="${task.id}" data-category="${task.category}" onclick="onTaskCardClick(${task.id})">
                <div class="tc-body">
                    <div class="tc-top-row">
                        <div class="tc-cat-chip">
                            <i class="${getCategoryIcon(task.category)}"></i>
                            <span>${formatCategory(task.category)}</span>
                        </div>
                        <div class="tc-top-right">
                            ${_vehBadge}
                            ${currentUser ? `<span class="bookmark-icon" onclick="event.stopPropagation(); toggleBookmark(${task.id}, this)" title="Bookmark"><i class="far fa-bookmark"></i></span>` : ''}
                        </div>
                    </div>
                    <h4 class="tc-title">${escapeHtml(task.title)}</h4>
                    <p class="tc-desc">${formatTaskDescription(task.description, { compact: true })}</p>
                    <div class="tc-stats">
                        <span class="tc-stat tc-stat-location"><i class="fas fa-map-marker-alt"></i> ${dist.toFixed(1)} km</span>
                        ${rating ? `<span class="tc-stat tc-stat-rating"><i class="fas fa-star"></i> ${rating.toFixed(1)}</span>` : ''}
                        <span class="tc-stat ${timerClass}"><i class="fas fa-clock"></i> ${timeLeft}</span>
                    </div>
                    <div class="tc-footer">
                        <div class="tc-poster">
                            <div class="tc-avatar">${posterInitial}</div>
                            <span class="tc-poster-name">${posterFirstName}</span>
                            ${task.postedBy && task.postedBy.verified ? '<span class="tc-poster-verified" title="Verified poster"><i class="fas fa-check-circle"></i></span>' : ''}
                            ${task.postedBy && task.postedBy.tasks_posted > 0 ? `<span class="tc-poster-taskcount">${task.postedBy.tasks_posted} posted</span>` : ''}
                        </div>
                        <div class="tc-earn">
                            <span class="tc-task-val">Task Value ₹${taskValue}</span>
                            <div class="tc-earn-row">
                                <span class="tc-earn-label">You Earn</span>
                                <span class="tc-earn-amount">₹${earnAmount}</span>
                            </div>
                        </div>
                    </div>
                    ${!isOwn ? (() => {
                        const myAccepted = myAcceptedTasks.find(at => at.id === task.id && (at.status === 'accepted' || at.status === 'in_progress'));
                        if (myAccepted) {
                            // Helper has accepted THIS task — show share button
                            return `<div class="tc-action-row">
                                <button class="task-card-accept-btn tc-accept-main task-card-accept-locked" disabled><i class="fas fa-check-circle"></i> Accepted</button>
                                <button class="tc-share-btn" onclick="event.stopPropagation(); shareTask(${task.id});" title="Share task on WhatsApp"><i class="fab fa-whatsapp"></i></button>
                            </div>`;
                        }
                        if (myAcceptedTasks.some(at => at.status === 'in_progress' || at.status === 'accepted')) {
                            return `<button class="task-card-accept-btn task-card-accept-locked" disabled title="Complete your current task before accepting a new one"><i class="fas fa-lock"></i> Task In Progress</button>`;
                        }
                        return `<button class="task-card-accept-btn" data-accept-task-id="${task.id}"><i class="fas fa-check-circle"></i> Accept Task</button>`;
                    })() : ''}
                </div>
            </div>
        `;
    }).join('');

    // Show "View All Tasks" button if there are more tasks
    if (hasMore && !showAll) {
        container.innerHTML += `
            <div class="view-all-tasks-wrap">
                <button class="btn btn-outline view-all-tasks-btn" onclick="document.getElementById('tasksList').dataset.showAll='true'; renderTasks();">
                    <i class="fas fa-th-list"></i> View All ${list.length} Tasks
                </button>
            </div>
        `;
    }
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
            ${(() => { const v = getRequiredVehicle(task.description); return v ? `<span class="task-vehicle-badge" title="Required vehicle">${escapeHtml(v.label)}</span>` : ''; })()}
            ${isOwner ? '<span class="owner-badge"><i class="fas fa-user-check"></i> Your Task</span>' : ''}
            <h2>${escapeHtml(task.title)}</h2>
            <div class="task-detail-meta">
                <span><i class="fas fa-map-marker-alt"></i> ${task.location.address}</span>
                <span><i class="fas fa-ruler"></i> ${dist.toFixed(1)} km away</span>
                <span class="task-timer"><i class="fas fa-clock"></i> ${timeLeft} left</span>
            </div>
        </div>
        
        <div class="task-detail-body">
            <h4>Description</h4>
            <div class="task-desc-full">${formatTaskDescription(task.description)}</div>
        </div>
        
        <div class="task-detail-map" id="taskDetailMap"></div>
        
        ${isOwner ? `
        <div class="task-detail-price task-detail-price-breakdown">
            <div class="price-breakdown-row">
                <span>Budget</span><span>₹${parseFloat(task.price).toFixed(2)}</span>
            </div>
            ${getTaskServiceCharge(task) > 0 ? `
            <div class="price-breakdown-row">
                <span>Service Charge <small>(Delivery/Distance)</small></span><span>+₹${getTaskServiceCharge(task).toFixed(2)}</span>
            </div>` : ''}
            <div class="price-breakdown-row price-breakdown-total">
                <h3>Total You Pay</h3><span class="price">₹${Math.round(getTaskFinalValue(task))}</span>
            </div>
        </div>` : `
        <div class="task-detail-price task-detail-price-breakdown">
            ${getTaskServiceCharge(task) > 0 ? `
            <div class="price-breakdown-row" style="color:var(--text-secondary);">
                <span>Task Value</span><span>₹${(parseFloat(task.price)+getTaskServiceCharge(task)).toFixed(2)}</span>
            </div>` : ''}
            <div class="price-breakdown-row price-breakdown-total">
                <div><h3>You Earn</h3><small>After ${Math.round(getCommissionRate(task.category||'other')*100)}% platform commission</small></div>
                <span class="price">₹${Math.round(getHelperEarnings(task))}</span>
            </div>
        </div>`}
        
        <div class="task-poster">
            <div class="poster-avatar"><i class="fas fa-user"></i></div>
            <div class="poster-info">
                <h4>${escapeHtml(task.postedBy.name)}</h4>
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
            <button class="btn btn-outline" onclick="shareTask(${task.id})" style="flex:0 0 auto; padding: 12px 16px; margin: 5px;" title="Share this task">
                <i class="fas fa-share-alt"></i>
            </button>
            ${!isOwner && currentUser ? `<button class="btn btn-outline" onclick="event.stopPropagation(); openDisputeModal(${task.id})" style="flex:0 0 auto; padding: 12px 16px; margin: 5px; color:#ef4444; border-color:#ef4444;" title="Report this task">
                <i class="fas fa-flag"></i>
            </button>
            <button class="btn btn-outline" onclick="event.stopPropagation(); openReportModal('${task.postedBy}', '${(task.posterName || 'User').replace(/'/g, "\\'")}')" style="flex:0 0 auto; padding: 12px 16px; margin: 5px; color:#f59e0b; border-color:#f59e0b;" title="Report User">
                <i class="fas fa-user-slash"></i>
            </button>` : ''}
            ${!isOwner ? `
            <button class="btn btn-secondary" style="flex: 1; padding: 12px; margin: 5px; background: #0ea5e9; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 600;" onclick="navigateToTask(${task.location.lat}, ${task.location.lng}, '${task.title.replace(/'/g, "\\'").replace(/"/g, '\\"')}')" title="Get directions to task location">
                <i class="fas fa-map-marker-alt"></i> Navigate
            </button>
            <button class="btn btn-primary modal-accept-btn" data-accept-task-id="${task.id}" style="flex: 1; padding: 12px; margin: 5px; background: #667eea; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 600;" onclick="acceptTask(${task.id})">
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
            // Modal animates in — Leaflet caches initial 0px container; force redraw after layout settles
            setTimeout(() => { try { miniMap.invalidateSize(); } catch(_){} }, 250);
            setTimeout(() => { try { miniMap.invalidateSize(); } catch(_){} }, 600);
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

    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    const theme = {
        title: isDark ? '#f1f5f9' : '#1e293b',
        body:  isDark ? '#cbd5e1' : '#64748b',
        muted: isDark ? '#94a3b8' : '#94a3b8',
        card:  isDark ? '#0f172a' : '#f8fafc',
        cardBorder: isDark ? '#1e293b' : '#e2e8f0',
        rowBorder: isDark ? '#1e293b' : '#f1f5f9',
        avatarBg: isDark ? '#334155' : '#e0e7ff',
        avatarFg: isDark ? '#cbd5e1' : '#4f46e5',
        statBg: isDark
            ? 'linear-gradient(135deg, rgba(99,102,241,0.18), rgba(14,165,233,0.18))'
            : 'linear-gradient(135deg, rgba(99,102,241,0.10), rgba(14,165,233,0.10))'
    };

    content.innerHTML = `
        <div style="padding: 30px 16px; text-align: center; color: ${theme.body};">
            <i class="fas fa-spinner fa-spin" style="font-size: 1.6rem; color: #6366f1;"></i>
            <p style="margin-top: 10px; font-size: 0.9rem;">Loading reviews...</p>
        </div>
    `;

    function starsRow(rating, size) {
        rating = Number(rating) || 0;
        size = size || 14;
        let html = '<span style="display:inline-flex;gap:2px;line-height:1;">';
        for (let i = 1; i <= 5; i++) {
            const cls = i <= Math.round(rating) ? 'fas fa-star' : 'far fa-star';
            html += `<i class="${cls}" style="color:#f59e0b;font-size:${size}px;"></i>`;
        }
        html += '</span>';
        return html;
    }

    function fmtDate(s) {
        if (!s) return '';
        try {
            const d = new Date(s);
            if (isNaN(d.getTime())) return '';
            return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
        } catch (e) { return ''; }
    }

    function initials(name) {
        return (name || '?').trim().split(/\s+/).map(p => p[0]).slice(0, 2).join('').toUpperCase() || '?';
    }

    try {
        const data = (typeof RatingsAPI !== 'undefined' && RatingsAPI.getReviews)
            ? await RatingsAPI.getReviews(userId)
            : (await apiRequest(`/user/${encodeURIComponent(userId)}/reviews`, { method: 'GET' })).data;
        const reviews = data?.reviews || [];
        const stats = data?.stats || {};
        const avg = Number(stats.avgRating || 0);
        const total = Number(stats.totalReviews || reviews.length || 0);

        let reviewsHtml = '';
        if (reviews.length === 0) {
            reviewsHtml = `
                <div style="padding: 36px 16px; text-align: center; background: ${theme.card}; border:1px solid ${theme.cardBorder}; border-radius: 14px;">
                    <i class="far fa-star" style="font-size: 2.4rem; color: ${theme.muted}; margin-bottom: 10px;"></i>
                    <h4 style="margin:0 0 6px; color:${theme.title};">No reviews yet</h4>
                    <p style="color:${theme.body}; font-size: 0.9rem; margin:0;">${escapeHtml(userName)} hasn't received any reviews.</p>
                </div>
            `;
        } else {
            reviewsHtml = reviews.map(r => `
                <div style="display:flex; gap:12px; padding:14px; background:${theme.card}; border:1px solid ${theme.cardBorder}; border-radius:12px; margin-bottom:10px;">
                    <div style="flex:0 0 38px; width:38px; height:38px; border-radius:50%; background:${theme.avatarBg}; color:${theme.avatarFg}; display:flex; align-items:center; justify-content:center; font-weight:700; font-size:13px;">
                        ${escapeHtml(initials(r.rater_name))}
                    </div>
                    <div style="flex:1; min-width:0;">
                        <div style="display:flex; justify-content:space-between; align-items:center; gap:8px; margin-bottom:4px; flex-wrap:wrap;">
                            <strong style="font-size:0.92rem; color:${theme.title};">${escapeHtml(r.rater_name || 'Anonymous')}</strong>
                            ${starsRow(r.rating, 13)}
                        </div>
                        ${r.review ? `<p style="color:${theme.body}; font-size:0.9rem; margin:4px 0; line-height:1.45; word-wrap:break-word;">${escapeHtml(r.review)}</p>` : ''}
                        <div style="display:flex; justify-content:space-between; align-items:center; gap:8px; margin-top:6px; flex-wrap:wrap;">
                            ${r.task_title ? `<small style="color:${theme.muted}; font-size:0.78rem;"><i class="fas fa-briefcase" style="margin-right:4px;"></i>${escapeHtml(r.task_title)}</small>` : '<span></span>'}
                            ${r.created_at ? `<small style="color:${theme.muted}; font-size:0.78rem;">${fmtDate(r.created_at)}</small>` : ''}
                        </div>
                    </div>
                </div>
            `).join('');
        }

        content.innerHTML = `
            <div style="padding: 4px 0;">
                <div style="display:flex; align-items:center; gap:10px; margin-bottom:14px;">
                    <button onclick="openTaskDetail(window._lastTaskId)" style="background:${theme.card}; color:${theme.title}; border:1px solid ${theme.cardBorder}; padding:7px 12px; border-radius:10px; font-size:0.85rem; font-weight:600; cursor:pointer; display:inline-flex; align-items:center; gap:6px;">
                        <i class="fas fa-arrow-left"></i> Back
                    </button>
                    <h3 style="margin:0; color:${theme.title}; font-size:1.05rem; flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">Reviews for ${escapeHtml(userName)}</h3>
                </div>
                <div style="display:flex; align-items:center; gap:16px; padding:18px; background:${theme.statBg}; border:1px solid ${theme.cardBorder}; border-radius:14px; margin-bottom:14px;">
                    <div style="text-align:center; min-width:80px;">
                        <div style="font-size:2rem; font-weight:800; color:${theme.title}; line-height:1;">${avg ? avg.toFixed(1) : '—'}</div>
                        <div style="margin-top:4px;">${starsRow(avg, 14)}</div>
                    </div>
                    <div style="flex:1; border-left:1px solid ${theme.cardBorder}; padding-left:16px;">
                        <div style="color:${theme.title}; font-weight:600; margin-bottom:2px;">${total} review${total === 1 ? '' : 's'}</div>
                        <div style="color:${theme.body}; font-size:0.85rem;">Based on completed tasks</div>
                    </div>
                </div>
                <div>${reviewsHtml}</div>
            </div>
        `;
    } catch (err) {
        console.error('Load reviews failed:', err);
        content.innerHTML = `
            <div style="padding: 30px 16px; text-align:center; background:${theme.card}; border:1px solid ${theme.cardBorder}; border-radius:14px;">
                <i class="fas fa-exclamation-circle" style="color:#ef4444; font-size:1.8rem;"></i>
                <p style="color:${theme.body}; margin:10px 0 14px;">Could not load reviews.</p>
                <button onclick="openTaskDetail(window._lastTaskId)" style="background:${theme.card}; color:${theme.title}; border:1px solid ${theme.cardBorder}; padding:8px 14px; border-radius:10px; font-weight:600; cursor:pointer;">
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

    // Immediate visual feedback — disable only accept-specific buttons
    var acceptBtns = document.querySelectorAll('.task-card-accept-btn, .modal-accept-btn');
    acceptBtns.forEach(function(btn) {
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Accepting...';
    });

    if (!currentUser) {
        showToast('Please login first');
        try { closeModal('taskDetailModal'); } catch(e) {}
        try { openModal('loginModal'); } catch(e) {}
        // Re-enable buttons
        resetAcceptButtons();
        return;
    }

    // Check if account is suspended
    if (typeof isAccountSuspended === 'function' && isAccountSuspended()) {
        try { closeModal('taskDetailModal'); } catch(e) {}
        if (typeof isBanned === 'function' && isBanned()) {
            showToast('Your account has been permanently banned. Contact support.');
        } else if (typeof isAdminSuspended === 'function' && isAdminSuspended()) {
            var reason = localStorage.getItem('taskearn_suspension_reason') || 'Contact support';
            showToast('Your account is suspended by admin. Reason: ' + reason);
        } else if (typeof isDebtSuspended === 'function' && isDebtSuspended()) {
            try { showDebtSuspendedPopup(); } catch(e) { showToast('Account suspended due to debt.'); }
        } else {
            try { showSuspendedPopup(); } catch(e) { showToast('Account suspended.'); }
        }
        resetAcceptButtons();
        return;
    }

    // KYC must be verified to accept tasks
    if (typeof isKYCVerified === 'function' && !isKYCVerified()) {
        try { closeModal('taskDetailModal'); } catch(e) {}
        showKYCRequiredPopup('accept tasks');
        resetAcceptButtons();
        return;
    }

    // Find task in local array (optional — used for localStorage save only)
    var task = tasks.find(function(t) { return t.id == taskId; });
    // Don't block if task not found locally — we can still call the API

    try {
        console.log('📡 Calling API to accept task:', taskId);

        // Call the accept API
        var data;
        if (typeof TasksAPI !== 'undefined' && TasksAPI.accept) {
            data = await TasksAPI.accept(taskId);
        } else {
            // Fallback: direct fetch if TasksAPI unavailable
            console.warn('⚠️ TasksAPI not available, using direct fetch');
            var apiBase = (typeof API_BASE_URL !== 'undefined' && API_BASE_URL) || 
                          (typeof window.TASKEARN_API_URL !== 'undefined' && window.TASKEARN_API_URL) ||
                          'https://taskearn-production-production.up.railway.app/api';
            var token = localStorage.getItem('taskearn_token');
            var resp = await fetch(apiBase + '/tasks/' + taskId + '/accept', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': token ? ('Bearer ' + token) : ''
                },
                mode: 'cors'
            });
            data = await resp.json();
            data._httpSuccess = resp.ok;
        }

        console.log('📥 Accept API response:', JSON.stringify(data));

        // Accept ANY successful response — be lenient
        var isSuccess = data && (data.success === true || data._httpSuccess === true || data.message === 'Task accepted successfully');

        if (isSuccess) {
            console.log('✅ Task accepted successfully!');

            // Update local state (non-critical)
            if (task) {
                task.status = 'accepted';
                task.acceptedBy = currentUser;
                task.acceptedAt = new Date().toISOString();
                try { myAcceptedTasks.push(task); } catch(e) {}
            }

            // Save task data for task-in-progress page (non-critical)
            try {
                var taskData = task || {};
                var taskLocation = (taskData.location) || {};
                localStorage.setItem('currentTask', JSON.stringify({
                    id: taskId,
                    title: taskData.title || '',
                    description: taskData.description || '',
                    category: taskData.category || '',
                    price: taskData.price || 0,
                    service_charge: taskData.service_charge || 0,
                    location: {
                        lat: parseFloat(taskLocation.lat) || 19.0760,
                        lng: parseFloat(taskLocation.lng) || 72.8777
                    },
                    providerId: taskData.postedBy ? taskData.postedBy.id : null,
                    providerName: taskData.postedBy ? taskData.postedBy.name : null,
                    providerPhone: taskData.postedBy ? taskData.postedBy.phone : null,
                    providerRating: taskData.postedBy ? taskData.postedBy.rating : null,
                    expiresAt: taskData.expiresAt || null,
                    postedAt: taskData.postedAt || null,
                    startTime: Date.now()
                }));
            } catch (e) {
                console.warn('localStorage save failed (non-critical):', e);
            }

            // Non-blocking updates
            try {
                if (typeof updateUserData === 'function' && currentUser.id) {
                    updateUserData(currentUser.id, {
                        acceptedTasks: typeof serializeTasks === 'function' ? serializeTasks(myAcceptedTasks) : []
                    }).catch(function(e) { console.warn('updateUserData failed:', e); });
                }
                try { closeModal('taskDetailModal'); } catch(e) {}
                try { if (typeof clearRoute === 'function') clearRoute(); } catch(e) {}
            } catch (e) {
                console.warn('Non-critical post-accept update failed:', e);
            }

            // REDIRECT — this is the critical action
            console.log('🚀 Redirecting to task-in-progress.html for task:', taskId);
            window.location.href = 'task-in-progress.html?taskId=' + taskId;
            return;
        } else {
            // API returned an error
            var errorMsg = (data && data.message) ? data.message : 'Failed to accept task. Please try again.';
            console.error('❌ Accept API returned failure:', errorMsg);
            if (data && data.needsKyc) {
                try { closeModal('taskDetailModal'); } catch(e) {}
                showKYCRequiredPopup('accept tasks');
            } else {
                showToast('❌ ' + errorMsg);
            }
            resetAcceptButtons();
        }
    } catch (err) {
        console.error('❌ Error accepting task:', err);
        showToast('❌ Network error. Please check your connection and try again.');
        resetAcceptButtons();
    }
}

// Reset accept buttons back to their original state
function resetAcceptButtons() {
    document.querySelectorAll('.task-card-accept-btn').forEach(function(btn) {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-check"></i> Accept Task';
    });
    document.querySelectorAll('.modal-accept-btn').forEach(function(btn) {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-check"></i> Accept';
    });
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

function isAdminSuspended() {
    return localStorage.getItem('taskearn_admin_suspended') === 'true';
}

function isBanned() {
    return localStorage.getItem('taskearn_banned') === 'true';
}

function isAccountSuspended() {
    if (isBanned()) return true;
    if (isAdminSuspended()) return true;
    if (isTimerSuspended()) return true;
    if (isDebtSuspended()) return true;
    return false;
}

// ---------- KYC enforcement helpers ----------
function getCurrentKYCStatus() {
    try {
        var u = currentUser || {};
        var status = (u.kycStatus || u.kyc_status || localStorage.getItem('taskearn_kyc_status') || 'none');
        return String(status).toLowerCase();
    } catch (e) { return 'none'; }
}

function isKYCVerified() {
    var s = getCurrentKYCStatus();
    return s === 'verified' || s === 'approved';
}

function showKYCRequiredPopup(action) {
    action = action || 'continue';
    var status = getCurrentKYCStatus();
    var subtitle;
    if (status === 'pending') {
        subtitle = 'Your KYC is under review. You can ' + action + ' once it has been verified by our team.';
    } else if (status === 'rejected') {
        subtitle = 'Your last KYC submission was rejected. Please re-submit valid documents in your Profile to ' + action + '.';
    } else {
        subtitle = 'KYC verification is mandatory before you can ' + action + '. It only takes a minute — verify your identity in Profile.';
    }
    var existing = document.getElementById('kycRequiredOverlay');
    if (existing) existing.remove();
    var overlay = document.createElement('div');
    overlay.id = 'kycRequiredOverlay';
    overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:10050;display:flex;align-items:center;justify-content:center;padding:20px;';
    var isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    var card = isDark ? '#1e293b' : '#ffffff';
    var titleC = isDark ? '#f1f5f9' : '#1e293b';
    var bodyC = isDark ? '#cbd5e1' : '#64748b';
    var closeBg = isDark ? '#334155' : '#f1f5f9';
    var closeC = isDark ? '#f1f5f9' : '#64748b';
    overlay.innerHTML = '<div style="background:' + card + ';border-radius:18px;max-width:400px;width:100%;padding:28px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,0.3);">' +
        '<div style="width:64px;height:64px;border-radius:50%;background:rgba(245,158,11,0.15);display:flex;align-items:center;justify-content:center;margin:0 auto 16px;">' +
            '<i class="fas fa-id-card" style="font-size:28px;color:#f59e0b;"></i>' +
        '</div>' +
        '<h3 style="color:' + titleC + ';margin-bottom:8px;font-size:1.25rem;">KYC Verification Required</h3>' +
        '<p style="color:' + bodyC + ';font-size:14px;line-height:1.6;margin-bottom:20px;">' + subtitle + '</p>' +
        '<button id="kycGotoVerifyBtn" style="width:100%;background:linear-gradient(135deg,#6366f1,#0ea5e9);color:#fff;padding:12px;border-radius:10px;font-weight:600;border:none;cursor:pointer;margin-bottom:8px;">' +
            (status === 'pending' ? 'View KYC Status' : 'Verify KYC Now') +
        '</button>' +
        '<button id="kycCloseBtn" style="width:100%;background:' + closeBg + ';color:' + closeC + ';padding:10px;border-radius:10px;font-weight:600;border:none;cursor:pointer;">Close</button>' +
    '</div>';
    document.body.appendChild(overlay);
    document.getElementById('kycCloseBtn').onclick = function() { overlay.remove(); };
    document.getElementById('kycGotoVerifyBtn').onclick = function() {
        overlay.remove();
        try { closeModal('postTaskModal'); } catch(e) {}
        try { closeModal('taskDetailModal'); } catch(e) {}
        if (typeof showPage === 'function') {
            showPage('profile');
            setTimeout(function() {
                var formSec = document.getElementById('kycFormSection');
                if (formSec && typeof formSec.scrollIntoView === 'function') formSec.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }, 250);
        } else {
            window.location.href = 'profile.html#kyc';
        }
    };
    overlay.onclick = function(e) { if (e.target === overlay) overlay.remove(); };
}

window.isKYCVerified = isKYCVerified;
window.showKYCRequiredPopup = showKYCRequiredPopup;

// ---------- Client-side spam / fraud content screen ----------
// Mirrors backend screen_task_content; backend is the source of truth.
function clientScreenTaskContent(title, description) {
    var text = ((title || '') + ' ' + (description || '')).toLowerCase();
    if (!text.trim()) return '';
    var rules = [
        [/\b(create|make|open|register|sign[- ]?up|generate|bulk)\b[^.]{0,40}\b(email|emails|gmail|yahoo|outlook|hotmail|account|accounts|id|ids|profile|profiles)\b/i,
            'Bulk account or email creation tasks are not allowed.'],
        [/\b(per|each|\/)\s*(email|account|id|signup|sign[- ]?up|profile)\b/i,
            'Tasks paying per account/email creation are not allowed.'],
        [/\b(sell|buy|rent|hire)\b[^.]{0,30}\b(account|accounts|gmail|whatsapp|instagram|facebook|telegram|otp|sim|number)\b/i,
            'Buying or selling accounts/credentials is prohibited.'],
        [/\b(receive|share|forward|read|provide|give|sell)\b[^.]{0,30}\b(otp|otps|one[- ]time[- ]password|verification\s*code|sms\s*code)\b/i,
            'OTP/verification-code sharing tasks are prohibited.'],
        [/\botp\s*(work|task|job|earn)\b/i, 'OTP-based earning tasks are prohibited.'],
        [/\b(use|share|rent|sell)\b[^.]{0,30}\b(aadhaar|aadhar|pan\s*card|kyc|bank\s*account|upi\s*id)\b/i,
            'Sharing or renting personal KYC documents is prohibited.'],
        [/\b(fake|paid|bulk)\b[^.]{0,20}\b(reviews?|ratings?|likes?|followers?|subscribers?|comments?|votes?)\b/i,
            'Fake review / engagement / follower tasks are prohibited.'],
        [/\b(click|watch)\s*(ads|advertisements|videos)\s*(bot|farm|loop)\b/i, 'Click-fraud tasks are prohibited.'],
        [/\b(usdt|btc|bitcoin|crypto|forex)\b[^.]{0,30}\b(investment|trade|trading|deposit|recharge|profit|earn)\b/i,
            'Crypto/forex investment tasks are not permitted.'],
        [/\b(money\s*mule|transfer\s*money|launder|cash[- ]out)\b/i, 'Money transfer / mule activity is prohibited.'],
        [/\b(hack|crack|bypass|unlock)\b[^.]{0,30}\b(password|account|server|whatsapp|instagram|facebook|gmail|wifi|otp)\b/i,
            'Hacking or unauthorized access tasks are prohibited.'],
        [/\b(escort|webcam\s*model|adult\s*content|nude|sex\s*chat|drugs?|weed|cocaine|heroin)\b/i,
            'Adult/illicit-content tasks are not allowed.'],
        [/\b(captcha\s*solving|typing\s*captcha)\b/i, 'Captcha-solving/spam tasks are not allowed.'],
        [/\b(spam|spamming)\b[^.]{0,20}\b(email|sms|whatsapp|message)\b/i, 'Spam/bulk messaging tasks are not allowed.'],
        [/(₹|rs\.?|inr)\s*\d{1,3}\s*(per|each|\/)\s*(email|account|signup|sign[- ]?up|otp|click|like|follower|review)/i,
            'Per-unit micro-payments for accounts/OTPs/clicks/reviews are not allowed.']
    ];
    for (var i = 0; i < rules.length; i++) {
        if (rules[i][0].test(text)) return rules[i][1];
    }
    return '';
}
window.clientScreenTaskContent = clientScreenTaskContent;


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
    if (msgEl) msgEl.textContent = 'Your wallet balance is negative. You cannot accept tasks or withdraw funds until your balance is back to ₹0 or above. Add the outstanding amount to your wallet to restore your account.';
    if (amountEl) amountEl.textContent = '₹' + amount.toFixed(2);
    const modal = document.getElementById('debtSuspendedModal');
    if (modal) {
        openModal('debtSuspendedModal');
    } else {
        showToast('⚠️ Your account is suspended due to a negative wallet balance. Add money to bring balance to ₹0.', 'error');
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
    // Sync admin suspension from server
    if (userData.adminSuspended) {
        localStorage.setItem('taskearn_admin_suspended', 'true');
        localStorage.setItem('taskearn_suspension_reason', userData.suspensionReason || 'Contact support');
    } else {
        localStorage.removeItem('taskearn_admin_suspended');
        localStorage.removeItem('taskearn_suspension_reason');
    }
    // Sync ban status
    if (userData.isBanned) {
        localStorage.setItem('taskearn_banned', 'true');
    } else {
        localStorage.removeItem('taskearn_banned');
    }
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
        if (typeof AuthAPI === 'undefined' || !AuthAPI.getCurrentUser) return;
        const result = await AuthAPI.getCurrentUser();
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
        // Save task data for the in-progress page
        localStorage.setItem('currentTask', JSON.stringify({
            id: task.id,
            title: task.title,
            category: task.category,
            price: task.price,
            service_charge: task.service_charge || 0,
            amount: (task.price || 0) + (task.service_charge || 0),
            providerName: task.postedBy?.name || 'Task Poster',
            providerPhone: task.postedBy?.phone || '',
            location: task.location || {},
            startTime: task.acceptedAt ? new Date(task.acceptedAt).getTime() : Date.now()
        }));
        window.location.href = 'task-in-progress.html?taskId=' + task.id;
    }
}

// Navigate to task-in-progress page when clicking accepted task card
function goToTaskInProgress(taskId) {
    const task = myAcceptedTasks.find(t => t.id == taskId);
    if (!task) return;
    // Only navigate for in-progress tasks, not completed/awaiting payment
    if (task.status === 'completed' || task.status === 'pending_payment' || task.status === 'paid' || task.status === 'verify_pending' || task.status === 'payment_released') return;
    // Save task data for the in-progress page
    localStorage.setItem('currentTask', JSON.stringify({
        id: task.id,
        title: task.title,
        category: task.category,
        price: task.price,
        service_charge: task.service_charge || 0,
        amount: (task.price || 0) + (task.service_charge || 0),
        providerName: task.postedBy?.name || 'Task Poster',
        providerPhone: task.postedBy?.phone || '',
        location: task.location || {},
        startTime: task.acceptedAt ? new Date(task.acceptedAt).getTime() : Date.now()
    }));
    window.location.href = 'task-in-progress.html?taskId=' + task.id;
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

    // Backend /tasks/<id>/abandon now deducts the 10% release penalty
    // atomically, so we no longer call WalletAPI.penalty here. The response
    // tells us the new balance + whether the helper is now debt-suspended.
    showToast('💸 Releasing task...');

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

    const penalty = (abandonResult && typeof abandonResult.releasePenalty === 'number')
        ? abandonResult.releasePenalty : 0;

    // Sync wallet balance + debt suspension from server response
    if (abandonResult && typeof abandonResult.newBalance === 'number') {
        currentUser.wallet = abandonResult.newBalance;
        try { await updateUserData(currentUser.id, { wallet: abandonResult.newBalance }); } catch (_) {}
        if (abandonResult.debtSuspended) {
            setDebtSuspension(abandonResult.debtAmount || Math.abs(abandonResult.newBalance));
            console.log('⚠️ Debt suspension activated. Amount owed:', abandonResult.debtAmount);
        }
    }
    try { await refreshWalletBalance(); } catch (_) {}

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
    } else if (abandonResult.debtSuspended) {
        try { showDebtSuspendedPopup(); } catch (_) {}
        addNotification({
            title: 'Account Suspended (Debt)',
            message: 'Your wallet balance is negative after the release penalty. Add money to bring it to ₹0 to restore your account.',
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
        if (isBanned()) {
            showToast('🚫 Your account has been permanently banned.', 'error');
        } else if (isAdminSuspended()) {
            showToast('⛔ Your account is suspended by admin.', 'error');
        } else if (isDebtSuspended()) {
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
    console.log('🗑️ deleteTask called with taskId:', taskId);

    if (!currentUser) {
        showToast('Please login first to delete tasks');
        try { openModal('loginModal'); } catch(e) {}
        return;
    }

    if (!confirm('Are you sure you want to delete this task?')) return;

    // Show visual feedback
    showToast('Deleting task...');

    // Call backend API to delete from database
    try {
        var result;
        if (typeof TasksAPI !== 'undefined' && TasksAPI.delete) {
            console.log('📡 Calling TasksAPI.delete for task:', taskId);
            result = await TasksAPI.delete(taskId);
            console.log('📥 Delete API response:', JSON.stringify(result));
        } else {
            // Fallback: direct fetch
            console.warn('⚠️ TasksAPI not available, using direct fetch');
            var apiBase = (typeof API_BASE_URL !== 'undefined' && API_BASE_URL) ||
                          'https://taskearn-production-production.up.railway.app/api';
            var token = localStorage.getItem('taskearn_token');
            if (!token) {
                showToast('❌ Session expired. Please login again.');
                try { openModal('loginModal'); } catch(e) {}
                return;
            }
            var resp = await fetch(apiBase + '/tasks/' + taskId, {
                method: 'DELETE',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ' + token
                },
                mode: 'cors'
            });
            result = await resp.json();
            console.log('📥 Direct fetch delete response:', JSON.stringify(result));
        }

        if (!result || !result.success) {
            var msg = (result && result.message) ? result.message : 'Could not delete task';
            console.error('❌ Delete failed:', msg);
            showToast('❌ ' + msg);
            return;
        }
    } catch (e) {
        console.error('❌ Delete API failed:', e.message);
        showToast('❌ Network error. Please try again.');
        return;
    }

    // Remove from local arrays (use == for loose comparison to handle number/string mismatch)
    tasks = tasks.filter(function(t) { return t.id != taskId; });
    myPostedTasks = myPostedTasks.filter(function(t) { return t.id != taskId; });

    try {
        updateUserData(currentUser.id, {
            postedTasks: serializeTasks(myPostedTasks)
        });
    } catch(e) { console.warn('updateUserData failed:', e); }

    showToast('✅ Task deleted successfully');
    try { closeModal('taskDetailModal'); } catch(e) {}
    try { renderTasks(); } catch(e) {}
    try { addTaskMarkers(); } catch(e) {}
    try { renderPostedTasks(); } catch(e) {}
    try { renderDashboard(); } catch(e) {}
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
    document.getElementById('editTaskLocation').value = task.location?.address || '';
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

    // Persist to backend
    try {
        const result = await TasksAPI.update(taskId, {
            title: newTitle,
            category: newCategory,
            description: newDescription,
            price: newPrice,
            location: { lat: newLat, lng: newLng, address: newLocation }
        });
        if (!result || !result.success) {
            showToast('❌ ' + (result ? result.message || 'Failed to save task' : 'Failed to save task'));
            return;
        }
    } catch (e) {
        showToast('❌ Error saving task. Please try again.');
        return;
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
        <p class="success-subtitle">Your task is now visible to nearby taskers for 24 hours</p>
        
        <div class="posted-task-preview">
            <div class="preview-header">
                <span class="task-category">${formatCategory(task.category)}</span>
                <span class="task-price">₹${task.price}</span>
            </div>
            <h4>${escapeHtml(task.title)}</h4>
            <div class="task-desc-full">${formatTaskDescription(task.description)}</div>
            <div class="preview-meta">
                <span><i class="fas fa-map-marker-alt"></i> ${task.location.address}</span>
                <span><i class="fas fa-clock"></i> 24 hours left</span>
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

    // Call backend FIRST to ensure DB status is updated.
    // Use TasksAPI/apiRequest so we get proxy + reverse-proxy fallback (handles
    // Indian ISP / carrier blocks of Railway DNS).
    try {
        let result;
        if (typeof TasksAPI !== 'undefined' && TasksAPI.complete) {
            result = await TasksAPI.complete(taskId);
        } else {
            const r = await apiRequest(`/tasks/${taskId}/complete`, { method: 'POST' });
            result = r.data || {};
        }
        if (!result || !result.success) {
            const msg = (result && result.message) || 'Could not mark task as completed';
            if (result && result.offline) {
                showToast('📡 ' + msg, 6000);
            } else {
                showToast(`❌ ${msg}`);
            }
            return;
        }
        console.log('✅ Backend: Task marked completed, poster notified');
    } catch (e) {
        showToast('❌ Could not reach the server. Please check your connection and try again.');
        console.error('Backend complete failed:', e && e.message);
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

// =============================================================
// RATE & REVIEW MODAL — used by both poster and helper after a
// task is paid/completed. Calls POST /api/task/<id>/rate.
// =============================================================
function openRateUserModal(opts) {
    opts = opts || {};
    var taskId = opts.taskId;
    var taskTitle = opts.taskTitle || 'this task';
    var otherName = opts.otherName || 'the other party';
    var role = opts.role || 'helper'; // 'helper' (rating helper) | 'poster'
    if (!taskId) { showToast('Missing task ID for rating'); return; }

    // Has the current user already rated this task locally? Avoid re-prompts.
    try {
        var ratedKey = 'rated_tasks_' + (currentUser && currentUser.id ? currentUser.id : 'anon');
        var rated = JSON.parse(localStorage.getItem(ratedKey) || '[]');
        if (rated.indexOf(String(taskId)) !== -1) return;
    } catch (e) {}

    var existing = document.getElementById('rateUserOverlay');
    if (existing) existing.remove();

    var isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    var card = isDark ? '#1e293b' : '#ffffff';
    var titleC = isDark ? '#f1f5f9' : '#1e293b';
    var bodyC = isDark ? '#cbd5e1' : '#64748b';
    var inputBg = isDark ? '#0f172a' : '#f8fafc';
    var inputBorder = isDark ? '#334155' : '#e2e8f0';
    var skipBg = isDark ? '#334155' : '#f1f5f9';
    var skipC = isDark ? '#f1f5f9' : '#64748b';

    var overlay = document.createElement('div');
    overlay.id = 'rateUserOverlay';
    overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.65);z-index:10060;display:flex;align-items:center;justify-content:center;padding:20px;';

    function starRow(name, label) {
        var html = '<div style="margin-bottom:14px;text-align:left;">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">' +
                '<div style="font-size:13px;color:' + bodyC + ';font-weight:500;">' + label + '</div>' +
                '<div class="rate-label" data-for="' + name + '" style="font-size:12px;color:' + bodyC + ';font-weight:600;"></div>' +
            '</div>' +
            '<div class="rate-stars" data-field="' + name + '" style="display:flex;gap:8px;">';
        for (var i = 1; i <= 5; i++) {
            html += '<i class="far fa-star rate-star" data-val="' + i + '" style="cursor:pointer;font-size:28px;color:#f59e0b;transition:transform .12s ease;"></i>';
        }
        html += '</div></div>';
        return html;
    }

    overlay.innerHTML = '<div style="background:' + card + ';border-radius:18px;max-width:440px;width:100%;padding:24px;box-shadow:0 12px 36px rgba(0,0,0,0.35);max-height:90vh;overflow-y:auto;">' +
        '<div style="text-align:center;margin-bottom:18px;">' +
            '<div style="width:60px;height:60px;border-radius:50%;background:rgba(245,158,11,0.15);display:flex;align-items:center;justify-content:center;margin:0 auto 12px;">' +
                '<i class="fas fa-star" style="font-size:26px;color:#f59e0b;"></i>' +
            '</div>' +
            '<h3 style="color:' + titleC + ';margin-bottom:6px;font-size:1.2rem;">Rate ' + escapeHtml(otherName) + '</h3>' +
            '<p style="color:' + bodyC + ';font-size:13px;">How was your experience with "' + escapeHtml(taskTitle) + '"?</p>' +
        '</div>' +
        starRow('rating', 'Overall rating') +
        starRow('punctuality', 'Punctuality') +
        starRow('communication', 'Communication') +
        starRow('quality', role === 'poster' ? 'Task clarity & fairness' : 'Quality of work') +
        '<div style="margin-bottom:14px;text-align:left;">' +
            '<div style="font-size:13px;color:' + bodyC + ';margin-bottom:6px;font-weight:500;">Write a short review (optional)</div>' +
            '<textarea id="rateReviewText" maxlength="500" rows="3" placeholder="Share your honest experience..." ' +
                'style="width:100%;padding:10px 12px;background:' + inputBg + ';color:' + titleC + ';border:1px solid ' + inputBorder + ';border-radius:10px;font-family:inherit;font-size:14px;resize:vertical;"></textarea>' +
        '</div>' +
        '<div style="display:flex;gap:10px;">' +
            '<button id="rateSkipBtn" style="flex:1;background:' + skipBg + ';color:' + skipC + ';padding:11px;border-radius:10px;font-weight:600;border:none;cursor:pointer;">Skip</button>' +
            '<button id="rateSubmitBtn" style="flex:2;background:linear-gradient(135deg,#6366f1,#0ea5e9);color:#fff;padding:11px;border-radius:10px;font-weight:600;border:none;cursor:pointer;">Submit Review</button>' +
        '</div>' +
    '</div>';
    document.body.appendChild(overlay);

    var values = { rating: 5, punctuality: 5, communication: 5, quality: 5 };
    var ratingWords = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];
    function paint(preview) {
        overlay.querySelectorAll('.rate-stars').forEach(function(row) {
            var field = row.getAttribute('data-field');
            var v = (preview && preview.field === field) ? preview.val : (values[field] || 0);
            row.querySelectorAll('.rate-star').forEach(function(s) {
                var sv = parseInt(s.getAttribute('data-val'), 10);
                s.className = 'rate-star ' + (sv <= v ? 'fas fa-star' : 'far fa-star');
            });
            var lbl = overlay.querySelector('.rate-label[data-for="' + field + '"]');
            if (lbl) lbl.textContent = v ? ratingWords[v] : '';
        });
    }
    overlay.querySelectorAll('.rate-stars').forEach(function(row) {
        var field = row.getAttribute('data-field');
        row.querySelectorAll('.rate-star').forEach(function(s) {
            var sv = parseInt(s.getAttribute('data-val'), 10);
            s.addEventListener('mouseenter', function() { paint({ field: field, val: sv }); });
            s.addEventListener('click', function() {
                values[field] = sv;
                paint();
            });
        });
        row.addEventListener('mouseleave', function() { paint(); });
    });
    paint();

    document.getElementById('rateSkipBtn').onclick = function() { overlay.remove(); };
    overlay.onclick = function(e) { if (e.target === overlay) overlay.remove(); };
    document.getElementById('rateSubmitBtn').onclick = async function() {
        var btn = this;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Submitting...';
        var review = (document.getElementById('rateReviewText').value || '').trim();
        try {
            var res;
            if (typeof RatingsAPI !== 'undefined' && RatingsAPI.rate) {
                res = await RatingsAPI.rate(taskId, values.rating, review, {
                    punctuality: values.punctuality,
                    communication: values.communication,
                    quality: values.quality
                });
            } else {
                var token = localStorage.getItem('taskearn_token');
                var apiBase = (typeof API_BASE_URL !== 'undefined' && API_BASE_URL) || 'https://taskearn-production-production.up.railway.app/api';
                var resp = await fetch(apiBase + '/task/' + taskId + '/rate', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': token ? ('Bearer ' + token) : '' },
                    body: JSON.stringify({ rating: values.rating, review: review, punctuality: values.punctuality, communication: values.communication, quality: values.quality })
                });
                res = await resp.json();
            }
            if (res && (res.success || res.message === 'Rating submitted successfully')) {
                showToast('✅ Thanks for your review!');
                try {
                    var key = 'rated_tasks_' + (currentUser && currentUser.id ? currentUser.id : 'anon');
                    var arr = JSON.parse(localStorage.getItem(key) || '[]');
                    arr.push(String(taskId));
                    localStorage.setItem(key, JSON.stringify(arr));
                } catch(e) {}
                overlay.remove();
                try { if (typeof loadProfileReviews === 'function') loadProfileReviews(); } catch(e) {}
            } else {
                var msg = (res && res.message) ? res.message : 'Could not submit rating';
                if (msg === 'Already rated') {
                    showToast('You have already rated this task.');
                    overlay.remove();
                } else {
                    showToast('❌ ' + msg);
                    btn.disabled = false;
                    btn.innerHTML = 'Submit Review';
                }
            }
        } catch (err) {
            console.error('Rating submit failed:', err);
            showToast('❌ Could not submit rating. Try again later.');
            btn.disabled = false;
            btn.innerHTML = 'Submit Review';
        }
    };
}
window.openRateUserModal = openRateUserModal;

// Stash a pending rating context, open the success modal, and let a simple
// onclick wrapper trigger the rating modal. We avoid inline JSON.stringify
// inside onclick="..." because embedded double-quotes break the attribute.
window.__pendingRate = null;
function triggerPendingRate() {
    try { closeModal('taskSuccessModal'); } catch (e) {}
    try { renderDashboard(); } catch (e) {}
    var ctx = window.__pendingRate;
    if (!ctx) return;
    window.__pendingRate = null;
    openRateUserModal(ctx);
}
window.triggerPendingRate = triggerPendingRate;

/**
 * Show "Payment Done" pop-up for the poster after paying
 */
function showPaymentDonePopup(task, totalPaid, helperReceives, newBalance) {
    const baseAmount = task.price || 0;
    const svcCharge = task.service_charge || 0;
    const totalTaskVal = baseAmount + svcCharge;
    // Posting fee DISABLED: const posterFee = totalTaskVal * 0.05;
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
                    <span style="color: #999;">Total Paid:</span>
                    <span style="font-weight: 600; color: #ef4444;">-₹${totalPaid.toFixed(2)}</span>
                </div>
                <hr style="border-color: rgba(255,255,255,0.1); margin: 12px 0;">
                <div style="display: flex; justify-content: space-between;">
                    <span style="font-weight: 600;">Your New Balance:</span>
                    <span style="font-weight: 700; color: #fbbf24;">₹${newBalance.toFixed(2)}</span>
                </div>
            </div>
            
            <button class="btn btn-primary btn-block" onclick="triggerPendingRate()">
                <i class="fas fa-star"></i> Rate Helper
            </button>
        </div>
    `;
    document.getElementById('taskSuccessContent').innerHTML = content;
    window.__pendingRate = {
        taskId: task.id,
        taskTitle: task.title || '',
        otherName: (task.acceptedBy && task.acceptedBy.name) || task.accepted_by_name || 'the helper',
        role: 'poster'
    };
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
        if ((task.status === 'paid' || task.status === 'completed') && !shownPayments.includes(task.id)) {
            const taskAmount = task.price || 0;
            const serviceCharge = task.service_charge || task.serviceCharge || 0;
            const totalTaskValue = taskAmount + serviceCharge;
            const _commRate = getCommissionRate(task.category || 'other');
            const helperEarnings = totalTaskValue * (1 - _commRate);
            const _commPct = Math.round(_commRate * 100);
            
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
                            <span style="color: #999;">Commission (${_commPct}%):</span>
                            <span style="font-weight: 600; color: #ef4444;">-₹${(totalTaskValue * _commRate).toFixed(2)}</span>
                        </div>
                        <hr style="border-color: rgba(255,255,255,0.1); margin: 12px 0;">
                        <div style="display: flex; justify-content: space-between;">
                            <span style="font-weight: 600;">You Received:</span>
                            <span style="font-weight: 700; font-size: 18px; color: #4ade80;">+₹${helperEarnings.toFixed(2)}</span>
                        </div>
                    </div>
                    
                    <button class="btn btn-primary btn-block" onclick="triggerPendingRate()">
                        <i class="fas fa-star"></i> Rate Poster
                    </button>
                </div>
            `;
            document.getElementById('taskSuccessContent').innerHTML = content;
            window.__pendingRate = {
                taskId: task.id,
                taskTitle: task.title || '',
                otherName: (task.postedBy && task.postedBy.name) || 'the poster',
                role: 'helper'
            };
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

    // Accepted statuses for payment: legacy completed/pending_payment + new verify_pending flow
    const payableStatuses = ['completed', 'pending_payment', 'verify_pending'];

    // If local status is stale, fetch real status from server before showing error
    if (!payableStatuses.includes(task.status)) {
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
        if (!payableStatuses.includes(task.status)) {
            showToast(`❌ Task status is '${task.status}', payment requires 'completed' status.`);
            return;
        }
    }

    // Calculate all amounts
    const taskAmount = task.price || 0;
    const serviceCharge = task.service_charge || 0;
    const totalTaskValue = taskAmount + serviceCharge;
    const commRate = getCommissionRate(task.category || 'other');
    const helperCommission = totalTaskValue * commRate;
    // Poster posting fee: DISABLED (was 5%)
    // const posterFee = totalTaskValue * 0.05;
    const totalCost = totalTaskValue; // No posting fee
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
                ${serviceCharge > 0 ? `
                <div style="display: flex; justify-content: space-between; margin-bottom: 10px; padding-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.06);">
                    <span style="color: #ccc;">Service Charge <span style="font-size:11px;opacity:0.7;">(Delivery/Distance)</span></span>
                    <span style="color: #fbbf24; font-weight: 600;">+₹${serviceCharge.toFixed(2)}</span>
                </div>` : ''}
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
    const commRate2 = getCommissionRate(task.category || 'other');
    const helperCommission = totalTaskValue * commRate2;
    // Poster posting fee DISABLED: const posterFee = totalTaskValue * 0.05;
    const totalCost = totalTaskValue; // No posting fee
    const helperNetReceives = totalTaskValue - helperCommission;

    try {
        console.log('📤 Sending payment request...');
        // Route through apiRequest so we get the Netlify proxy reverse-fallback
        // when Railway is blocked by the user's carrier / ISP.
        const r = await apiRequest(`/tasks/${taskId}/pay-helper`, {
            method: 'POST',
            body: JSON.stringify({ taskId: taskId })
        });
        const result = r.data || {};
        console.log('📥 Payment response:', result);

        if (result.success) {
            if (currentUser) {
                currentUser.wallet = result.posterNewBalance;
                localStorage.setItem('taskearn_user', JSON.stringify(currentUser));
            }

            // Remove paid task from myPostedTasks and add to paid history for rating
            const paidTask = { ...task, status: 'paid' };
            myPostedTasks = myPostedTasks.filter(t => t.id != taskId);
            // Add to paid posted tasks history so poster can rate the helper
            if (!myPaidPostedTasks.find(pt => pt.id == taskId)) {
                myPaidPostedTasks.push({
                    id: paidTask.id,
                    title: paidTask.title,
                    category: paidTask.category,
                    price: paidTask.price,
                    service_charge: paidTask.service_charge || 0,
                    status: 'paid',
                    accepted_by: paidTask.accepted_by || paidTask.acceptedBy,
                    helper_name: paidTask.helper_name || paidTask.helperName || 'Helper',
                    postedAt: paidTask.postedAt
                });
            }
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

    // KYC must be verified to post tasks
    if (typeof isKYCVerified === 'function' && !isKYCVerified()) {
        closeModal('postTaskModal');
        showKYCRequiredPopup('post tasks');
        return;
    }

    // Client-side spam/fraud screening (defense-in-depth — server enforces too)
    try {
        var _title = (document.getElementById('modalTaskTitle')?.value || '');
        var _desc = (document.getElementById('modalTaskDescription')?.value || '');
        var _violation = clientScreenTaskContent(_title, _desc);
        if (_violation) {
            showToast('🚫 ' + _violation, 7000);
            return;
        }
    } catch (e) { /* non-blocking */ }

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
    // Distance-aware service charge for pick&drop / delivery / moving.
    const distanceKm = (typeof window.__wmLastDistance === 'number') ? window.__wmLastDistance : null;
    const serviceCharge = getServiceCharge(category, distanceKm);
    // Posting fee DISABLED: const platformFeeForSubmit = Math.round((totalPrice + serviceCharge) * 0.05 * 100) / 100;
    const platformFeeForSubmit = 0; // No posting fee
    const totalPayable = totalPrice + serviceCharge; // No posting fee

    // If a specific vehicle was chosen for ride/delivery categories, surface it
    // on the task so only taskers with that vehicle are eligible.
    const vehicleKey = (typeof window.__wmSelectedVehicle === 'string') ? window.__wmSelectedVehicle : null;
    const VEHICLE_LABEL = { bike: '\uD83C\uDFCD\uFE0F Bike', auto: '\uD83D\uDEFA Auto', mini: '\uD83D\uDE97 Mini Car', sedan: '\uD83D\uDE99 Sedan' };
    let descriptionText = document.getElementById('modalTaskDescription').value || '';
    if (vehicleKey && VEHICLE_LABEL[vehicleKey] && !descriptionText.includes('Required vehicle:')) {
        descriptionText = '🚕 Required vehicle: ' + VEHICLE_LABEL[vehicleKey]
            + '  —  Only taskers with this vehicle should accept.\n\n'
            + descriptionText;
    }

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
        description: descriptionText,
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
                if (result.needsKyc) {
                    closeModal('postTaskModal');
                    showKYCRequiredPopup('post tasks');
                    return;
                }
                if (result.policyViolation) {
                    closeModal('postTaskModal');
                    showToast('🚫 ' + (result.message || 'Task violates content policy and was blocked.'), 7000);
                    return;
                }
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
        expiresAt: new Date(Date.now() + 24 * 3600000),
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

// Display authentication status in UI (authStatus element removed from UI)
function updateAuthenticationStatus() {
    // Status indicator removed — no UI element to update
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

                // Subscribe to push notifications after login (non-blocking)
                setTimeout(() => { try { initPushNotifications(); } catch (_) {} }, 3500);

                // Profile completeness nudge (shown once per session)
                setTimeout(() => {
                    if (sessionStorage.getItem('_profileNudgeDone')) return;
                    sessionStorage.setItem('_profileNudgeDone', '1');
                    const missing = [];
                    if (!currentUser.phone) missing.push('phone number');
                    if (!currentUser.profile_photo && !currentUser.profilePhoto) missing.push('profile photo');
                    if (!currentUser.bio) missing.push('bio');
                    if (missing.length > 0) {
                        const nudge = document.createElement('div');
                        nudge.id = '_profileNudge';
                        nudge.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;border-radius:14px;padding:14px 18px;z-index:9999;max-width:360px;width:calc(100% - 32px);box-shadow:0 8px 30px rgba(0,0,0,0.3);animation:slideUpPWA 0.3s ease;display:flex;align-items:center;gap:12px;';
                        nudge.innerHTML = '<span style="font-size:1.5rem;">👤</span><div style="flex:1;"><strong style="display:block;font-size:14px;">Complete your profile</strong><span style="font-size:12px;opacity:0.85;">Add your ' + missing.join(' & ') + ' to get more tasks</span></div><a href="profile.html" style="background:rgba(255,255,255,0.2);color:#fff;border-radius:8px;padding:7px 12px;text-decoration:none;font-size:12px;font-weight:700;white-space:nowrap;">Update</a><button onclick="document.getElementById(\'_profileNudge\').remove()" style="background:none;border:none;color:rgba(255,255,255,0.6);cursor:pointer;font-size:1rem;padding:0 0 0 6px;"><i class="fas fa-times"></i></button>';
                        document.body.appendChild(nudge);
                        setTimeout(() => { const e = document.getElementById('_profileNudge'); if (e) e.remove(); }, 8000);
                    }
                }, 2000);
                
                // If on profile.html, refresh profile UI (was stuck at "Loading...")
                if ((window.location.pathname.split('/').pop() || '').toLowerCase() === 'profile.html') {
                    setTimeout(() => loadProfilePage(), 150);
                }
                
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
    const inviteCode = (document.getElementById('signupInviteCode')?.value || '').trim().toUpperCase();
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
                dob: dob,
                invite_code: inviteCode
            });
            
            if (result.success) {
                currentUser = result.user;
                myPostedTasks = [];
                myAcceptedTasks = [];
                myCompletedTasks = [];
                
                // Close signup and show email verification
                closeModal('signupModal');
                
                // Clear form
                document.getElementById('signupFirstName').value = '';
                document.getElementById('signupLastName').value = '';
                document.getElementById('signupEmail').value = '';
                document.getElementById('signupPassword').value = '';
                if (document.getElementById('signupPhone')) document.getElementById('signupPhone').value = '';
                document.getElementById('signupDOB').value = '';
                
                // Show email verification modal
                if (result.requiresVerification) {
                    const emailDisplay = email.replace(/(.{2})(.*)(@.*)/, '$1***$3');
                    const verifyText = document.getElementById('verifyEmailText');
                    if (verifyText) verifyText.textContent = 'We\'ve sent a 6-digit code to ' + emailDisplay;
                    openModal('emailVerifyModal');
                    // Focus first OTP input
                    setTimeout(() => {
                        const d1 = document.getElementById('otpDigit1');
                        if (d1) d1.focus();
                    }, 300);
                    startResendTimer();
                } else {
                    // Already verified (shouldn't happen for new user, but handle it)
                    showToast('🎉 Welcome to Workmate4u! Your ID: ' + currentUser.id);
                    updateNavForUser();
                    const tasksLoaded = await loadTasksFromServer();
                    setTimeout(() => renderDashboard(), 100);
                    if ((window.location.pathname.split('/').pop() || '').toLowerCase() === 'profile.html') {
                        setTimeout(() => loadProfilePage(), 150);
                    }
                    setTimeout(showOnboarding, 500);
                }
                
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

// ========== EMAIL VERIFICATION OTP FUNCTIONS ==========

let resendTimerInterval = null;

function otpInputHandler(el, idx) {
    // Only allow digits
    el.value = el.value.replace(/[^0-9]/g, '');
    if (el.value && idx < 6) {
        const next = document.getElementById('otpDigit' + (idx + 1));
        if (next) next.focus();
    }
    // Auto-submit when all 6 digits filled
    if (idx === 6 && el.value) {
        const otp = getOTPValue();
        if (otp.length === 6) verifyEmailOTP();
    }
}

function otpKeyHandler(event, idx) {
    if (event.key === 'Backspace' && !event.target.value && idx > 1) {
        const prev = document.getElementById('otpDigit' + (idx - 1));
        if (prev) { prev.focus(); prev.select(); }
    }
}

function otpPasteHandler(event) {
    event.preventDefault();
    const paste = (event.clipboardData || window.clipboardData).getData('text').replace(/[^0-9]/g, '').slice(0, 6);
    for (let i = 0; i < 6; i++) {
        const d = document.getElementById('otpDigit' + (i + 1));
        if (d) d.value = paste[i] || '';
    }
    if (paste.length === 6) {
        document.getElementById('otpDigit6').focus();
        verifyEmailOTP();
    }
}

function getOTPValue() {
    let otp = '';
    for (let i = 1; i <= 6; i++) {
        const d = document.getElementById('otpDigit' + i);
        otp += d ? d.value : '';
    }
    return otp;
}

async function verifyEmailOTP() {
    const otp = getOTPValue();
    if (!otp || otp.length !== 6) {
        showToast('❌ Please enter the 6-digit code');
        return;
    }
    
    const btn = document.getElementById('verifyOTPBtn');
    if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Verifying...';
    }
    
    try {
        const data = await AuthAPI.verifyEmail(otp) || {};
        
        if (data.success) {
            closeModal('emailVerifyModal');
            showToast('✅ Email verified!');
            if (currentUser) {
                currentUser.email_verified = true;
                currentUser.emailVerified = true;
            }
            updateNavForUser();
            const tasksLoaded = await loadTasksFromServer();
            setTimeout(() => renderDashboard(), 100);
            if ((window.location.pathname.split('/').pop() || '').toLowerCase() === 'profile.html') {
                setTimeout(() => loadProfilePage(), 150);
            }

            // Phone verification is currently optional — go straight to onboarding.
            // Users can verify their phone later from Profile if/when desired.
            setTimeout(showOnboarding, 500);
        } else {
            showToast('❌ ' + (data.message || 'Invalid code. Please try again.'));
            // Clear OTP inputs
            for (let i = 1; i <= 6; i++) {
                const d = document.getElementById('otpDigit' + i);
                if (d) d.value = '';
            }
            const d1 = document.getElementById('otpDigit1');
            if (d1) d1.focus();
        }
    } catch (err) {
        showToast('❌ Verification failed. Please try again.');
    } finally {
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = '<i class="fas fa-check-circle"></i> Verify Email';
        }
    }
}

async function resendVerificationOTP() {
    const btn = document.getElementById('resendOTPBtn');
    if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Sending...';
    }
    
    try {
        const data = await AuthAPI.sendVerificationOTP() || {};
        
        if (data.success) {
            showToast('📧 New verification code sent!');
            startResendTimer();
        } else {
            showToast('❌ ' + (data.message || 'Failed to resend code'));
        }
    } catch (err) {
        showToast('❌ Failed to resend code');
    } finally {
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = '<i class="fas fa-redo"></i> Resend Code';
        }
    }
}

function startResendTimer() {
    const btn = document.getElementById('resendOTPBtn');
    const timerEl = document.getElementById('resendTimer');
    if (btn) btn.style.display = 'none';
    if (timerEl) timerEl.style.display = 'block';
    
    let seconds = 60;
    if (resendTimerInterval) clearInterval(resendTimerInterval);
    
    if (timerEl) timerEl.textContent = 'Resend available in ' + seconds + 's';
    
    resendTimerInterval = setInterval(() => {
        seconds--;
        if (timerEl) timerEl.textContent = 'Resend available in ' + seconds + 's';
        if (seconds <= 0) {
            clearInterval(resendTimerInterval);
            if (btn) btn.style.display = 'inline-block';
            if (timerEl) timerEl.style.display = 'none';
        }
    }, 1000);
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
                
                // Remove old profile items and refresh item (will be re-added at bottom)
                const oldProfileItems = mobileMenuList.querySelectorAll('.mobile-profile-item, .mobile-logout-item, .mobile-dashboard-item, .mobile-refresh-item');
                oldProfileItems.forEach(item => item.remove());
                
                // Add user profile and logout for mobile
                const profileLi = document.createElement('li');
                profileLi.className = 'mobile-profile-item';
                profileLi.innerHTML = `<a href="profile.html" onclick="toggleMobileMenu();"><i class="fas fa-user-circle"></i> ${escapeHtml(currentUser.name)}</a>`;
                mobileMenuList.appendChild(profileLi);
                
                const dashboardLi = document.createElement('li');
                dashboardLi.className = 'mobile-dashboard-item';
                dashboardLi.innerHTML = `<a href="#my-tasks" onclick="scrollToSection('my-tasks'); toggleMobileMenu();"><i class="fas fa-tasks"></i> My Tasks</a>`;
                mobileMenuList.appendChild(dashboardLi);
                
                const logoutLi = document.createElement('li');
                logoutLi.className = 'mobile-logout-item';
                logoutLi.innerHTML = `<button class="btn btn-primary" onclick="logout(); toggleMobileMenu();">Logout</button>`;
                mobileMenuList.appendChild(logoutLi);

                const refreshLi = document.createElement('li');
                refreshLi.className = 'mobile-refresh-item';
                refreshLi.style.cssText = 'border-top:1px solid var(--border,#e2e8f0);margin-top:8px;padding-top:8px;';
                refreshLi.innerHTML = `<button class="btn btn-outline" style="width:100%;color:var(--gray);" onclick="hardRefreshApp()"><i class="fas fa-rotate-right"></i> Refresh App</button>`;
                mobileMenuList.appendChild(refreshLi);
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
                
                // Remove stale refresh item so we can re-add it at the bottom
                mobileMenuList.querySelectorAll('.mobile-refresh-item').forEach(i => i.remove());

                // Check if login/signup buttons exist, if not add them
                if (!mobileMenuList.querySelector('button')) {
                    const loginLi = document.createElement('li');
                    loginLi.innerHTML = `<button class="btn btn-outline" onclick="openModal('loginModal')">Login</button>`;
                    mobileMenuList.appendChild(loginLi);

                    const signupLi = document.createElement('li');
                    signupLi.innerHTML = `<button class="btn btn-primary" onclick="openModal('signupModal')">Sign Up</button>`;
                    mobileMenuList.appendChild(signupLi);
                }

                // Always keep Refresh App at the bottom
                const refreshLi = document.createElement('li');
                refreshLi.className = 'mobile-refresh-item';
                refreshLi.style.cssText = 'border-top:1px solid var(--border,#e2e8f0);margin-top:8px;padding-top:8px;';
                refreshLi.innerHTML = `<button class="btn btn-outline" style="width:100%;color:var(--gray);" onclick="hardRefreshApp()"><i class="fas fa-rotate-right"></i> Refresh App</button>`;
                mobileMenuList.appendChild(refreshLi);
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
            <h2>${escapeHtml(currentUser.name)}</h2>
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
    // Fast-path: if currentUser not yet set by async session restore,
    // read the cached user from localStorage so the profile renders instantly
    // instead of waiting 1-3 seconds for the Railway token-verify round-trip.
    if (!currentUser) {
        try {
            const _cached = localStorage.getItem('taskearn_user');
            if (_cached) currentUser = JSON.parse(_cached);
        } catch (_e) {}
    }
    if (!currentUser) return;
    
    // Render from currentUser immediately, then refresh from server
    renderProfileUI();
    
    // Fetch fresh user data from server to ensure profile is up to date
    // Skip if photo was just uploaded to avoid overwriting optimistic preview
    if (_photoJustUploaded) { _photoJustUploaded = false; return; }
    if (typeof AuthAPI !== 'undefined' && AuthAPI.getCurrentUser) {
        AuthAPI.getCurrentUser().then(function(result) {
            if (result && result.success && result.user) {
                Object.assign(currentUser, Object.fromEntries(
                    Object.entries(result.user).filter(([k]) => !k.startsWith('__'))
                ));
                saveUserToStorage(currentUser);
                renderProfileUI();
            }
        }).catch(function() { /* use cached data */ });
    }
    
    // Also refresh wallet balance
    refreshWalletBalance().then(function() { renderProfileUI(); }).catch(function() {});
    
    // Fetch user reviews
    loadProfileReviews();
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
    if (sinceEl) {
        if (currentUser.joinedAt) {
            sinceEl.innerHTML = '<i class="fas fa-calendar-alt"></i> Member since ' +
                new Date(currentUser.joinedAt).toLocaleDateString('en-IN', { year: 'numeric', month: 'long' });
        } else {
            sinceEl.innerHTML = '<i class="fas fa-calendar-alt"></i> Member';
        }
    }
    
    // Stats — use server-computed values first, fall back to client-side
    var completedCount = currentUser.tasksCompleted || myCompletedTasks.length || 0;
    var totalEarned = currentUser.totalEarnings || 0;
    if (!totalEarned && myCompletedTasks.length > 0) {
        totalEarned = myCompletedTasks.reduce(function(sum, t) {
            if (t.earnedAmount) return sum + t.earnedAmount;
            return sum + getHelperEarnings(t);
        }, 0);
        totalEarned = Math.round(totalEarned * 100) / 100;
    }
    var postedCount = currentUser.tasksPosted || myPostedTasks.length || 0;
    
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
    if (fp) {
        var phoneText = currentUser.phone || 'Not provided';
        var verified = !!currentUser.phoneVerified;
        var badge = verified
            ? '<span style="margin-left:8px;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;background:#dcfce7;color:#16a34a;"><i class="fas fa-check-circle"></i> Verified</span>'
            : '<span style="margin-left:8px;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;background:#fef3c7;color:#d97706;">Not verified</span>';
        var verifyBtn = verified
            ? ''
            : '<button type="button" onclick="openPhoneVerifyModal()" style="margin-left:8px;padding:4px 10px;border-radius:6px;border:1px solid #2563eb;background:#2563eb;color:#fff;font-size:11px;font-weight:600;cursor:pointer;">Verify Now</button>';
        fp.innerHTML = '<span>' + (phoneText) + '</span>' + badge + verifyBtn;
    }
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

    // Populate Earnings Dashboard
    var earningsPanel = document.getElementById('earningsDashboard');
    if (earningsPanel && currentUser) {
        earningsPanel.style.display = 'block';

        // Check email verification status
        checkEmailVerification();
        var etAmt = document.getElementById('earningsTotalAmount');
        if (etAmt) etAmt.textContent = '₹' + (typeof totalEarned === 'number' ? totalEarned.toFixed(2) : totalEarned);
        var etTasks = document.getElementById('earningsTotalTasks');
        if (etTasks) etTasks.textContent = completedCount;

        var listEl = document.getElementById('earningsDetailList');
        if (listEl && myCompletedTasks.length > 0) {
            listEl.innerHTML = myCompletedTasks.slice().reverse().map(function(t) {
                var amt = getTaskFinalValue(t);
                var earned = t.earnedAmount || getHelperEarnings(t);
                var date = t.completedAt ? new Date(t.completedAt).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' }) : '';
                return '<div style="display:flex;justify-content:space-between;align-items:center;padding:10px 0;border-bottom:1px solid var(--border,#e2e8f0);">' +
                    '<div><div style="font-weight:600;font-size:14px;">' + (t.title || 'Task') + '</div><div style="font-size:12px;color:#94a3b8;">' + date + '</div></div>' +
                    '<div style="font-weight:700;color:#10b981;">+₹' + earned.toFixed(2) + '</div></div>';
            }).join('');
        } else if (listEl) {
            listEl.innerHTML = '<p style="text-align:center;color:#94a3b8;padding:20px;">No completed tasks yet</p>';
        }

        // Add export button if not already present
        if (!document.getElementById('exportTransBtn')) {
            var exportWrap = document.createElement('div');
            exportWrap.style.cssText = 'text-align:center;margin-top:12px;';
            exportWrap.innerHTML = '<button id="exportTransBtn" onclick="exportTransactionsCSV()" style="background:#667eea;color:white;border:none;padding:8px 18px;border-radius:8px;cursor:pointer;font-size:13px;"><i class="fas fa-download"></i> Export Transactions</button>';
            earningsPanel.appendChild(exportWrap);
        }
    }
}

function toggleEarningsDetail() {
    var list = document.getElementById('earningsDetailList');
    var icon = document.getElementById('earningsToggleIcon');
    if (list) {
        var show = list.style.display === 'none';
        list.style.display = show ? 'block' : 'none';
        if (icon) icon.className = show ? 'fas fa-chevron-up' : 'fas fa-chevron-down';
    }
}

function toggleReviewsSection() {
    var panel = document.getElementById('reviewsCollapsible');
    var btn = document.getElementById('reviewsToggleBtn');
    var chevron = document.getElementById('reviewsChevron');
    if (!panel) return;
    var isHidden = panel.style.display === 'none' || panel.style.display === '';
    panel.style.display = isHidden ? 'block' : 'none';
    if (btn) btn.innerHTML = isHidden
        ? 'Hide <i class="fas fa-chevron-up" id="reviewsChevron" style="font-size:10px;"></i>'
        : 'Show <i class="fas fa-chevron-down" id="reviewsChevron" style="font-size:10px;"></i>';
}

async function loadProfileReviews() {
    if (!currentUser) {
        try {
            const _c = localStorage.getItem('taskearn_user');
            if (_c) currentUser = JSON.parse(_c);
        } catch (_e) {}
    }
    if (!currentUser) return;
    var container = document.getElementById('profileReviewsList');
    if (!container) return;
    
    try {
        var result = await apiRequest('/user/' + currentUser.id + '/reviews', { method: 'GET' });
        if (result && result.success && result.data) {
            var data = result.data;
            var reviews = data.reviews || [];
            var stats = data.stats || {};
            
            // Backend returns camelCase keys: totalReviews, avgRating
            var totalReviews = stats.totalReviews || stats.total_reviews || 0;
            var avgRating = stats.avgRating || stats.avg_rating || null;
            
            // Update rating stat with server value
            var sr = document.getElementById('statRating');
            if (sr && avgRating) sr.textContent = parseFloat(avgRating).toFixed(1);
            
            // Update reviews count
            var rc = document.getElementById('reviewsCount');
            if (rc) rc.textContent = totalReviews + ' review' + (totalReviews !== 1 ? 's' : '');
            
            if (reviews.length === 0) {
                container.innerHTML = '<p style="text-align:center;color:#94a3b8;padding:20px;font-size:14px;">No reviews yet. Complete tasks to get reviews!</p>';
                return;
            }
            
            container.innerHTML = reviews.map(function(r) {
                var stars = '';
                for (var i = 0; i < 5; i++) {
                    stars += i < Math.round(r.rating) ? '★' : '☆';
                }
                var date = r.created_at ? new Date(r.created_at).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
                return '<div style="padding:12px 0;border-bottom:1px solid var(--border,#e2e8f0);">' +
                    '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;">' +
                    '<span style="font-weight:600;font-size:14px;">' + (r.rater_name ? escapeHtml(r.rater_name) : 'User') + '</span>' +
                    '<span style="font-size:12px;color:#94a3b8;">' + date + '</span></div>' +
                    '<div style="color:#f59e0b;font-size:14px;letter-spacing:2px;margin-bottom:4px;">' + stars + '</div>' +
                    (r.review ? '<p style="font-size:13px;color:var(--text-secondary,#64748b);margin:0;">' + escapeHtml(r.review) + '</p>' : '') +
                    (r.task_title ? '<div style="font-size:11px;color:#94a3b8;margin-top:4px;">Task: ' + escapeHtml(r.task_title) + '</div>' : '') +
                    '</div>';
            }).join('');
        }
    } catch (e) {
        container.innerHTML = '<p style="text-align:center;color:#94a3b8;padding:20px;font-size:14px;">Unable to load reviews</p>';
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
                Object.assign(currentUser, Object.fromEntries(
                    Object.entries(result.user).filter(([k]) => !k.startsWith('__'))
                ));
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
        var bar = document.getElementById('pwdStrengthBar');
        if (bar) { bar.style.width = '0'; }
        var txt = document.getElementById('pwdStrengthText');
        if (txt) { txt.textContent = ''; }
    }
}

function togglePwdEye(inputId, btn) {
    var input = document.getElementById(inputId);
    if (!input) return;
    var isText = input.type === 'text';
    input.type = isText ? 'password' : 'text';
    var icon = btn.querySelector('i');
    if (icon) { icon.className = isText ? 'fas fa-eye' : 'fas fa-eye-slash'; }
}

function updatePwdStrengthBar(pwd) {
    var bar = document.getElementById('pwdStrengthBar');
    var txt = document.getElementById('pwdStrengthText');
    if (!bar || !txt) return;
    if (!pwd) { bar.style.width = '0'; txt.textContent = ''; return; }
    var score = 0;
    if (pwd.length >= 6)  score++;
    if (pwd.length >= 10) score++;
    if (/[A-Z]/.test(pwd)) score++;
    if (/[0-9]/.test(pwd)) score++;
    if (/[^A-Za-z0-9]/.test(pwd)) score++;
    var levels = [
        {w:'20%', c:'#ef4444', t:'Weak'},
        {w:'40%', c:'#f59e0b', t:'Fair'},
        {w:'65%', c:'#f59e0b', t:'Moderate'},
        {w:'85%', c:'#10b981', t:'Strong'},
        {w:'100%',c:'#059669', t:'Very Strong'}
    ];
    var l = levels[Math.min(score, 5) - 1] || levels[0];
    bar.style.width = l.w; bar.style.background = l.c;
    txt.textContent = l.t; txt.style.color = l.c;
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
        function bindPhotoInput() {
            var inp = document.getElementById('profilePhotoInput');
            if (inp && !inp._bound) {
                inp._bound = true;
                inp.addEventListener('change', handleProfilePhoto);
            }
        }
        function initProfile() {
            // Poll until currentUser is set by the async session restore (network verify may take >300ms)
            var _attempts = 0;
            function _tryLoad() {
                bindPhotoInput();
                if (typeof currentUser !== 'undefined' && currentUser) {
                    loadProfilePage();
                } else if (_attempts++ < 20) {
                    // Retry every 300ms for up to 6 seconds
                    setTimeout(_tryLoad, 300);
                }
                // After max retries, if still no user — page will show login prompt via updateNavForUser
            }
            setTimeout(_tryLoad, 300);
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
    
    // Show earn nudge card if wallet is low / negative
    const walletBal = currentUser ? (currentUser.wallet || 0) : 0;
    if (currentUser && (currentUser.walletLow || walletBal < 0)) {
        const walletWarningEl = document.getElementById('walletLowWarning');
        if (walletWarningEl) {
            walletWarningEl.innerHTML = `
                <div style="margin-bottom:18px;border-radius:16px;overflow:hidden;background:linear-gradient(135deg,#6366f1 0%,#8b5cf6 60%,#a855f7 100%);color:#fff;padding:18px 20px;display:flex;align-items:center;gap:16px;box-shadow:0 4px 20px rgba(99,102,241,0.25);">
                    <div style="width:48px;height:48px;background:rgba(255,255,255,0.15);border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:1.4rem;">💼</div>
                    <div style="flex:1;">
                        <div style="font-weight:700;font-size:1rem;margin-bottom:2px;">Ready to earn more?</div>
                        <div style="font-size:0.8rem;opacity:0.85;">Tasks near you are waiting. Accept one and grow your wallet today.</div>
                    </div>
                    <a href="browse.html" style="flex-shrink:0;background:#fff;color:#6366f1;font-weight:700;font-size:0.82rem;padding:9px 16px;border-radius:10px;text-decoration:none;white-space:nowrap;">Browse Tasks →</a>
                    <button onclick="this.parentElement.parentElement.style.display='none'" style="background:none;border:none;color:rgba(255,255,255,0.6);cursor:pointer;font-size:1.1rem;flex-shrink:0;padding:0 0 0 4px;"><i class="fas fa-times"></i></button>
                </div>
            `;
            walletWarningEl.style.display = 'block';
        }
    }
    
    renderPostedTasks();
    renderPaidPostedTasks();
    renderAcceptedTasks();
    renderCompletedTasks();

    // Highlight task if navigated from notification
    const urlHighlight = new URLSearchParams(window.location.search).get('highlight');
    if (urlHighlight) {
        function tryHighlight() {
            const taskEl = document.querySelector(`[data-task-id="${urlHighlight}"]`);
            if (taskEl) {
                taskEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
                taskEl.style.boxShadow = '0 0 0 3px #4ade80';
                setTimeout(() => { taskEl.style.boxShadow = ''; }, 3000);
                return true;
            }
            return false;
        }
        // Retry: card may not exist until server data loads
        setTimeout(() => { if (!tryHighlight()) setTimeout(tryHighlight, 2000); }, 300);
    }
    
    // Sync notifications from server (non-blocking) so poster sees Pay Now from helper
    syncNotificationsFromServer();
    
    // Check if helper has any recently paid tasks to show pop-up
    setTimeout(() => checkAndShowPaymentReceived(), 500);
}

async function posterCancelTask(taskId) {
    const task = (myPostedTasks || []).find(t => t.id == taskId);
    if (!task) { showToast('Task not found'); return; }
    if (task.status !== 'accepted') {
        showToast('Only accepted tasks can be cancelled this way.');
        return;
    }

    const helperName = task.helper_name || task.helperName || 'the helper';
    const reason = window.prompt(
        'Cancel and permanently delete this task?\n\n' +
        helperName + ' will be notified. The task will be removed and will NOT be visible to anyone else.\n\n' +
        'Optional reason (visible to helper):',
        ''
    );
    if (reason === null) return; // user clicked Cancel

    showToast('Cancelling task...');
    try {
        const res = await TasksAPI.posterCancel(taskId, reason);
        if (res && res.success) {
            showToast('✅ ' + (res.message || 'Task cancelled and removed'));
            try {
                // Remove the task entirely from the poster's local list
                if (Array.isArray(myPostedTasks)) {
                    const idx = myPostedTasks.findIndex(x => x.id == taskId);
                    if (idx !== -1) myPostedTasks.splice(idx, 1);
                }
                // Also remove from any global tasks list if present
                if (typeof tasks !== 'undefined' && Array.isArray(tasks)) {
                    const i2 = tasks.findIndex(x => x.id == taskId);
                    if (i2 !== -1) tasks.splice(i2, 1);
                }
            } catch (e) {}
            try { renderPostedTasks(); } catch (e) {}
            try { if (typeof loadTasks === 'function') loadTasks(); } catch (e) {}
        } else {
            showToast('❌ ' + ((res && res.message) || 'Could not cancel task'), 'error');
        }
    } catch (err) {
        console.error('posterCancelTask failed:', err);
        showToast('❌ Network error while cancelling task', 'error');
    }
}
window.posterCancelTask = posterCancelTask;

// ── Verify & Pay Task (Poster releases payment from task card) ─────────────
// Shows the full payment invoice popup so the poster can review the breakdown.
async function verifyAndPayTask(taskId) {
    if (!currentUser) { alert('Please login first'); return; }
    await showPaymentInvoice(taskId);
}
window.verifyAndPayTask = verifyAndPayTask;

// ── Mark Task Completed (Helper after payment released) ────────────────────
async function markTaskCompleted(taskId) {
    const token = localStorage.getItem('taskearn_token');
    if (!token) { alert('Please login first'); return; }
    try {
        const resp = await fetch((window.API_BASE_URL || '') + '/tasks/' + taskId + '/mark-completed', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token }
        });
        const result = await resp.json();
        if (result.success) {
            myAcceptedTasks = myAcceptedTasks.filter(t => t.id != taskId);
            renderAcceptedTasks();
            openRatingPopup(taskId);
        } else {
            alert(result.message || 'Could not mark as completed. Please try again.');
        }
    } catch (e) {
        alert('Network error. Please try again.');
    }
}
window.markTaskCompleted = markTaskCompleted;

// ── Verify Task Done (Helper: accepted → verify_pending) ──────────────────
async function verifyTaskDone(taskId, btnEl) {
    const token = localStorage.getItem('taskearn_token');
    if (!token) { alert('Please login first'); return; }
    if (!confirm('Have you completed this task? The poster will be notified to verify and pay.')) return;
    if (btnEl) { btnEl.disabled = true; btnEl.textContent = 'Sending...'; }
    try {
        const resp = await fetch((window.API_BASE_URL || '') + '/tasks/' + taskId + '/verify', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token }
        });
        const result = await resp.json();
        if (result.success) {
            showToast('✅ Verification sent! Waiting for poster to pay.', 'success');
            // Update local task status so UI reflects change immediately
            const task = myAcceptedTasks.find(t => t.id == taskId);
            if (task) task.status = 'verify_pending';
            renderAcceptedTasks();
            await syncUserTasksFromServer();
            renderDashboard();
            // Share prompt — invite others to earn
            setTimeout(() => {
                if (localStorage.getItem('share_task_prompt_shown')) return;
                localStorage.setItem('share_task_prompt_shown', '1');
                const title = task ? task.title : 'a task';
                const waText = encodeURIComponent(`I just completed "${title}" on Workmate4u and got paid! 💸\nYou can also earn money doing tasks nearby 👉 https://workmate4u.com`);
                const el = document.createElement('div');
                el.id = 'shareEarnPrompt';
                el.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:#1e293b;color:#fff;border-radius:14px;padding:16px 18px;z-index:9999;max-width:360px;width:calc(100% - 32px);box-shadow:0 8px 30px rgba(0,0,0,0.3);animation:slideUpPWA 0.3s ease;';
                el.innerHTML = `<div style="display:flex;align-items:center;gap:12px;"><span style="font-size:1.8rem;">🎉</span><div style="flex:1;"><strong style="display:block;margin-bottom:2px;">Great work!</strong><span style="font-size:0.8rem;opacity:0.75;">Share your success with friends</span></div><button onclick="document.getElementById('shareEarnPrompt').remove()" style="background:none;border:none;color:rgba(255,255,255,0.5);cursor:pointer;font-size:1rem;"><i class="fas fa-times"></i></button></div><a href="https://wa.me/?text=${waText}" target="_blank" rel="noopener" style="display:flex;align-items:center;justify-content:center;gap:8px;margin-top:12px;background:#25D366;color:#fff;border-radius:10px;padding:10px;text-decoration:none;font-weight:700;"><i class="fab fa-whatsapp"></i> Share on WhatsApp</a>`;
                document.body.appendChild(el);
                setTimeout(() => { const e = document.getElementById('shareEarnPrompt'); if (e) e.remove(); }, 10000);
            }, 2000);
        } else {
            alert(result.message || 'Could not send verification. Please try again.');
            if (btnEl) { btnEl.disabled = false; btnEl.innerHTML = '<i class="fas fa-check-double"></i> Verify Task Done'; }
        }
    } catch (e) {
        alert('Network error. Please try again.');
        if (btnEl) { btnEl.disabled = false; btnEl.innerHTML = '<i class="fas fa-check-double"></i> Verify Task Done'; }
    }
}
window.verifyTaskDone = verifyTaskDone;

// ── Rating Popup ───────────────────────────────────────────────────────────
function openRatingPopup(taskId) {
    let popup = document.getElementById('taskRatingPopup');
    if (!popup) {
        popup = document.createElement('div');
        popup.id = 'taskRatingPopup';
        popup.innerHTML = `
            <div style="background:#fff;border-radius:16px;padding:30px;max-width:380px;width:90%;text-align:center;">
                <div style="font-size:50px;margin-bottom:10px;">🌟</div>
                <h3 style="margin:0 0 8px;">Rate the Poster</h3>
                <p style="color:#666;font-size:14px;margin-bottom:20px;">How was your experience? (Optional)</p>
                <input type="hidden" id="ratingTaskId">
                <div id="starRatingRow" style="font-size:36px;margin-bottom:16px;cursor:pointer;">
                    <span class="rating-star" data-value="1">☆</span>
                    <span class="rating-star" data-value="2">☆</span>
                    <span class="rating-star" data-value="3">☆</span>
                    <span class="rating-star" data-value="4">☆</span>
                    <span class="rating-star" data-value="5">☆</span>
                </div>
                <textarea id="ratingReviewText" placeholder="Write a review... (optional)" style="width:100%;box-sizing:border-box;border:1px solid #ddd;border-radius:8px;padding:10px;font-size:14px;resize:none;margin-bottom:16px;" rows="3"></textarea>
                <div style="display:flex;gap:10px;">
                    <button onclick="closeRatingPopup()" style="flex:1;padding:12px;background:#f0f0f0;border:none;border-radius:8px;cursor:pointer;font-weight:600;">Skip</button>
                    <button onclick="submitTaskRating()" style="flex:1;padding:12px;background:linear-gradient(135deg,#f59e0b,#d97706);color:#000;border:none;border-radius:8px;cursor:pointer;font-weight:700;">Submit</button>
                </div>
            </div>`;
        popup.style.cssText = 'display:none;position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:10000;align-items:center;justify-content:center;';
        document.body.appendChild(popup);
        popup.querySelectorAll('.rating-star').forEach(star => {
            star.addEventListener('click', function() {
                const val = parseInt(this.dataset.value);
                popup.querySelectorAll('.rating-star').forEach(s => {
                    s.textContent = parseInt(s.dataset.value) <= val ? '★' : '☆';
                    if (parseInt(s.dataset.value) <= val) s.classList.add('selected'); else s.classList.remove('selected');
                });
            });
        });
    }
    document.getElementById('ratingTaskId').value = taskId;
    popup.querySelectorAll('.rating-star').forEach(s => { s.textContent = '☆'; s.classList.remove('selected'); });
    if (document.getElementById('ratingReviewText')) document.getElementById('ratingReviewText').value = '';
    popup.style.display = 'flex';
}
window.openRatingPopup = openRatingPopup;

function closeRatingPopup() {
    const popup = document.getElementById('taskRatingPopup');
    if (popup) popup.style.display = 'none';
}
window.closeRatingPopup = closeRatingPopup;

async function submitTaskRating() {
    const taskId = document.getElementById('ratingTaskId')?.value;
    // querySelectorAll returns all selected stars (1 through N); take the last one's value
    const selectedStars = document.querySelectorAll('#taskRatingPopup .rating-star.selected');
    const rating = selectedStars.length ? parseInt(selectedStars[selectedStars.length - 1].dataset.value) : 0;
    const review = document.getElementById('ratingReviewText')?.value.trim() || '';
    if (!rating) { closeRatingPopup(); return; }
    const token = localStorage.getItem('taskearn_token');
    if (!token) { closeRatingPopup(); return; }
    try {
        await fetch((window.API_BASE_URL || '') + '/tasks/' + taskId + '/rate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
            body: JSON.stringify({ rating: rating, review: review })
        });
    } catch (e) {}
    showToast('⭐ Thank you for your rating!', 'success');
    await syncUserTasksFromServer();
    renderDashboard();
    closeRatingPopup();
}
window.submitTaskRating = submitTaskRating;

function renderPostedTasks() {
    const el = document.getElementById('myPostedTasks');
    if (!el) return;

    // Show active (incl. expired) and accepted posted tasks (not completed/payment_released/paid — those go to history)
    const visiblePostedTasks = myPostedTasks.filter(t => {
        if (t.status === 'accepted' || t.status === 'pending_payment' || t.status === 'verify_pending') return true;
        if (t.status !== 'active') return false;
        return true; // include expired — rendered with Expired badge
    });

    if (visiblePostedTasks.length === 0) {
        el.innerHTML = '<div class="empty-state"><i class="fas fa-clipboard-list"></i><h3>No posted tasks</h3><button class="btn btn-primary" onclick="openModal(\'postTaskModal\')">Post a Task</button></div>';
        return;
    }

    el.innerHTML = visiblePostedTasks.map(t => {
        let helperHTML = '';
        if ((t.status === 'accepted' || t.status === 'pending_payment' || t.status === 'verify_pending') && t.accepted_by) {
            const hName = t.helper_name || t.helperName || 'Helper';
            const hPhone = t.helper_phone || t.helperPhone || '';
            const hRating = t.helper_rating || t.helperRating || 0;
            const hTasks = t.helper_tasks_completed || t.helperTasksCompleted || 0;
            helperHTML = `
                <div style="background:var(--card-bg, rgba(74,222,128,0.06));border:1px solid var(--border-color, rgba(74,222,128,0.2));border-radius:10px;padding:14px;margin-top:12px;">
                    <div style="display:flex;align-items:center;gap:12px;margin-bottom:10px;">
                        <div style="width:42px;height:42px;border-radius:50%;background:linear-gradient(135deg,#4ade80,#22c55e);display:flex;align-items:center;justify-content:center;color:#fff;font-weight:700;font-size:16px;">${hName.charAt(0).toUpperCase()}</div>
                        <div style="flex:1;">
                            <div style="font-weight:600;font-size:15px;">${escapeHtml(hName)}</div>
                            <div style="font-size:12px;color:#888;">
                                ${hRating > 0 ? '<i class="fas fa-star" style="color:#fbbf24;"></i> ' + Number(hRating).toFixed(1) : ''}
                                ${hTasks > 0 ? ' &middot; ' + hTasks + ' tasks done' : ''}
                            </div>
                        </div>
                    </div>
                    <div style="display:flex;gap:8px;">
                        ${hPhone ? '<a href="tel:' + hPhone + '" class="btn" style="flex:1;background:#4ade80;color:#000;text-align:center;padding:10px;border-radius:8px;font-weight:600;text-decoration:none;font-size:13px;"><i class="fas fa-phone"></i> Call</a>' : ''}
                        ${hPhone ? '<a href="https://wa.me/' + hPhone.replace(/[^0-9]/g, '') + '" target="_blank" class="btn" style="flex:1;background:#25D366;color:#fff;text-align:center;padding:10px;border-radius:8px;font-weight:600;text-decoration:none;font-size:13px;"><i class="fab fa-whatsapp"></i> WhatsApp</a>' : ''}
                    </div>
                </div>`;
        }

        const isExpiredTask = t.status === 'active' && getTimeLeft(t.expiresAt) === 'Expired';
        let statusLabel = t.status;
        let statusClass = t.status;
        if (isExpiredTask) { statusLabel = '⏰ Expired'; statusClass = 'expired'; }
        else if (t.status === 'accepted') { statusLabel = 'Accepted'; statusClass = 'accepted'; }
        else if (t.status === 'completed' || t.status === 'pending_payment') { statusLabel = 'Awaiting Payment'; statusClass = 'warning'; }
        else if (t.status === 'verify_pending') { statusLabel = '⏳ Verify & Pay'; statusClass = 'warning'; }
        else if (t.status === 'payment_released') { statusLabel = '✅ Payment Released'; statusClass = 'paid'; }

        let actionsHTML = '';
        if (isExpiredTask) {
            actionsHTML = `<div class="task-actions" style="margin-top:10px;">
                <div style="background:rgba(239,68,68,0.07);border:1px solid rgba(239,68,68,0.2);border-radius:8px;padding:10px 12px;margin-bottom:8px;font-size:13px;color:#ef4444;">
                    <i class="fas fa-clock"></i> This task expired without being accepted.
                </div>
                <div style="display:flex;gap:8px;">
                    <button class="btn btn-danger" style="flex:1;" onclick="deleteTask(${t.id})"><i class="fas fa-trash"></i> Delete</button>
                    <button class="btn btn-primary" style="flex:1;" onclick="openEditTask(${t.id})"><i class="fas fa-rotate-right"></i> Re-post</button>
                </div>
            </div>`;
        } else if (t.status === 'active') {
            actionsHTML = `<div class="task-actions">
                    <button class="btn btn-edit" onclick="openEditTask(${t.id})"><i class="fas fa-edit"></i> Edit</button>
                    <button class="btn btn-danger" onclick="deleteTask(${t.id})"><i class="fas fa-trash"></i> Delete</button>
                </div>`;
        } else if (t.status === 'accepted') {
            actionsHTML = `<div class="task-actions" style="margin-top:10px;">
                    <button class="btn" style="width:100%;background:#ef4444;color:#fff;font-weight:600;padding:10px;border-radius:8px;border:none;" onclick="posterCancelTask(${t.id})" title="Helper unresponsive? Cancel and delete this task">
                        <i class="fas fa-times-circle"></i> Cancel & Delete Task
                    </button>
                </div>`;
        } else if (t.status === 'verify_pending') {
            const totalAmt = getTaskFinalValue(t);
            actionsHTML = `<div class="task-actions" style="margin-top:10px;">
                    <button class="btn" style="width:100%;background:linear-gradient(135deg,#f59e0b,#d97706);color:#000;font-weight:700;padding:12px;border-radius:10px;border:none;font-size:15px;" onclick="verifyAndPayTask(${t.id})">
                        <i class="fas fa-check-circle"></i> ✅ Verify & Pay Now (₹${totalAmt.toFixed(2)})
                    </button>
                </div>`;
        }

        return `
            <div class="my-task-card" data-task-id="${t.id}">
                <div class="my-task-card-header">
                    <span class="task-category">${formatCategory(t.category)}</span>
                    ${(() => { const v = getRequiredVehicle(t.description); return v ? `<span class="task-vehicle-badge" title="Required vehicle">${escapeHtml(v.label)}</span>` : ''; })()}
                    <span class="task-status ${statusClass}">${statusLabel}</span>
                </div>
                <h4>${escapeHtml(t.title)}</h4>
                <div class="task-meta"><span>₹${Math.round((parseFloat(t.price)||0)+(parseFloat(t.service_charge)||0))}</span><span>${getTimeLeft(t.expiresAt)}</span></div>
                ${helperHTML}
                ${actionsHTML}
            </div>
        `;
    }).join('');
}

function renderAcceptedTasks() {
    const el = document.getElementById('myAcceptedTasks');
    if (!el) return;

    // Filter out only paid tasks — expiry is irrelevant once accepted
    const visibleAcceptedTasks = myAcceptedTasks.filter(t => {
        if (t.status === 'paid') return false;
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
                <p style="color: #666; font-size: 13px; margin: 0;">You'll receive ₹${getHelperEarnings(t).toFixed(0)} (after ${Math.round(getCommissionRate(t.category||'other')*100)}% commission)</p>
            </div>`;
        } else if (t.status === 'verify_pending') {
            // Helper sent verification, waiting for poster to pay
            statusHTML = '⏳ Waiting for Payment';
            statusColor = 'warning';
            actionHTML = `<div style="background: rgba(245,158,11, 0.1); border: 1px solid #f59e0b; border-radius: 8px; padding: 12px; margin-top: 10px;">
                <p style="color: #d97706; margin-bottom: 8px; font-weight:600;">
                    <i class="fas fa-hourglass-half"></i> Verification sent! Waiting for poster to pay...
                </p>
                <p style="color: #666; font-size: 13px; margin: 0;">You'll receive ₹${getHelperEarnings(t).toFixed(0)} (after ${Math.round(getCommissionRate(t.category||'other')*100)}% commission)</p>
            </div>`;
        } else if (t.status === 'payment_released') {
            // Payment released, helper needs to mark as completed
            statusHTML = '💰 Payment Released';
            statusColor = 'paid';
            actionHTML = `<div style="background: rgba(16,185,129, 0.1); border: 1px solid #10b981; border-radius: 8px; padding: 12px; margin-top: 10px;">
                <p style="color: #059669; margin-bottom: 10px; font-weight:600;">
                    <i class="fas fa-check-circle"></i> Payment received! Tap to finalize.
                </p>
                <button onclick="event.stopPropagation(); markTaskCompleted(${t.id})" style="width:100%;background:linear-gradient(135deg,#10b981,#059669);color:#fff;border:none;border-radius:8px;padding:12px;font-weight:700;font-size:15px;cursor:pointer;">
                    <i class="fas fa-flag-checkered"></i> 🎉 Mark as Completed
                </button>
            </div>`;
        } else {
            // Still in progress - show action buttons
            const posterPhone = t.poster_phone || t.postedBy?.phone || '';
            const taskLat = t.location?.lat || '';
            const taskLng = t.location?.lng || '';
            actionHTML = `<div style="margin-top:10px;">
                <button onclick="event.stopPropagation(); verifyTaskDone(${t.id}, this)" style="width:100%;background:linear-gradient(135deg,#6366f1,#4f46e5);color:#fff;border:none;border-radius:8px;padding:12px;font-weight:700;font-size:15px;cursor:pointer;margin-bottom:8px;">
                    <i class="fas fa-check-double"></i> Verify Task Done
                </button>
                <div style="display:flex;flex-wrap:wrap;gap:8px;">
                    ${posterPhone ? `<a href="tel:${escapeHtml(posterPhone)}" class="btn" style="flex:1;min-width:120px;background:#6366f1;color:#fff;text-decoration:none;text-align:center;display:inline-flex;align-items:center;justify-content:center;gap:4px;" onclick="event.stopPropagation();"><i class="fas fa-phone"></i> Contact</a>` : ''}
                    ${taskLat && taskLng ? `<button class="btn" style="flex:1;min-width:120px;background:#0ea5e9;color:#fff;" onclick="event.stopPropagation(); navigateToTask(${taskLat}, ${taskLng}, '${escapeHtml(t.title).replace(/'/g, "\\\\'")}')"><i class="fas fa-map-marker-alt"></i> Navigate</button>` : ''}
                    <button class="btn" style="flex:1;min-width:120px;background:#ef4444;color:#fff;" onclick="event.stopPropagation(); abandonTask(${t.id})"><i class="fas fa-times"></i> Release Task</button>
                </div>
            </div>`;
        }
        
        return `
            <div class="my-task-card" style="cursor:pointer;" onclick="goToTaskInProgress(${t.id})">
                <div class="my-task-card-header">
                    <span class="task-category">${formatCategory(t.category)}</span>
                    ${(() => { const v = getRequiredVehicle(t.description); return v ? `<span class="task-vehicle-badge" title="Required vehicle">${escapeHtml(v.label)}</span>` : ''; })()}
                    <span class="task-status ${statusColor}">${statusHTML}</span>
                </div>
                <h4>${escapeHtml(t.title)}</h4>
                <div class="task-meta"><span>Earn: ₹${Math.round(getHelperEarnings(t))}</span><span>${t.expiresAt ? getTimeLeft(t.expiresAt) : (t.location && t.location.address ? t.location.address : '')}</span></div>
                ${actionHTML}
            </div>
        `;
    }).join('');
}

function renderCompletedTasks() {
    const el = document.getElementById('myCompletedTasks');
    if (!el) return;

    // Client-side 48h guard (server already cleaned up, but protect localStorage stale data)
    const cutoff48h = Date.now() - (48 * 3600 * 1000);
    const visible = myCompletedTasks.filter(t => !t.paidAt || new Date(t.paidAt).getTime() > cutoff48h);

    // Also show payment_released tasks (pending mark-complete) from myAcceptedTasks
    const pendingComplete = myAcceptedTasks.filter(t => t.status === 'payment_released');

    if (visible.length === 0 && pendingComplete.length === 0) {
        el.innerHTML = '<div class="empty-state"><i class="fas fa-trophy"></i><h3>No completed tasks</h3></div>';
        return;
    }

    // Pending mark-complete section
    let pendingHTML = '';
    if (pendingComplete.length > 0) {
        pendingHTML = `<div style="margin-bottom:20px;">
            <h4 style="margin:0 0 12px;color:#059669;"><i class="fas fa-hand-holding-usd"></i> Payment Received — Tap to Finalize</h4>
            ${pendingComplete.map(t => {
                const earned = t.earnedAmount || Math.round(getHelperEarnings(t) * 100) / 100;
                return `<div class="my-task-card" style="border:2px solid #10b981;">
                    <div class="my-task-card-header">
                        <span class="task-category">${formatCategory(t.category)}</span>
                        <span class="task-status" style="background:#10b981;color:#fff;">💰 Payment Released</span>
                    </div>
                    <h4>${escapeHtml(t.title)}</h4>
                    <p>You'll earn: <strong style="color:#10b981;">₹${earned.toFixed(2)}</strong></p>
                    <button onclick="markTaskCompleted(${t.id})" style="width:100%;background:linear-gradient(135deg,#10b981,#059669);color:#fff;border:none;border-radius:8px;padding:12px;font-weight:700;font-size:15px;cursor:pointer;margin-top:10px;">
                        <i class="fas fa-flag-checkered"></i> 🎉 Mark as Completed
                    </button>
                </div>`;
            }).join('')}
        </div>`;
    }

    // Calculate total earned (after platform commission)
    const totalEarned = visible.reduce((s, t) => {
        if (t.earnedAmount) return s + t.earnedAmount;
        return s + Math.round(getHelperEarnings(t) * 100) / 100;
    }, 0);

    el.innerHTML = `
        <div style="background:linear-gradient(135deg,#10b981,#34d399);color:white;padding:25px;border-radius:15px;text-align:center;margin-bottom:20px;">
            <h3 style="margin:0;">Total Earned</h3>
            <p style="font-size:2.5rem;font-weight:800;margin:10px 0;">₹${totalEarned.toFixed(2)}</p>
            <small style="opacity:0.9;">${visible.length} task${visible.length > 1 ? 's' : ''} completed (after platform commission)</small>
        </div>
        ${pendingHTML}
        ${visible.map(t => {
            const taskBaseVal = (parseFloat(t.price)||0) + (parseFloat(t.service_charge)||0);
            const earned = t.earnedAmount || getHelperEarnings(t);
            const _commPct2 = Math.round(getCommissionRate(t.category||'other') * 100);
            const posterName = t.poster_name || (t.postedBy && t.postedBy.name) || 'Poster';
            const posterId = t.poster_user_id || (t.postedBy && t.postedBy.id) || t.posted_by || '';
            const posterPhone = t.poster_phone || (t.postedBy && t.postedBy.phone) || '';
            const posterEmail = t.poster_email || (t.postedBy && t.postedBy.email) || '';
            const alreadyRated = hasRatedTask(t.id);
            const rateBtn = alreadyRated
                ? `<span style="color:#10b981;font-weight:600;font-size:13px;"><i class="fas fa-check-circle"></i> Poster Rated</span>`
                : `<button class="btn" style="background:linear-gradient(135deg,#f59e0b,#fbbf24);color:#000;font-weight:600;font-size:13px;padding:8px 16px;border-radius:8px;border:none;cursor:pointer;"
                    onclick="openRateUserModal({taskId:${t.id},taskTitle:'${escapeHtml(t.title).replace(/'/g, "\\'")  }',otherName:'${escapeHtml(posterName).replace(/'/g, "\\'")  }',otherUserId:'${escapeHtml(String(posterId))}',role:'helper'})">
                    <i class="fas fa-star"></i> Rate Poster
                  </button>`;

            // Poster contact section
            let contactHTML = '';
            const _pidBadge = posterId ? `<span style="font-size:11px;color:#888;background:rgba(99,102,241,0.12);padding:2px 6px;border-radius:4px;margin-left:6px;font-weight:400;">ID: ${escapeHtml(String(posterId))}</span>` : '';
            if (posterPhone || posterEmail) {
                contactHTML = `<div style="background:var(--card-bg,rgba(99,102,241,0.06));border:1px solid var(--border-color,rgba(99,102,241,0.2));border-radius:10px;padding:12px;margin:10px 0;">
                    <div style="font-size:12px;color:#888;margin-bottom:6px;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;">Poster Details</div>
                    <div style="font-weight:600;margin-bottom:6px;">${escapeHtml(posterName)}${_pidBadge}</div>
                    <div style="display:flex;gap:8px;flex-wrap:wrap;">
                        ${posterPhone ? `<a href="tel:${escapeHtml(posterPhone)}" class="btn" style="flex:1;min-width:100px;background:#4ade80;color:#000;text-align:center;padding:8px;border-radius:8px;font-weight:600;text-decoration:none;font-size:13px;"><i class="fas fa-phone"></i> Call</a>` : ''}
                        ${posterPhone ? `<a href="https://wa.me/${posterPhone.replace(/[^0-9]/g,'')}" target="_blank" class="btn" style="flex:1;min-width:100px;background:#25D366;color:#fff;text-align:center;padding:8px;border-radius:8px;font-weight:600;text-decoration:none;font-size:13px;"><i class="fab fa-whatsapp"></i> WhatsApp</a>` : ''}
                        ${posterEmail ? `<a href="mailto:${escapeHtml(posterEmail)}" class="btn" style="flex:1;min-width:100px;background:#6366f1;color:#fff;text-align:center;padding:8px;border-radius:8px;font-weight:600;text-decoration:none;font-size:13px;"><i class="fas fa-envelope"></i> Email</a>` : ''}
                    </div>
                </div>`;
            } else if (posterName && posterName !== 'Poster') {
                contactHTML = `<p style="color:#888;font-size:13px;margin-bottom:6px;">Posted by: <strong>${escapeHtml(posterName)}</strong>${_pidBadge}</p>`;
            } else if (posterId) {
                contactHTML = `<p style="color:#888;font-size:13px;margin-bottom:6px;">Poster ID: <strong>${escapeHtml(String(posterId))}</strong></p>`;
            }

            return `<div class="my-task-card">
                <div class="my-task-card-header">
                    <span class="task-category">${formatCategory(t.category)}</span>
                    <span class="task-status paid" style="background:#10b981;color:#fff;">Completed</span>
                </div>
                <h4>${escapeHtml(t.title)}</h4>
                ${contactHTML}
                <p>Earned: <strong style="color:#10b981;">₹${earned.toFixed(2)}</strong> <small>(₹${taskBaseVal.toFixed(2)} task value − ${_commPct2}% commission)</small></p>
                <div style="margin-top:10px;">${rateBtn}</div>
            </div>`;
        }).join('')}
    `;
}

function renderPaidPostedTasks() {
    const el = document.getElementById('myPaidPostedTasks');
    if (!el) return;

    // 48h cutoff — same window as completed tasks
    const _paidCutoff = Date.now() - (48 * 3600 * 1000);
    const _visiblePaid = myPaidPostedTasks.filter(t => {
        const ts = t.completedAt || t.postedAt;
        return !ts || new Date(ts).getTime() > _paidCutoff;
    });

    if (_visiblePaid.length === 0) {
        el.innerHTML = '<div class="empty-state" style="padding:20px 0;"><i class="fas fa-history"></i><h3 style="font-size:15px;">No paid tasks yet</h3></div>';
        return;
    }

    el.innerHTML = _visiblePaid.map(t => {
        const helperName = t.helper_name || 'Helper';
        const helperId = t.accepted_by || '';
        const alreadyRated = hasRatedTask(t.id);
        const rateBtn = alreadyRated
            ? `<span style="color:#10b981;font-weight:600;font-size:13px;"><i class="fas fa-check-circle"></i> Helper Rated</span>`
            : `<button class="btn" style="background:linear-gradient(135deg,#f59e0b,#fbbf24);color:#000;font-weight:600;font-size:13px;padding:8px 16px;border-radius:8px;border:none;cursor:pointer;"
                onclick="openRateUserModal({taskId:${t.id},taskTitle:'${escapeHtml(t.title).replace(/'/g, "\\'")  }',otherName:'${escapeHtml(helperName).replace(/'/g, "\\'")  }',otherUserId:'${escapeHtml(String(helperId))}',role:'poster'})">
                <i class="fas fa-star"></i> Rate Helper
               </button>`;
        return `<div class="my-task-card">
            <div class="my-task-card-header">
                <span class="task-category">${formatCategory(t.category)}</span>
                <span class="task-status paid" style="background:#6366f1;color:#fff;">Paid</span>
            </div>
            <h4>${escapeHtml(t.title)}</h4>
            <p style="color:#888;font-size:13px;margin-bottom:6px;">Completed by: <strong>${escapeHtml(helperName)}</strong></p>
            <div style="margin-top:10px;">${rateBtn}</div>
        </div>`;
    }).join('');
}

// ========================================
// FILTERS
// ========================================

let _searchDebounceTimer = null;

function applyFilters() {
    const cat = document.getElementById('filterCategory').value;
    const dist = parseInt(document.getElementById('filterDistance').value);
    const minB = parseInt(document.getElementById('minBudget').value) || 0;
    const maxB = parseInt(document.getElementById('maxBudget').value) || 999999;
    const searchEl = document.getElementById('filterSearch');
    const searchTerm = searchEl ? searchEl.value.trim().toLowerCase() : '';

    // Client-side filter on already-loaded tasks
    const filtered = tasks.filter(t => {
        if (t.status !== 'active') return false;
        if (getTimeLeft(t.expiresAt) === 'Expired') return false;
        const d = getDistance(userLocation.lat, userLocation.lng, t.location.lat, t.location.lng);
        if (cat !== 'all' && t.category !== cat) return false;
        if (d > dist) return false;
        if (t.price < minB || t.price > maxB) return false;
        if (searchTerm && !(t.title || '').toLowerCase().includes(searchTerm) && !(t.description || '').toLowerCase().includes(searchTerm)) return false;
        return true;
    });

    renderTasks(filtered);
    showToast('Found ' + filtered.length + ' tasks');

    // Also do server-side search for broader results (debounced)
    if (searchTerm.length >= 2 && typeof SearchAPI !== 'undefined') {
        clearTimeout(_searchDebounceTimer);
        _searchDebounceTimer = setTimeout(async () => {
            try {
                const params = { q: searchTerm };
                if (cat !== 'all') params.category = cat;
                if (minB > 0) params.min_price = minB;
                if (maxB < 999999) params.max_price = maxB;
                const result = await SearchAPI.search(params);
                if (result.success && result.tasks && result.tasks.length > 0) {
                    // Merge server results with local - add any new tasks not already loaded
                    const existingIds = new Set(tasks.map(t => t.id));
                    let newCount = 0;
                    result.tasks.forEach(st => {
                        if (!existingIds.has(st.id)) {
                            tasks.push(st);
                            newCount++;
                        }
                    });
                    if (newCount > 0) {
                        applyFilters(); // Re-filter with merged data
                    }
                }
            } catch (e) {
                console.log('Server search error:', e);
            }
        }, 500);
    }
}

function clearFilters() {
    document.getElementById('filterCategory').value = 'all';
    document.getElementById('filterDistance').value = 10;
    document.getElementById('distanceValue').textContent = '10';
    document.getElementById('minBudget').value = '';
    document.getElementById('maxBudget').value = '';
    var searchEl = document.getElementById('filterSearch');
    if (searchEl) searchEl.value = '';
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

function getCategoryIcon(cat) {
    const icons = {
        household: 'fas fa-home',
        delivery: 'fas fa-truck',
        tutoring: 'fas fa-book-open',
        transport: 'fas fa-car',
        vehicle: 'fas fa-wrench',
        repair: 'fas fa-tools',
        photography: 'fas fa-camera',
        freelance: 'fas fa-laptop-code',
        waste: 'fas fa-trash-alt',
        cleaning: 'fas fa-broom',
        cooking: 'fas fa-utensils',
        petcare: 'fas fa-paw',
        gardening: 'fas fa-leaf',
        shopping: 'fas fa-shopping-bag',
        eventhelp: 'fas fa-calendar-check',
        moving: 'fas fa-dolly',
        techsupport: 'fas fa-headset',
        beauty: 'fas fa-spa',
        laundry: 'fas fa-tshirt',
        catering: 'fas fa-concierge-bell',
        babysitting: 'fas fa-baby',
        eldercare: 'fas fa-user-friends',
        fitness: 'fas fa-dumbbell',
        painting: 'fas fa-paint-roller',
        electrician: 'fas fa-bolt',
        plumbing: 'fas fa-faucet',
        carpentry: 'fas fa-hammer',
        tailoring: 'fas fa-cut',
    };
    return icons[cat] || 'fas fa-briefcase';
}

function getTimerUrgencyClass(timeLeft) {
    if (!timeLeft || timeLeft === 'Expired') return 'tc-timer-expired';
    // Only minutes left (no hours, no days) — very urgent
    if (/^\d+m/.test(timeLeft) && !timeLeft.includes('h') && !timeLeft.includes('d')) return 'tc-timer-urgent';
    // Under 3 hours
    const hMatch = timeLeft.match(/^(\d+)h/);
    if (hMatch && parseInt(hMatch[1]) < 3) return 'tc-timer-warning';
    return 'tc-timer-ok';
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
    // Block posting tasks when wallet is in debt
    if (id === 'postTaskModal') {
        if (typeof isDebtSuspended === 'function' && isDebtSuspended()) {
            try { showDebtSuspendedPopup(); } catch(e) {
                showToast('❌ Your account has a negative balance. Top up your wallet to post tasks.');
            }
            return;
        }
        resetBonusOnModalOpen();
    }
    document.getElementById(id)?.classList.add('active');
    document.body.classList.add('modal-open');
    // Re-attempt Google Sign-In init when login/signup modal opens. If the
    // GIS library hasn't finished loading yet, poll briefly until it does.
    if (id === 'loginModal' || id === 'signupModal') {
        if (typeof initGoogleSignIn === 'function') {
            const tryInit = (attempts) => {
                if (typeof google !== 'undefined' && google.accounts && google.accounts.id) {
                    try { initGoogleSignIn(); } catch (e) { console.warn('Google init retry failed', e); }
                } else if (attempts < 30) {
                    setTimeout(() => tryInit(attempts + 1), 200);
                }
            };
            tryInit(0);
        }
    }
}

function closeModal(id) {
    document.getElementById(id)?.classList.remove('active');
    // Only unlock scroll when no modal is open
    if (!document.querySelector('.modal.active')) {
        document.body.classList.remove('modal-open');
    }
}

function switchModal(from, to) {
    closeModal(from);
    setTimeout(() => openModal(to), 200);
}

function toggleMobileMenu() {
    document.getElementById('mobileMenu')?.classList.toggle('active');
}

function hardRefreshApp() {
    toggleMobileMenu();
    var clearAndReload = function() {
        if ('caches' in window) {
            caches.keys().then(function(keys) {
                return Promise.all(keys.map(function(k) { return caches.delete(k); }));
            }).then(function() { location.reload(true); }).catch(function() { location.reload(true); });
        } else {
            location.reload(true);
        }
    };
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.getRegistration().then(function(reg) {
            if (reg) {
                if (reg.waiting) reg.waiting.postMessage({ type: 'SKIP_WAITING' });
                reg.unregister().then(clearAndReload).catch(clearAndReload);
            } else {
                clearAndReload();
            }
        }).catch(clearAndReload);
    } else {
        clearAndReload();
    }
}

function scrollToSection(id) {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
    // Refresh map tiles after scrolling to map section
    if (map && (id === 'find-tasks' || id === 'map')) {
        setTimeout(() => map.invalidateSize(), 400);
    }
}

function showToast(msg, duration = 3000) {
    const toast = document.getElementById('toast');
    const text = document.getElementById('toastMessage');
    if (toast && text) {
        text.textContent = msg;
        toast.classList.add('show');
        setTimeout(() => toast.classList.remove('show'), duration);
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
    
    // Get service charge based on selected category.
    // Service charge ONLY for Delivery/Pick&Drop categories; 0 for everything else.
    const category = document.getElementById('modalTaskCategory')?.value || 'other';
    const distanceKm = (typeof window.__wmLastDistance === 'number') ? window.__wmLastDistance : null;
    const serviceCharge = getServiceCharge(category, distanceKm); // 0 for non-delivery
    const chargeInfo = getServiceChargeInfo(category);

    // Task Posting Fee: DISABLED (was 5%). No fee added to poster's total.
    // const platformFee = Math.round((total + serviceCharge) * 0.05 * 100) / 100;
    const platformFee = 0; // DISABLED
    const totalPayable = total + serviceCharge; // What poster pays (no posting fee)
    const taskValueForHelper = total + serviceCharge;
    const commissionRate = getCommissionRate(category); // 15% delivery, 17% others
    const helperCommission = Math.round(taskValueForHelper * commissionRate * 100) / 100;
    const workerEarns = taskValueForHelper - helperCommission;
    
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
    const platformFeeDisplay = document.getElementById('platformFeeAmount');
    
    if (budgetDisplay) {
        budgetDisplay.textContent = '₹' + total;
    }
    if (payableDisplay) {
        payableDisplay.textContent = '₹' + totalPayable.toFixed(0);
    }
    if (workerEarnsDisplay) {
        workerEarnsDisplay.textContent = '₹' + workerEarns.toFixed(0);
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
    if (platformFeeDisplay) {
        platformFeeDisplay.textContent = '₹0';
    }

    // Hide the platform-fee row (posting fee disabled).
    const platformRow = platformFeeDisplay ? platformFeeDisplay.closest('.charge-row') : null;
    if (platformRow) platformRow.style.display = 'none';
    // Show service-charge row ONLY for Delivery/Pick&Drop categories.
    const feeRow = document.getElementById('serviceChargeRow');
    const timeRow = document.getElementById('serviceChargeTimeRow');
    if (feeRow) feeRow.style.display = serviceCharge > 0 ? '' : 'none';
    if (timeRow) timeRow.style.display = serviceCharge > 0 ? '' : 'none';
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
        // Auto-trigger fair-price recompute for distance-based categories.
        try {
            const dropApiInput = document.getElementById('modalTaskLocation_drop');
            if (typeof window.__wmRefreshDistance === 'function') window.__wmRefreshDistance();
            else if (dropApiInput) dropApiInput.dispatchEvent(new Event('blur', { bubbles: true }));
        } catch (e) {}
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
            if (e.target === this && !this.getAttribute('data-required')) {
                this.classList.remove('active');
                if (!document.querySelector('.modal.active')) {
                    document.body.classList.remove('modal-open');
                }
                clearRoute();
            }
        };
    });

    // Escape key
    document.onkeydown = function(e) {
        if (e.key === 'Escape') {
            document.querySelectorAll('.modal.active').forEach(m => {
                if (!m.getAttribute('data-required')) m.classList.remove('active');
            });
            if (!document.querySelector('.modal.active')) document.body.classList.remove('modal-open');
            clearRoute();
        }
    };

    // Scroll effect
    window.onscroll = function() {
        const nav = document.querySelector('.navbar');
        if (nav) nav.style.boxShadow = window.scrollY > 50 ? '0 4px 20px rgba(0,0,0,0.1)' : '';
    };

    // Safety: clear any stale scroll lock on load (e.g. from crashed previous session)
    if (!document.querySelector('.modal.active')) {
        document.body.classList.remove('modal-open');
    }

    // Track first user gesture so AudioContext can be created legally
    function _markUserInteracted() {
        window._userHasInteracted = true;
        document.removeEventListener('click', _markUserInteracted);
        document.removeEventListener('touchstart', _markUserInteracted);
        document.removeEventListener('keydown', _markUserInteracted);
    }
    document.addEventListener('click', _markUserInteracted, { once: true, passive: true });
    document.addEventListener('touchstart', _markUserInteracted, { once: true, passive: true });
    document.addEventListener('keydown', _markUserInteracted, { once: true, passive: true });
}

// ========================================
// EMAIL VERIFICATION
// ========================================

function checkEmailVerification() {
    var banner = document.getElementById('emailVerifyBanner');
    if (!banner || !currentUser) return;
    banner.style.display = currentUser.emailVerified ? 'none' : 'block';
}

function startEmailVerification() {
    if (!currentUser || !currentUser.email) { showToast('Please login first', 'error'); return; }

    showToast('Sending verification code...', 'info');

    var token = localStorage.getItem('taskearn_token');
    fetch((window.API_BASE_URL || '') + '/auth/send-verification-otp', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token }
    }).then(function(resp) { return resp.json(); })
    .then(function(data) {
        if (data.success) {
            showToast('Verification code sent to ' + currentUser.email, 'success');
            promptEmailOTP();
        } else {
            showToast(data.message || 'Failed to send verification code', 'error');
        }
    }).catch(function(err) {
        console.error('❌ Send verification OTP error:', err);
        showToast('Network error. Please try again.', 'error');
    });
}

function promptEmailOTP() {
    var html = '<div style="text-align:center;padding:20px;">' +
        '<div style="width:60px;height:60px;border-radius:50%;background:linear-gradient(135deg,#f59e0b,#fbbf24);display:flex;align-items:center;justify-content:center;margin:0 auto 16px;"><i class="fas fa-envelope-open" style="font-size:24px;color:white;"></i></div>' +
        '<h3 style="margin-bottom:8px;">Enter Verification Code</h3>' +
        '<p style="color:#64748b;margin-bottom:20px;">We sent a 6-digit code to your email</p>' +
        '<input type="text" id="emailVerifyInput" maxlength="6" style="text-align:center;font-size:24px;letter-spacing:8px;padding:12px;border:2px solid #e2e8f0;border-radius:12px;width:200px;font-weight:700;" placeholder="000000">' +
        '<div style="margin-top:20px;display:flex;gap:10px;justify-content:center;">' +
        '<button class="btn btn-outline" onclick="closeModal(\'emailVerifyModal\')">Cancel</button>' +
        '<button class="btn btn-primary" onclick="confirmEmailVerify()">Verify</button>' +
        '</div></div>';

    var modal = document.getElementById('emailVerifyModal');
    if (!modal) {
        modal = document.createElement('div');
        modal.className = 'modal';
        modal.id = 'emailVerifyModal';
        modal.innerHTML = '<div class="modal-content" style="max-width:380px;"></div>';
        document.body.appendChild(modal);
    }
    modal.querySelector('.modal-content').innerHTML = html;
    openModal('emailVerifyModal');
}

function confirmEmailVerify() {
    var input = document.getElementById('emailVerifyInput');
    if (!input) { showToast('Could not find input field. Please try again.', 'error'); return; }
    var code = input.value.trim();
    if (!code || code.length !== 6) {
        showToast('Please enter the 6-digit code', 'error');
        return;
    }

    // Disable button to prevent double-tap
    var verifyBtn = input.parentElement && input.parentElement.querySelector ? input.parentElement.parentElement.querySelector('.btn-primary') : null;
    if (verifyBtn) { verifyBtn.disabled = true; verifyBtn.textContent = 'Verifying...'; }

    var token = localStorage.getItem('taskearn_token');
    fetch((window.API_BASE_URL || '') + '/auth/verify-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
        body: JSON.stringify({ otp: code })
    }).then(function(resp) {
        return resp.json();
    }).then(function(data) {
        if (data.success) {
            currentUser.emailVerified = true;
            showToast('Email verified successfully!', 'success');
            closeModal('emailVerifyModal');
            checkEmailVerification();
        } else {
            showToast(data.message || 'Verification failed', 'error');
            if (verifyBtn) { verifyBtn.disabled = false; verifyBtn.textContent = 'Verify'; }
        }
    }).catch(function(e) {
        console.error('Email verify error:', e);
        showToast('Network error. Please try again.', 'error');
        if (verifyBtn) { verifyBtn.disabled = false; verifyBtn.textContent = 'Verify'; }
    });
}

// ========================================
// ONBOARDING TUTORIAL
// ========================================

function showOnboarding() {
    if (localStorage.getItem('onboarding_done')) return;

    var steps = [
        { icon: 'fa-hand-wave', title: 'Welcome to Workmate4u!', desc: 'Your local task marketplace. Post tasks you need help with or earn money by completing tasks nearby.' },
        { icon: 'fa-search-location', title: 'Browse Tasks', desc: 'Find tasks near you on the map. Use filters to search by category, distance, and budget.' },
        { icon: 'fa-clipboard-check', title: 'Accept & Earn', desc: 'Accept tasks, complete them, and get paid directly to your wallet. It\'s that simple!' },
        { icon: 'fa-plus-circle', title: 'Post Tasks', desc: 'Need help? Post a task with your budget and location. Helpers nearby will see it instantly.' },
        { icon: 'fa-wallet', title: 'Wallet & Payments', desc: 'Add money to your wallet, pay for tasks, and withdraw your earnings anytime.' }
    ];

    var currentStep = 0;

    function renderStep() {
        var s = steps[currentStep];
        var overlay = document.getElementById('onboardingOverlay');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'onboardingOverlay';
            overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.7);z-index:10001;display:flex;align-items:center;justify-content:center;padding:20px;';
            document.body.appendChild(overlay);
        }
        var isDark = document.documentElement.getAttribute('data-theme') === 'dark';
        var cardBg = isDark ? '#1e293b' : '#ffffff';
        var titleColor = isDark ? '#f1f5f9' : '#1e293b';
        var bodyColor = isDark ? '#cbd5e1' : '#64748b';
        var dotInactive = isDark ? '#334155' : '#e2e8f0';
        var btnBg = isDark ? '#334155' : '#ffffff';
        var btnBorder = isDark ? '#475569' : '#e2e8f0';
        var btnColor = isDark ? '#f1f5f9' : '#64748b';
        overlay.innerHTML = '<div style="background:' + cardBg + ';border-radius:20px;max-width:380px;width:100%;padding:40px 30px;text-align:center;animation:slideIn 0.3s ease;box-shadow:0 10px 30px rgba(0,0,0,0.3);">' +
            '<div style="width:70px;height:70px;border-radius:50%;background:linear-gradient(135deg,#6366f1,#0ea5e9);display:flex;align-items:center;justify-content:center;margin:0 auto 20px;"><i class="fas ' + s.icon + '" style="font-size:28px;color:white;"></i></div>' +
            '<h2 style="margin-bottom:10px;color:' + titleColor + ';font-size:1.3rem;">' + s.title + '</h2>' +
            '<p style="color:' + bodyColor + ';margin-bottom:24px;line-height:1.6;">' + s.desc + '</p>' +
            '<div style="display:flex;gap:6px;justify-content:center;margin-bottom:20px;">' + steps.map(function(_, i) { return '<div style="width:8px;height:8px;border-radius:50%;background:' + (i === currentStep ? '#6366f1' : dotInactive) + ';"></div>'; }).join('') + '</div>' +
            '<div style="display:flex;gap:10px;justify-content:center;">' +
            (currentStep > 0 ? '<button onclick="window._onboardPrev()" style="padding:10px 20px;border:1px solid ' + btnBorder + ';border-radius:10px;background:' + btnBg + ';cursor:pointer;font-weight:600;color:' + btnColor + ';">Back</button>' : '<button onclick="window._onboardSkip()" style="padding:10px 20px;border:1px solid ' + btnBorder + ';border-radius:10px;background:' + btnBg + ';cursor:pointer;font-weight:600;color:' + btnColor + ';">Skip</button>') +
            '<button onclick="window._onboardNext()" style="padding:10px 20px;border:none;border-radius:10px;background:linear-gradient(135deg,#6366f1,#0ea5e9);color:white;cursor:pointer;font-weight:600;">' + (currentStep === steps.length - 1 ? 'Get Started' : 'Next') + '</button>' +
            '</div></div>';
    }

    window._onboardNext = function() {
        if (currentStep < steps.length - 1) { currentStep++; renderStep(); }
        else { closeOnboarding(); }
    };
    window._onboardPrev = function() {
        if (currentStep > 0) { currentStep--; renderStep(); }
    };
    window._onboardSkip = function() { closeOnboarding(); };

    function closeOnboarding() {
        localStorage.setItem('onboarding_done', '1');
        var el = document.getElementById('onboardingOverlay');
        if (el) el.remove();
    }

    renderStep();
}

// ========================================
// SHARE TASK
// ========================================

function shareTask(taskId) {
    var task = tasks.find(function(t) { return t.id == taskId; });
    if (!task) return;

    var text = task.title + ' - ₹' + getTaskFinalValue(task) + ' on Workmate4u';
    var url = 'https://www.workmate4u.com/browse.html';

    if (navigator.share) {
        navigator.share({ title: task.title, text: text, url: url }).catch(function() {});
    } else {
        // Fallback: show share options
        var wa = 'https://wa.me/?text=' + encodeURIComponent(text + ' ' + url);
        var tw = 'https://twitter.com/intent/tweet?text=' + encodeURIComponent(text) + '&url=' + encodeURIComponent(url);
        var fb = 'https://www.facebook.com/sharer/sharer.php?u=' + encodeURIComponent(url);
        var shareHTML = '<div style="text-align:center;padding:20px;">' +
            '<h3 style="margin-bottom:16px;">Share this Task</h3>' +
            '<p style="color:#64748b;margin-bottom:20px;">' + task.title + '</p>' +
            '<div style="display:flex;gap:12px;justify-content:center;flex-wrap:wrap;">' +
            '<a href="' + wa + '" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:8px;padding:12px 20px;background:#25d366;color:#fff;border-radius:10px;text-decoration:none;font-weight:600;"><i class="fab fa-whatsapp"></i> WhatsApp</a>' +
            '<a href="' + tw + '" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:8px;padding:12px 20px;background:#1da1f2;color:#fff;border-radius:10px;text-decoration:none;font-weight:600;"><i class="fab fa-twitter"></i> Twitter</a>' +
            '<a href="' + fb + '" target="_blank" rel="noopener" style="display:inline-flex;align-items:center;gap:8px;padding:12px 20px;background:#1877f2;color:#fff;border-radius:10px;text-decoration:none;font-weight:600;"><i class="fab fa-facebook"></i> Facebook</a>' +
            '</div>' +
            '<button class="btn btn-outline" onclick="closeModal(\'shareModal\')" style="margin-top:20px;padding:10px 24px;">Close</button>' +
            '</div>';

        var modal = document.getElementById('shareModal');
        if (!modal) {
            modal = document.createElement('div');
            modal.className = 'modal';
            modal.id = 'shareModal';
            modal.innerHTML = '<div class="modal-content" style="max-width:420px;"></div>';
            document.body.appendChild(modal);
        }
        modal.querySelector('.modal-content').innerHTML = shareHTML;
        openModal('shareModal');
    }
}

// ========================================
// GLOBAL EXPORTS
// ========================================

window.openModal = openModal;
window.closeModal = closeModal;
window.switchModal = switchModal;
window.handleLogin = handleLogin;
window.handleSignup = handleSignup;
window.verifyEmailOTP = verifyEmailOTP;
window.resendVerificationOTP = resendVerificationOTP;
window.otpInputHandler = otpInputHandler;
window.otpKeyHandler = otpKeyHandler;
window.otpPasteHandler = otpPasteHandler;
window.handleTaskSubmit = handleTaskSubmit;
window.openTaskDetail = openTaskDetail;
window.shareTask = shareTask;
window.getServiceCharge = getServiceCharge;
window.getServiceChargeInfo = getServiceChargeInfo;
window.getTaskPostingFee = getTaskPostingFee;
window.getTaskServiceCharge = getTaskServiceCharge;
window.getTaskPlatformFee = getTaskPlatformFee;
window.getTaskFinalValue = getTaskFinalValue;
window.navigateToTask = navigateToTask;
window.acceptTask = acceptTask;
window.abandonTask = abandonTask;
window.penaltyContinueTask = penaltyContinueTask;
window.penaltyConfirmRelease = penaltyConfirmRelease;
window.deleteTask = deleteTask;
window.completeTask = completeTask;
window.openEditTask = openEditTask;
window.saveTaskEdit = saveTaskEdit;
window.selectBudgetIncrease = selectBudgetIncrease;
window.updateNewBudget = updateNewBudget;

// Nudge customBudget by a small ± amount (replaces big bonus chips).
function nudgeBudget(delta) {
    const input = document.getElementById('customBudget');
    if (!input) return;
    const cur = parseInt(input.value, 10) || 0;
    const next = Math.max(0, cur + delta);
    input.value = next;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    if (typeof window.updateTotalBudgetDisplay === 'function') {
        try { window.updateTotalBudgetDisplay(); } catch (e) {}
    }
    // Briefly highlight the input so the change is visible.
    try {
        input.style.transition = 'background-color .25s ease';
        input.style.backgroundColor = '#ecfdf5';
        setTimeout(() => { input.style.backgroundColor = ''; }, 350);
    } catch (e) {}
}
window.nudgeBudget = nudgeBudget;

// ========================================
// GOOGLE SIGN-IN
// ========================================

// Initialize Google Sign-In buttons when GIS library loads
async function initGoogleSignIn() {
    console.log('🔄 initGoogleSignIn called');
    
    if (typeof google === 'undefined' || !google.accounts) {
        console.log('⏳ Google GIS library not loaded yet');
        return;
    }
    
    if (!window.GOOGLE_CLIENT_ID) {
        try {
            // Use apiRequest so the Netlify proxy fallback kicks in if the
            // direct Railway URL fails to resolve (Indian ISP blocks etc).
            let configResp = null;
            if (typeof apiRequest === 'function') {
                const r = await apiRequest('/config/google-client-id');
                configResp = r && r.data ? r.data : null;
            } else {
                const API_BASE = window.API_BASE_URL || '/.netlify/functions/api-proxy/api';
                const resp = await fetch(API_BASE + '/config/google-client-id');
                configResp = await resp.json();
            }
            console.log('📦 Google client ID response:', configResp);
            if (configResp && configResp.success && configResp.clientId) {
                window.GOOGLE_CLIENT_ID = configResp.clientId;
            } else {
                console.warn('❌ Google client ID not available');
                return;
            }
        } catch (e) {
            console.error('❌ Failed to fetch Google client ID:', e);
            return;
        }
    }
    
    console.log('✅ Google Client ID loaded, initializing...');
    
    // Guard: only initialize once — calling it twice causes a console warning.
    // But still re-render buttons each call (modals may open after first init).
    if (!window._googleSignInInitialized) {
        window._googleSignInInitialized = true;
        google.accounts.id.initialize({
            client_id: window.GOOGLE_CLIENT_ID,
            callback: handleGoogleCredentialResponse,
            auto_select: false,
            cancel_on_tap_outside: true,
            // FedCM required on Chrome 121+ desktop (third-party cookies blocked)
            use_fedcm_for_prompt: true,
            ux_mode: 'popup'
        });
    }
    
    // Ensure each login/signup modal has a Google button container.
    // Many pages (browse, posted, accepted, completed, profile) ship the
    // modal HTML without the placeholder div, so create one on the fly.
    function ensureGoogleBtnContainer(modalId, btnId) {
        const modal = document.getElementById(modalId);
        if (!modal) return null;
        let container = document.getElementById(btnId);
        if (container) return container;
        const content = modal.querySelector('.modal-content') || modal;
        // Try to insert just before modal-footer if present, else append
        container = document.createElement('div');
        container.id = btnId;
        container.style.cssText = 'display:flex;justify-content:center;min-height:44px;margin:14px 0;';
        // Add divider if no .social-divider already in the modal
        if (!content.querySelector('.social-divider')) {
            const divider = document.createElement('div');
            divider.className = 'social-divider';
            divider.style.cssText = 'display:flex;align-items:center;gap:12px;margin:18px 0 14px;';
            divider.innerHTML = '<hr style="flex:1;border:none;border-top:1px solid #e2e8f0;"><span style="color:#94a3b8;font-size:13px;white-space:nowrap;">or continue with</span><hr style="flex:1;border:none;border-top:1px solid #e2e8f0;">';
            const footer = content.querySelector('.modal-footer');
            if (footer) { content.insertBefore(divider, footer); content.insertBefore(container, footer); }
            else { content.appendChild(divider); content.appendChild(container); }
        } else {
            const footer = content.querySelector('.modal-footer');
            if (footer) content.insertBefore(container, footer);
            else content.appendChild(container);
        }
        return container;
    }
    const loginBtn = ensureGoogleBtnContainer('loginModal', 'googleSignInBtn_login');
    if (loginBtn && !window._googleLoginBtnRendered) {
        window._googleLoginBtnRendered = true;
        loginBtn.innerHTML = '';
        google.accounts.id.renderButton(loginBtn, {
            type: 'standard',
            size: 'large',
            text: 'signin_with',
            theme: 'outline',
            width: 300
        });
        console.log('✅ Google button rendered in login modal');
    }
    const signupBtn = ensureGoogleBtnContainer('signupModal', 'googleSignInBtn_signup');
    if (signupBtn && !window._googleSignupBtnRendered) {
        window._googleSignupBtnRendered = true;
        signupBtn.innerHTML = '';
        google.accounts.id.renderButton(signupBtn, {
            type: 'standard',
            size: 'large',
            text: 'signup_with',
            theme: 'outline',
            width: 300
        });
        console.log('✅ Google button rendered in signup modal');
    }
    
    window._googleSignInReady = true;
}

// Called when GIS script loads
window.onGoogleLibraryLoad = function() {
    console.log('📦 Google GIS library loaded');
    initGoogleSignIn();
};

// Also try to init when modals open (in case GIS loaded before DOM)
function handleGoogleLogin() {
    if (!window._googleSignInReady) {
        initGoogleSignIn();
    }
}

async function handleGoogleCredentialResponse(response) {
    if (!response.credential) {
        showToast('❌ Google login cancelled', 'error');
        return;
    }

    // If the Google button is in the signup modal, grab the invite code
    const signupModal = document.getElementById('signupModal');
    const inviteField = document.getElementById('signupInviteCode');
    const isSignupContext = signupModal && signupModal.classList.contains('active');
    let inviteCode = '';

    if (isSignupContext && inviteField) {
        inviteCode = inviteField.value.trim().toUpperCase();
        if (!inviteCode) {
            // Scroll to and highlight the invite code field
            inviteField.focus();
            inviteField.style.borderColor = '#ef4444';
            inviteField.style.boxShadow = '0 0 0 3px rgba(239,68,68,0.2)';
            setTimeout(() => {
                inviteField.style.borderColor = '';
                inviteField.style.boxShadow = '';
            }, 3000);
            showToast('❌ Please enter your invite code first', 'error');
            return;
        }
    }

    try {
        // Send the ID token (and invite code if present) to our backend
        const result = await apiRequest('/auth/google', {
            method: 'POST',
            body: JSON.stringify({
                credential: response.credential,
                invite_code: inviteCode
            })
        });

        if (result.success && result.data && result.data.success) {
            // Store token - data is nested inside result.data
            if (result.data.token) {
                localStorage.setItem('taskearn_token', result.data.token);
            }
            currentUser = result.data.user;
            saveCurrentSession(currentUser);
            showToast('✅ Welcome, ' + (currentUser.name || currentUser.email));
            closeModal('loginModal');
            closeModal('signupModal');
            updateNavForUser();
            const tasksLoaded = await loadTasksFromServer();
            setTimeout(() => renderDashboard(), 100);
            // Check if profile is incomplete (Google users often lack phone/DOB)
            if (!currentUser.phone || !currentUser.dob) {
                setTimeout(() => showCompleteProfileModal(), 800);
            }
        } else {
            const msg = (result.data && result.data.message) || 'Google login failed';
            showToast('❌ ' + msg, 'error');
        }
    } catch (err) {
        console.error('Google login error:', err);
        showToast('❌ Google login failed', 'error');
    }
}

// ── Complete Profile Modal (for Google sign-in users missing phone/DOB) ──
function showCompleteProfileModal() {
    // Remove existing modal if any
    const old = document.getElementById('completeProfileModal');
    if (old) old.remove();

    const needPhone = !currentUser.phone;
    const needDob = !currentUser.dob;
    if (!needPhone && !needDob) return;

    const modal = document.createElement('div');
    modal.className = 'modal active';
    modal.id = 'completeProfileModal';
    modal.innerHTML = `
        <div class="modal-content" style="max-width:420px;">
            <div style="text-align:center;padding:8px 0 16px;">
                <div style="width:56px;height:56px;border-radius:50%;background:linear-gradient(135deg,#6366f1,#a855f7);display:flex;align-items:center;justify-content:center;margin:0 auto 12px;">
                    <i class="fas fa-user-edit" style="font-size:24px;color:#fff;"></i>
                </div>
                <h2 style="margin-bottom:6px;">Complete Your Profile</h2>
                <p style="color:#64748b;font-size:14px;">Please add these details to use all features</p>
            </div>
            <form onsubmit="submitCompleteProfile(event)">
                ${needPhone ? `
                <div class="form-group">
                    <label for="cpPhone">Phone Number <span style="color:#ef4444;">*</span></label>
                    <input type="tel" id="cpPhone" placeholder="+91 98765 43210" required
                        style="width:100%;padding:10px 12px;border:1px solid #e2e8f0;border-radius:8px;font-size:14px;">
                    <small style="color:#64748b;">Required to contact task posters/helpers</small>
                </div>` : ''}
                ${needDob ? `
                <div class="form-group">
                    <label for="cpDob">Date of Birth <span style="color:#ef4444;">*</span></label>
                    <input type="date" id="cpDob" required
                        style="width:100%;padding:10px 12px;border:1px solid #e2e8f0;border-radius:8px;font-size:14px;">
                    <small style="color:#64748b;">You must be 16 or older to use Workmate4u</small>
                </div>` : ''}
                <button type="submit" class="btn btn-primary btn-block" style="margin-top:10px;">
                    <i class="fas fa-check"></i> Save & Continue
                </button>
            </form>
        </div>`;
    modal.setAttribute('data-required', '1');
    document.body.appendChild(modal);
    // Prevent backdrop click from dismissing
    modal.onclick = function(e) { if (e.target === modal) e.stopImmediatePropagation(); };
}

async function submitCompleteProfile(e) {
    e.preventDefault();
    const phoneEl = document.getElementById('cpPhone');
    const dobEl = document.getElementById('cpDob');
    const updates = {};

    if (phoneEl) {
        const phone = phoneEl.value.trim();
        if (!phone) { showToast('❌ Please enter your phone number', 'error'); return; }
        updates.phone = phone;
    }
    if (dobEl) {
        const dob = dobEl.value;
        if (!dob) { showToast('❌ Please enter your date of birth', 'error'); return; }
        const age = Math.floor((Date.now() - new Date(dob).getTime()) / (365.25 * 24 * 3600000));
        if (age < 16) { showToast('❌ You must be 16 or older to use Workmate4u', 'error'); return; }
        updates.dob = dob;
    }

    try {
        const result = await apiRequest('/user/profile', {
            method: 'PUT',
            body: JSON.stringify(updates)
        });
        if (result.success && result.data && result.data.success) {
            currentUser = result.data.user;
            saveCurrentSession(currentUser);
            closeModal('completeProfileModal');
            showToast('✅ Profile updated successfully!');
        } else {
            showToast('❌ ' + ((result.data && result.data.message) || 'Update failed'), 'error');
        }
    } catch (err) {
        showToast('❌ Failed to update profile', 'error');
    }
}

// ========================================
// KYC VERIFICATION
// ========================================

function onKycDocTypeChange() {
    const docType = document.getElementById('kycDocType').value;
    const frontSection = document.getElementById('kycFrontUploadSection');
    const backSection = document.getElementById('kycBackUploadSection');
    const hint = document.getElementById('kycDocHint');

    if (!docType) {
        if (frontSection) frontSection.style.display = 'none';
        if (backSection) backSection.style.display = 'none';
        return;
    }

    if (hint) hint.textContent = docType === 'pan' ? 'PAN: e.g. ABCDE1234F' : 'Aadhaar: 12 digits';

    if (frontSection) frontSection.style.display = '';

    if (docType === 'aadhaar') {
        if (backSection) backSection.style.display = '';
    } else {
        // PAN: back side not needed — clear and hide it
        clearKYCImage('back');
        if (backSection) backSection.style.display = 'none';
    }
}

async function submitKYC() {
    const docType = document.getElementById('kycDocType').value;
    const docNum = document.getElementById('kycDocNumber').value.trim();

    if (!docType) { showToast('❌ Please select a document type', 'error'); return; }
    if (!docNum) { showToast('❌ Please enter document number', 'error'); return; }

    if (!window._kycFrontBase64) {
        showToast('❌ Please upload the front side photo', 'error');
        return;
    }
    if (docType === 'aadhaar' && !window._kycBackBase64) {
        showToast('❌ Please upload the back side photo of Aadhaar', 'error');
        return;
    }

    const ackEl = document.getElementById('kycAcknowledge');
    if (!ackEl || !ackEl.checked) {
        showToast('❌ Please tick the legal declaration to confirm the documents are genuine', 'error');
        return;
    }

    const btn = document.getElementById('kycSubmitBtn');
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Verifying...';

    try {
        const result = await KYCAPI.submit(docType, docNum, window._kycFrontBase64, window._kycBackBase64 || null, true);
        console.log('[KYC] Server response:', result);
        if (result && result.success) {
            showToast('✅ ' + (result.message || 'KYC submitted successfully!'));
            window._kycFrontBase64 = null;
            window._kycBackBase64 = null;
            loadKYCStatus();
        } else {
            let msg = (result && result.message) || 'KYC submission failed';
            // "Invalid JSON response" means the server returned a non-JSON error (e.g. 413 payload too large)
            if (!msg || msg === 'Invalid JSON response' || msg.toLowerCase().includes('invalid json')) {
                msg = 'Upload failed — the images may be too large. Please try photos taken at lower resolution.';
            }
            console.error('[KYC] Rejected by server:', msg, result);
            showToast('❌ ' + msg, 'error');
            try { alert('KYC submission failed:\n\n' + msg); } catch(_) {}
        }
    } catch (err) {
        console.error('[KYC] Submit failed:', err);
        showToast('❌ KYC submission failed: ' + (err && err.message ? err.message : 'network error'), 'error');
    } finally {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-paper-plane"></i> Submit & Verify';
    }
}

function compressKYCImage(file) {
    return new Promise(function(resolve, reject) {
        const reader = new FileReader();
        reader.onload = function(e) {
            const img = new Image();
            img.onload = function() {
                const MAX_W = 1200, MAX_H = 1000;
                let w = img.width, h = img.height;
                if (w > MAX_W || h > MAX_H) {
                    const scale = Math.min(MAX_W / w, MAX_H / h);
                    w = Math.round(w * scale);
                    h = Math.round(h * scale);
                }
                const canvas = document.createElement('canvas');
                canvas.width = w;
                canvas.height = h;
                canvas.getContext('2d').drawImage(img, 0, 0, w, h);
                resolve(canvas.toDataURL('image/jpeg', 0.82));
            };
            img.onerror = reject;
            img.src = e.target.result;
        };
        reader.onerror = reject;
        reader.readAsDataURL(file);
    });
}

async function previewKYCImage(input, side) {
    const file = input.files[0];
    if (!file) return;

    if (file.size > 15 * 1024 * 1024) {
        showToast('❌ Image too large. Max 15MB', 'error');
        input.value = '';
        return;
    }

    try {
        const data = await compressKYCImage(file);
        if (side === 'back') {
            window._kycBackBase64 = data;
            const preview = document.getElementById('kycBackPreview');
            const previewImg = document.getElementById('kycBackPreviewImg');
            const uploadArea = document.getElementById('kycBackUploadArea');
            if (previewImg) previewImg.src = data;
            if (preview) preview.style.display = '';
            if (uploadArea) uploadArea.style.display = 'none';
        } else {
            window._kycFrontBase64 = data;
            const preview = document.getElementById('kycFrontPreview');
            const previewImg = document.getElementById('kycFrontPreviewImg');
            const uploadArea = document.getElementById('kycFrontUploadArea');
            if (previewImg) previewImg.src = data;
            if (preview) preview.style.display = '';
            if (uploadArea) uploadArea.style.display = 'none';
        }
    } catch (err) {
        showToast('❌ Could not process image. Please try a different file.', 'error');
        input.value = '';
    }
}

function clearKYCImage(side) {
    if (side === 'back') {
        window._kycBackBase64 = null;
        const input = document.getElementById('kycDocBack');
        if (input) input.value = '';
        const preview = document.getElementById('kycBackPreview');
        const uploadArea = document.getElementById('kycBackUploadArea');
        if (preview) preview.style.display = 'none';
        if (uploadArea) uploadArea.style.display = '';
    } else {
        window._kycFrontBase64 = null;
        const input = document.getElementById('kycDocFront');
        if (input) input.value = '';
        const preview = document.getElementById('kycFrontPreview');
        const uploadArea = document.getElementById('kycFrontUploadArea');
        if (preview) preview.style.display = 'none';
        if (uploadArea) uploadArea.style.display = '';
    }
}

async function loadKYCStatus() {
    try {
        const result = await KYCAPI.getStatus();
        if (!result.success) return;
        
        const kyc = result.kyc || {};
        const status = kyc.status;
        const badge = document.getElementById('kycBadge');
        const formSection = document.getElementById('kycFormSection');
        const statusSection = document.getElementById('kycStatusSection');
        
        if (!badge) return;
        
        if (status === 'none' || !status) {
            badge.textContent = 'Not Verified';
            badge.style.background = '#fef3c7'; badge.style.color = '#d97706';
            if (formSection) formSection.style.display = '';
            if (statusSection) statusSection.style.display = 'none';
        } else {
            if (formSection) formSection.style.display = 'none';
            if (statusSection) statusSection.style.display = '';
            
            const docTypeEl = document.getElementById('kycDocTypeDisplay');
            const docNumEl = document.getElementById('kycDocNumberDisplay');
            const statusEl = document.getElementById('kycStatusDisplay');
            if (docTypeEl) docTypeEl.textContent = (kyc.documentType || '').toUpperCase();
            if (docNumEl) {
                const num = kyc.documentNumber || '';
                docNumEl.textContent = num.length > 4 ? '****' + num.slice(-4) : num;
            }
            
            if (status === 'pending') {
                badge.textContent = 'Pending';
                badge.style.background = '#fef3c7'; badge.style.color = '#d97706';
                if (statusEl) statusEl.innerHTML = '<span style="color:#d97706;"><i class="fas fa-clock"></i> Under Review</span>';
            } else if (status === 'verified' || status === 'approved') {
                badge.textContent = 'Verified ✓';
                badge.style.background = '#d1fae5'; badge.style.color = '#059669';
                if (statusEl) statusEl.innerHTML = '<span style="color:#059669;"><i class="fas fa-check-circle"></i> Verified</span>';
                const verRow = document.getElementById('kycVerifiedAtRow');
                const verAt = document.getElementById('kycVerifiedAt');
                if (verRow && kyc.verifiedAt) {
                    verRow.style.display = '';
                    verAt.textContent = new Date(kyc.verifiedAt).toLocaleDateString('en-IN');
                }
            } else if (status === 'rejected') {
                badge.textContent = 'Rejected';
                badge.style.background = '#fee2e2'; badge.style.color = '#dc2626';
                const reason = kyc.flagReason ? escapeHtml(kyc.flagReason) : '';
                if (statusEl) statusEl.innerHTML = '<span style="color:#dc2626;"><i class="fas fa-times-circle"></i> Rejected' + (reason ? ' — ' + reason : '') + '</span>';
                if (formSection) formSection.style.display = '';
            }
        }
    } catch (err) {
        console.error('KYC status error:', err);
    }
}

// ========================================
// REPORT & BLOCK USER
// ========================================

let reportTargetUserId = null;

function openReportModal(userId, userName) {
    reportTargetUserId = userId;
    const nameEl = document.getElementById('reportUserName');
    if (nameEl) nameEl.textContent = 'Reporting: ' + userName;
    document.getElementById('reportReason').value = '';
    document.getElementById('reportDetails').value = '';
    openModal('reportUserModal');
}

async function submitReport() {
    if (!reportTargetUserId) return;
    const reason = document.getElementById('reportReason').value;
    const details = document.getElementById('reportDetails').value.trim();
    
    if (!reason) { showToast('❌ Please select a reason', 'error'); return; }
    
    try {
        const result = await ReportAPI.reportUser(reportTargetUserId, reason, details);
        if (result.success) {
            showToast('✅ Report submitted. Our team will review it.');
            closeModal('reportUserModal');
        } else {
            showToast('❌ ' + (result.message || 'Report failed'), 'error');
        }
    } catch (err) {
        showToast('❌ Failed to submit report', 'error');
    }
}

async function blockUser(userId) {
    if (!confirm('Block this user? They won\'t be able to see your tasks or message you.')) return;
    try {
        const result = await ReportAPI.blockUser(userId);
        if (result.success) {
            showToast('✅ User blocked');
        } else {
            showToast('❌ ' + (result.message || 'Block failed'), 'error');
        }
    } catch (err) {
        showToast('❌ Failed to block user', 'error');
    }
}

async function unblockUser(userId) {
    try {
        const result = await ReportAPI.unblockUser(userId);
        if (result.success) {
            showToast('✅ User unblocked');
        } else {
            showToast('❌ ' + (result.message || 'Unblock failed'), 'error');
        }
    } catch (err) {
        showToast('❌ Failed to unblock user', 'error');
    }
}

// ========================================
// PROFILE PAGE INIT HOOKS
// ========================================

// Hook into existing profile load to initialize new features
(function() {
    const origRenderDashboard = window.renderDashboard;
    if (typeof origRenderDashboard === 'function') {
        window.renderDashboard = function() {
            origRenderDashboard.apply(this, arguments);
            // Initialize KYC on profile page
            if (document.getElementById('kycCard')) {
                loadKYCStatus();
            }
        };
    }
})();

// ========================================
// PUSH NOTIFICATIONS
// ========================================

/**
 * Subscribe the current user to web push notifications.
 * Called once after login (or when user explicitly enables them).
 * Silently exits if the browser doesn't support push or permission is denied.
 */
async function initPushNotifications() {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) return;
    // Don't re-subscribe if we've already done it this session
    if (sessionStorage.getItem('push_subscribed')) return;

    const permission = Notification.permission;
    if (permission === 'denied') return;

    // Ask permission only if not yet granted
    if (permission !== 'granted') {
        const result = await Notification.requestPermission();
        if (result !== 'granted') return;
    }

    await enablePushAndSubscribe();
}

async function enablePushAndSubscribe() {
    try {
        // Fetch VAPID public key from our server
        const { success, publicKey } = await PushAPI.getVapidKey();
        if (!success || !publicKey) return;

        const reg = await navigator.serviceWorker.ready;

        // Check for existing subscription first
        let sub = await reg.pushManager.getSubscription();
        if (!sub) {
            // Convert base64url public key to Uint8Array
            const appServerKey = urlBase64ToUint8Array(publicKey);
            sub = await reg.pushManager.subscribe({
                userVisibleOnly: true,
                applicationServerKey: appServerKey
            });
        }

        // Send subscription to our backend (with optional location)
        let lat = null, lng = null;
        try {
            const pos = await new Promise((res, rej) =>
                navigator.geolocation.getCurrentPosition(res, rej, { timeout: 3000 })
            );
            lat = pos.coords.latitude;
            lng = pos.coords.longitude;
        } catch (_) {}

        await PushAPI.subscribe(sub.toJSON(), lat, lng);
        sessionStorage.setItem('push_subscribed', '1');
        console.log('[push] Subscribed to push notifications');
    } catch (e) {
        console.warn('[push] Subscribe failed:', e);
    }
}

async function disablePushNotifications() {
    try {
        const reg = await navigator.serviceWorker.ready;
        const sub = await reg.pushManager.getSubscription();
        if (sub) await sub.unsubscribe();
        await PushAPI.unsubscribe();
        sessionStorage.removeItem('push_subscribed');
        console.log('[push] Unsubscribed from push notifications');
    } catch (e) {
        console.warn('[push] Unsubscribe failed:', e);
    }
}

/** Convert a base64url string to a Uint8Array (required by PushManager.subscribe) */
function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    return Uint8Array.from([...raw].map(c => c.charCodeAt(0)));
}

// Legacy no-op stubs (kept for any older cached pages that call them)
function requestPushPermission() { initPushNotifications(); }
function showPushBannerIfNeeded() {
    const banner = document.getElementById('pushBanner');
    if (banner) banner.style.display = 'none';
}

// Window exports for new features
window.handleGoogleLogin = handleGoogleLogin;
window.handleGoogleCredentialResponse = handleGoogleCredentialResponse;
window.submitKYC = submitKYC;
window.loadKYCStatus = loadKYCStatus;
window.previewKYCImage = previewKYCImage;
window.clearKYCImage = clearKYCImage;
window.openReportModal = openReportModal;
window.submitReport = submitReport;
window.blockUser = blockUser;
window.unblockUser = unblockUser;
window.requestPushPermission = requestPushPermission;
window.initPushNotifications = initPushNotifications;

// ========================================
// Phone OTP verification (lazy-injected modal)
// ========================================
function _phoneVerifyEnsureModal() {
    if (document.getElementById('phoneVerifyModal')) return;
    var html = ''
        + '<div class="modal" id="phoneVerifyModal" role="dialog" aria-modal="true" aria-label="Verify Phone">'
        + '  <div class="modal-content" style="max-width:420px;">'
        + '    <div class="modal-header">'
        + '      <h2><i class="fas fa-mobile-alt"></i> Verify Mobile Number</h2>'
        + '      <button class="modal-close" onclick="closePhoneVerifyModal()" aria-label="Close"><i class="fas fa-times"></i></button>'
        + '    </div>'
        + '    <div class="modal-body" id="phoneVerifyBody" style="padding:18px;">'
        + '      <p style="margin:0 0 12px;color:#64748b;font-size:14px;">Enter your 10-digit Indian mobile number. We\'ll send a one-time code by SMS.</p>'
        + '      <div class="form-group" id="phoneVerifyStep1">'
        + '        <label for="phoneVerifyInput">Mobile Number</label>'
        + '        <input type="tel" id="phoneVerifyInput" placeholder="+91 98765 43210" inputmode="numeric" autocomplete="tel" style="width:100%;padding:10px;border:1px solid #e2e8f0;border-radius:8px;font-size:15px;">'
        + '        <button class="btn btn-primary btn-block" id="phoneVerifySendBtn" onclick="sendPhoneOTP()" style="margin-top:14px;">Send OTP</button>'
        + '      </div>'
        + '      <div class="form-group" id="phoneVerifyStep2" style="display:none;">'
        + '        <p id="phoneVerifyMaskMsg" style="margin:0 0 10px;font-size:13px;color:#16a34a;"></p>'
        + '        <label for="phoneVerifyOtp">6-digit OTP</label>'
        + '        <input type="tel" id="phoneVerifyOtp" placeholder="● ● ● ● ● ●" maxlength="6" inputmode="numeric" autocomplete="one-time-code" style="width:100%;padding:10px;border:1px solid #e2e8f0;border-radius:8px;font-size:18px;letter-spacing:4px;text-align:center;">'
        + '        <button class="btn btn-primary btn-block" id="phoneVerifyConfirmBtn" onclick="confirmPhoneOTP()" style="margin-top:14px;">Verify</button>'
        + '        <button class="btn btn-block" onclick="resetPhoneOTP()" style="margin-top:8px;background:transparent;color:#2563eb;border:none;cursor:pointer;font-size:13px;">Use a different number</button>'
        + '      </div>'
        + '      <div id="phoneVerifyError" style="display:none;background:#fee2e2;color:#b91c1c;padding:8px 10px;border-radius:6px;font-size:13px;margin-top:10px;"></div>'
        + '    </div>'
        + '  </div>'
        + '</div>';
    var div = document.createElement('div');
    div.innerHTML = html;
    document.body.appendChild(div.firstChild);
}

function openPhoneVerifyModal(opts) {
    opts = opts || {};
    _phoneVerifyEnsureModal();
    resetPhoneOTP();
    // Pre-fill from currentUser or explicit phone
    var input = document.getElementById('phoneVerifyInput');
    var phone = opts.phone || (typeof currentUser !== 'undefined' && currentUser && currentUser.phone) || '';
    if (input && phone) input.value = phone;
    // If forced (post-signup) hide the close button so the user can't skip easily
    var closeBtn = document.querySelector('#phoneVerifyModal .modal-close');
    if (closeBtn) closeBtn.style.display = opts.required ? 'none' : '';
    var modal = document.getElementById('phoneVerifyModal');
    if (modal) modal.classList.add('active');
    // Auto-send OTP if requested and we have a phone
    if (opts.autoSend && phone) {
        setTimeout(function () { sendPhoneOTP(); }, 200);
    }
}

function closePhoneVerifyModal() {
    var modal = document.getElementById('phoneVerifyModal');
    if (modal) modal.classList.remove('active');
}

function resetPhoneOTP() {
    var s1 = document.getElementById('phoneVerifyStep1');
    var s2 = document.getElementById('phoneVerifyStep2');
    if (s1) s1.style.display = '';
    if (s2) s2.style.display = 'none';
    var err = document.getElementById('phoneVerifyError');
    if (err) err.style.display = 'none';
    var otp = document.getElementById('phoneVerifyOtp');
    if (otp) otp.value = '';
}

function _phoneVerifyShowError(msg) {
    var err = document.getElementById('phoneVerifyError');
    if (err) { err.textContent = msg; err.style.display = 'block'; }
}

async function sendPhoneOTP() {
    var phone = (document.getElementById('phoneVerifyInput').value || '').trim();
    if (!phone) { _phoneVerifyShowError('Enter your mobile number'); return; }
    var digits = phone.replace(/\D/g, '');
    if (digits.length < 10) { _phoneVerifyShowError('Enter a valid 10-digit number'); return; }

    var btn = document.getElementById('phoneVerifySendBtn');
    btn.disabled = true; btn.textContent = 'Sending…';
    try {
        var res = await AuthAPI.sendPhoneOTP(phone);
        if (res && res.success) {
            document.getElementById('phoneVerifyStep1').style.display = 'none';
            document.getElementById('phoneVerifyStep2').style.display = '';
            document.getElementById('phoneVerifyMaskMsg').textContent =
                'OTP sent to ' + (res.maskedPhone || phone) + '. Check your messages.';
            var otpEl = document.getElementById('phoneVerifyOtp');
            if (otpEl) otpEl.focus();
        } else {
            _phoneVerifyShowError((res && res.message) || 'Could not send OTP');
        }
    } catch (e) {
        _phoneVerifyShowError((e && e.message) || 'Network error. Try again.');
    } finally {
        btn.disabled = false; btn.textContent = 'Send OTP';
    }
}

async function confirmPhoneOTP() {
    var otp = (document.getElementById('phoneVerifyOtp').value || '').trim();
    if (!/^\d{6}$/.test(otp)) { _phoneVerifyShowError('Enter the 6-digit OTP'); return; }
    var btn = document.getElementById('phoneVerifyConfirmBtn');
    btn.disabled = true; btn.textContent = 'Verifying…';
    try {
        var res = await AuthAPI.verifyPhoneOTP(otp);
        if (res && res.success) {
            // Persist updated user
            if (res.user) {
                try {
                    currentUser = res.user;
                    localStorage.setItem('taskearn_user', JSON.stringify(res.user));
                } catch (_) {}
            }
            closePhoneVerifyModal();
            if (typeof showToast === 'function') showToast('✅ Mobile number verified');
            if (typeof renderProfileUI === 'function') renderProfileUI();
            // If this was the post-signup chained flow, show onboarding next.
            if (typeof showOnboarding === 'function' &&
                document.querySelector('#phoneVerifyModal .modal-close[style*="none"]') === null) {
                // (close was hidden during the required flow; once verified, run onboarding)
            }
            if (typeof showOnboarding === 'function') {
                setTimeout(showOnboarding, 300);
            }
        } else {
            _phoneVerifyShowError((res && res.message) || 'Verification failed');
        }
    } catch (e) {
        _phoneVerifyShowError((e && e.message) || 'Network error. Try again.');
    } finally {
        btn.disabled = false; btn.textContent = 'Verify';
    }
}

window.openPhoneVerifyModal = openPhoneVerifyModal;
window.closePhoneVerifyModal = closePhoneVerifyModal;
window.sendPhoneOTP = sendPhoneOTP;
window.confirmPhoneOTP = confirmPhoneOTP;
window.resetPhoneOTP = resetPhoneOTP;
window.loadRecommendedTasks = loadRecommendedTasks;
window.enablePushAndSubscribe = enablePushAndSubscribe;
window.testPushNotification = testPushNotification;
window.showPushBannerIfNeeded = showPushBannerIfNeeded;
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
window.toggleEarningsDetail = toggleEarningsDetail;
window.startEmailVerification = startEmailVerification;
window.confirmEmailVerify = confirmEmailVerify;
window.saveNewPassword = saveNewPassword;
window.toggleNotifications = toggleNotifications;
window.markAsRead = markAsRead;
window.clearAllNotifications = clearAllNotifications;
window.handleNotificationAction = handleNotificationAction;
window.executePayment = executePayment;
window.showPaymentInvoice = showPaymentInvoice;
window.goToTaskInProgress = goToTaskInProgress;

// New feature functions
window.confirmDeleteAccount = confirmDeleteAccount;
window.openDisputeModal = openDisputeModal;
window.submitDispute = submitDispute;
window.toggleBookmark = toggleBookmark;
window.exportTransactionsCSV = exportTransactionsCSV;

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
// FORGOT PASSWORD SYSTEM WITH OTP
// Using SendGrid (backend sends emails)
// ========================================

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

// Step 2: Send OTP (backend sends via SendGrid)
async function sendOTP(method) {
    if (forgotPasswordState.isSending) {
        showToast('⏳ Please wait, sending OTP...');
        return;
    }
    
    forgotPasswordState.method = method;
    forgotPasswordState.isSending = true;
    forgotPasswordState.otpExpiry = Date.now() + 10 * 60 * 1000; // 10 min (matches backend)
    
    if (method === 'email') {
        showToast('✅ OTP sent to your email!', 4000);
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
    // Re-call backend to generate new OTP (sent via SendGrid)
    try {
        const result = await AuthAPI.forgotPassword(forgotPasswordState.email);
        if (result.success) {
            forgotPasswordState.resetToken = result.resetToken;
            forgotPasswordState.otpExpiry = Date.now() + 10 * 60 * 1000;
            
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


// ========================================
// HOMEPAGE ATTRACTION FEATURES
// ========================================

// 1. Hero quote rotation
(function initHeroQuotes() {
    function rotate() {
        const quotes = document.querySelectorAll('.hero-quote');
        if (!quotes.length) return;
        let active = 0;
        quotes.forEach((q, i) => { if (q.classList.contains('active')) active = i; });
        quotes[active].classList.remove('active');
        quotes[(active + 1) % quotes.length].classList.add('active');
    }
    if (document.querySelector('.hero-quote')) {
        setInterval(rotate, 4000);
    } else {
        document.addEventListener('DOMContentLoaded', function() {
            if (document.querySelector('.hero-quote')) setInterval(rotate, 4000);
        });
    }
})();

// 2. Earnings Calculator
function updateCalc() {
    const ratePerTask = parseInt(document.getElementById('calcCategory')?.value || 500);
    // Cap tasks/day at 8 — beyond that is unrealistic for a single person
    const tasksPerDay = Math.min(8, parseInt(document.getElementById('calcTasks')?.value || 3));
    // Direct "days per week" slider (replaces broken hours→days conversion)
    const daysPerWeek = Math.min(7, parseInt(document.getElementById('calcDays')?.value || 5));

    // ~4.33 weeks per month
    const tasksPerMonth = Math.round(tasksPerDay * daysPerWeek * 4.33);
    const gross = tasksPerMonth * ratePerTask;
    // Platform deducts commission from helper: 17% general, 15% delivery categories
    // Using 17% as a conservative default for the earnings calculator
    const platformCut = Math.round(gross * 0.17);
    const net = gross - platformCut;
    const weekly = Math.round(net / 4.33);

    const el   = document.getElementById('calcMonthly');
    const elW  = document.getElementById('calcWeekly');
    const elP  = document.getElementById('calcPlatformCut');
    const elTM = document.getElementById('calcTasksMonth');

    if (el)   el.textContent  = '₹' + net.toLocaleString('en-IN');
    if (elW)  elW.textContent = '₹' + weekly.toLocaleString('en-IN') + '/week';
    if (elP)  elP.textContent = '₹' + platformCut.toLocaleString('en-IN') + ' (12%)';
    if (elTM) elTM.textContent = tasksPerMonth + ' tasks/month';
}
window.updateCalc = updateCalc;
document.addEventListener('DOMContentLoaded', updateCalc);

// WhatsApp share for task cards
function shareTask(taskId) {
    const task = (typeof tasks !== 'undefined') && tasks.find(t => t.id == taskId);
    const title = task ? task.title : 'a task';
    const text = encodeURIComponent(`Check out this task on Workmate4u: "${title}" — earn money helping nearby! https://workmate4u.netlify.app/browse.html`);
    window.open('https://wa.me/?text=' + text, '_blank', 'noopener,noreferrer');
}
window.shareTask = shareTask;

// 3. Urgency indicator: pulse task cards expiring in < 2h
(function addUrgencyPulse() {
    function check() {
        document.querySelectorAll('.task-card[data-task-id]').forEach(card => {
            const id = card.dataset.taskId;
            const task = (typeof tasks !== 'undefined') && tasks.find(t => t.id == id);
            if (!task) return;
            const ms = new Date(task.expiresAt) - Date.now();
            if (ms > 0 && ms < 2 * 3600 * 1000) {
                card.classList.add('tc-urgent');
            } else {
                card.classList.remove('tc-urgent');
            }
        });
    }
    setInterval(check, 60000);
    document.addEventListener('DOMContentLoaded', () => setTimeout(check, 2000));
})();

// 5. Hero stat counter animation (update floor values with real data if available)
function animateCounter(el, target, prefix, suffix) {
    if (!el) return;
    const duration = 1200;
    const start = Date.now();
    const from = 0;
    function step() {
        const p = Math.min((Date.now() - start) / duration, 1);
        const val = Math.round(from + (target - from) * (1 - Math.pow(1 - p, 3)));
        el.textContent = prefix + val.toLocaleString('en-IN') + suffix;
        if (p < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
}

// Observe hero stat section and animate when in view
(function observeHeroStats() {
    const stats = document.getElementById('heroStatUsers');
    if (!stats) return;
    const obs = new IntersectionObserver((entries) => {
        entries.forEach(e => {
            if (e.isIntersecting) {
                animateCounter(document.getElementById('heroStatUsers'), 500, '', '+');
                animateCounter(document.getElementById('heroStatTasks'), 200, '', '+');
                obs.disconnect();
            }
        });
    }, { threshold: 0.5 });
    obs.observe(stats);
})();




