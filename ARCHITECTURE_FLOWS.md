# Architecture Diagram & Flow

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                       Frontend Layer (Browser)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  index.html (Dashboard)                                  │   │
│  │  - Main UI                                               │   │
│  │  - Notification bell (line 95)                           │   │
│  │  - Accepted Tasks tab (line 573)                         │   │
│  │  - Completed Tasks tab (line 578)                        │   │
│  │  - Task cards                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                 ┌────────────┼────────────┐                     │
│                 │                         │                     │
│  ┌─────────────▼──────────┐  ┌──────────▼────────────┐         │
│  │ task-in-progress.html  │  │ poster-live-          │         │
│  │ (Helper Working)       │  │ tracking.html         │         │
│  │ - Mark Undone button   │  │ (Poster Tracking)     │         │
│  │   (line 503)           │  │ - Live location feed  │         │
│  │ - Timer                │  │ - Helper info         │         │
│  │ - Location sharing     │  └───────────────────────┘         │
│  └────────────────────────┘                                     │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  JavaScript Layer                                        │   │
│  │  ┌────────────────────────────────────────────────────┐ │   │
│  │  │ app.js (~6000+ lines)                              │ │   │
│  │  │ Core Logic:                                        │ │   │
│  │  │ - showNotification()          (line 179)           │ │   │
│  │  │ - syncNotificationsFromServer()                    │ │   │
│  │  │ - autoRedirectToAcceptedTaskTracking() (line 827)  │ │   │
│  │  │ - updateNotificationUI()                           │ │   │
│  │  │ - addNotification()                                │ │   │
│  │  │ - handleNotificationAction()                       │ │   │
│  │  │ - taskAcceptance logic                             │ │   │
│  │  │ - completeTask()               (line 2900)         │ │   │
│  │  │                                                    │ │   │
│  │  │ Global Arrays:                                     │ │   │
│  │  │ - myAcceptedTasks[]  (localStorage)               │ │   │
│  │  │ - myPostedTasks[]    (localStorage)               │ │   │
│  │  │ - tasks[]            (in-memory)                  │ │   │
│  │  │ - notifications[]    (localStorage)               │ │   │
│  │  └────────────────────────────────────────────────────┘ │   │
│  │                                                          │   │
│  │  ┌────────────────────────────────────────────────────┐ │   │
│  │  │ api-client.js (~800 lines)                         │ │   │
│  │  │ API Abstraction Layer:                             │ │   │
│  │  │ - TasksAPI                                         │ │   │
│  │  │     .accept(taskId)              (line 601)        │ │   │
│  │  │     .complete(taskId)            (line 606)        │ │   │
│  │  │ - NotificationsAPI               (line 800)        │ │   │
│  │  │     .getAll()                                      │ │   │
│  │  │     .markAsRead(notificationId)  (line 811)        │ │   │
│  │  │     .delete(notificationId)      (line 819)        │ │   │
│  │  │     .clearTaskNotifications()    (line 827)        │ │   │
│  │  │ - WalletAPI, AuthAPI, etc...                       │ │   │
│  │  └────────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Local Storage                                           │   │
│  │  - taskearn_user (with acceptedTasks array)             │   │
│  │  - taskearn_token (auth token)                           │   │
│  │  - notifications_{userId} (JSON array)                   │   │
│  │  - taskearn_tracking_redirect_{userId}_{taskId}         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP/HTTPS
                              │ JSON
                              │
┌──────────────────────────────────────────────────────────────────┐
│                       Backend Layer                              │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Flask REST API Server (backend/server.py)              │   │
│  │  ~5000+ lines                                            │   │
│  │                                                          │   │
│  │  Task Endpoints:                                         │   │
│  │  POST   /api/tasks/{id}/accept      (line 818)          │   │
│  │  POST   /api/tasks/{id}/undo-accept (line 1226)         │   │
│  │  POST   /api/tasks/{id}/complete                        │   │
│  │  GET    /api/tasks/{id}/details                         │   │
│  │                                                          │   │
│  │  Notification Endpoints:                                 │   │
│  │  GET    /api/notifications          (line 4496)         │   │
│  │  POST   /api/notifications/{id}/read (line 4526)        │   │
│  │  DELETE /api/notifications/{id}     (line 4549)         │   │
│  │  POST   /api/notifications/clear-task/{id} (line 4570)  │   │
│  │                                                          │   │
│  │  Other: Auth, Wallet, Payments, etc...                  │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              │ Query/Update                      │
│                              │                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Database Layer (backend/database.py)                    │   │
│  │  SQLite (dev) / PostgreSQL (production)                  │   │
│  │                                                          │   │
│  │  Tables:                                                 │   │
│  │  ┌─ users                                               │   │
│  │  │  - id, name, email, rating, tasks_posted, etc       │   │
│  │  │                                                      │   │
│  │  ├─ tasks  (Main table for this analysis)              │   │
│  │  │  - id, title, price, posted_by, accepted_by,        │   │
│  │  │    accepted_at, completed_at, status                │   │
│  │  │    [status: 'active' | 'accepted' | 'completed']    │   │
│  │  │                                                      │   │
│  │  ├─ notifications  (Notification storage)              │   │
│  │  │  - id, user_id, task_id, title, message,            │   │
│  │  │    notification_type, status, data (JSON), created_at│  │
│  │  │                                                      │   │
│  │  ├─ wallets & wallet_transactions                       │   │
│  │  │  - For payment processing                            │   │
│  │  │                                                      │   │
│  │  ├─ location_tracking                                   │   │
│  │  │  - For live helper tracking                          │   │
│  │  │                                                      │   │
│  │  └─ Other tables: payments, ratings, sos_alerts, etc   │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Mark Task Undone - Detailed Flow

```
HELPER'S PERSPECTIVE:
═══════════════════════

Helper opens "Task In Progress" page
        │
        ▼
[task-in-progress.html] displays:
- Task details
- Timer
- "Mark Task Undone" button (line 503)
- "Complete Task" button
        │
        ├─ Helper clicks "Mark Task Undone"
        │
        ▼
        markTaskUndone() function called (line 658)
        │
        ├─ Show confirmation dialog
        │├─ User cancels → return
        │└─ User confirms → continue
        │
        ▼
        stopLiveLocationSharing() - stop sharing location
        clearInterval(timerInterval) - stop timer
        │
        ▼
        fetch('/api/tasks/{id}/undo-accept', {
            method: 'POST',
            headers: {'Authorization': 'Bearer token'}
        })
        │
        ────────────────────────────────────┐
                                            │
        ┌───────────────────────────────────┘
        │
        ▼ BACKEND PROCESSING
────────────────────────────
[backend/server.py - Line 1226]
undo_accept_task(task_id):
│
├─ Verify task, verify user accepted it
│  └─ Check: database.tasks WHERE
│     id = task_id AND
│     accepted_by = current_user_id AND
│     status = 'accepted'
│
├─ Update task status back to 'active'
│  └─ UPDATE tasks SET
│     status = 'active',
│     accepted_by = NULL,
│     accepted_at = NULL
│
├─ Create notification for POSTER
│  └─ INSERT INTO notifications:
│     - user_id = poster_id
│     - notification_type = 'task_undone'
│     - title = '⚠️ Helper Withdrew'
│     - message = '{name} withdrew from your task'
│     - status = 'unread'
│
└─ Return: {'success': True, ...}
        │
        ────────────────────────────────────┐
                                            │
        ┌───────────────────────────────────┘
        │
        ▼ BACK TO FRONTEND
────────────────────────────
Response received in markTaskUndone()
│
├─ Success response?
│  │
│  ├─ YES:
│  │  ├─ Update localStorage
│  │  │  └─ Get taskearn_user object
│  │  │  └─ Remove task from acceptedTasks array
│  │  │  └─ Save back to localStorage
│  │  │
│  │  └─ Redirect to index.html
│  │     └─ window.location.href = 'index.html'
│  │
│  └─ NO:
│     └─ Show error alert
│        └─ alert('Failed to mark task as undone')


POSTER'S PERSPECTIVE (After helper marked undone):
══════════════════════════════════════════════════

Poster is on Dashboard [index.html]
        │
        ▼
App.js detects activity
        │
        ├─ syncNotificationsFromServer() called periodically
        │  │
        │  └─ GET /api/notifications
        │     │
        │     ▼
        │  Backend returns:
        │  [
        │    {
        │      id: 123,
        │      user_id: 'poster',
        │      task_id: 456,
        │      notification_type: 'task_undone',
        │      title: '⚠️ Helper Withdrew',
        │      message: 'John withdrew from your task',
        │      status: 'unread',
        │      data: {'type': 'view', 'taskId': 456},
        │      created_at: '2024-03-22T10:30:00Z'
        │    }
        │  ]
        │
        ├─ Notifications saved to localStorage
        │  └─ localStorage.setItem(`notifications_${posterId}`, JSON.stringify([...]))
        │
        ├─ updateNotificationUI() called
        │  │
        │  └─ Updates notification badge
        │     └─ Badge count: 1
        │
        ├─ autoRedirectToAcceptedTaskTracking() called
        │  │
        │  └─ Check: Is task in myPostedTasks with status='accepted'?
        │     └─ NO! Task is now status='active'
        │     └─ autoRedirectToAcceptedTaskTracking() SKIPS redirect
        │
        └─ Poster sees notification in dropdown
           └─ Notification shows: "John withdrew from your task 'Grocery Delivery'"
           └─ Task re-appears in "Available Tasks" list
           └─ Task can be accepted by another helper

RESULT:
═══════
✅ Helper's task removed from acceptedTasks
✅ Helper redirected back to dashboard
✅ Task status reverted to 'active' in database
✅ Poster notified about withdrawal
✅ NO redirect loop (task no longer 'accepted', so not auto-redirected to tracking)
✅ Task available for other helpers to accept
```

---

## Task Acceptance with Notification Flow

```
HELPER'S SIDE:
═════════════

[index.html] - Available Tasks section
        │
        ├─ Helper views task card
        └─ Helper clicks "Accept" button
        │
        ▼
        TasksAPI.accept(taskId)  [api-client.js line 601]
        │
        ▼
        POST /api/tasks/{taskId}/accept
        
        ────────────────────────────────────┐
                                            │
        ┌───────────────────────────────────┘
        │
        ▼ BACKEND [server.py line 818]
────────────────────────────────────
accept_task(task_id):

1. Verify task exists and is 'active'
   └─ SELECT * FROM tasks WHERE id=? AND status='active'

2. Can't accept own task
   └─ IF task.posted_by == current_user: FAIL

3. Update task in database
   └─ UPDATE tasks SET
        status = 'accepted',           ◄─ CRITICAL CHANGE
        accepted_by = helper_id,       ◄─ CRITICAL CHANGE
        accepted_at = NOW()

4. Query helper details for notification
   └─ SELECT name, phone FROM users WHERE id = helper_id
   └─ Get: "John Doe"

5. Create ACTION DATA for notification
   └─ action_data = {
        "type": "tracking",
        "label": "Track Helper",
        "taskId": 456,
        "url": "poster-live-tracking.html?task=456"
      }

6. Create notification for POSTER
   └─ INSERT INTO notifications (
        user_id = poster_id,
        task_id = task_id,
        notification_type = 'task_accepted',
        title = 'Task Accepted! 🎉',
        message = 'John Doe accepted your task. Open tracking to see location.',
        status = 'unread',
        data = action_data_json,
        created_at = NOW()
      )

7. Return success
   └─ {'success': True, 'message': 'Task accepted successfully'}
        │
        ────────────────────────────────────┐
                                            │
        ┌───────────────────────────────────┘
        │
        ▼ BACK TO FRONTEND

Response received in accept() handler:
        │
        ├─ Update myAcceptedTasks array
        │  └─ myAcceptedTasks.push(taskData)
        │
        ├─ Remove from available tasks list
        │  └─ tasks = tasks.filter(t => t.id !== taskId)
        │
        ├─ Update localStorage
        │  └─ currentUser.acceptedTasks = myAcceptedTasks
        │  └─ localStorage.setItem('taskearn_user', JSON.stringify(currentUser))
        │
        └─ Show success notification
           └─ showNotification('✅ Task accepted! Open notification to track!')


POSTER'S SIDE (Meanwhile):
═════════════════════════

Poster is browsing dashboard [index.html]
        │
        ▼
app.js loads notifications:
        │
        ├─ Page loads → loadNotifications() called initially
        │  └─ Check localStorage: `notifications_{posterId}`
        │  └─ If empty, no notifications shown yet
        │
        ├─ Periodic sync (every 5-10 seconds or on user activity)
        │  │
        │  └─ syncNotificationsFromServer() called
        │     │
        │     ├─ GET /api/notifications
        │     │
        │     ▼ Backend returns:
        │     [{
        │       id: 789,
        │       user_id: 'poster_id',
        │       task_id: 456,
        │       notification_type: 'task_accepted',
        │       title: 'Task Accepted! 🎉',
        │       message: 'John Doe accepted your task...',
        │       status: 'unread',
        │       data: '{"type":"tracking","label":"Track Helper",...}',
        │       created_at: '2024-03-22T10:15:00Z'
        │     }]
        │
        ├─ Process & normalize notification
        │  └─ Parse action data from JSON
        │  └─ Set taskId, createdAt, read status
        │
        ├─ Save to localStorage
        │  └─ localStorage.setItem(`notifications_${posterId}`, JSON.stringify([...]))
        │
        ├─ updateNotificationUI() called
        │  │
        │  └─ Update badge count
        │     └─ Badge shows: "1" (1 unread notification)
        │     └─ Badge visible in notification bell
        │
        ├─ Render notification in dropdown
        │  │
        │  └─ Notification shows in list:
        │     ┌─────────────────────────────────┐
        │     │ 🎉 Task Accepted! 🎉            │
        │     │ John Doe accepted your task      │
        │     │ 1 minute ago                     │
        │     │ [Track Helper] button            │
        │     └─────────────────────────────────┘
        │
        └─ autoRedirectToAcceptedTaskTracking() called
           │
           ├─ Check: Is this task in myPostedTasks with status='accepted'?
           │  └─ YES! Task.status = 'accepted', task.accepted_by = John's ID
           │
           ├─ Check: Is task NOT in active tasks list?
           │  └─ YES! Task was removed from active list when accepted
           │
           ├─ Check: Not already redirected?
           │  └─ YES! First time, not yet set in sessionStorage
           │
           ├─ ALL CHECKS PASS → Redirect!
           │  │
           │  ├─ Set sessionStorage redirect flag
           │  │  └─ sessionStorage.setItem(
           │  │     `taskearn_tracking_redirect_poster_{taskId}`, '1')
           │  │
           │  ├─ Show toast: "📍 Task accepted. Opening live tracking..."
           │  │
           │  └─ Redirect to tracking page (500ms delay)
           │     └─ window.location.href = 'poster-live-tracking.html?task=456'
           │
           ▼
        [poster-live-tracking.html loads]
        - Shows live location of John (helper)
        - Shows John's phone, rating, tasks completed
        - Real-time location updates
        - SOS alarm if needed


RESULT:
═══════
✅ Helper: Task added to acceptedTasks, removed from available
✅ Helper: Redirected to task-in-progress.html (by clicking notification or manually)
✅ Poster: Receives notification about acceptance
✅ Poster: Auto-redirected to tracking page
✅ Poster: Can see helper's live location and contact info
✅ Database: Task status = 'accepted', accepted_by = helper_id
```

---

## Redirect Loop Prevention Mechanism

```
SCENARIO: Helper marks task undone
═════════════════════════════════════

BEFORE FIX (caused infinite loops):
──────────────────────────────────

1. Helper marks task undone
   └─ Task status: 'accepted' → 'active'
   └─ Notification sent to poster

2. Poster gets notification (task_undone type)
   └─ autoRedirectToAcceptedTaskTracking() checks:
      └─ "Is task in myPostedTasks with status='accepted'?"
      └─ "Was there an old notification about accepting?"
      └─ Could find OLD notification about acceptance
      └─ REDIRECT TRIGGERED! ❌

3. Poster redirected to poster-live-tracking.html
   └─ Location tracking fails (helper withdrew)
   └─ Page shows errors

4. Poster goes back to dashboard
   └─ sessionStorage cleared or doesn't exist
   └─ Steps 1-3 repeat → LOOP! ❌


AFTER FIX (prevents loops):
──────────────────────────

1. Helper marks task undone
   └─ Task status: 'accepted' → 'active'
   └─ accepted_by = NULL
   └─ Notification sent to poster

2. Poster gets notification (task_undone type)
   └─ autoRedirectToAcceptedTaskTracking() checks:
   │
   ├─ Check 1: Is task in myPostedTasks with status='accepted'?
   │  └─ SEARCH: myPostedTasks.find(t => t.id === taskId && t.status === 'accepted')
   │  └─ Task is now status='active' (backend updated it)
   │  └─ App likely hasn't fetched updated task state YET
   │  └─ But next check will catch it...
   │
   ├─ Check 2: Is task NOT in active tasks list?
   │  └─ SEARCH: tasks.find(t => t.id === taskId && t.status === 'active')
   │  └─ YES! Task is in active list now (restored)
   │  └─ This means task is no longer in "accepted" state
   │
   ├─ Check 3: sessionStorage redirect flag?
   │  └─ `taskearn_tracking_redirect_poster_{taskId}`
   │  └─ Set only when actually redirecting
   │
   ├─ FINAL DECISION:
   │  └─ If CHECK 1 FAILS (task not in myPostedTasks with accepted status)
   │  └─ OR CHECK 2 PASSES (task is in active list)
   │  └─ → DON'T REDIRECT ✅
   │
   │  ├─ Instead show error:
   │  │  └─ showToast('❌ This task is no longer being tracked.')
   │  │
   │  └─ Mark notification as read
   │     └─ Mark as read so it doesn't keep triggering

3. Poster stays on dashboard
   └─ Notification stays visible
   └─ Task back in available list
   └─ NO LOOP! ✅


KEY CODE (app.js lines ~827-860):
──────────────────────────────────

function autoRedirectToAcceptedTaskTracking(notificationList) {
    if (!currentUser || !Array.isArray(notificationList)) return;
    
    const target = notificationList.find(n => {
        const taskRef = n.taskId || n.task_id || n.action?.taskId;
        const isUnread = n.status === 'unread' || !n.read;
        
        // ✅ FIX: Multiple validation checks
        
        // Check 1: Task still in posted tasks with 'accepted' status?
        const taskInPosted = myPostedTasks.find(t => 
            t.id === taskRef && t.status === 'accepted'
        );
        
        // Check 2: Task NOT in active tasks list?
        const taskNoLongerAccepted = tasks.find(t => 
            t.id === taskRef && t.status === 'active'
        );
        
        // Only redirect if:
        // - Task WAS accepted (in myPostedTasks)
        // - AND task is no longer in active list (withdrawn)
        const shouldRedirect = taskInPosted && !taskNoLongerAccepted;
        
        return isUnread && shouldRedirect; // All conditions must pass
    });
    
    if (!target) return; // No valid notification found, don't redirect
    
    // ...redirect logic here...
}


RESULT:
═══════
✅ Prevents infinite loops
✅ Only redirects when task is legitimately accepted
✅ Doesn't redirect when helper withdraws (marked undone)
✅ Gracefully handles task state transitions
```

---

## State Diagram: Task Lifecycle

```
                    TASK LIFECYCLE
                    ══════════════

    ┌─────────────┐
    │   CREATED   │
    │   (NEW)     │
    └──────┬──────┘
           │
           ├─ INSERT INTO tasks
           │  - status = 'active'
           │  - posted_by = user_id
           │  - accepted_by = NULL
           │
           ▼
    ┌─────────────────────┐
    │     ACTIVE          │
    │ (Available)         │
    │                     │
    │ - Any helper can    │
    │   accept it         │
    │ - Visible in        │
    │   browse tasks      │
    └──────┬──────────────┘
           │
     ┌─────┴──────┐
     │            │
     │ ACCEPT     │ EXPIRE (timeout)
     │ (helper    │
     │  clicks)   │
     │            │
     ▼            ▼
┌──────────┐  ┌─────────┐
│ACCEPTED  │  │EXPIRED  │
│          │  │         │
│accepted_ │  │Removed  │
│by= user_id  │from     │
│          │  │display  │
└────┬─────┘  └─────────┘
     │
     ├──undo──┐
     │ (mark  │
     │ undone)│
     │        │
     ▼        ▼
  ┌────────────────┐
  │    ACTIVE      │
  │ (Re-available) │
  │                │ ◄──── Can be accepted by another helper
  └────────────────┘
     │
     │ COMPLETE (helper marks done)
     │
     ▼
┌──────────────────┐
│   COMPLETED      │
│                  │
│ - Payment issued │
│ - Helper earned  │
│ - Poster deduct  │
│ - Location stop  │
│ - Archived       │
└──────────────────┘


TRANSITIONS:
════════════

NEW → ACTIVE
  (automatically on creation)

ACTIVE → ACCEPTED
  POST /api/tasks/{id}/accept
  [backend/server.py line 818]
  - Helper clicks Accept
  - Backend: UPDATE status = 'accepted', accepted_by = ?

ACCEPTED → ACTIVE
  POST /api/tasks/{id}/undo-accept
  [backend/server.py line 1226]
  - Helper marks undone
  - Backend: UPDATE status = 'active', accepted_by = NULL

ACTIVE → COMPLETED
  POST /api/tasks/{id}/complete
  - Helper marks complete
  - Payment processed

ACTIVE → EXPIRED
  Background job/timeout
  - Task expires after certain time
  - Not shown to users

ACCEPTED → COMPLETED
  (Note: cannot go directly,
   must undo first then re-accept?)


STATUS VALUES IN DATABASE:
═════════════════════════

'active'     - Available for any helper to accept
'accepted'   - Accepted by a helper, in progress
'completed'  - Finished and payment processed
'expired'    - Timeout, no longer available (archived)
'cancelled'  - Cancelled by poster (not shown in flow)
```

---

## Database Query Examples

```sql
-- Get all active tasks visible to helpers
SELECT * FROM tasks 
WHERE status = 'active' 
ORDER BY created_at DESC;

-- Find task accepted by specific helper
SELECT * FROM tasks 
WHERE id = 456 
AND accepted_by = 'helper_user_id'
AND status = 'accepted';

-- Check if user can accept (can't accept own task)
SELECT * FROM tasks 
WHERE id = 456 
AND posted_by != 'helper_user_id'
AND status = 'active';

-- Get all notifications for user
SELECT * FROM notifications 
WHERE user_id = 'poster_id'
ORDER BY created_at DESC
LIMIT 50;

-- Mark task as accepted
UPDATE tasks 
SET status = 'accepted', accepted_by = 'helper_id', accepted_at = NOW()
WHERE id = 456;

-- Mark task as undone
UPDATE tasks 
SET status = 'active', accepted_by = NULL, accepted_at = NULL
WHERE id = 456;

-- Create acceptance notification
INSERT INTO notifications 
(user_id, task_id, notification_type, title, message, status, data, created_at)
VALUES (
  'poster_id',
  456,
  'task_accepted',
  'Task Accepted! 🎉',
  'John accepted your task "Grocery Delivery"',
  'unread',
  '{"type":"tracking","label":"Track Helper","taskId":456,"url":"..."}',
  NOW()
);

-- Create withdrawal notification
INSERT INTO notifications 
(user_id, task_id, notification_type, title, message, status, data, created_at)
VALUES (
  'poster_id',
  456,
  'task_undone',
  '⚠️ Helper Withdrew',
  'John withdrew from your task',
  'unread',
  '{"type":"view","taskId":456}',
  NOW()
);

-- Mark notification as read
UPDATE notifications 
SET status = 'read', read_at = NOW()
WHERE id = 789 AND user_id = 'poster_id';

-- Get unread count
SELECT COUNT(*) as unread_count
FROM notifications
WHERE user_id = 'poster_id' AND status = 'unread';

-- Delete old read notifications
DELETE FROM notifications
WHERE user_id = 'poster_id'
AND status = 'read'
AND created_at < DATE_SUB(NOW(), INTERVAL 30 DAY);
```

---

## File Dependencies Map

```
index.html
  ├─ Loads: app.js
  ├─ Loads: api-client.js
  ├─ Uses: localStorage (taskearn_user, notifications_*)
  ├─ API Calls: GET /api/notifications (via syncNotificationsFromServer)
  └─ Calls: TasksAPI.accept(), TasksAPI.complete()

task-in-progress.html
  ├─ Contains: markTaskUndone() function
  ├─ Calls: fetch('/api/tasks/{id}/undo-accept')
  ├─ Uses: localStorage (taskearn_user, taskearn_token)
  ├─ Stops: Location sharing, Timer
  └─ Redirects: window.location.href = 'index.html'

poster-live-tracking.html
  ├─ Calls: GET /api/tasks/{id}/location-tracking
  ├─ Uses: WebSocket or polling for live location
  └─ Displays: Helper's live location, contact info

app.js
  ├─ Imports: api-client.js functions
  ├─ Manages: Global arrays (myAcceptedTasks, tasks, notifications)
  ├─ Calls: 
  │  ├─ syncNotificationsFromServer()
  │  ├─ autoRedirectToAcceptedTaskTracking()
  │  ├─ TasksAPI.accept()
  │  ├─ TasksAPI.complete()
  │  ├─ NotificationsAPI.getAll()
  │  ├─ NotificationsAPI.delete()
  │  └─ NotificationsAPI.markAsRead()
  ├─ Uses: localStorage extensively
  └─ Manages: Notification UI updates

api-client.js
  ├─ Depends on: Fetch API
  ├─ Exports: TasksAPI, NotificationsAPI, AuthAPI, WalletAPI, etc.
  ├─ Uses: Authorization header with token
  ├─ Calls: Backend endpoints
  └─ Returns: Promises with result objects

backend/server.py
  ├─ Imports: database.py functions
  ├─ Depends on: Flask, psycopg2/sqlite3
  ├─ Endpoints:
  │  ├─ POST /api/tasks/{id}/accept ──► accept_task()
  │  ├─ POST /api/tasks/{id}/undo-accept ──► undo_accept_task()
  │  ├─ GET /api/notifications ──► get_notifications()
  │  ├─ POST /api/notifications/{id}/read ──► mark_notification_read()
  │  ├─ DELETE /api/notifications/{id} ──► delete_notification()
  │  └─ POST /api/notifications/clear-task/{id} ──► clear_task_notifications()
  ├─ Uses: database.get_db() context manager
  └─ Writes: To database tables

backend/database.py
  ├─ Defines: Database connection functions
  ├─ Initializes: All table schemas
  ├─ Provides: get_db() context manager
  ├─ Supports: PostgreSQL and SQLite
  ├─ Uses: Environment variables for config
  └─ Tables: users, tasks, notifications, wallets, payments, location_tracking, etc.
```

---

## Request/Response Examples

```json
// 1. ACCEPT TASK REQUEST & RESPONSE

REQUEST:
POST /api/tasks/456/accept
Headers:
  - Content-Type: application/json
  - Authorization: Bearer eyJhbGc...
Body: {}

RESPONSE 200 OK:
{
  "success": true,
  "message": "Task accepted successfully"
}

─────────────────────────────────────

// 2. UNDO ACCEPT TASK REQUEST & RESPONSE

REQUEST:
POST /api/tasks/456/undo-accept
Headers:
  - Content-Type: application/json
  - Authorization: Bearer eyJhbGc...
Body: {}

RESPONSE 200 OK:
{
  "success": true,
  "message": "Task marked as undone. It is now available for other helpers."
}

─────────────────────────────────────

// 3. GET NOTIFICATIONS REQUEST & RESPONSE

REQUEST:
GET /api/notifications
Headers:
  - Authorization: Bearer eyJhbGc...

RESPONSE 200 OK:
{
  "success": true,
  "notifications": [
    {
      "id": 789,
      "user_id": "poster_123",
      "task_id": 456,
      "notification_type": "task_accepted",
      "title": "Task Accepted! 🎉",
      "message": "John Doe accepted your task \"Grocery Delivery\"",
      "status": "unread",
      "data": "{\"type\":\"tracking\",\"label\":\"Track Helper\",\"taskId\":456,\"url\":\"poster-live-tracking.html?task=456\"}",
      "created_at": "2024-03-22T10:15:30Z",
      "read_at": null
    }
  ],
  "count": 1
}

─────────────────────────────────────

// 4. MARK NOTIFICATION AS READ REQUEST & RESPONSE

REQUEST:
POST /api/notifications/789/read
Headers:
  - Authorization: Bearer eyJhbGc...
Body: {}

RESPONSE 200 OK:
{
  "success": true,
  "message": "Notification marked as read"
}

─────────────────────────────────────

// 5. DELETE NOTIFICATION REQUEST & RESPONSE

REQUEST:
DELETE /api/notifications/789
Headers:
  - Authorization: Bearer eyJhbGc...

RESPONSE 200 OK:
{
  "success": true,
  "message": "Notification deleted"
}
```

