# Quick Reference: File Locations & Functions

## MARK AS UNDONE FEATURE

### Frontend - Where Button Is
- **File**: [task-in-progress.html](task-in-progress.html#L503)
- **Button Location**: Line 503
- **Handler Function**: `markTaskUndone()` (lines 655-710)
- **What It Does**: 
  - Confirms with user
  - Calls `/api/tasks/{id}/undo-accept` endpoint
  - Stops location sharing
  - Removes task from localStorage acceptedTasks
  - Redirects to index.html

### Backend - Processing
- **File**: [backend/server.py](backend/server.py#L1226)
- **Endpoint**: `POST /api/tasks/<int:task_id>/undo-accept` (line 1226)
- **What It Does**:
  - Verifies task is accepted by current user
  - Reverts status from 'accepted' → 'active'
  - Clears accepted_by and accepted_at fields
  - Creates notification for task poster
  - Returns success response

---

## NOTIFICATION SYSTEM

### Frontend - UI Components
- **File**: [index.html](index.html#L94)
- **Elements**:
  - Notification wrapper (line 94)
  - Bell button with onclick="toggleNotifications()" (line 95)
  - Badge showing unread count (line 97)
  - Dropdown with notification list (line 99)
  - Clear All button (line 102)
  - Mobile notification item (line 130)

### Frontend - Logic & Display
- **File**: [app.js](app.js#L175)
- **Key Functions**:
  - `showNotification(message, type, duration)` (line 179) - Shows toast notification
  - `syncNotificationsFromServer()` (line ~790) - Fetches from backend
  - `updateNotificationUI()` (line ~890) - Updates badge & list
  - `addNotification(notification)` - Adds notification locally
  - `markAsRead(notifId)` - Marks single notification as read
  - `clearAllNotifications()` - Clears all notifications
  - `handleNotificationAction(notifId, actionType, taskId)` - Handles clicks
  - `toggleNotifications()` - Shows/hides dropdown

### Backend - API
- **File**: [backend/server.py](backend/server.py#L4496)
- **Endpoints**:
  - `GET /api/notifications` (line 4496) - Get all notifications
  - `POST /api/notifications/{id}/read` (line 4526) - Mark as read
  - `DELETE /api/notifications/{id}` (line 4549) - Delete notification
  - `POST /api/notifications/clear-task/{id}` (line 4570) - Clear for task

### Backend - Database Storage
- **File**: [backend/database.py](backend/database.py#L250) (approximate line for notifications table)
- **Table**: `notifications`
- **Key Columns**:
  - `id` - Notification ID
  - `user_id` - Who receives it
  - `task_id` - Related task
  - `notification_type` - 'task_accepted', 'task_undone', etc.
  - `title` - Short title
  - `message` - Full message
  - `status` - 'unread' or 'read'
  - `data` - JSON with action info
  - `created_at` - Timestamp

### API Client - Abstraction Layer
- **File**: [api-client.js](api-client.js#L800)
- **Object**: `NotificationsAPI`
- **Methods**:
  - `async getAll()` - Fetch all notifications
  - `async markAsRead(notificationId)` - Mark as read
  - `async delete(notificationId)` - Delete
  - `async clearTaskNotifications(taskId)` - Clear for task

---

## TASK REDIRECTS

### Auto-Redirect on Task Acceptance
- **File**: [app.js](app.js#L827)
- **Function**: `autoRedirectToAcceptedTaskTracking(notificationList)` (line 827)
- **What It Does**:
  - When helper accepts task, poster gets redirected to tracking page
  - But only if certain conditions met:
    ✓ Task is still in myPostedTasks with status='accepted'
    ✓ Task is NOT back in active tasks list
    ✓ Not already redirected this session
  - Uses `sessionStorage` to prevent loops
  - Redirects to: `poster-live-tracking.html?task={taskId}`

### Notification Action Handling
- **File**: [app.js](app.js#L1000)  
- **Function**: `handleNotificationAction(notifId, actionType, taskId)` (line ~1000)
- **What It Does**:
  - Handles clicks on notification action buttons
  - Types: 'payment', 'tracking', 'task'
  - For tracking: validates task still accepted before redirecting
  - Prevents redirect if task is no longer active
  - Shows error: "This task is no longer being tracked"

### Preventing Redirect Loops
- **Strategy**: Session storage + task state validation
- **Key Code** (line ~1035-1050 in app.js):
  ```javascript
  const alreadyRedirectedKey = `taskearn_tracking_redirect_${currentUser.id}_{taskId}`;
  if (sessionStorage.getItem(alreadyRedirectedKey)) return; // Already redirected
  
  // Validate task still accepted
  const taskInPosted = myPostedTasks.find(t => t.id === taskRef && t.status === 'accepted');
  const taskNoLongerAccepted = tasks.find(t => t.id === taskRef && t.status === 'active');
  
  if (!taskInPosted || taskNoLongerAccepted) {
      showToast('❌ This task is no longer being tracked...', 'error');
      return;
  }
  ```

**Related Document**: [REDIRECT_LOOP_FIX_COMPLETE.md](REDIRECT_LOOP_FIX_COMPLETE.md)

---

## TASK STATE MANAGEMENT

### Frontend - Arrays
- **File**: [app.js](app.js) - global scope
- **Arrays**:
  - `myAcceptedTasks` - Tasks accepted by current helper
  - `myPostedTasks` - Tasks posted by current user
  - `tasks` - All available tasks
  - `notifications` - All notifications for user

### Frontend - Persistence
- **LocalStorage Keys**:
  ```javascript
  'taskearn_user'                     // Current user + acceptedTasks
  'taskearn_token'                    // Auth token
  `notifications_{userId}`            // User's notifications
  `taskearn_tracking_redirect_{userId}_{taskId}`  // Redirect tracking
  ```

### Backend - Task Status States
- **File**: [backend/database.py](backend/database.py#L91)
- **Table**: `tasks`
- **Status Column Values**:
  - `'active'` - Available for any helper to accept
  - `'accepted'` - Has been accepted by a helper, in progress
  - `'completed'` - Task finished and paid

### Backend - Task Fields
- `id` - Task ID
- `title` - Task name
- `description` - Details
- `posted_by` - User ID of poster
- `accepted_by` - User ID of helper (NULL if not accepted)
- `accepted_at` - When accepted (NULL if not accepted)
- `completed_at` - When completed (NULL if not done)
- `status` - One of: 'active', 'accepted', 'completed'
- `price` - Task amount in rupees
- `service_charge` - Service charge

---

## TASK ACCEPTANCE FLOW

1. **Helper Views Available Task** → [index.html](index.html)
2. **Helper Clicks Accept** → Calls `TasksAPI.accept(taskId)`
3. **API Client Sends** → `POST /api/tasks/{id}/accept` via [api-client.js](api-client.js#L601)
4. **Backend Processing** → [backend/server.py](backend/server.py#L818):
   - Updates task status to 'accepted'
   - Sets accepted_by = helper_id
   - Creates notification for poster
5. **Notification Action** → For poster:
   - Auto-redirects to `poster-live-tracking.html`
   - Shows live location of helper
6. **Helper Works on Task** → On [task-in-progress.html](task-in-progress.html)
7. **Helper Completes or Marks Undone**:
   - Complete: Task finished, payment processed
   - Undo: Task reverts to 'active', available again

---

## DATABASE SCHEMA QUICK REFERENCE

### users
```
id, name, email, password_hash, phone, dob, rating,
tasks_posted, tasks_completed, total_earnings, is_suspended, ...
```

### tasks
```
id, title, description, category, location_lat, location_lng,
location_address, price, service_charge, posted_by, posted_at,
expires_at, [accepted_by], [accepted_at], [completed_at], status
```

### notifications
```
id, user_id, task_id, notification_type, title, message,
status ('unread'|'read'), data (JSON), created_at, read_at
```

### wallets
```
id, user_id (unique), balance, total_added, total_spent,
total_earned, total_cashback, created_at, updated_at
```

### wallet_transactions
```
id, wallet_id, user_id, type, amount, balance_after,
description, reference_id, task_id, status, created_at
```

---

## COMMON OPERATIONS

### Accept a Task (Helper)
1. Click Accept on task card in [index.html](index.html)
2. = `TasksAPI.accept(taskId)` in [api-client.js](api-client.js#L601)
3. → `POST /api/tasks/{id}/accept` in [backend/server.py](backend/server.py#L818)
4. → Task status becomes 'accepted'
5. → Notification sent to poster

### Mark Task Undone (Helper)
1. On [task-in-progress.html](task-in-progress.html), click "Mark Task Undone" button (line 503)
2. = `markTaskUndone()` function (lines 655-710)
3. → `POST /api/tasks/{id}/undo-accept` in [backend/server.py](backend/server.py#L1226)
4. → Task status reverts to 'active'
5. → Notification sent to poster about withdrawal
6. → Redirect to [index.html](index.html)

### View Notifications (All Users)
1. Click bell icon in header of [index.html](index.html) (line 95)
2. = `toggleNotifications()` function in [app.js](app.js)
3. → Shows dropdown with recent notifications
4. → Click to mark as read or clear

### Notification Processing
1. Load [index.html](index.html)
2. `syncNotificationsFromServer()` called in [app.js](app.js)
3. → `GET /api/notifications` from [backend/server.py](backend/server.py#L4496)
4. → Notifications saved to localStorage
5. → `updateNotificationUI()` updates display
6. → `autoRedirectToAcceptedTaskTracking()` may redirect poster

---

## KEY VARIABLES & CONSTANTS

```javascript
// In app.js (global scope):

currentUser          // Current logged-in user object
currentUserRole      // 'poster' or 'helper'

myAcceptedTasks      // Array of tasks helper has accepted
myPostedTasks        // Array of tasks user posted
tasks                // Array of all available tasks
notifications        // Array of user's notifications

API_URL              // Backend API base URL
```

---

## TESTING ENDPOINTS

Quick API calls to test:

```bash
# Get notifications
curl -H "Authorization: Bearer {token}" \
  https://api-url/api/notifications

# Accept a task
curl -X POST -H "Authorization: Bearer {token}" \
  https://api-url/api/tasks/123/accept

# Mark task undone
curl -X POST -H "Authorization: Bearer {token}" \
  https://api-url/api/tasks/123/undo-accept

# Mark notification as read
curl -X POST -H "Authorization: Bearer {token}" \
  https://api-url/api/notifications/456/read

# Delete notification
curl -X DELETE -H "Authorization: Bearer {token}" \
  https://api-url/api/notifications/456
```

---

See [CODEBASE_STRUCTURE_ANALYSIS.md](CODEBASE_STRUCTURE_ANALYSIS.md) for detailed documentation.
