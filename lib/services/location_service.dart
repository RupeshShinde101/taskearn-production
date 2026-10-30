import 'dart:convert';
import 'package:http/http.dart' as http;
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

  /// Calculates accurate road driving distance (km) between two points,
  /// matching Google Maps routing via OSRM with an offline city winding factor fallback.
  static Future<double> calculateRoadDistance(LatLng a, LatLng b) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${a.longitude},${a.latitude};${b.longitude},${b.latitude}?overview=false',
      );
      final resp = await http.get(url, headers: {'User-Agent': 'Workmate4uApp/1.0'})
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final distMeters = (routes[0]['distance'] as num?)?.toDouble();
          if (distMeters != null && distMeters > 0) {
            return distMeters / 1000.0;
          }
        }
      }
    } catch (_) {}

    // Fallback: Straight-line distance multiplied by city road detour index (~1.26x)
    final straightKm = distanceBetween(a, b);
    return straightKm * 1.26;
  }
}
