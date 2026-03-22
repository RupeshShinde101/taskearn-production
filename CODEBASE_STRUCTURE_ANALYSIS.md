# TaskEarn Codebase Structure Analysis

## Overview
This document maps the files related to **mark as undone** functionality, task acceptance, notifications, redirects, and task state management in the TaskEarn application.

---

## 1. FRONTEND: HTML & JAVASCRIPT FILES

### 1.1 Main Dashboard & UI
**File:** [index.html](index.html)
- **Purpose:** Main dashboard page for both task posters and helpers
- **Key Features:**
  - Accepted Tasks tab (line 551, 573-574) - displays `myAcceptedTasks`
  - Completed Tasks tab (line 553-554) - displays `myCompletedTasks`
  - Notification system UI (lines 94-107):
    - Notification bell icon with badge
    - Notification dropdown with notification list
    - Clear all notifications button
  - Mobile notification item (line 130-132)
  - Main task display sections

**Key HTML Elements:**
```html
<div class="tab-content" id="acceptedTasks">
    <div class="my-tasks-list" id="myAcceptedTasks">
        <!-- Dynamically populated by app.js -->
    </div>
</div>
```

---

### 1.2 Task In Progress Page
**File:** [task-in-progress.html](task-in-progress.html)
- **Purpose:** Page shown to helpers when they accept a task and begin working
- **Key Features:**
  - "Complete Task" button (line 495)
  - **"Mark Task Undone" button (line 503)** ← Main feature for this analysis
  - Location sharing functionality
  - Timer for task duration
  - Task details display

**Key Button:**
```html
<button class="btn-undo" onclick="markTaskUndone()">
    Mark Task Undone
</button>
```

**Implementation (lines 655-710):**
```javascript
function markTaskUndone() {
    if (!confirm('Are you sure you want to mark this task as undone?')) {
        return;
    }

    const token = localStorage.getItem('taskearn_token') || '';
    
    fetch(API_URL + '/tasks/' + currentTask.id + '/undo-accept', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
        }
    })
    .then(res => res.json())
    .then(data => {
        if (data.success) {
            // Stop location sharing and timer
            stopLiveLocationSharing();
            clearInterval(timerInterval);
            
            // Update localStorage: Remove from acceptedTasks
            let currentUser = JSON.parse(localStorage.getItem('taskearn_user') || '{}');
            currentUser.acceptedTasks = currentUser.acceptedTasks.filter(t => t.id !== currentTask.id);
            localStorage.setItem('taskearn_user', JSON.stringify(currentUser));
            
            // Redirect back to dashboard
            window.location.href = 'index.html';
        }
    });
}
```

---

### 1.3 Poster Live Tracking Page
**File:** [poster-live-tracking.html](poster-live-tracking.html)
- **Purpose:** Shows poster the live location of helper working on their task
- **Key Features:**
  - Live location tracking of helper
  - Contact information display
  - Real-time updates
  - SOS alert functionality

---

## 2. MAIN APPLICATION LOGIC

### 2.1 Main Application File
**File:** [app.js](app.js)
- **Size:** Large file ~6000+ lines
- **Purpose:** Core application logic for dashboard, task management, notifications, and UI

**Key Sections Related to Your Query:**

#### A. NOTIFICATION SYSTEM (Lines 175-250+)
```javascript
function showNotification(message, type = 'info', duration = 5000) {
    // Creates notification element with animation
    // Shows different colors based on type: error, success, info
    // Auto-dismisses after duration
}
```

#### B. NOTIFICATION SYNCHRONIZATION (Lines ~800-870)
```javascript
async function syncNotificationsFromServer() {
    // Fetches notifications from backend API
    // Processes and normalizes data
    // Saves to localStorage: notifications_${currentUser.id}
    // Calls updateNotificationUI() and autoRedirectToAcceptedTaskTracking()
}
```

#### C. AUTO-REDIRECT LOGIC FOR TASK ACCEPTANCE (Lines ~827-860)
```javascript
function autoRedirectToAcceptedTaskTracking(notificationList) {
    // When helper accepts task, automatically redirects to poster-live-tracking.html
    // Prevents redirect loops by checking:
    //   1. Task is still in myPostedTasks with status='accepted'
    //   2. Task is NOT in the active tasks list
    // Uses sessionStorage to prevent redirect loops
}
```

**Key Variables & Arrays:**
- `myAcceptedTasks` - Array of tasks accepted by current user
- `myPostedTasks` - Array of tasks posted by current user
- `tasks` - Array of all available tasks
- `notifications` - Array of user's notifications

**Key Functions:**
- `showNotification()` - Shows toast notification
- `syncNotificationsFromServer()` - Fetches notifications from backend
- `autoRedirectToAcceptedTaskTracking()` - Auto-redirect poster to tracking page
- `handleNotificationAction()` - Handles notification button clicks
- `updateNotificationUI()` - Updates badge count and notification list
- `addNotification()` - Adds new notification locally
- `markAsRead()` - Marks single notification as read
- `clearAllNotifications()` - Clears all notifications

**Related Functions for Task Acceptance (Lines ~2600+):**
```javascript
// Accept task (helper side)
// Calls API to accept task
// Updates myAcceptedTasks array
// Shows success notification

// Complete task (helper side)
async function completeTask(taskId) {
    // Updates task status to 'completed'
    // Deducts money from poster's wallet
    // Creates payment notification
}
```

**Redirect Loop Fix (Lines ~1035-1050):**
The code validates that a task is still accepted before redirecting:
```javascript
// ✅ FIX: Validate that task is still accepted before redirecting
const taskInPosted = myPostedTasks.find(t => t.id === taskId && t.status === 'accepted');
const taskNoLongerAccepted = tasks.find(t => t.id === taskId && t.status === 'active');

if (!taskInPosted || taskNoLongerAccepted) {
    showToast('❌ This task is no longer being tracked. It may have been marked as undone.', 'error');
    return;
}
```

---

### 2.2 API Client Library
**File:** [api-client.js](api-client.js)
- **Purpose:** Abstraction layer for all API calls
- **Key Exports:**
  - `TasksAPI` - Task operations
  - `NotificationsAPI` - Notification operations
  - `AuthAPI` - Authentication
  - `WalletAPI` - Wallet operations

**Task API Methods (Lines ~595-620):**
```javascript
TasksAPI = {
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
    // ... more methods
};
```

**Notifications API Methods (Lines ~800-855):**
```javascript
NotificationsAPI = {
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

    // Clear task notifications
    async clearTaskNotifications(taskId) {
        const result = await apiRequest(`/notifications/clear-task/${taskId}`, {
            method: 'POST'
        });
        return result.data;
    }
};
```

---

## 3. BACKEND: FLASK API

### 3.1 Main Server
**File:** [backend/server.py](backend/server.py)
- **Purpose:** Flask REST API backend
- **Database:** SQLite (development) or PostgreSQL (production)

**Relevant API Endpoints:**

#### A. Accept Task Endpoint (Lines ~818-880)
```python
@app.route('/api/tasks/<int:task_id>/accept', methods=['POST'])
@require_auth
def accept_task(task_id):
    """Accept a task"""
    # Updates task status from 'active' → 'accepted'
    # Sets accepted_by and accepted_at fields
    # Creates notification for task poster
    # Notification action: 'tracking' with URL to poster-live-tracking.html
    # Returns: {'success': True, 'message': '...'}
```

**Key Logic:**
- Checks if task exists and is 'active'
- Prevents user from accepting their own task
- Creates notification for **task poster** (not helper)
- Notification includes action data with direct link to tracking page

#### B. Mark As Undone Endpoint (Lines ~1226-1310)
```python
@app.route('/api/tasks/<int:task_id>/undo-accept', methods=['POST'])
@require_auth
def undo_accept_task(task_id):
    """Mark task as undone - revert from accepted back to active"""
    # Checks task is accepted by current user
    # Reverts task status from 'accepted' → 'active'
    # Sets accepted_by = NULL and accepted_at = NULL
    # Creates notification for task poster that helper withdrew
    # Notification type: 'task_undone' with message "Helper Withdrew"
    # Returns: {'success': True, 'message': 'Task marked as undone...'}
```

**Key Logic:**
- Only helper who accepted the task can undo
- Makes task available again for other helpers
- Notifies poster that helper withdrew
- Clears location tracking when helper withdraws

---

### 3.2 Database Schema
**File:** [backend/database.py](backend/database.py)

**Key Tables:**

#### A. TASKS Table (Lines ~91-121)
```sql
CREATE TABLE tasks (
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
    accepted_by VARCHAR(50) REFERENCES users(id),      ← Helper who accepted
    accepted_at TIMESTAMP,                              ← When task was accepted
    completed_at TIMESTAMP,                             ← When task was completed
    status VARCHAR(20) DEFAULT 'active'                 ← 'active' | 'accepted' | 'completed'
)
```

**Task Status States:**
- `'active'` - Task is available for helpers to accept
- `'accepted'` - Task has been accepted by a helper
- `'completed'` - Task has been completed

#### B. NOTIFICATIONS Table
```sql
CREATE TABLE notifications (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL REFERENCES users(id),
    task_id INTEGER REFERENCES tasks(id),
    notification_type VARCHAR(50) NOT NULL,            ← 'task_accepted', 'task_undone', etc.
    title VARCHAR(255) NOT NULL,
    message TEXT,
    status VARCHAR(20) DEFAULT 'unread',               ← 'unread' | 'read'
    data TEXT,                                          ← JSON with action data
    created_at TIMESTAMP NOT NULL,
    read_at TIMESTAMP
)
```

**Indexes:**
```sql
CREATE INDEX idx_notifications_user_status 
ON notifications(user_id, status)
```

#### C. USERS Table
```sql
CREATE TABLE users (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    rating DECIMAL(3,2) DEFAULT 5.0,
    tasks_posted INTEGER DEFAULT 0,
    tasks_completed INTEGER DEFAULT 0,
    total_earnings DECIMAL(12,2) DEFAULT 0,
    is_suspended BOOLEAN DEFAULT FALSE,
    ... other fields
)
```

---

### 3.3 Notifications API Endpoints

#### A. Get Notifications (Lines ~4496-4523)
```python
@app.route('/api/notifications', methods=['GET'])
@require_auth
def get_notifications():
    """Get notifications for current user"""
    # Returns: {
    #     'success': True,
    #     'notifications': [...],
    #     'count': n
    # }
    # Limits to last 50 notifications
    # Ordered by created_at DESC (newest first)
```

#### B. Mark as Read (Lines ~4526-4547)
```python
@app.route('/api/notifications/<int:notification_id>/read', methods=['POST'])
@require_auth
def mark_notification_read(notification_id):
    """Mark notification as read"""
    # Updates status from 'unread' → 'read'
    # Sets read_at timestamp
```

#### C. Delete Notification (Lines ~4549-4567)
```python
@app.route('/api/notifications/<int:notification_id>', methods=['DELETE'])
@require_auth
def delete_notification(notification_id):
    """Delete notification"""
    # Removes notification from database
```

#### D. Clear Task Notifications (Lines ~4570-4588)
```python
@app.route('/api/notifications/clear-task/<int:task_id>', methods=['POST'])
@require_auth
def clear_task_notifications(task_id):
    """Clear notifications for a completed task"""
    # Removes all notifications for specific task
```

---

## 4. DATA PERSISTENCE & STORAGE

### 4.1 LocalStorage Keys
The frontend uses localStorage for client-side persistence:

```javascript
// User information
localStorage.setItem('taskearn_user', JSON.stringify(currentUser));
  - currentUser.acceptedTasks - Array of accepted tasks
  - currentUser.wallet - Wallet balance

// Authentication
localStorage.getItem('taskearn_token')

// Notifications
localStorage.setItem(`notifications_${currentUser.id}`, JSON.stringify(notifications));

// Session tracking (to prevent redirect loops)
sessionStorage.setItem(`taskearn_tracking_redirect_${currentUser.id}_${taskId}`, '1');
sessionStorage.setItem(`taskearn_accepted_task_${taskId}`, JSON.stringify(task));
```

### 4.2 Task Persistence in Accepted Tasks List
**File:** [ACCEPTED_TASKS_PERSISTENCE_FIX.md](ACCEPTED_TASKS_PERSISTENCE_FIX.md) - Documents the fix

When user navigates away and returns:
1. `myAcceptedTasks` array restored from `currentUser.acceptedTasks` in localStorage
2. If empty, data fetched from backend API
3. Tasks automatically re-rendered in UI

---

## 5. FLOW DIAGRAMS

### 5.1 Task Acceptance Flow

```
Helper accepts task:
┌─────────────────────────────────────────────────────────┐
│ 1. Helper clicks "Accept" on available task             │
│    → Calls TasksAPI.accept(taskId)                      │
│    → POST /api/tasks/{id}/accept                        │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│ 2. Backend (server.py):                                 │
│    → Updates task status: 'active' → 'accepted'         │
│    → Sets accepted_by = helper_id                       │
│    → Sets accepted_at = timestamp                       │
│    → Creates notification for TASK POSTER               │
│    → Notification type: 'task_accepted'                 │
│    → Notification action: {'type': 'tracking', ...}     │
│    → Returns success response                           │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│ 3. Frontend (app.js/index.html):                        │
│    → Updates myAcceptedTasks array                      │
│    → Adds task to acceptedTasks display                 │
│    → Removes task from available tasks                  │
│    → Saves to localStorage                              │
│    → Shows success notification                         │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Mark As Undone Flow

```
Helper marks task as undone:
┌─────────────────────────────────────────────────────────┐
│ 1. Helper on task-in-progress.html                      │
│    Clicks "Mark Task Undone" button                     │
│    → Calls markTaskUndone()                             │
│    → POST /api/tasks/{id}/undo-accept                   │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│ 2. Backend (server.py):                                 │
│    → Verifies task is accepted by current helper       │
│    → Updates task status: 'accepted' → 'active'         │
│    → Sets accepted_by = NULL                            │
│    → Sets accepted_at = NULL                            │
│    → Creates notification for TASK POSTER               │
│    → Notification type: 'task_undone'                   │
│    → Message: "X withdrew from your task"               │
│    → Returns success response                           │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│ 3. Frontend (task-in-progress.html):                    │
│    → Stops location sharing                             │
│    → Clears task timer                                  │
│    → Removes task from localStorage acceptedTasks       │
│    → Redirects to index.html                            │
│    → Updates myAcceptedTasks display                    │
│    → Task re-appears in available tasks                 │
└─────────────────────────────────────────────────────────┘
```

### 5.3 Notification System Flow

```
Poster receives notification when helper accepts their task:
┌─────────────────────────────────────────────────────────┐
│ 1. Helper accepts task                                  │
│    → Backend creates notification in DB                 │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│ 2. Poster navigates to dashboard (index.html)           │
│    → app.js calls syncNotificationsFromServer()         │
│    → GET /api/notifications                             │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│ 3. Backend returns all unread notifications             │
│    Notifications saved to localStorage                  │
│    updateNotificationUI() called                        │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│ 4. Notification displayed in UI:                        │
│    → Badge count updated                                │
│    → Notification appears in dropdown                   │
│    → Shows title, message, time                         │
│    → Has action button ("Track Helper")                 │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│ 5. Auto-redirect triggered:                             │
│    → Helper task still accepted & not in active list    │
│    → Auto-redirects poster to poster-live-tracking.html │
│    → Session storage prevents repeat redirects          │
└─────────────────────────────────────────────────────────┘
```

### 5.4 Redirect Loop Prevention

```
When helper marks task as undone:
┌─────────────────────────────────────────────────────────┐
│ 1. markTaskUndone() called on task-in-progress.html     │
│    → Backend reverts task to 'active' status            │
│    → Task removed from accepted_by                      │
│    → Notification sent to poster: "Helper withdrew"     │
│                                                          │
│ 2. Poster receives notification                          │
│    → syncNotificationsFromServer() processes it         │
│    → autoRedirectToAcceptedTaskTracking() called        │
│                                                          │
│ 3. Validation checks prevent redirect loop:             │
│    ✓ Is task in myPostedTasks with status='accepted'?   │
│    ✓ Is task NOT in active tasks list?                  │
│    ✓ Has already been redirected this session?          │
│                                                          │
│ 4. Since task is now 'active' again:                    │
│    → autoRedirectToAcceptedTaskTracking() SKIPS redirect │
│    → Poster is NOT redirected                           │
│    → Poster stays on current page                       │
│    → Notification shows "Helper withdrew"               │
└─────────────────────────────────────────────────────────┘
```

---

## 6. KEY FILES SUMMARY TABLE

| File | Type | Purpose | Lines | Key Functions/Endpoints |
|------|------|---------|-------|------------------------|
| [index.html](index.html) | HTML | Main dashboard | ~1400+ | Accepted/Completed tabs, Notification UI |
| [task-in-progress.html](task-in-progress.html) | HTML | Task progress page | ~700 | Mark Task Undone button, markTaskUndone() |
| [poster-live-tracking.html](poster-live-tracking.html) | HTML | Live tracking page | ~600 | Live location display, helper info |
| [app.js](app.js) | JavaScript | Main app logic | ~6000+ | Notifications, redirects, task management |
| [api-client.js](api-client.js) | JavaScript | API abstraction | ~800+ | TasksAPI, NotificationsAPI, AuthAPI |
| [backend/server.py](backend/server.py) | Python/Flask | REST API | ~5000+ | /api/tasks/{id}/accept, /api/tasks/{id}/undo-accept, /api/notifications |
| [backend/database.py](backend/database.py) | Python | Database layer | ~400+ | DB initialization, schema, connection management |

---

## 7. IMPLEMENTATION CHECKLIST

### Mark As Undone Feature
- ✅ Frontend button implementation: `task-in-progress.html` (line 503)
- ✅ Frontend handler: `markTaskUndone()` function (lines 655-710)
- ✅ API endpoint: `POST /api/tasks/{id}/undo-accept` (backend/server.py:1226)
- ✅ Database update: `tasks.status = 'active'` and `tasks.accepted_by = NULL`
- ✅ Notification: Created for task poster
- ✅ LocalStorage cleanup: Remove task from `acceptedTasks`
- ✅ Redirect: Returns to `index.html`

### Notification System
- ✅ Frontend UI: `index.html` (lines 94-107)
- ✅ Notification Bell: With badge count
- ✅ Dropdown: Lists last 20 notifications
- ✅ Backend storage: `notifications` table
- ✅ API endpoints: GET, POST read, DELETE, clear-task
- ✅ Auto-sync: `syncNotificationsFromServer()` in app.js
- ✅ Action buttons: For payment, task, tracking actions

### Task Redirects
- ✅ Auto-redirect to tracking: `autoRedirectToAcceptedTaskTracking()`
- ✅ Redirect loop prevention: Session storage checks
- ✅ Task state validation: Ensures task still accepted
- ✅ Redirect from notifications: Handles payment/task/tracking notifications

### Task State Management
- ✅ Database states: 'active', 'accepted', 'completed'
- ✅ Frontend arrays: `myAcceptedTasks`, `myPostedTasks`, `tasks`
- ✅ LocalStorage persistence: User object with acceptedTasks
- ✅ Restoration: Auto-restore from storage on page reload

---

## 8. IMPORTANT NOTES

1. **Notification Action Data Format**: Stored as JSON string in `notifications.data` field
   ```json
   {
       "type": "tracking|payment|task",
       "label": "Button Label",
       "taskId": 123,
       "url": "poster-live-tracking.html?task=123"
   }
   ```

2. **Task Status Lifecycle**:
   - Created: `status = 'active'`
   - Helper accepts: `status = 'accepted'`, `accepted_by = helper_id`
   - Helper marks undone: `status = 'active'`, `accepted_by = NULL`
   - Helper completes: `status = 'completed'`, `completed_at = timestamp`

3. **Notification Types**:
   - `'task_accepted'` - When helper accepts task
   - `'task_undone'` - When helper marks task undone
   - `'task_completed'` - When task is marked complete
   - `'payment_required'` - When payment needed
   - Other types: Various action notifications

4. **Redirect Prevention**:
   - Uses `sessionStorage` to track redirects per user per task
   - Checks if task still accepted before redirecting
   - Prevents infinite loops if helper withdraws

5. **LocalStorage User Object Structure**:
   ```javascript
   {
       id: "user_id",
       name: "John Doe",
       role: "helper|poster",
       wallet: 1000.50,
       acceptedTasks: [...],
       token: "auth_token",
       ...
   }
   ```
