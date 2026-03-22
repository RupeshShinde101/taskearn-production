# Posted Tasks Visibility Fix - When Helper Marks Task as Undone

## Problem Statement
When a helper accepts a task and later marks it as undone, the task disappears from the poster's "Posted Tasks" section. The task should remain visible in the poster's section until:
- The timer expires
- The poster manually deletes the task  
- Someone completes the task

## Root Cause Analysis

### The Issue
1. **Posted Tasks Loading**: The frontend was using the `/api/tasks` endpoint which only returns tasks with `status = 'active'`
2. **Status Change on Accept**: When a helper accepts a task, its status changes from 'active' to 'accepted'
3. **Task Disappears**: The task no longer appears in the `/api/tasks` results, so it's removed from browse view
4. **Status Revert on Undo**: When helper marks as undone, backend correctly sets status back to 'active'
5. **Visibility Issue**: The poster's `myPostedTasks` array isn't properly synced with the backend's user-specific task endpoint

### Why This Happens
The `/api/tasks` endpoint returns only active tasks suitable for browsing. But the poster needs to see ALL their posted tasks regardless of status. The solution is to use a dedicated `/api/user/tasks` endpoint that returns:
- All posted tasks (regardless of status)
- All accepted tasks by the current user
- All completed tasks by the current user

## Solution Implemented

### 1. Added getUserTasks() Method to TasksAPI
**File**: `api-client.js`, Line ~568

```javascript
// ✅ NEW: Get user's tasks (posted, accepted, completed)
async getUserTasks() {
    const result = await apiRequest('/user/tasks', {
        method: 'GET'
    });
    return result.data;
}
```

### 2. Updated loadTasksFromServer() to Use User Tasks Endpoint
**File**: `app.js`, Lines ~1288-1350

The function now:
1. Calls TasksAPI.getAll() to get available tasks
2. Also calls TasksAPI.getUserTasks() to get user's own tasks
3. Loads posted tasks from the user endpoint (which includes ALL statuses)
4. Falls back to syncing with server data if user endpoint fails
5. Properly syncs `myPostedTasks` with latest data from backend

```javascript
// ✅ NEW: Also load user's posted tasks to ensure poster sees all their tasks
let userTasksResult = null;
if (typeof TasksAPI.getUserTasks === 'function' && currentUser) {
    console.log('🚀 Calling TasksAPI.getUserTasks for user:', currentUser.id);
    try {
        userTasksResult = await TasksAPI.getUserTasks();
        if (userTasksResult && userTasksResult.postedTasks) {
            console.log('📋 User posted tasks:', userTasksResult.postedTasks.length);
        }
    } catch (e) {
        console.warn('⚠️ Could not load user tasks:', e.message);
    }
}

// Load from user endpoint if available
if (currentUser && userTasksResult && userTasksResult.postedTasks) {
    console.log('🔄 Loading posted tasks from /user/tasks endpoint...');
    myPostedTasks = userTasksResult.postedTasks.map(t => ({
        ...t,
        postedAt: new Date(t.posted_at),
        expiresAt: new Date(t.expires_at)
    }));
    console.log(`✅ Loaded ${myPostedTasks.length} posted task(s) from user endpoint`);
    updateUserData(currentUser.id, {
        postedTasks: serializeTasks(myPostedTasks)
    });
}
```

### 3. Added Posted Tasks Restoration to renderDashboard()
**File**: `app.js`, Lines ~5056-5067

Safety net that restores posted tasks from localStorage when rendering the dashboard:

```javascript
// ✅ FIX: Restore posted tasks from localStorage if missing
if (currentUser && (!myPostedTasks || myPostedTasks.length === 0)) {
    console.log('🔄 Restoring posted tasks from localStorage...');
    try {
        let savedUser = JSON.parse(localStorage.getItem(STORAGE_KEYS.CURRENT_USER) || 'null');
        if (!savedUser) {
            savedUser = JSON.parse(localStorage.getItem('taskearn_user') || '{}');
        }
        if (savedUser && savedUser.postedTasks && Array.isArray(savedUser.postedTasks)) {
            myPostedTasks = deserializeTasks(savedUser.postedTasks);
            console.log(`✅ Restored ${myPostedTasks.length} posted task(s)`);
        }
    } catch (e) {
        console.error('⚠️ Error restoring posted tasks:', e);
    }
}
```

### 4. Enhanced Page Visibility Handler
**File**: `app.js`, Lines ~1707-1757

Auto-restores both accepted and posted tasks when page becomes visible:

```javascript
document.addEventListener('visibilitychange', () => {
    if (!document.hidden && currentUser) {
        // Restore accepted tasks...
        
        // ✅ NEW: Also restore posted tasks from localStorage
        const restoredPostedTasks = deserializeTasks(savedUser.postedTasks);
        if (restoredPostedTasks.length > 0 && (!myPostedTasks || restoredPostedTasks.length > myPostedTasks.length)) {
            console.log(`✅ Restored ${restoredPostedTasks.length} posted task(s)`);
            myPostedTasks = restoredPostedTasks;
            setTimeout(() => renderDashboard(), 100);
        }
    }
});
```

## How It Works

### Scenario: Helper Marks Task as Undone

1. **Helper accepts task**
   - Backend: Task status = 'accepted'
   - Frontend: Task moves out of browse list (only 'active' tasks shown)
   - Poster: Task disappears from available tasks (correct behavior)

2. **Helper marks task as undone**
   - Backend: Task status = 'active', acceptedBy = NULL
   - task-in-progress.html: Removes from helper's acceptedTasks
   - Frontend: Calls helper's dashboard

3. **Poster's app auto-refreshes (30 seconds)**
   - Calls loadTasksFromServer()
   - Calls TasksAPI.getUserTasks()
   - Gets ALL posted tasks from `/api/user/tasks` endpoint
   - ✅ Task with 'active' status now appears in myPostedTasks
   - ✅ Dashboard renders with task visible in "Posted Tasks"

4. **If poster navigates away and returns**
   - renderDashboard() restores myPostedTasks from localStorage
   - ✅ Task is still visible
   
5. **If poster switches browser tabs**
   - visibilitychange event fires
   - Auto-restores myPostedTasks from localStorage
   - ✅ Task is visible when returning to tab

## Data Flow

```
Helper Marks Undone
    ↓
Backend: status 'accepted' → 'active'
    ↓
Frontend: loadTasksFromServer() called (auto-refresh)
    ↓
TasksAPI.getUserTasks() ← Returns ALL user's tasks
    ↓
myPostedTasks updated with fresh data
    ↓
Task visible in "Posted Tasks" ✅
```

## Task Status Display in Posted Tasks

The renderPostedTasks() function shows different UI based on status:

```javascript
if (t.status === 'active') {
    // Show Edit/Delete buttons - task is available for acceptance
    actionHTML = `<button onclick="openEditTask(${t.id})">Edit</button>`;
} else if (t.status === 'accepted') {
    // Show task is pending (helper accepted it)
    actionHTML = `<div>Pending - waiting for helper to complete</div>`;
} else if (t.status === 'completed') {
    // Show awaiting payment
    actionHTML = `<div>Completed - awaiting your payment</div>`;
}
```

## Backend Endpoint Details

### /api/user/tasks (GET)
**Authentication**: Required
**Returns**:
```json
{
    "success": true,
    "postedTasks": [
        {
            "id": 1,
            "status": "active" | "accepted" | "completed",
            "posted_by": userId,
            ...
        }
    ],
    "acceptedTasks": [...],
    "completedTasks": [...]
}
```

**Includes**:
- ✅ Tasks posted by user regardless of status
- ✅ Tasks accepted by user
- ✅ Tasks completed by user
- ✅ Latest data from database

## Three-Layer Protection for Posted Tasks

1. **Load Layer** (loadTasksFromServer)
   - Primary source: TasksAPI.getUserTasks()
   - Fallback: Sync with server data
   - Timing: Every 30 seconds (auto-refresh)

2. **Render Layer** (renderDashboard)
   - Safety net: Restore from localStorage
   - Timing: Every time dashboard renders
   - Prevents display of stale data

3. **Visibility Layer** (visibilitychange event)
   - Auto-restore on tab return
   - Auto-restore when page becomes active
   - Timing: Whenever page becomes visible

## Files Modified

1. **api-client.js**
   - Added `TasksAPI.getUserTasks()` method

2. **app.js**
   - Enhanced `loadTasksFromServer()` to use user tasks endpoint
   - Added posted tasks restoration to `renderDashboard()`
   - Enhanced `visibilitychange` event handler

## Verification Steps

1. ✅ Log in as poster and create a task
2. ✅ Log in as helper (different browser/window)
3. ✅ Helper accepts the task
4. ✅ Verify task disappears from poster's available tasks (correct)
5. ✅ Helper navigates to task-in-progress and marks as undone
6. ✅ Verify task reappears in poster's "Posted Tasks" immediately or within 30 seconds
7. ✅ Check browser console for restoration logs

## Console Output Expected

When task is marked as undone and page refreshes:
```
📡 Loading tasks from backend server...
🚀 Calling TasksAPI.getAll...
🚀 Calling TasksAPI.getUserTasks for user: [userId]
📥 User tasks response received
📋 User posted tasks: [count]
🔄 Loading posted tasks from /user/tasks endpoint...
✅ Loaded [count] posted task(s) from user endpoint
```

When returning to Posted Tasks tab:
```
🔄 Restoring posted tasks from localStorage...
✅ Restored [count] posted task(s)
```

## Summary

The fix ensures that:
- ✅ Posters always see their tasks in "Posted Tasks" section
- ✅ Tasks remain visible after helper marks as undone
- ✅ Tasks persist across page navigations
- ✅ Tasks persist when switching browser tabs
- ✅ Multiple layers of protection prevent data loss
- ✅ Proper sync between frontend and backend data
