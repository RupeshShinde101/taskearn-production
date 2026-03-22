# Code Execution Flow Diagrams

## Flow 1: Task Acceptance & Auto-Redirect Flow

```
┌──────────────────────────────────────────────────────────────┐
│ Helper Clicks "ACCEPT" on Task Card (index.html)              │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ FRONTEND: acceptTask() function in app.js                    │
│  ├─ Validate task exists in tasks[]                         │
│  ├─ POST /api/tasks/{taskId}/accept                         │
│  └─ await response.json()                                   │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ BACKEND: /api/tasks/{taskId}/accept endpoint [server.py#L... │
│  ├─ Check: Task exists && status='active'                   │
│  ├─ Check: User not poster                                  │
│  ├─ UPDATE tasks SET status='accepted', accepted_by=USER_ID │
│  ├─ Get helper's name from users table                      │
│  ├─ Create notification for POSTER:                         │
│  │  └─ INSERT INTO notifications (                          │
│  │      user_id=POSTER_ID,                                  │
│  │      notification_type='task_accepted',                  │
│  │      title='Task Accepted! 🎉',                          │
│  │      data=JSON.stringify({                               │
│  │        type: 'tracking',                    ← TYPE        │
│  │        url: 'poster-live-tracking.html?task=123', ← URL  │
│  │        taskId: 123                                       │
│  │      }),                                                 │
│  │      status='unread'          ← UNREAD                   │
│  │  )                                                        │
│  ├─ Create notification for HELPER (confirmation)           │
│  └─ COMMIT                                                   │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ FRONTEND: Task Accept Response Received                      │
│  ├─ Remove task from tasks[] (no longer active)             │
│  ├─ Call syncTasksFromServer() [app.js#~350]               │
│  ├─ Reload tasks[], posted tasks, accepted tasks           │
│  ├─ Call syncNotificationsFromServer() [app.js#770]        │
│  └─ (Usually called on page load, may need manual call)    │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ syncNotificationsFromServer() [app.js#L770]                  │
│  ├─ GET /api/notifications                                   │
│  ├─ Parse JSON data field:                                  │
│  │  notification.data = '{"type":"tracking","url":"..."}'   │
│  │  notification.action = JSON.parse(notification.data)     │
│  ├─ Normalize fields (taskId, read, createdAt, etc)        │
│  ├─ localStorage.setItem(`notifications_${userId}`, ...)    │
│  ├─ notifications = processedNotifications                  │
│  ├─ updateNotificationUI()  [app.js#L890]                  │
│  │  └─ Render notifications in dropdown                     │
│  │     ├─ Show notification title & message                 │
│  │     ├─ Add action button if action exists                │
│  │     └─ Button onclick="handleNotificationAction(...)"   │
│  └─ autoRedirectToAcceptedTaskTracking(notificationList)    │
│     [app.js#L827]  ← THIS IS WHERE AUTO-REDIRECT HAPPENS   │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ autoRedirectToAcceptedTaskTracking() [app.js#L827]           │
│                                                               │
│ PRECONDITIONS CHECK:                                         │
│  ├─ currentUser exists?         [Line 829]                   │
│  ├─ notificationList is array?  [Line 829]                   │
│  ├─ Not already on tracking page? [Line 830]                │
│                                                               │
│ FIND TRACKING NOTIFICATION:                                  │
│  ├─ For each notification:                                   │
│  │   └─ notification.action.type === 'tracking'?   [L837]   │
│  │   └─ notification.action.url exists?            [L837]   │
│  │   └─ notification.status === 'unread'?          [L837]   │
│  │                                                           │
│  │     TASK STATE VALIDATION:                               │
│  │     ├─ Query myPostedTasks for task with:      [L841]   │
│  │     │  └─ id === taskRef AND status === 'accepted'      │
│  │     │                                                     │
│  │     ├─ Query tasks for SAME task with:         [L842]   │
│  │     │  └─ id === taskRef AND status === 'active'        │
│  │     │     (If found → task was rejected/undone)          │
│  │     │                                                     │
│  │     └─ shouldRedirect = taskInPosted && !taskNoLonger   │
│  │                          [L844]                          │
│  │                                                           │
│  │     REDIRECT KEY CHECK:                                 │
│  │     ├─ Check sessionStorage[`taskearn_tracking_...`]    │
│  │     │  (Prevents double-redirect)                        │
│  │     │                                                    │
│  │     └─ Return true if ALL conditions met      [L845]    │
│                                                               │
│ ACTION ON SUCCESS:                                           │
│  ├─ Set sessionStorage to prevent re-redirect    [L854]    │
│  ├─ showToast('📍 Task accepted. Opening...')    [L856]    │
│  ├─ setTimeout 400ms                             [L857]    │
│  └─ window.location.href = action.url            [L858]    │
│     (→ poster-live-tracking.html?task=123)                  │
│                                                               │
│ ACTION ON FAILURE:                                           │
│  └─ return; (silently skip)                      [L852]    │
│     (No error shown, just doesn't redirect)                  │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ RESULT:                                                      │
│  ✅ If all conditions met: Auto-redirect after 400ms         │
│  ❌ If any condition fails: No redirect (user sees button)   │
│  → User can still click "Track Helper" button manually      │
└──────────────────────────────────────────────────────────────┘
```

---

## Flow 2: Manual Tracking Button Click

```
┌──────────────────────────────────────────────────────────────┐
│ Poster Clicks "Track Helper" Button on Notification           │
│ (If auto-redirect didn't happen)                              │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ onclick="handleNotificationAction(notifId, 'tracking', taskId)"│
│ [app.js#L945]                                                 │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ handleNotificationAction(notifId, 'tracking', taskId)        │
│ [app.js#L1022]                                               │
│                                                               │
│ FIND NOTIFICATION:                                           │
│  └─ notifications.find(n => n.id === notifId)              │
│     ├─ If not found → showToast('Notification not found')   │
│     └─ If found → continue                                  │
│                                                               │
│ HANDLE 'TRACKING' ACTION:                                    │
│  ├─ Query myPostedTasks for task:                          │
│  │  └─ id === taskId AND status === 'accepted'  [L1043]   │
│  │                                                           │
│  ├─ Query tasks for SAME task:                            │
│  │  └─ id === taskId AND status === 'active' [L1044]     │
│  │     (Means helper withdrew)                              │
│  │                                                           │
│  ├─ If task NOT in myPostedTasks              [L1046]      │
│  │  └─ showToast('Cannot redirect: Task no longer tracked')│
│  │  └─ markAsRead(notifId)                                │
│  │  └─ return;  (EXIT - no redirect)                      │
│  │                                                           │
│  ├─ If task back in active list              [L1046]      │
│  │  └─ showToast('Cannot redirect: Task marked as undone')│
│  │  └─ markAsRead(notifId)                                │
│  │  └─ return;  (EXIT - no redirect)                      │
│  │                                                           │
│  └─ If both OK: [L1050-1053]                              │
│     ├─ trackingUrl = notification.action.url               │
│     │  (fallback: 'poster-live-tracking.html?task=123')   │
│     ├─ window.location.href = trackingUrl                 │
│     └─ return;  (REDIRECT!)                               │
│                                                               │
│ MARK NOTIFICATION AS READ:                                  │
│  └─ markAsRead(notifId)  [app.js#L1058]                    │
│     ├─ notifications = notifications.map(n =>              │
│     │    n.id === notifId ? {...n, read: true} : n       │
│     │  )                                                    │
│     └─ updateNotificationUI()  (update UI)                │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ RESULT:                                                      │
│  ✅ If task still accepted: Redirect to poster-live-tracking │
│  ❌ If task marked undone: Error message, no redirect        │
│  → Notification marked as read either way                    │
└──────────────────────────────────────────────────────────────┘
```

---

## Flow 3: Helper Location Sharing (Real-Time)

```
┌──────────────────────────────────────────────────────────────┐
│ Helper Opens task-in-progress.html?task=123                  │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ Page Load → window.addEventListener('load', ...)             │
│  ├─ loadTaskDetails()  [task-in-progress.html#L528]         │
│  │  └─ Get currentTask from localStorage                    │
│  ├─ initializeMap()    [task-in-progress.html#L700]         │
│  │  ├─ L.map('map') → Create Leaflet map                   │
│  │  ├─ Add OpenStreetMap tiles                              │
│  │  ├─ Add red marker at task location                     │
│  │  └─ displayLocationInfo()                                │
│  └─ startLiveLocationSharing()  [task-in-progress.html#L880]│
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ startLiveLocationSharing() [task-in-progress.html#L880]      │
│  ├─ Check: browser supports geolocation              [#881] │
│  ├─ Check: token exists                              [#882] │
│  ├─ Check: task ID exists                            [#883] │
│  │                                                           │
│  ├─ navigator.geolocation.watchPosition(              [#900]│
│  │   onSuccess,   // Position callback                     │
│  │   onError,     // Error callback                        │
│  │   options      // enableHighAccuracy, timeout, etc      │
│  │ )                                                        │
│  │                                                           │
│  ├─ Options: [#961]                                         │
│  │  ├─ enableHighAccuracy: true     (use GPS, not WiFi)    │
│  │  ├─ maximumAge: 0                 (don't use cached)    │
│  │  └─ timeout: 15000                (15 sec max wait)     │
│  │                                                           │
│  └─ locationWatchId assigned         [#900]                │
│     (ID used later to stop watching)                        │
│                                                               │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ GPS POSITION CALLBACK (repeats every GPS update)             │
│ onSuccess: function(position) [task-in-progress.html#L902]   │
│                                                               │
│ THROTTLE CHECK:                                              │
│  ├─ const now = Date.now()                       [#903]     │
│  ├─ if (now - lastLocationSentAt < 5000) return  [#905]    │
│  │  (Don't send more than once per 5 seconds)              │
│  │  → Skip to next GPS update                              │
│  └─ lastLocationSentAt = now                      [#906]    │
│                                                               │
│ EXTRACT COORDINATES:                                        │
│  ├─ const coords = {                              [#908]    │
│  │   lat: position.coords.latitude,                        │
│  │   lng: position.coords.longitude,                       │
│  │   accuracy: position.coords.accuracy,                   │
│  │   heading: position.coords.heading,                     │
│  │   speed: position.coords.speed                          │
│  │ }                                                        │
│                                                               │
│ LOG & SEND:                                                 │
│  ├─ console.log('📡 Location: ...') [#915]                 │
│  └─ pushLiveLocation(coords)  [#916]                       │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ pushLiveLocation(location) [task-in-progress.html#L919]      │
│                                                               │
│ UPDATE LOCAL MAP:                                           │
│  ├─ if (map) {                                   [#923]     │
│  │  ├─ Remove old userMarker if exists  [#926]           │
│  │  ├─ Create blue marker at new coords [#930]           │
│  │  │  └─ L.marker([lat, lng], { icon... }).addTo(map)   │
│  │  ├─ userMarker.bindPopup(...)       [#944]            │
│  │  ├─ Calculate center between task & helper            │
│  │  └─ map.setView([centerLat, centerLng], 14)  [#950]   │
│  └─ }                                                       │
│                                                               │
│ SEND TO BACKEND:                                            │
│  └─ fetch(API_URL + '/tracking/update-location', {         │
│      method: 'POST',                              [#953]    │
│      headers: {...},                                        │
│      body: JSON.stringify({                       [#959]    │
│        taskId: currentTask.id,                              │
│        location: location                                  │
│      })                                                     │
│  })                                                          │
│   .catch(err => console.warn(...))                          │
│                                                               │
│ Repeat: Every ~5 seconds if location changes               │
│ (or on every GPS update, whichever is more frequent)       │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ BACKEND: POST /api/tracking/update-location [server.py#2036] │
│                                                               │
│ PARSE REQUEST:                                              │
│  ├─ task_id = request.json['taskId']     [#2041]          │
│  ├─ location = request.json['location']   [#2042]          │
│  └─ Validate both provided              [#2044]            │
│                                                               │
│ VERIFY AUTHORIZATION:                                       │
│  ├─ Query tasks WHERE id = task_id      [#2049]           │
│  ├─ Check user is posted_by OR accepted_by [#2053]       │
│  └─ Return 403 if not authorized                          │
│                                                               │
│ DEACTIVATE OLD LOCATIONS:                                   │
│  └─ UPDATE location_tracking            [#2058]            │
│     SET is_active = FALSE                                   │
│     WHERE task_id = task_id AND user_id = user_id         │
│     (Only one active location per task per user)           │
│                                                               │
│ INSERT NEW LOCATION:                                        │
│  └─ INSERT INTO location_tracking (       [#2064]          │
│      task_id, user_id, user_type,                         │
│      latitude, longitude, accuracy, heading, speed,        │
│      recorded_at, is_active                               │
│     ) VALUES (...)                                         │
│     ├─ recorded_at = DateTime.now(UTC)                     │
│     └─ is_active = TRUE                                    │
│                                                               │
│ RETURN 200 OK:                                              │
│  └─ { "success": true, "message": "Location updated" }    │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ GPS ERROR CALLBACK (if GPS unavailable) [#925]              │
│ onError: function(error)                                     │
│                                                               │
│ ERROR CODES:                                                │
│  ├─ Code 1: Permission Denied                              │
│  │  └─ User denied location access                         │
│  │  └─ console.warn + show user prompt                     │
│  ├─ Code 2: Position Unavailable                           │
│  │  └─ GPS signal unavailable                              │
│  │  └─ Try again later                                     │
│  └─ Code 3: Timeout (15 seconds)                           │
│     └─ GPS took too long to get fix                        │
│     └─ Retry location sharing           [#938]             │
│     └─ setTimeout(startLiveLocationSharing, 10000)         │
│        (Retry after 10 seconds)                            │
│                                                               │
│ All errors logged to console for debugging                 │
└──────────────────────────────────────────────────────────────┘
```

---

## Flow 4: Poster Views Helper Location (Real-Time Polling)

```
┌──────────────────────────────────────────────────────────────┐
│ Poster Navigates to poster-live-tracking.html?task=123        │
│ (From auto-redirect OR manual button click)                  │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ Page Load → Initialize                                       │
│  ├─ Load task details (task ID from URL params)            │
│  ├─ Initialize Leaflet map                                  │
│  ├─ Add task location marker (red)                         │
│  └─ START POLLING FOR HELPER LOCATION                      │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ POLLING LOOP (repeats every 3 seconds)                       │
│                                                               │
│ setInterval(() => {                   [poster-live-tracking] │
│                                                               │
│  ├─ fetch(`/api/tracking/${taskId}/location`, {            │
│  │   headers: {                                              │
│  │     'Authorization': `Bearer ${token}`                   │
│  │   }                                                       │
│  │ })                                                        │
│  │  .then(res => res.json())                                │
│  │  .then(data => {                                         │
│  │                                                           │
│  │    IF data.location exists:                             │
│  │     ├─ updateHelperMarker(data.location)                │
│  │     │  └─ Remove old marker [Line 150]                  │
│  │     │  └─ Create blue marker at [lat, lng] [L152]       │
│  │     │  └─ map.setView([lat, lng], 14) [L160]           │
│  │     │                                                    │
│  │     ├─ updateETADisplay(data.eta, data.distance)        │
│  │     │  └─ DOM: #eta text = data.eta                    │
│  │     │  └─ DOM: #distance text = data.distance           │
│  │     │  └─ DOM: #lastUpdated = current time              │
│  │     │                                                    │
│  │     └─ Console: "📍 Helper location: ..."               │
│  │                                                           │
│  │    ELSE:                                                 │
│  │     ├─ data.status === 'completed'                     │
│  │     │  └─ Show "Task completed!" message                │
│  │     ├─ data.status === 'waiting'                       │
│  │     │  └─ Show "Waiting for helper to start"           │
│  │     └─ data.status === 'no_location'                   │
│  │        └─ Show "Location not available yet"            │
│  │                                                           │
│  │  })                                                       │
│  │  .catch(err => console.error('Fetch error:', err))      │
│  │                                                           │
│  }, 3000);  // ← Every 3 seconds                           │
│                                                               │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ BACKEND: GET /api/tracking/{taskId}/location [server.py#1950]│
│                                                               │
│ AUTHORIZATION:                                              │
│  ├─ Get task WHERE id = task_id        [#1953]             │
│  └─ Verify user is poster OR helper    [#1959]             │
│     Return 403 if not authorized                            │
│                                                               │
│ TASK STATUS CHECKS:                                         │
│  ├─ if status === 'completed':         [#1963]             │
│  │  └─ Return { status: 'completed', message: '...' }      │
│  ├─ if not accepted_by:                [#1971]             │
│  │  └─ Return { status: 'waiting', message: '...' }        │
│  └─ (continue to fetch location)                           │
│                                                               │
│ FETCH HELPER LOCATION:                                      │
│  └─ SELECT FROM location_tracking      [#1982]             │
│     WHERE task_id = task_id                                │
│     AND user_id = helper_id                                │
│     AND is_active = TRUE                                    │
│     ORDER BY recorded_at DESC LIMIT 1                      │
│                                                               │
│     If location not found:              [#1990]             │
│      └─ Return { status: 'no_location', message: '...' }   │
│                                                               │
│ CALCULATE ETA & DISTANCE:                                   │
│  ├─ Use Haversine formula          [#1999-2008]            │
│  │  ├─ Calc distance: current_loc to task_location        │
│  │  ├─ Assume avg speed 20 km/h (city)                    │
│  │  ├─ eta_minutes = distance / 20 * 60                   │
│  │  └─ distance_text = "X.X km" or "Arriving"             │
│  │                                                           │
│  └─ Return formatted values                                 │
│                                                               │
│ RETURN 200 OK:                                              │
│  └─ {                                                        │
│      "success": true,                                       │
│      "location": {                                          │
│        "lat": 28.6139,                                     │
│        "lng": 77.2090,                                     │
│        "accuracy": 10.5,       // meters                  │
│        "heading": 45,          // degrees                 │
│        "speed": 5.2,           // m/s                     │
│        "timestamp": "2026-03-22T10:30:45Z"                │
│      },                                                     │
│      "eta": "12 mins",                                     │
│      "distance": "2.5 km"                                  │
│    }                                                        │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ FRONTEND: Response Processed (repeats every 3 seconds)       │
│                                                               │
│ LIVE MAP UPDATES:                                           │
│  ├─ Blue helper marker moves to latest coordinates         │
│  ├─ ETA countdown updates                                   │
│  ├─ Distance recalculated                                  │
│  └─ Last update timestamp shown                            │
│                                                               │
│ CONTINUOUS: Until task marked completed OR helper withdrawn │
│ THEN: Stop polling (cancel interval), show final status      │
└──────────────────────────────────────────────────────────────┘
```

---

## Flow 5: Helper Marks Task Undone (Withdraw)

```
┌──────────────────────────────────────────────────────────────┐
│ Helper on task-in-progress.html clicks "Mark Task Undone"    │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ markTaskUndone() [task-in-progress.html#L710]               │
│  ├─ Confirm: "Are you sure?"                                │
│  └─ if (!confirm) return;  (User cancels)                  │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ POST /api/tasks/{taskId}/undo-accept [task-in-progress.html] │
│  ├─ Payload: { /* empty or with reason */ }               │
│  └─ Headers: Authorization Bearer token                     │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ BACKEND: /api/tasks/{taskId}/undo-accept [server.py#1261]  │
│                                                               │
│ VERIFY:                                                      │
│  ├─ SELECT FROM tasks WHERE id = task_id         [#1278]   │
│  ├─ Check: accepted_by = current_user            [#1280]   │
│  ├─ Check: status = 'accepted'                   [#1280]   │
│  └─ If checks fail: Return 404                            │
│                                                               │
│ REVERT TASK:                                                │
│  ├─ UPDATE tasks                                 [#1293]   │
│  │  SET status = 'active'       (Back to available)        │
│  │  accepted_by = NULL          (No helper)                │
│  │  accepted_at = NULL                                     │
│  │  WHERE id = task_id                                     │
│  │                                                           │
│  └─ COMMIT  [#1294]  ← CRITICAL!                          │
│     (Must commit to persist change)                        │
│                                                               │
│ NOTIFY POSTER:                                              │
│  └─ INSERT INTO notifications      [#1309]                │
│     title = '⚠️ Helper Withdrew'                          │
│     message = '{name} withdrew from your task'           │
│     user_id = task['posted_by']  (Poster's ID)           │
│     status = 'unread'                                     │
│                                                               │
│ NOTIFY HELPER:                                              │
│  └─ INSERT INTO notifications      [#1320]                │
│     title = '✅ Task Unmarked'                             │
│     message = 'You have withdrawn from the task'          │
│     user_id = current_user  (Helper's ID)                 │
│     status = 'unread'                                     │
│                                                               │
│ COMMIT NOTIFICATIONS  [#1333]  ← CRITICAL!                │
│  └─ Both notifications saved to DB                         │
│                                                               │
│ RETURN 200 OK:                                              │
│  └─ { "success": true, "message": "Task marked as undone" }│
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ FRONTEND: Response Received                                  │
│                                                               │
│ STOP LOCATION SHARING:                                       │
│  ├─ stopLiveLocationSharing()   [task-in-progress.html#L1005]│
│  │  ├─ navigator.geolocation.clearWatch(watchId)          │
│  │  ├─ Remove blue marker from map                         │
│  │  └─ POST /api/tracking/stop/{taskId}  (cleanup)        │
│  │                                                           │
│  ├─ clearInterval(timerInterval)  (Stop timer)             │
│  │                                                           │
│  ├─ Update localStorage  [#O748]                           │
│  │  └─ Remove task from currentUser.acceptedTasks[]       │
│  │  └─ localStorage.setItem('taskearn_user', ...)         │
│  │                                                           │
│  └─ alert('✅ Task marked as undone.')                     │
│                                                               │
│ REDIRECT TO DASHBOARD:  [#762]                             │
│  └─ window.location.href = 'index.html'                    │
│     (Main dashboard, not specific tab to avoid loops)      │
└────────────────────────┬─────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ POSTER EFFECTS:                                              │
│                                                               │
│ 1. Task back in Active List:                                │
│   └─ On poster's refresh, task appears in "Available Tasks" │
│                                                               │
│ 2. Auto-Redirect PREVENTS Second Redirect:                  │
│   └─ If poster still on dashboard                          │
│   └─ 'Track Helper' notification still unread              │
│                                                               │
│   But autoRedirectToAcceptedTaskTracking checks:           │
│    ├─ Task in myPostedTasks? YES (still accepted in memory)│
│    ├─ Task in tasks (active)? YES ← NEW!                  │
│    └─ shouldRedirect = YES && !YES = FALSE                │
│       (Blocks redirect because task back in active)        │
│                                                               │
│   Alternative check marks notification as read:            │
│   └─ cleanupStaleTrackingNotifications()  [app.js#L867]   │
│      └─ Finds notifications for tasks no longer accepted   │
│      └─ Marks them as read (removes red dot)              │
│                                                               │
│ 3. Manual Button Click Shows Error:                         │
│   └─ If poster tries "Track Helper" button                │
│   └─ handleNotificationAction() checks same conditions     │
│   └─ Shows: "❌ This task is no longer being tracked"     │
│      (because task back in active list)                    │
└──────────────────────────────────────────────────────────────┘
```

---

## Data Flow Summary

### Database Tables Involved

```
┌─────────────────────────────────────┐
│ USERS TABLE                         │
│ ├─ id (PK)                          │
│ ├─ name, phone, email               │
│ ├─ role (poster|helper)             │
│ └─ rating, tasks_completed, etc     │
└─────────────────────────────────────┘
           ▲         ▲
           │         │
           │         └─ Get helper/poster details
           │
    
┌─────────────────────────────────────┐
│ TASKS TABLE                         │
│ ├─ id (PK)                          │
│ ├─ title, description, category     │
│ ├─ posted_by (FK → users.id)        │
│ ├─ accepted_by (FK → users.id)      │
│ ├─ location_lat, location_lng       │
│ ├─ location_address                 │
│ ├─ price, service_charge            │
│ ├─ status ('active'|'accepted'...) │
│ ├─ posted_at, accepted_at           │
│ ├─ completed_at, paid_at            │
│ └─ expires_at                       │
└─────────────────────────────────────┘
           ▲
           │ Helper location endpoint checks status here
           │ 'completed' → Stop tracking
           │ !accepted_by → Show waiting
           │ 'active' again → Task withdrawn
           └─ Update status to 'accepted' when helper accepts

┌─────────────────────────────────────┐
│ NOTIFICATIONS TABLE                 │
│ ├─ id (PK)                          │
│ ├─ user_id (FK → users.id)          │
│ ├─ task_id (FK → tasks.id)          │
│ ├─ notification_type                │
│ ├─ title, message                   │
│ ├─ data (JSON string)               │
│ │  └─ For tracking: type, url, etc  │
│ ├─ status ('unread'|'read')         │
│ └─ created_at                       │
└─────────────────────────────────────┘
           ▲
           │ Frontend syncs & checks unread status
           │ Parses data field as JSON
           └─ Renders action buttons

┌─────────────────────────────────────┐
│ LOCATION_TRACKING TABLE (★ CRITICAL)│
│ ├─ id (PK)                          │
│ ├─ task_id (FK → tasks.id)          │
│ ├─ user_id (FK → users.id)          │
│ ├─ user_type ('helper'|'poster')    │
│ ├─ latitude, longitude              │
│ ├─ accuracy (in meters)             │
│ ├─ heading, speed                   │
│ ├─ recorded_at (timestamp)          │
│ ├─ is_active (1|0)                  │
│ └─ created_at, updated_at           │
└─────────────────────────────────────┘
           ▲
           │ Helper INSERTS (every ~5 sec)
           │ Poster FETCHES (every ~3 sec)
           │ Multiple old records deactivated
           └─ Only latest is_active=1 used
```

