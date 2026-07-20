import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static Future<LatLng?> getCurrentLocation() async {
    try {
      // 1. Check if location services are enabled on the device
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // 2. Check / request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      // 3. Return last-known position instantly if available and recent (<5 min)
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          final age = DateTime.now().difference(last.timestamp);
          if (age.inMinutes < 5) {
            return LatLng(last.latitude, last.longitude);
          }
        }
      } catch (_) {}

      // 4. High accuracy (GPS) — 15s
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        return LatLng(pos.latitude, pos.longitude);
      } catch (_) {}

      // 5. Medium accuracy (network + GPS) — 8s
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8),
        );
        return LatLng(pos.latitude, pos.longitude);
      } catch (_) {}

      // 6. Low accuracy (network only) — 5s
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 5),
        );
        return LatLng(pos.latitude, pos.longitude);
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }

  static Stream<Position> getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // metres
      ),
    );
  }

  static double distanceBetween(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
          a.latitude, a.longitude, b.latitude, b.longitude) /
        1000; // km
  }
}
