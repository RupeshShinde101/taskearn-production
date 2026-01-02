# 🗺️ TaskEarn Live Tracking - Production Setup Guide

## Overview
Real-time GPS tracking system for TaskEarn - a production-ready multi-user service platform similar to Blinkit/Zomato.

---

## 1. Get Your Mapbox Access Token (FREE)

1. Go to [Mapbox Sign Up](https://account.mapbox.com/auth/signup/)
2. Create a free account
3. Navigate to [Access Tokens](https://account.mapbox.com/access-tokens/)
4. Copy your **Default public token** or create a new one

### Free Tier Includes:
- ✅ 50,000 free map loads/month
- ✅ 100,000 free geocoding requests/month
- ✅ 100,000 free directions requests/month
- ✅ Route optimization

---

## 2. Configure Your Application

### Step 1: Update tracking.html
Open `tracking.html` and replace the placeholder token (around line 600):

```javascript
mapboxgl.accessToken = 'pk.eyJ1IjoieW91ci11c2VybmFtZSIsImEiOiJjbG...';
```

### Step 2: Update tracking.js
Open `tracking.js` and update the config:

```javascript
const TrackingConfig = {
    MAPBOX_TOKEN: 'pk.eyJ1IjoieW91ci11c2VybmFtZSIsImEiOiJjbG...',
    // ...
};
```

---

## 3. Backend API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/user/active-tracking` | GET | Get user's active tasks for tracking |
| `/api/tracking/<task_id>` | GET | Get full tracking info for a task |
| `/api/tracking/<task_id>/location` | GET | Get helper's current location |
| `/api/tracking/update-location` | POST | Update location (for helpers) |
| `/api/tracking/stop/<task_id>` | POST | Stop location sharing |
| `/api/tracking/history/<task_id>` | GET | Get location history |

---

## 4. Multi-User Roles

### Task Poster (Customer):
- Views helper's real-time location
- Sees ETA and distance
- Can optionally share location to help helper find them
- Can call/message helper

### Helper (Service Provider):
- Must share location when accepting a task
- Location auto-updates every 2-3 seconds
- Can mark task as completed from tracking page
- Customer can see their movement in real-time

---

## 5. Key Features

### Real-Time Tracking:
- 📍 Location updates every 3 seconds
- 🛣️ Route visualization using Mapbox Directions API
- ⏱️ Live ETA calculation based on actual route
- 📱 Mobile responsive design

### Multi-User Support:
- 👤 Role-based UI (poster vs helper)
- 🔒 Secure JWT authentication
- 🔐 Authorization checks on all endpoints
- 📊 Activity timeline

### Error Handling:
- 🔄 Auto-reconnect on connection loss
- ⚠️ User-friendly error messages
- 📍 Graceful handling of GPS permission denial

---

## 6. How to Use

### For Customers:
1. Post a task with location
2. Wait for helper to accept
3. Click "Track Task" button or go to Live Tracking page
4. Watch helper approach in real-time

### For Helpers:
1. Accept a task
2. Go to Live Tracking page
3. Location sharing starts automatically
4. Complete task when done

---

## 7. Production Deployment

### Backend (Railway/Render):
```bash
cd backend
pip install -r requirements.txt
python server.py
```

The `location_tracking` table is created automatically on first run.

### Frontend:
Just deploy static files. Update the API URL if needed:
```javascript
window.TASKEARN_API_URL = 'https://your-backend-url.com/api';
```

---

## 8. Security Considerations

- ✅ All tracking endpoints require authentication
- ✅ Users can only access their own task tracking
- ✅ Location data is marked inactive when sharing stops
- ✅ HTTPS required for geolocation API

---

## 9. Cost Estimation (Mapbox)

### Free Tier:
- First 50,000 map loads: FREE
- First 100,000 directions: FREE

### For 10,000 deliveries/month:
- Estimated cost: ~$50-100/month after free tier

---

## 10. Troubleshooting

| Issue | Solution |
|-------|----------|
| Map not loading | Check Mapbox token is valid |
| No location updates | Ensure HTTPS and location permission |
| "Not authorized" error | User must be poster or helper of the task |
| ETA showing "Calculating" | Helper hasn't shared location yet |

---

Happy Tracking! 🚀
