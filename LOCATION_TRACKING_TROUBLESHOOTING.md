# Location Tracking & Auto-Redirect: Troubleshooting Guide

## Quick Diagnosis Matrix

Pick your symptom below and follow the investigation steps.

---

## Symptom 1: Poster NOT Auto-Redirected to Tracking Page

### What Should Happen
1. Helper accepts task
2. Poster gets notification: "Task Accepted" with "Track Helper" button
3. ⚠️ **MISSING**: Automatic redirect to `poster-live-tracking.html?task={id}` after 400ms

### Investigation Steps

#### Step 1.1: Check Notification Created (Backend)
**Expected**: Backend creates notification with `action.type='tracking'`

File: [backend/server.py](backend/server.py#L844-L860)
```python
# When helper accepts task:
action_data = json.dumps({
    'type': 'tracking',
    'label': 'Track Helper',
    'taskId': task_id,
    'url': f'poster-live-tracking.html?task={task_id}'
})

cursor.execute('''
    INSERT INTO notifications (user_id, task_id, notification_type, title, message, status, data, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''', (
    task['posted_by'],  # Poster's user ID
    task_id,
    'task_accepted',
    'Task Accepted! 🎉',
    f'{helper_name} accepted your task...',
    'unread',  # ← Must be 'unread' for auto-redirect
    action_data,
    accepted_at
))
```

**Check**:
```sql
-- In your database:
SELECT id, user_id, notification_type, title, data, status 
FROM notifications 
WHERE task_id = 123 
AND notification_type = 'task_accepted' 
AND user_id = /* POSTER_ID */;

-- Look at the `data` column - should contain JSON:
-- {"type": "tracking", "label": "Track Helper", "taskId": 123, "url": "poster-live-tracking.html?task=123"}

-- Status must be: 'unread' (not 'read')
```

#### Step 1.2: Check Notification Synced to Frontend
**Expected**: Browser receives notification in response from `GET /api/notifications`

**On Dashboard (Console)**:
```javascript
// Check if notification synced properly
notifications.forEach(n => {
    if (n.notification_type === 'task_accepted') {
        console.log('✅ Found task_accepted notification:', {
            id: n.id,
            taskId: n.taskId,
            action: n.action,
            status: n.status,
            read: n.read
        });
    }
});
```

**Expected Output**:
```javascript
✅ Found task_accepted notification: {
    id: 12345,
    taskId: 123,
    action: {
        type: "tracking",
        label: "Track Helper",
        taskId: 123,
        url: "poster-live-tracking.html?task=123"
    },
    status: "unread",
    read: false
}
```

**If NOT found**:
- Notification didn't get synced from backend
- Check `syncNotificationsFromServer()` in [app.js](app.js#L770) - is it being called?
- Check browser Network tab for `GET /api/notifications` - is it 200 OK?

#### Step 1.3: Check Task State Arrays
**Expected**: Task exists in BOTH arrays with correct status

On Dashboard (Console):
```javascript
// Check posted tasks
const myTask = myPostedTasks.find(t => t.id === 123);
console.log('myPostedTasks entry:', myTask?.status);  // Should be 'accepted'

// Check active tasks
const inActive = tasks.find(t => t.id === 123 && t.status === 'active');
console.log('Task still in active list?', inActive ? 'YES ❌' : 'NO ✅');

// For auto-redirect to work:
// myPostedTasks must have status='accepted'
// AND task must NOT be in active list
```

**If Task Status Wrong**:
- Task was accepted but `myPostedTasks` not updated
- Call `refreshMyTasks()` manually to sync
- Check if `tasks/accept` endpoint updates are synced to localStorage

#### Step 1.4: Check Auto-Redirect Function Triggers
**Expected**: `autoRedirectToAcceptedTaskTracking()` is called with unread notifications

Add debug logging: [app.js#L827](app.js#L827)

```javascript
// IN BROWSER CONSOLE (paste this):
// Override the function with logging
const originalAutoRedirect = autoRedirectToAcceptedTaskTracking;
window.autoRedirectToAcceptedTaskTracking = function(notifList) {
    console.log('🔍 autoRedirectToAcceptedTaskTracking called with', notifList.length, 'notifications');
    
    const trackingNotifs = notifList.filter(n => n.action?.type === 'tracking');
    console.log('   Found tracking notifs:', trackingNotifs.length);
    
    trackingNotifs.forEach(n => {
        const taskRef = n.taskId || n.task_id || n.action?.taskId;
        const taskInPosted = myPostedTasks.find(t => t.id === taskRef && t.status === 'accepted');
        const taskNoLongerAccepted = tasks.find(t => t.id === taskRef && t.status === 'active');
        
        console.log(`   Task ${taskRef}:`, {
            inPosted: !!taskInPosted,
            inActive: !!taskNoLongerAccepted,
            unread: n.status === 'unread',
            hasUrl: !!n.action?.url,
            alreadyRedirected: sessionStorage.getItem(`taskearn_tracking_redirect_${currentUser.id}_${taskRef}`)
        });
    });
    
    return originalAutoRedirect.call(this, notifList);
};

// Now: syncNotificationsFromServer() and watch the logs
```

**Debugging Output Interpretation**:
- `inPosted: true` ✅ Task found in myPostedTasks
- `inActive: false` ✅ Task NOT in active list
- `unread: true` ✅ Notification is unread
- `hasUrl: true` ✅ Notification has tracking URL
- `alreadyRedirected: null` ✅ Not yet redirected (null is good)

**If any are false**: That's your blocker!

#### Step 1.5: Check SessionStorage Redirect Flag
**Expected**: Redirect happens once, flag prevents repeats

```javascript
// In console:
sessionStorage.getItem(`taskearn_tracking_redirect_${currentUser.id}_123`);
// Should be null before first redirect
// Should be '1' after redirect
```

---

## Symptom 2: Helper Location Not Showing on Poster's Map

### What Should Happen
1. Helper on `task-in-progress.html` starts location sharing
2. Poster on `poster-live-tracking.html` sees blue helper marker on map
3. ⚠️ **MISSING**: Marker never appears OR stuck at default location

### Investigation Steps

#### Step 2.1: Check Helper's Location Permission
**On task-in-progress.html (Console)**:
```javascript
// Test if geolocation API works
navigator.geolocation.getCurrentPosition(
    (position) => {
        console.log('✅ GPS Permission OK:', {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            accuracy: position.coords.accuracy
        });
    },
    (error) => {
        console.error('❌ GPS Permission DENIED:', error.message);
        console.log('Error code:', error.code);
        // 1 = Permission denied
        // 2 = Position unavailable  
        // 3 = Timeout
    }
);
```

**If Error Code 1 (Permission Denied)**:
- Chrome/Firefox: Show browser location prompt
  - Click address bar lock icon → Site settings → Reset permissions
  - Reload page, allow location access
- On HTTPS only: If using HTTP, location will fail
  - Must be either HTTPS or localhost

#### Step 2.2: Check Location is Being Sent
**On task-in-progress.html**:

Watch Network tab (DevTools → Network tab):
1. Open task-in-progress.html
2. Watch for POST requests to `/api/tracking/update-location`
3. Should see requests every 5 seconds

**If you see the requests**:
```javascript
// Check payload in Network tab
POST /api/tracking/update-location
{
    "taskId": 123,
    "location": {
        "lat": 28.6139,
        "lng": 77.2090,
        "accuracy": 10.5
    }
}
```

**If NOT sending**:
- ```javascript
  // Check if locationWatchId is set (console):
  console.log('locationWatchId:', locationWatchId);  // Should be a number, not null
  ```
  - If null, `startLiveLocationSharing()` didn't run
  - Check: Is task ID loaded correctly?
  ```javascript
  console.log('currentTask:', currentTask);
  console.log('token:', localStorage.getItem('taskearn_token'));
  ```

#### Step 2.3: Check Location Data Stored in Database
**In Database**:
```sql
-- Check location_tracking table
SELECT id, task_id, user_id, latitude, longitude, accuracy, recorded_at, is_active
FROM location_tracking
WHERE task_id = 123
ORDER BY recorded_at DESC
LIMIT 10;
```

**Expected**: Multiple rows with different timestamps (every 5 seconds)

**If rows are empty or old**:
- Location POST endpoint not receiving data → Check network error
- Location POST endpoint failing → Check backend logs
- Endpoint not inserting → DB permission issue

#### Step 2.4: Check Poster is Fetching Location
**On poster-live-tracking.html (Console)**:

Watch Network tab:
1. Open poster-live-tracking.html
2. Should see GET requests to `/api/tracking/123/location`
3. Should happen every 3 seconds

**If requests are failing** (404, 500, etc.):
```javascript
// Manually test the endpoint
fetch('/api/tracking/123/location', {
    headers: {
        'Authorization': `Bearer ${localStorage.getItem('taskearn_token')}`
    }
})
.then(r => r.json())
.then(data => console.log('Response:', data));
```

**Expected Response**:
```json
{
    "success": true,
    "location": {
        "lat": 28.6139,
        "lng": 77.2090,
        "accuracy": 10.5,
        "timestamp": "2026-03-22T10:30:45Z"
    },
    "eta": "12 mins",
    "distance": "2.5 km"
}
```

**If getting 404**: Task ID not found or user not authorized
**If getting error about no location**: DB has no recent location data

#### Step 2.5: Check Map Rendering
**On poster-live-tracking.html**:

```javascript
// Check if map initialized
console.log('Map:', map);  // Should be a Leaflet map object, not undefined

// Check if helper marker exists
console.log('Helper marker:', helperMarker);  // Should exist, not null

// Check if marker has location
if (helperMarker) {
    console.log('Marker position:', helperMarker.getLatLng());
}
```

**If map is undefined**:
- Leaflet.js library didn't load
- Check Network tab: Did CDN script load successfully?
- Check console for errors in map initialization

**If marker is null**:
- Location data not being rendered
- Check if `updateHelperMarker()` function is called
- Add logging:
  ```javascript
  // Intercept the fetch
  const originalFetch = window.fetch;
  window.fetch = function(...args) {
      if (args[0].includes('/api/tracking')) {
          console.log('📡 Fetching location...');
      }
      return originalFetch.apply(this, args)
          .then(r => {
              if (args[0].includes('/location')) {
                  console.log('📍 Location received:', r.clone().json());
              }
              return r;
          });
  };
  ```

---

## Symptom 3: Map Shows But Coordinates Are Wrong

### What Should Happen
- Task location marker (red) at correct coordinates
- Helper marker (blue) updates to helper's GPS location
- Both markers visible on map

### Investigation Steps

#### Step 3.1: Check Task Location Loaded
**On task-in-progress.html**:

```javascript
console.log('Task location:', currentTask.location);
// Expected: { lat: 28.6139, lng: 77.2090, address: "..." }

// Check map is centered on this
console.log('Map center:', map.getCenter());
// Should be approximately [lat, lng]
```

#### Step 3.2: Check Helper Location Being Updated
**On poster-live-tracking.html**:

```javascript
// When you see helper marker on map:
console.log('Helper marker position:', helperMarker.getLatLng());
console.log('Task marker position:', taskMarker.getLatLng());

// Should be different locations!
```

**If both are the same coordinates**:
- Helper location not being fetched
- OR update function using wrong coordinates

#### Step 3.3: Check Location Accuracy
**On task-in-progress.html**:

```javascript
// GPS accuracy varies!
// ±100m is normal outdoors, worse indoors
console.log('Current accuracy:', position.coords.accuracy);  // In meters
```

**Bad accuracy causes**:
- Indoors (GPS signal blocked)
- Urban canyon (between tall buildings)
- GPS taking time to lock on
- Cached position used (wait 1-2 minutes for fresh)

---

## Symptom 4: "Cannot Redirect" Error When Clicking Tracking Button

### What Should Happen
- Poster clicks "Track Helper" button on notification
- Opens `poster-live-tracking.html` with helper location

### Error Message Shown
```
❌ This task is no longer being tracked. It may have been marked as undone.
```

### Root Cause & Fix

**The error comes from**: [app.js#1036-1041](app.js#L1036)

```javascript
if (actionType === 'tracking') {
    const taskInPosted = myPostedTasks.find(t => t.id === taskId && t.status === 'accepted');
    const taskNoLongerAccepted = tasks.find(t => t.id === taskId && t.status === 'active');
    
    if (!taskInPosted || taskNoLongerAccepted) {
        // ← This condition triggered
        showToast('❌ This task is no longer being tracked...');
        return;
    }
}
```

**Diagnosis**:

```javascript
// In console:
const taskId = 123;
const taskInPosted = myPostedTasks.find(t => t.id === taskId && t.status === 'accepted');
const taskNoLongerAccepted = tasks.find(t => t.id === taskId && t.status === 'active');

console.log('Task in myPostedTasks?', !!taskInPosted);
console.log('Task back in active list?', !!taskNoLongerAccepted);

if (!taskInPosted) {
    console.log('❌ Task not in myPostedTasks!');
    console.log('All posted tasks:', myPostedTasks.map(t => ({id: t.id, status: t.status})));
}
```

**Fixes**:
1. **If task not in myP​ostedTasks**: Call `refreshMyTasks()` to reload
2. **If task back in active**: Helper marked it as undone, task can't be tracked
3. **If both empty**: Data not synced, try refreshing page

---

## Symptom 5: Map is Blank/Gray (Tiles Not Loading)

### Investigation

**On poster-live-tracking.html or task-in-progress.html (Console)**:

```javascript
// Check Leaflet loaded
console.log('L (Leaflet):', typeof L);  // Should be 'object', not 'undefined'

// Check map exists
console.log('Map:', map);  // Should be map object

// Check if tile errors in console
// Look for failed CDN requests in Network tab
```

**If Leaflet not loaded**:
- CDN script failed: Update script URL in HTML
- Try local copy: Download leaflet.js and use local path

**If tiles Not loading**:
- OpenStreetMap CDN blocked (check Network tab)
- CORS issue (if using proxy)
- Try fallback tile layer:
  ```javascript
  L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png').addTo(map);
  ```

---

## Symptom 6: GPS Stops Updating After 15 Seconds

### Root Cause
Geolocation timeout set to 15 seconds - if GPS doesn't get fix, it fails

**In [task-in-progress.html#967](task-in-progress.html#L967)**:
```javascript
navigator.geolocation.watchPosition(
    successCallback,
    errorCallback,
    {
        enableHighAccuracy: true,
        maximumAge: 0,
        timeout: 15000  // ← 15 second timeout
    }
);
```

**On timeout, errorCallback fires with error code 3**:
```javascript
if (error.code === 3) {
    console.log('GPS request timed out');
    // Auto-retry after 10 seconds
    setTimeout(startLiveLocationSharing, 10000);
}
```

**Why timeout happens**:
- Weak GPS signal (indoors)
- Slow to get first fix
- Location services disabled

**Fix**:
1. Move outdoors with clear sky view
2. Wait 30-60 seconds for GPS to get satellite lock
3. Try again - second time usually faster
4. If still failing: Check phone location services enabled

---

## Performance Check: Are Requests Too Frequent?

### Task-in-Progress (Helper)
**Location update frequency**: Every 5 seconds (throttled)

```javascript
// In pushLiveLocation()
const now = Date.now();
if (now - lastLocationSentAt < 5000) return;  // ← 5 second minimum
```

✅ Good - saves battery and API load

### Poster-Live-Tracking (Poster)
**Location fetch frequency**: Every 3 seconds (polling)

```javascript
// In poster-live-tracking.html
setInterval(() => {
    fetch(`/api/tracking/${taskId}/location`);
}, 3000);  // ← Every 3 seconds
```

⚠️ High frequency, but reasonable for live tracking

**Network impact**: 
- Helper: 12 requests/minute to `/api/tracking/update-location`
- Poster: 20 requests/minute from `/api/tracking/{id}/location`
- Total: ~30 API calls/minute for one tracked task

---

## Summary Checklist

### Before calling support:

- [ ] Task exists in `myPostedTasks` after helper accepts
- [ ] Notification has `action.type='tracking'` and `action.url`
- [ ] Browser console shows no JS errors
- [ ] GPS permission granted (Chrome → address bar lock icon)
- [ ] Using HTTPS or localhost (required for GPS)
- [ ] Database has `location_tracking` rows with recent timestamps
- [ ] Network tab shows POST to `/api/tracking/update-location` every 5s
- [ ] Network tab shows GET from `/api/tracking/{id}/location` every 3s
- [ ] Leaflet.js CDN loaded successfully (check Network tab)
- [ ] Map container `#map` has height > 0px

If all checked: Issue is likely in custom JS or edge case logic.

