/**
 * TaskEarn - Live GPS Tracking Module
 * Real-time location tracking using Mapbox
 * Production-ready multi-user service platform
 */

// ========================================
// CONFIGURATION
// ========================================

const TrackingConfig = {
    // LOCAL MODE - No external API
    // GPS tracking disabled
    
    POLL_INTERVAL: 3000,  // 3 seconds
    SEND_INTERVAL: 2000,    // 2 seconds
    
    GEO_OPTIONS: {
        enableHighAccuracy: true,
        maximumAge: 3000,
        timeout: 10000
    },
    
    MAP_DEFAULTS: {
        center: [77.2090, 28.6139], // Delhi, India
        zoom: 14,
        style: null // No map available
    },
    
    AVG_SPEED_CITY: 20,
    AVG_SPEED_HIGHWAY: 50
};

// ========================================
// TRACKING CLASS
// ========================================

class TaskEarnTracker {
    constructor(options = {}) {
        this.mapContainer = options.mapContainer || 'trackingMap';
        
        this.map = null;
        this.markers = {
            helper: null,
            pickup: null,
            destination: null,
            user: null
        };
        
        this.watchId = null;
        this.pollInterval = null;
        this.isTracking = false;
        this.isSharing = false;
        this.currentTaskId = null;
        this.userRole = null; // 'poster' or 'helper'
        
        // Callbacks
        this.onLocationUpdate = options.onLocationUpdate || (() => {});
        this.onETAUpdate = options.onETAUpdate || (() => {});
        this.onStatusChange = options.onStatusChange || (() => {});
        this.onError = options.onError || console.error;
        this.onConnected = options.onConnected || (() => {});
        this.onDisconnected = options.onDisconnected || (() => {});
    }

    // ========================================
    // MAP INITIALIZATION
    // ========================================

    initMap(center = null) {
        if (typeof mapboxgl === 'undefined') {
            this.onError('Mapbox GL JS not loaded. Please include Mapbox script.');
            return null;
        }

        mapboxgl.accessToken = TrackingConfig.MAPBOX_TOKEN;

        const mapCenter = center || TrackingConfig.MAP_DEFAULTS.center;

        this.map = new mapboxgl.Map({
            container: this.mapContainer,
            style: TrackingConfig.MAP_DEFAULTS.style,
            center: mapCenter,
            zoom: TrackingConfig.MAP_DEFAULTS.zoom
        });

        // Add navigation controls
        this.map.addControl(new mapboxgl.NavigationControl(), 'top-right');
        
        // Add geolocate control for user to find themselves
        this.map.addControl(
            new mapboxgl.GeolocateControl({
                positionOptions: { enableHighAccuracy: true },
                trackUserLocation: true,
                showUserHeading: true
            }),
            'top-right'
        );

        // Add scale control
        this.map.addControl(new mapboxgl.ScaleControl(), 'bottom-left');

        return this.map;
    }

    // ========================================
    // MARKER MANAGEMENT
    // ========================================

    createMarker(type, coordinates, popup = null) {
        const markerStyles = {
            helper: {
                className: 'delivery-marker',
                icon: 'fa-motorcycle',
                color: '#6366f1'
            },
            pickup: {
                className: 'pickup-marker',
                icon: 'fa-store',
                color: '#10b981'
            },
            destination: {
                className: 'destination-marker',
                icon: 'fa-flag-checkered',
                color: '#ef4444'
            },
            user: {
                className: 'user-marker',
                icon: 'fa-user',
                color: '#0ea5e9'
            }
        };

        const style = markerStyles[type] || markerStyles.helper;

        const el = document.createElement('div');
        el.className = style.className;
        el.innerHTML = `<i class="fas ${style.icon}"></i>`;
        el.style.cssText = `
            width: 40px;
            height: 40px;
            background: ${style.color};
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 16px;
            box-shadow: 0 4px 15px ${style.color}66;
            border: 3px solid white;
            cursor: pointer;
        `;

        const marker = new mapboxgl.Marker(el)
            .setLngLat(coordinates);

        if (popup) {
            marker.setPopup(new mapboxgl.Popup().setHTML(popup));
        }

        return marker;
    }

    setHelperMarker(coordinates, popupHtml = null) {
        if (this.markers.helper) {
            this.markers.helper.setLngLat(coordinates);
        } else {
            this.markers.helper = this.createMarker('helper', coordinates, popupHtml);
            this.markers.helper.addTo(this.map);
        }
    }

    setPickupMarker(coordinates, address) {
        if (this.markers.pickup) {
            this.markers.pickup.setLngLat(coordinates);
        } else {
            this.markers.pickup = this.createMarker('pickup', coordinates, 
                `<strong>Pickup</strong><br>${address}`);
            this.markers.pickup.addTo(this.map);
        }
    }

    setDestinationMarker(coordinates, address) {
        if (this.markers.destination) {
            this.markers.destination.setLngLat(coordinates);
        } else {
            this.markers.destination = this.createMarker('destination', coordinates,
                `<strong>Delivery</strong><br>${address}`);
            this.markers.destination.addTo(this.map);
        }
    }

    // ========================================
    // ROUTE DRAWING
    // ========================================

    async drawRoute(origin, destination, color = '#6366f1') {
        if (!origin || !destination) return null;

        const url = `https://api.mapbox.com/directions/v5/mapbox/driving/${origin[0]},${origin[1]};${destination[0]},${destination[1]}?geometries=geojson&overview=full&access_token=${mapboxgl.accessToken}`;

        try {
            const response = await fetch(url);
            const data = await response.json();

            if (!data.routes || data.routes.length === 0) return null;

            const route = data.routes[0];
            const routeGeometry = route.geometry;

            // Remove existing route
            if (this.map.getSource('route')) {
                this.map.removeLayer('route');
                this.map.removeSource('route');
            }

            // Add new route with gradient effect
            this.map.addSource('route', {
                type: 'geojson',
                data: {
                    type: 'Feature',
                    properties: {},
                    geometry: routeGeometry
                }
            });

            this.map.addLayer({
                id: 'route',
                type: 'line',
                source: 'route',
                layout: {
                    'line-join': 'round',
                    'line-cap': 'round'
                },
                paint: {
                    'line-color': color,
                    'line-width': 6,
                    'line-opacity': 0.85
                }
            });

            // Return route info with calculated ETA
            const distanceKm = route.distance / 1000;
            const durationMins = Math.round(route.duration / 60);

            return {
                distance: route.distance, // meters
                distanceKm: distanceKm,
                duration: route.duration, // seconds
                durationMins: durationMins,
                geometry: routeGeometry,
                eta: durationMins < 1 ? 'Arriving' : `${durationMins} mins`,
                distanceText: distanceKm < 1 ? `${Math.round(route.distance)} m` : `${distanceKm.toFixed(1)} km`
            };

        } catch (error) {
            this.onError('Failed to draw route: ' + error.message);
            return null;
        }
    }

    // ========================================
    // LIVE TRACKING (Polling for location updates)
    // ========================================

    async startTracking(taskId, role = 'poster') {
        this.currentTaskId = taskId;
        this.userRole = role;
        this.isTracking = true;

        // Start polling for location updates
        this.pollInterval = setInterval(() => {
            this.fetchHelperLocation(taskId);
        }, TrackingConfig.POLL_INTERVAL);

        // Initial fetch
        await this.fetchHelperLocation(taskId);
        this.onConnected();
    }

    stopTracking() {
        this.isTracking = false;
        
        if (this.pollInterval) {
            clearInterval(this.pollInterval);
            this.pollInterval = null;
        }

        this.onDisconnected();
    }

    async fetchHelperLocation(taskId) {
        const token = localStorage.getItem('taskearn_token');
        
        try {
            const response = await fetch(`${this.apiUrl}/tracking/${taskId}/location`, {
                headers: {
                    'Authorization': `Bearer ${token}`
                }
            });

            const data = await response.json();

            if (data.success) {
                // Check task status
                if (data.status === 'completed') {
                    this.onStatusChange('completed');
                    this.stopTracking();
                    return;
                }

                if (data.status === 'waiting') {
                    this.onStatusChange('waiting');
                    return;
                }

                if (data.status === 'no_location') {
                    this.onStatusChange('no_location');
                    return;
                }

                if (data.location) {
                    const coords = [data.location.lng, data.location.lat];
                    
                    // Update helper marker
                    this.setHelperMarker(coords);

                    // Update route if destination exists
                    if (this.markers.destination) {
                        const destCoords = this.markers.destination.getLngLat().toArray();
                        const routeInfo = await this.drawRoute(coords, destCoords);
                        
                        // Use route API ETA if available
                        if (routeInfo) {
                            this.onETAUpdate({
                                eta: routeInfo.eta,
                                distance: routeInfo.distanceText
                            });
                        }
                    }

                    // Callback with location data
                    this.onLocationUpdate(data.location);
                    
                    // Use server ETA if route ETA not available
                    if (data.eta) {
                        this.onETAUpdate({
                            eta: data.eta,
                            distance: data.distance
                        });
                    }
                }
            }

        } catch (error) {
            this.onError('Failed to fetch location: ' + error.message);
            this.onDisconnected();
        }
    }

    // ========================================
    // SHARE MY LOCATION (For Helpers)
    // ========================================

    startSharingLocation(taskId) {
        if (!navigator.geolocation) {
            this.onError('Geolocation not supported by this browser');
            return false;
        }

        if (!taskId) {
            this.onError('Task ID required for location sharing');
            return false;
        }

        this.isSharing = true;

        this.watchId = navigator.geolocation.watchPosition(
            async (position) => {
                const location = {
                    lat: position.coords.latitude,
                    lng: position.coords.longitude,
                    accuracy: position.coords.accuracy,
                    heading: position.coords.heading,
                    speed: position.coords.speed,
                    timestamp: new Date().toISOString()
                };

                // Update own marker
                this.setUserMarker([location.lng, location.lat]);

                // Send to server
                await this.sendLocationToServer(taskId, location);
            },
            (error) => {
                let message = 'Location error';
                switch (error.code) {
                    case error.PERMISSION_DENIED:
                        message = 'Location permission denied';
                        break;
                    case error.POSITION_UNAVAILABLE:
                        message = 'Location unavailable';
                        break;
                    case error.TIMEOUT:
                        message = 'Location request timeout';
                        break;
                }
                this.onError(message);
                this.isSharing = false;
            },
            TrackingConfig.GEO_OPTIONS
        );

        return true;
    }

    async sendLocationToServer(taskId, location) {
        const token = localStorage.getItem('taskearn_token');

        try {
            const response = await fetch(`${this.apiUrl}/tracking/update-location`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({
                    taskId: taskId,
                    location: location
                })
            });

            const data = await response.json();
            if (!data.success) {
                console.warn('Location update failed:', data.message);
            }
        } catch (error) {
            this.onError('Failed to send location: ' + error.message);
        }
    }

    stopSharingLocation(taskId = null) {
        if (this.watchId) {
            navigator.geolocation.clearWatch(this.watchId);
            this.watchId = null;
        }
        this.isSharing = false;

        // Notify server to stop tracking
        if (taskId) {
            const token = localStorage.getItem('taskearn_token');
            fetch(`${this.apiUrl}/tracking/stop/${taskId}`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${token}`
                }
            }).catch(console.error);
        }
    }

    setUserMarker(coords, popup = 'Your Location') {
        if (this.markers.user) {
            this.markers.user.setLngLat(coords);
        } else {
            const el = document.createElement('div');
            el.style.cssText = `
                width: 36px;
                height: 36px;
                background: #0ea5e9;
                border-radius: 50%;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
                font-size: 14px;
                box-shadow: 0 4px 15px rgba(14, 165, 233, 0.4);
                border: 3px solid white;
            `;
            el.innerHTML = '<i class="fas fa-user"></i>';

            this.markers.user = new mapboxgl.Marker(el)
                .setLngLat(coords)
                .setPopup(new mapboxgl.Popup().setText(popup))
                .addTo(this.map);
        }
    }

    // ========================================
    // UTILITIES
    // ========================================

    fitBoundsToMarkers() {
        const bounds = new mapboxgl.LngLatBounds();
        let hasMarkers = false;

        Object.values(this.markers).forEach(marker => {
            if (marker) {
                bounds.extend(marker.getLngLat());
                hasMarkers = true;
            }
        });

        if (hasMarkers) {
            this.map.fitBounds(bounds, { padding: 80 });
        }
    }

    centerOnHelper() {
        if (this.markers.helper) {
            this.map.flyTo({
                center: this.markers.helper.getLngLat(),
                zoom: 16
            });
        }
    }

    // Calculate distance between two points (Haversine formula)
    calculateDistance(lat1, lon1, lat2, lon2) {
        const R = 6371; // Earth's radius in km
        const dLat = this.deg2rad(lat2 - lat1);
        const dLon = this.deg2rad(lon2 - lon1);
        const a = 
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(this.deg2rad(lat1)) * Math.cos(this.deg2rad(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c; // Distance in km
    }

    deg2rad(deg) {
        return deg * (Math.PI / 180);
    }

    // Estimate ETA based on distance and average speed
    estimateETA(distanceKm, avgSpeedKmh = 20) {
        const hours = distanceKm / avgSpeedKmh;
        const minutes = Math.round(hours * 60);
        
        if (minutes < 1) return 'Arriving';
        if (minutes < 60) return `${minutes} mins`;
        
        const hrs = Math.floor(minutes / 60);
        const mins = minutes % 60;
        return `${hrs}h ${mins}m`;
    }

    // ========================================
    // CLEANUP
    // ========================================

    destroy() {
        this.stopTracking();
        this.stopSharingLocation(this.currentTaskId);

        Object.values(this.markers).forEach(marker => {
            if (marker) marker.remove();
        });

        if (this.map) {
            this.map.remove();
            this.map = null;
        }
    }
}

// ========================================
// EXPORT FOR GLOBAL USE
// ========================================

window.TaskEarnTracker = TaskEarnTracker;
window.TrackingConfig = TrackingConfig;

// ========================================
// HELPER FUNCTIONS FOR MULTI-USER PLATFORM
// ========================================

/**
 * Open tracking page for a specific task
 */
function trackTask(taskId) {
    if (!taskId) {
        console.error('Task ID required');
        return;
    }
    window.location.href = `tracking.html?task=${taskId}`;
}

/**
 * Check if user is logged in
 */
function isLoggedIn() {
    return !!localStorage.getItem('taskearn_token');
}

/**
 * Get current user ID from localStorage
 */
function getCurrentUserId() {
    try {
        const userStr = localStorage.getItem('taskearn_user');
        if (userStr) {
            const user = JSON.parse(userStr);
            return user.id || user.userId || user.user_id || null;
        }
    } catch (e) {
        console.error('Error getting user ID:', e);
    }
    return null;
}

/**
 * Check if user has location permissions
 */
async function checkLocationPermission() {
    if (!navigator.permissions) return 'prompt';
    
    try {
        const result = await navigator.permissions.query({ name: 'geolocation' });
        return result.state; // 'granted', 'denied', or 'prompt'
    } catch (e) {
        return 'prompt';
    }
}

/**
 * Request location permission with user-friendly handling
 */
function requestLocationAccess(callback) {
    if (!navigator.geolocation) {
        callback({ 
            success: false, 
            message: 'Geolocation not supported by your browser' 
        });
        return;
    }

    navigator.geolocation.getCurrentPosition(
        (position) => {
            callback({
                success: true,
                lat: position.coords.latitude,
                lng: position.coords.longitude,
                accuracy: position.coords.accuracy
            });
        },
        (error) => {
            let message = 'Unable to get your location.';
            switch (error.code) {
                case error.PERMISSION_DENIED:
                    message = 'Please allow location access to use live tracking.';
                    break;
                case error.POSITION_UNAVAILABLE:
                    message = 'Location information unavailable.';
                    break;
                case error.TIMEOUT:
                    message = 'Location request timed out.';
                    break;
            }
            callback({ success: false, message: message });
        },
        { enableHighAccuracy: true }
    );
}

/**
 * Format distance for display
 */
function formatDistance(meters) {
    if (meters < 1000) {
        return `${Math.round(meters)} m`;
    }
    return `${(meters / 1000).toFixed(1)} km`;
}

/**
 * Format duration for display
 */
function formatDuration(seconds) {
    const mins = Math.round(seconds / 60);
    if (mins < 1) return 'Arriving';
    if (mins < 60) return `${mins} mins`;
    const hrs = Math.floor(mins / 60);
    const remainMins = mins % 60;
    return `${hrs}h ${remainMins}m`;
}

/**
 * Get user's active tasks for tracking
 */
async function getActiveTrackingTasks() {
    const token = localStorage.getItem('taskearn_token');
    if (!token) return [];

    try {
        const response = await fetch(`${window.TASKEARN_API_URL}/user/active-tracking`, {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });

        const data = await response.json();
        return data.success ? data.tasks : [];
    } catch (error) {
        console.error('Error fetching active tasks:', error);
        return [];
    }
}

// Make functions globally available
window.trackTask = trackTask;
window.isLoggedIn = isLoggedIn;
window.getCurrentUserId = getCurrentUserId;
window.checkLocationPermission = checkLocationPermission;
window.requestLocationAccess = requestLocationAccess;
window.formatDistance = formatDistance;
window.formatDuration = formatDuration;
window.getActiveTrackingTasks = getActiveTrackingTasks;

console.log('🗺️ TaskEarn Tracking Module v2.0 - Production Ready');
