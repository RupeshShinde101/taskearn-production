import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A rich location suggestion result with coordinates, type, and icons.
class LocationSearchResult {
  final String title;
  final String subtitle;
  final double lat;
  final double lon;
  final String type; // 'transit', 'mall', 'hospital', 'residential', 'office', 'landmark', 'locality', 'general'

  const LocationSearchResult({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lon,
    this.type = 'general',
  });

  String get fullAddress =>
      subtitle.isEmpty ? title : '$title, $subtitle';

  LatLng toLatLng() => LatLng(lat, lon);

  IconData get icon {
    switch (type) {
      case 'transit':
        return Icons.directions_transit;
      case 'mall':
        return Icons.shopping_bag_outlined;
      case 'hospital':
        return Icons.local_hospital_outlined;
      case 'residential':
        return Icons.apartment_outlined;
      case 'office':
        return Icons.business_outlined;
      case 'landmark':
        return Icons.account_balance_outlined;
      case 'locality':
        return Icons.location_city_outlined;
      default:
        return Icons.place_outlined;
    }
  }

  Color get iconColor {
    switch (type) {
      case 'transit':
        return const Color(0xFF0284C7); // Sky blue
      case 'mall':
        return const Color(0xFFD97706); // Amber / orange
      case 'hospital':
        return const Color(0xFFDC2626); // Red
      case 'residential':
        return const Color(0xFF059669); // Emerald
      case 'office':
        return const Color(0xFF4F46E5); // Indigo
      case 'landmark':
        return const Color(0xFF9333EA); // Purple
      case 'locality':
        return const Color(0xFF2563EB); // Royal Blue
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }
}

/// Comprehensive multi-tier location search & autocomplete service:
/// Tier 1: Instant Curated Local Knowledge Base (Pune, PCMC, Maharashtra hubs)
/// Tier 2: Photon Geocoder (OSM-powered typeahead autocomplete with typo tolerance)
/// Tier 3: Nominatim (India-bounded OpenStreetMap forward geocoder)
/// Tier 4: Native Android / Google Play Services Geocoder fallback
class LocationSearchService {
  // Center of Pune
  static const LatLng defaultPuneCenter = LatLng(18.5204, 73.8567);

  /// Search for location suggestions matching [query].
  /// Returns top relevant results with zero delay for local matches + enriched online POIs.
  static Future<List<LocationSearchResult>> search(
    String query, {
    LatLng? userLocation,
    int limit = 7,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];

    // 1. Instant Curated Local Matches (<5ms)
    final curatedMatches = _searchCurated(q);

    // 2. Fetch Photon and/or Nominatim online suggestions
    final onlineMatches = await _fetchOnlineSuggestions(
      query.trim(),
      userLocation: userLocation ?? defaultPuneCenter,
      limit: limit,
    );

    // 3. Fallback: Native Device Geocoding if online is sparse
    List<LocationSearchResult> nativeMatches = [];
    if (curatedMatches.isEmpty && onlineMatches.isEmpty) {
      nativeMatches = await _fetchNativeGeocode(query.trim());
    }

    // 4. Merge and deduplicate by proximity (<250m) or identical title
    final combined = <LocationSearchResult>[];

    void addIfUnique(LocationSearchResult item) {
      for (final existing in combined) {
        if (existing.title.toLowerCase() == item.title.toLowerCase()) return;
        final d = _approxDistanceMeters(existing.lat, existing.lon, item.lat, item.lon);
        if (d < 250) return;
      }
      combined.add(item);
    }

    // Prioritize high-accuracy curated matches
    for (final c in curatedMatches) {
      addIfUnique(c);
      if (combined.length >= limit) return combined;
    }

    for (final o in onlineMatches) {
      addIfUnique(o);
      if (combined.length >= limit) return combined;
    }

    for (final n in nativeMatches) {
      addIfUnique(n);
      if (combined.length >= limit) return combined;
    }

    return combined;
  }

  /// Instant local curated search across hundreds of Pune / Maharashtra locations
  static List<LocationSearchResult> _searchCurated(String q) {
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return [];

    final matched = <_ScoredResult>[];

    for (final item in _curatedLocations) {
      int score = 0;
      final titleLower = item.title.toLowerCase();
      final subLower = item.subtitle.toLowerCase();
      final allKeys = [...item.keywords, titleLower, subLower];

      bool allTokensMatched = true;
      for (final t in tokens) {
        bool tokenFound = false;
        for (final k in allKeys) {
          if (k == t) {
            score += 10;
            tokenFound = true;
          } else if (k.startsWith(t)) {
            score += 6;
            tokenFound = true;
          } else if (k.contains(t)) {
            score += 3;
            tokenFound = true;
          }
        }
        if (!tokenFound) {
          allTokensMatched = false;
          break;
        }
      }

      if (allTokensMatched) {
        if (titleLower.startsWith(tokens.first)) score += 5;
        matched.add(_ScoredResult(item.toResult(), score));
      }
    }

    matched.sort((a, b) => b.score.compareTo(a.score));
    return matched.map((m) => m.result).take(6).toList();
  }

  /// Photon geocoder query (specifically optimized for search-as-you-type)
  static Future<List<LocationSearchResult>> _fetchOnlineSuggestions(
    String query, {
    required LatLng userLocation,
    int limit = 7,
  }) async {
    final results = <LocationSearchResult>[];

    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}'
        '&lat=${userLocation.latitude}&lon=${userLocation.longitude}&limit=$limit',
      );

      final resp = await http.get(uri, headers: {
        'User-Agent': 'Workmate4u/1.0 (com.workmate4u.workmate4u)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? [];

        for (final f in features) {
          final props = f['properties'] as Map<String, dynamic>? ?? {};
          final geom = f['geometry'] as Map<String, dynamic>? ?? {};
          final coords = geom['coordinates'] as List<dynamic>?;
          if (coords == null || coords.length < 2) continue;

          final lon = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();

          final name = (props['name'] as String?)?.trim() ??
              (props['street'] as String?)?.trim() ??
              '';
          if (name.isEmpty) continue;

          // Assemble subtitle
          final localityParts = <String>[];
          final street = props['street'] as String?;
          final district = (props['district'] ?? props['county'] ?? props['city']) as String?;
          final state = props['state'] as String?;

          if (street != null && street.isNotEmpty && street != name) {
            localityParts.add(street);
          }
          if (district != null && district.isNotEmpty) {
            localityParts.add(district);
          }
          if (state != null && state.isNotEmpty) {
            localityParts.add(state);
          }

          final subtitle = localityParts.join(', ');
          final osmVal = (props['osm_value'] as String?)?.toLowerCase() ?? '';
          final osmKey = (props['osm_key'] as String?)?.toLowerCase() ?? '';

          final type = _detectType(osmVal, osmKey, name);

          results.add(LocationSearchResult(
            title: name,
            subtitle: subtitle.isEmpty ? 'India' : subtitle,
            lat: lat,
            lon: lon,
            type: type,
          ));
        }
      }
    } catch (_) {}

    // If Photon failed or returned very few results, fallback to Nominatim with India bias
    if (results.length < 3) {
      try {
        final nomUri = Uri.https('nominatim.openstreetmap.org', '/search', {
          'q': query,
          'format': 'json',
          'limit': '5',
          'countrycodes': 'in',
          'viewbox': '73.5,18.8,74.2,18.3',
          'bounded': '0',
          'addressdetails': '1',
        });

        final nomResp = await http.get(nomUri, headers: {
          'User-Agent': 'Workmate4u/1.0 (com.workmate4u.workmate4u)',
          'Accept-Language': 'en',
        }).timeout(const Duration(seconds: 4));

        if (nomResp.statusCode == 200) {
          final items = jsonDecode(nomResp.body) as List<dynamic>;
          for (final it in items) {
            final m = it as Map<String, dynamic>;
            final dispName = (m['display_name'] as String?) ?? '';
            final lat = double.tryParse(m['lat']?.toString() ?? '');
            final lon = double.tryParse(m['lon']?.toString() ?? '');
            if (lat == null || lon == null || dispName.isEmpty) continue;

            final parts = dispName.split(',');
            final title = parts.first.trim();
            final subtitle = parts.skip(1).take(3).map((s) => s.trim()).join(', ');
            final type = (m['type'] as String?) ?? 'general';

            results.add(LocationSearchResult(
              title: title,
              subtitle: subtitle,
              lat: lat,
              lon: lon,
              type: _detectType(type, '', title),
            ));
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// Device Native Google Play Services Geocoder fallback
  static Future<List<LocationSearchResult>> _fetchNativeGeocode(String query) async {
    final list = <LocationSearchResult>[];
    try {
      final locs = await locationFromAddress('$query, Pune, Maharashtra, India')
          .timeout(const Duration(seconds: 3));
      for (final l in locs.take(2)) {
        list.add(LocationSearchResult(
          title: query,
          subtitle: 'Pune, Maharashtra',
          lat: l.latitude,
          lon: l.longitude,
          type: 'general',
        ));
      }
    } catch (_) {}
    return list;
  }

  static String _detectType(String osmVal, String osmKey, String name) {
    final lowerName = name.toLowerCase();

    if (osmVal.contains('station') ||
        osmVal.contains('subway') ||
        osmVal.contains('bus') ||
        osmVal.contains('airport') ||
        osmVal.contains('aerodrome') ||
        lowerName.contains('metro') ||
        lowerName.contains('railway') ||
        lowerName.contains('station') ||
        lowerName.contains('bus stand') ||
        lowerName.contains('airport')) {
      return 'transit';
    }
    if (osmVal.contains('mall') ||
        osmVal.contains('supermarket') ||
        osmVal.contains('shop') ||
        lowerName.contains('mall') ||
        lowerName.contains('marketcity') ||
        lowerName.contains('dmart') ||
        lowerName.contains('croma')) {
      return 'mall';
    }
    if (osmVal.contains('hospital') ||
        osmVal.contains('clinic') ||
        osmVal.contains('doctors') ||
        lowerName.contains('hospital') ||
        lowerName.contains('clinic')) {
      return 'hospital';
    }
    if (osmVal.contains('apartment') ||
        osmVal.contains('residential') ||
        lowerName.contains('society') ||
        lowerName.contains('apartments') ||
        lowerName.contains('residency') ||
        lowerName.contains('park town')) {
      return 'residential';
    }
    if (osmVal.contains('commercial') ||
        osmVal.contains('office') ||
        osmVal.contains('industrial') ||
        lowerName.contains('tech park') ||
        lowerName.contains('cybercity') ||
        lowerName.contains('eon') ||
        lowerName.contains('it park') ||
        lowerName.contains('infotech')) {
      return 'office';
    }
    if (osmVal.contains('attraction') ||
        osmVal.contains('monument') ||
        osmVal.contains('tourism') ||
        lowerName.contains('fort') ||
        lowerName.contains('wada') ||
        lowerName.contains('palace') ||
        lowerName.contains('temple')) {
      return 'landmark';
    }
    if (osmVal.contains('suburb') ||
        osmVal.contains('locality') ||
        osmVal.contains('neighbourhood') ||
        osmVal.contains('village') ||
        osmVal.contains('city')) {
      return 'locality';
    }
    return 'general';
  }

  static double _approxDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a)); // meters
  }

  // ── Curated Pune, PCMC & Maharashtra Database ───────────────────────────
  static final List<_CuratedLocation> _curatedLocations = [
    // ── Localities & Suburbs ──
    _CuratedLocation('Hinjewadi Phase 1', 'Rajiv Gandhi Infotech Park, Pune', 18.5913, 73.7389, 'office', ['hinjewadi', 'hinjawadi', 'phase 1', 'it park']),
    _CuratedLocation('Hinjewadi Phase 2', 'Rajiv Gandhi Infotech Park, Pune', 18.5880, 73.7120, 'office', ['hinjewadi', 'hinjawadi', 'phase 2', 'wipro']),
    _CuratedLocation('Hinjewadi Phase 3', 'Rajiv Gandhi Infotech Park, Pune', 18.5775, 73.6930, 'office', ['hinjewadi', 'hinjawadi', 'phase 3', 'tcs', 'techzone']),
    _CuratedLocation('Wakad', 'Pimpri-Chinchwad, Pune', 18.5987, 73.7660, 'locality', ['wakad', 'dange chowk', 'bhumkar', 'kaspate vasti']),
    _CuratedLocation('Baner', 'Pune, Maharashtra', 18.5590, 73.7868, 'locality', ['baner', 'baner road', 'pashan link road']),
    _CuratedLocation('Balewadi High Street', 'Balewadi, Pune', 18.5750, 73.7712, 'locality', ['balewadi', 'high street', 'stadium']),
    _CuratedLocation('Aundh', 'Pune, Maharashtra', 18.5602, 73.8031, 'locality', ['aundh', 'parihar chowk', 'iti road', 'bremen']),
    _CuratedLocation('Pashan', 'Pune, Maharashtra', 18.5385, 73.7929, 'locality', ['pashan', 'pashan lake', 'sus road']),
    _CuratedLocation('Bavdhan', 'Pune, Maharashtra', 18.5143, 73.7684, 'locality', ['bavdhan', 'chandani chowk', 'nda road']),
    _CuratedLocation('Kothrud', 'Paud Road, Pune', 18.5074, 73.8077, 'locality', ['kothrud', 'paud road', 'karve road', 'vanaz']),
    _CuratedLocation('Karve Nagar', 'Pune, Maharashtra', 18.4895, 73.8160, 'locality', ['karve nagar', 'hingne', 'cummins']),
    _CuratedLocation('Deccan Gymkhana', 'Pune, Maharashtra', 18.5167, 73.8417, 'locality', ['deccan', 'gymkhana', 'goodluck chowk']),
    _CuratedLocation('FC Road', 'Fergusson College Road, Shivajinagar, Pune', 18.5221, 73.8412, 'locality', ['fc road', 'fergusson', 'gokhale path']),
    _CuratedLocation('JM Road', 'Jangali Maharaj Road, Shivajinagar, Pune', 18.5240, 73.8475, 'locality', ['jm road', 'jangali maharaj']),
    _CuratedLocation('Shivaji Nagar', 'Pune, Maharashtra', 18.5314, 73.8446, 'locality', ['shivajinagar', 'shivaji nagar', 'coep', 'simla office']),
    _CuratedLocation('Pune Camp', 'Pune Cantonment, MG Road, Pune', 18.5140, 73.8780, 'locality', ['camp', 'mg road', 'cantonment', 'east street']),
    _CuratedLocation('Koregaon Park (KP)', 'Pune, Maharashtra', 18.5362, 73.8940, 'locality', ['koregaon park', 'kp', 'north main road', 'osho']),
    _CuratedLocation('Kalyani Nagar', 'Pune, Maharashtra', 18.5477, 73.9034, 'locality', ['kalyani nagar', 'joggers park', 'cerebrum']),
    _CuratedLocation('Viman Nagar', 'Pune, Maharashtra', 18.5679, 73.9143, 'locality', ['viman nagar', 'symbiosis', 'clover park']),
    _CuratedLocation('Kharadi', 'Pune, Maharashtra', 18.5516, 73.9349, 'locality', ['kharadi', 'eon', 'wtc', 'world trade center']),
    _CuratedLocation('Magarpatta City', 'Hadapsar, Pune', 18.5089, 73.9260, 'locality', ['magarpatta', 'cybercity', 'destination centre']),
    _CuratedLocation('Hadapsar', 'Pune, Maharashtra', 18.5089, 73.9260, 'locality', ['hadapsar', 'gadital', 'saswad road']),
    _CuratedLocation('Fatima Nagar', 'Wanowrie, Pune', 18.5030, 73.8990, 'locality', ['fatima nagar', 'wanowrie']),
    _CuratedLocation('NIBM Road', 'Kondhwa, Pune', 18.4790, 73.8970, 'locality', ['nibm', 'nibm road', 'salunke vihar']),
    _CuratedLocation('Kondhwa', 'Pune, Maharashtra', 18.4746, 73.8860, 'locality', ['kondhwa', 'lullanagar', 'khadi machine']),
    _CuratedLocation('Undri', 'Pune, Maharashtra', 18.4550, 73.9090, 'locality', ['undri', 'pisoli', 'corinthian']),
    _CuratedLocation('Bibvewadi', 'Pune, Maharashtra', 18.4770, 73.8640, 'locality', ['bibvewadi', 'market yard', 'salisbury park']),
    _CuratedLocation('Katraj', 'Pune, Maharashtra', 18.4575, 73.8508, 'locality', ['katraj', 'snake park', 'bharati vidyapeeth']),
    _CuratedLocation('Ambegaon BK', 'Katraj, Pune', 18.4520, 73.8370, 'locality', ['ambegaon', 'dhankawadi']),
    _CuratedLocation('Sinhagad Road', 'Pune, Maharashtra', 18.4750, 73.8250, 'locality', ['sinhagad road', 'anand nagar', 'manik baug']),
    _CuratedLocation('Dhayari', 'Sinhagad Road, Pune', 18.4480, 73.8180, 'locality', ['dhayari', 'dhayari phata', 'nanded city']),
    _CuratedLocation('Warje', 'Pune, Maharashtra', 18.4816, 73.7963, 'locality', ['warje', 'warje malwadi', 'mai mangeshkar']),
    _CuratedLocation('Pimpri', 'PCMC, Pune', 18.6279, 73.8009, 'locality', ['pimpri', 'pcmc', 'finolex']),
    _CuratedLocation('Chinchwad', 'PCMC, Pune', 18.6298, 73.7997, 'locality', ['chinchwad', 'chaphekar chowk', 'elpro']),
    _CuratedLocation('Bhosari', 'MIDC, PCMC, Pune', 18.6247, 73.8468, 'locality', ['bhosari', 'midc', 'landewadi']),
    _CuratedLocation('Moshi', 'PCMC, Pune', 18.6750, 73.8436, 'locality', ['moshi', 'spine road', 'toll plaza']),
    _CuratedLocation('Nigdi', 'Pradhikaran, PCMC, Pune', 18.6548, 73.7684, 'locality', ['nigdi', 'pradhikaran', 'bhakti shakti']),
    _CuratedLocation('Akurdi', 'PCMC, Pune', 18.6493, 73.7707, 'locality', ['akurdi', 'railway station', 'dy patil']),
    _CuratedLocation('Ravet', 'PCMC, Pune', 18.6310, 73.7350, 'locality', ['ravet', 'brts', 'shinde vasti']),
    _CuratedLocation('Punawale', 'PCMC, Pune', 18.6250, 73.7380, 'locality', ['punawale', 'kate wasti']),
    _CuratedLocation('Tathawade', 'PCMC, Pune', 18.6180, 73.7480, 'locality', ['tathawade', 'jspm', 'dange chowk']),
    _CuratedLocation('Wagholi', 'Nagar Road, Pune', 18.5808, 73.9804, 'locality', ['wagholi', 'baif road', 'ivy estate']),
    _CuratedLocation('Lohegaon', 'Pune, Maharashtra', 18.5910, 73.9290, 'locality', ['lohegaon', 'dhanori', 'airport road']),
    _CuratedLocation('Dhanori', 'Pune, Maharashtra', 18.5820, 73.8960, 'locality', ['dhanori', 'tingre nagar', 'vishrantwadi']),
    _CuratedLocation('Vishrantwadi', 'Pune, Maharashtra', 18.5680, 73.8760, 'locality', ['vishrantwadi', 'alandi road']),
    _CuratedLocation('Yerwada', 'Pune, Maharashtra', 18.5520, 73.8820, 'locality', ['yerwada', 'shastri nagar', 'commerzone']),
    _CuratedLocation('Pimple Saudagar', 'PCMC, Pune', 18.5980, 73.7910, 'locality', ['pimple saudagar', 'kokane chowk', 'shivar garden']),
    _CuratedLocation('Pimple Nilakh', 'PCMC, Pune', 18.5810, 73.7840, 'locality', ['pimple nilakh', 'vishal nagar']),
    _CuratedLocation('Pimple Gurav', 'PCMC, Pune', 18.5870, 73.8180, 'locality', ['pimple gurav', 'kashid park']),
    _CuratedLocation('Thergaon', 'PCMC, Pune', 18.6140, 73.7760, 'locality', ['thergaon', 'dange chowk', 'aditya birla']),

    // ── IT Parks & Corporate Hubs ──
    _CuratedLocation('EON Free Zone IT Park', 'Kharadi, Pune', 18.5516, 73.9480, 'office', ['eon', 'kharadi', 'eon it park', 'free zone']),
    _CuratedLocation('World Trade Center (WTC)', 'Kharadi, Pune', 18.5535, 73.9430, 'office', ['wtc', 'world trade center', 'kharadi']),
    _CuratedLocation('Cybercity Magarpatta', 'Magarpatta City, Hadapsar, Pune', 18.5140, 73.9310, 'office', ['cybercity', 'magarpatta it park']),
    _CuratedLocation('SP Infocity', 'Saswad Road, Fursungi, Pune', 18.4830, 73.9630, 'office', ['sp infocity', 'fursungi', 'accenture']),
    _CuratedLocation('Panchshil Tech Park', 'Viman Nagar, Pune', 18.5610, 73.9110, 'office', ['panchshil tech park', 'viman nagar']),
    _CuratedLocation('Commerzone IT Park', 'Yerwada, Pune', 18.5620, 73.8740, 'office', ['commerzone', 'yerwada']),
    _CuratedLocation('ICC Trade Tower', 'Senapati Bapat Road, Shivajinagar, Pune', 18.5330, 73.8320, 'office', ['icc trade tower', 'sb road', 'marriott']),
    _CuratedLocation('Embassy TechZone', 'Hinjewadi Phase 2, Pune', 18.5880, 73.7120, 'office', ['embassy', 'techzone', 'hinjewadi phase 2']),
    _CuratedLocation('Quadron Business Park', 'Hinjewadi Phase 2, Pune', 18.5890, 73.7080, 'office', ['quadron', 'hinjewadi phase 2']),

    // ── Malls & Shopping Centers ──
    _CuratedLocation('Phoenix Marketcity', 'Viman Nagar Road, Pune', 18.5620, 73.9167, 'mall', ['phoenix', 'marketcity', 'viman nagar', 'mall']),
    _CuratedLocation('Amanora Mall', 'Hadapsar, Pune', 18.5178, 73.9440, 'mall', ['amanora', 'mall', 'hadapsar', 'town']),
    _CuratedLocation('Seasons Mall', 'Magarpatta City, Hadapsar, Pune', 18.5089, 73.9260, 'mall', ['seasons', 'mall', 'magarpatta']),
    _CuratedLocation('The Pavilion Mall', 'Senapati Bapat Road, Shivajinagar, Pune', 18.5340, 73.8310, 'mall', ['pavilion', 'mall', 'sb road', 'pvr']),
    _CuratedLocation('Westend Mall', 'Aundh, Pune', 18.5615, 73.8075, 'mall', ['westend', 'mall', 'aundh', 'cinepolis']),
    _CuratedLocation('Kumar Pacific Mall', 'Shankar Sheth Road, Swargate, Pune', 18.5020, 73.8710, 'mall', ['kumar pacific', 'mall', 'swargate']),
    _CuratedLocation('Elpro City Square', 'Chinchwad, Pune', 18.6320, 73.7930, 'mall', ['elpro', 'city square', 'chinchwad mall']),
    _CuratedLocation('SGS Mall', 'Camp, MG Road, Pune', 18.5140, 73.8780, 'mall', ['sgs mall', 'camp', 'mg road']),

    // ── Transit & Transport Hubs ──
    _CuratedLocation('Pune Railway Station', 'Station Road, Pune', 18.5289, 73.8744, 'transit', ['pune station', 'railway station', 'train']),
    _CuratedLocation('Shivajinagar Railway Station', 'Shivajinagar, Pune', 18.5310, 73.8500, 'transit', ['shivajinagar station', 'railway']),
    _CuratedLocation('Swargate ST Bus Stand', 'Swargate, Pune', 18.5018, 73.8636, 'transit', ['swargate', 'bus stand', 'st stand']),
    _CuratedLocation('Pune International Airport (PNQ)', 'Lohegaon, Pune', 18.5822, 73.9197, 'transit', ['pune airport', 'pnq', 'lohegaon airport']),
    _CuratedLocation('Civil Court Metro Station', 'Shivajinagar, Pune', 18.5290, 73.8560, 'transit', ['civil court metro', 'metro station']),
    _CuratedLocation('Ruby Hall Clinic Metro Station', 'Sassoon Road, Pune', 18.5330, 73.8770, 'transit', ['ruby hall metro', 'metro station']),
    _CuratedLocation('Vanaz Metro Station', 'Kothrud, Pune', 18.5040, 73.7990, 'transit', ['vanaz metro', 'kothrud metro']),
    _CuratedLocation('PCMC Metro Station', 'Pimpri, Pune', 18.6280, 73.8010, 'transit', ['pcmc metro', 'pimpri metro']),

    // ── Hospitals ──
    _CuratedLocation('Ruby Hall Clinic', '40 Sassoon Road, Pune', 18.5327, 73.8777, 'hospital', ['ruby hall', 'clinic', 'sassoon road', 'hospital']),
    _CuratedLocation('Jehangir Hospital', 'Near Pune Station, Sassoon Road, Pune', 18.5290, 73.8750, 'hospital', ['jehangir hospital', 'pune station']),
    _CuratedLocation('Deenanath Mangeshkar Hospital', 'Erandwane, Pune', 18.5010, 73.8320, 'hospital', ['deenanath', 'mangeshkar hospital', 'erandwane']),
    _CuratedLocation('Jupiter Hospital', 'Baner Road, Baner, Pune', 18.5600, 73.7850, 'hospital', ['jupiter hospital', 'baner']),
    _CuratedLocation('Sahyadri Super Speciality Hospital', 'Deccan Gymkhana, Pune', 18.5130, 73.8370, 'hospital', ['sahyadri hospital', 'deccan', 'karve road']),
    _CuratedLocation('Manipal Hospital', 'Kharadi, Pune', 18.5490, 73.9420, 'hospital', ['manipal hospital', 'kharadi', 'columbia asia']),
    _CuratedLocation('Aditya Birla Memorial Hospital', 'Thergaon, Chinchwad, Pune', 18.6180, 73.7740, 'hospital', ['aditya birla hospital', 'chinchwad', 'thergaon']),
    _CuratedLocation('Sancheti Hospital', 'Shivajinagar, Pune', 18.5320, 73.8520, 'hospital', ['sancheti hospital', 'shivajinagar', 'orthopedic']),

    // ── Landmarks & Heritage ──
    _CuratedLocation('Shaniwar Wada', 'Bajirao Road, Kasba Peth, Pune', 18.5194, 73.8554, 'landmark', ['shaniwar wada', 'wada', 'kasba peth']),
    _CuratedLocation('Aga Khan Palace', 'Nagar Road, Kalyani Nagar, Pune', 18.5524, 73.9015, 'landmark', ['aga khan palace', 'gandhi memorial', 'nagar road']),
    _CuratedLocation('Sinhagad Fort', 'Thoptewadi, Sinhagad Ghat, Pune', 18.3663, 73.7558, 'landmark', ['sinhagad fort', 'sinhagad']),
    _CuratedLocation('Dagdusheth Halwai Ganpati Temple', 'Budhwar Peth, Pune', 18.5165, 73.8560, 'landmark', ['dagdusheth', 'ganpati temple', 'budhwar peth']),
    _CuratedLocation('Pune University (SPPU)', 'Ganeshkhind, Pune', 18.5530, 73.8240, 'landmark', ['pune university', 'sppu', 'ganeshkhind']),
    _CuratedLocation('COEP Technological University', 'Wellesley Road, Shivajinagar, Pune', 18.5290, 73.8570, 'landmark', ['coep', 'college of engineering', 'shivajinagar']),
    _CuratedLocation('Fergusson College', 'FC Road, Shivajinagar, Pune', 18.5230, 73.8380, 'landmark', ['fergusson college', 'fc road']),
    _CuratedLocation('Symbiosis International University', 'Viman Nagar, Pune', 18.5660, 73.9130, 'landmark', ['symbiosis', 'viman nagar campus']),
    _CuratedLocation('MIT World Peace University', 'Paud Road, Kothrud, Pune', 18.5170, 73.8150, 'landmark', ['mit', 'world peace university', 'kothrud']),
    _CuratedLocation('Bharati Vidyapeeth University', 'Katraj, Pune', 18.4590, 73.8540, 'landmark', ['bharati vidyapeeth', 'katraj campus']),
  ];
}

class _CuratedLocation {
  final String title;
  final String subtitle;
  final double lat;
  final double lon;
  final String type;
  final List<String> keywords;

  _CuratedLocation(
    this.title,
    this.subtitle,
    this.lat,
    this.lon,
    this.type,
    this.keywords,
  );

  LocationSearchResult toResult() => LocationSearchResult(
        title: title,
        subtitle: subtitle,
        lat: lat,
        lon: lon,
        type: type,
      );
}

class _ScoredResult {
  final LocationSearchResult result;
  final int score;
  _ScoredResult(this.result, this.score);
}
