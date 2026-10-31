class CategoryBudgetSuggestion {
  final double minBudget;
  final double suggestedBudget;
  final double maxBudget;
  final String localityName;
  final String localityTier;

  const CategoryBudgetSuggestion({
    required this.minBudget,
    required this.suggestedBudget,
    required this.maxBudget,
    required this.localityName,
    required this.localityTier,
  });
}

class Task {
  final String id;
  final String title;
  final String description;
  final String category;
  final double budget;
  final double? serviceCharge;
  final String status;
  final String posterId;
  final String posterName;
  final String? posterAvatar;
  final double posterRating;
  final String? helperId;
  final String? helperName;
  final String? helperPhone;
  final double latitude;
  final double longitude;
  final String? address;
  final String? city;
  final double? distanceKm;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final double? helperRating;
  final String? completionProof;
  final String? posterPhone;
  final bool isPaid;
  final bool isHidden;
  /// True when the poster has already submitted a rating for the helper on this task.
  final bool posterHasRatedHelper;
  /// True when the helper has already submitted a rating for the poster on this task.
  final bool helperHasRatedPoster;
  // ── Delivery-specific fields ──────────────────────────────────────────────
  /// For delivery/pickup tasks: the pickup / start-location address.
  final String? pickupAddress;
  /// For delivery/pickup tasks: the drop / destination address.
  final String? dropAddress;
  /// Drop location latitude (for navigation).
  final double? dropLatitude;
  /// Drop location longitude (for navigation).
  final double? dropLongitude;
  /// Release penalty amount (10% of total task value) — shown if helper abandons
  final double releasePenalty;
  /// Daily releases used (0-3) — max 3 releases per 24h before 48h suspension
  final int dailyReleasesUsed;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.budget,
    this.serviceCharge,
    required this.status,
    required this.posterId,
    required this.posterName,
    this.posterAvatar,
    this.posterRating = 0.0,
    this.helperId,
    this.helperName,
    this.helperPhone,
    this.posterPhone,
    required this.latitude,
    required this.longitude,
    this.address,
    this.city,
    this.distanceKm,
    required this.createdAt,
    this.expiresAt,
    this.acceptedAt,
    this.completedAt,
    this.helperRating,
    this.completionProof,
    this.isPaid = false,
    this.isHidden = false,
    this.posterHasRatedHelper = false,
    this.helperHasRatedPoster = false,
    this.pickupAddress,
    this.dropAddress,
    this.dropLatitude,
    this.dropLongitude,
    this.releasePenalty = 0.0,
    this.dailyReleasesUsed = 0,
  });

  // ── Timestamp parsing ────────────────────────────────────────────────────
  // Handles three server formats:
  //  1. ISO-8601 with timezone  "2026-07-12T10:30:00+00:00" / "...Z"
  //  2. ISO-8601 naive (UTC)    "2026-07-12T10:30:00.123"   (no Z / offset)
  //  3. RFC-1123 / HTTP-date    "Thu, 12 Jul 2026 10:30:00 GMT"  ← Flask 3 default
  //
  // Format 3 caused every task to show DateTime.now() on reopen because
  // Dart's DateTime.tryParse does not understand HTTP-date strings.

  /// Parse RFC-1123 / HTTP-date strings (Flask 3's default datetime format).
  /// Returns a local DateTime, or null if the string doesn't match.
  static DateTime? _parseRfc1123(String s) {
    const months = <String, int>{
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    // Split on commas + whitespace, drop empties.
    final parts = s.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
    // With weekday:    ['Thu', '12', 'Jul', '2026', '10:30:00', 'GMT']
    // Without weekday: ['12',  'Jul', '2026', '10:30:00', 'GMT']
    final int dayIdx, monthIdx, yearIdx, timeIdx;
    if (parts.length >= 6 && int.tryParse(parts[0]) == null) {
      dayIdx = 1; monthIdx = 2; yearIdx = 3; timeIdx = 4;
    } else if (parts.length >= 5) {
      dayIdx = 0; monthIdx = 1; yearIdx = 2; timeIdx = 3;
    } else {
      return null;
    }
    final day   = int.tryParse(parts[dayIdx]);
    final month = months[parts[monthIdx].toLowerCase()];
    final year  = int.tryParse(parts[yearIdx]);
    final tp    = parts[timeIdx].split(':');
    if (day == null || month == null || year == null || tp.isEmpty) return null;
    final hour   = int.tryParse(tp[0]);
    final minute = tp.length > 1 ? int.tryParse(tp[1]) : 0;
    final second = tp.length > 2 ? (int.tryParse(tp[2]) ?? 0) : 0;
    if (hour == null || minute == null) return null;
    // HTTP-date is always UTC; convert to device-local for display.
    return DateTime.utc(year, month, day, hour, minute, second).toLocal();
  }

  /// Parse any date/time value the server may send and return a local DateTime.
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now().toUtc();
    final s = value.toString().trim();
    if (s.isEmpty) return DateTime.now().toUtc();
    // Detect an explicit timezone marker: trailing 'Z' or an offset like +05:30
    final hasZone =
        s.endsWith('Z') || RegExp(r'[+\-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasZone) {
      final utc = DateTime.tryParse('${s}Z');
      if (utc != null) return utc; // already UTC (isUtc=true)
    }
    final dt = DateTime.tryParse(s);
    if (dt != null) return dt.isUtc ? dt : dt.toUtc();
    // Last resort: RFC-1123 / HTTP-date from Flask's default JSON encoder.
    return _parseRfc1123(s)?.toUtc() ?? DateTime.now().toUtc();
  }

  /// Like [_parseDate] but returns null for null/empty/unparseable values
  /// instead of falling back to DateTime.now().  Used for optional timestamps
  /// (completedAt, acceptedAt) so we never invent a fake timestamp.
  static DateTime? _parseDateOrNull(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    final hasZone =
        s.endsWith('Z') || RegExp(r'[+\-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasZone) {
      final utc = DateTime.tryParse('${s}Z');
      if (utc != null) return utc;
    }
    final dt = DateTime.tryParse(s);
    if (dt != null) return dt.isUtc ? dt : dt.toUtc();
    return _parseRfc1123(s)?.toUtc();
  }

  /// Returns the first non-empty string value found in [map] for any of [keys].
  static String _firstNonEmpty(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return '';
    for (final key in keys) {
      final v = map[key];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '';
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    // ── location ────────────────────────────────────────────────────────────
    // API returns either a nested `location: {lat, lng, address}` object
    // OR flat columns `location_lat`, `location_lng`, `location_address`.
    final loc = json['location'];
    final locLat = loc is Map ? loc['lat'] : null;
    final locLng = loc is Map ? loc['lng'] : null;
    final locAddr = loc is Map ? loc['address'] : null;

    // ── pickup / destination ─────────────────────────────────────────────
    // Browse/user-task API returns:
    //   location: {lat, lng, address}   ← pickup location
    //   drop_location: {lat, lng, address} | null  ← drop location
    // Some task-detail endpoints may return pickup/destination instead.
    final pickup = json['pickup'];
    final destination = json['destination'];
    // The main public API uses drop_location (not destination)
    final dropLoc = json['drop_location'];

    // ── poster ───────────────────────────────────────────────────────────────
    // The API may return the poster as any of: postedBy, poster, posted_by
    // (populated nested object) OR as flat poster_id / poster_name fields.
    // MongoDB uses _id; SQL APIs use id. Handle all variants.
    final dynamic postedByRaw =
        json['postedBy'] ?? json['poster'] ?? json['posted_by'];
    final Map<String, dynamic>? postedBy =
        postedByRaw is Map<String, dynamic> ? postedByRaw : null;

    final posterId = _firstNonEmpty(postedBy, const ['_id', 'id'])
        .isNotEmpty
        ? _firstNonEmpty(postedBy, const ['_id', 'id'])
        : (json['poster_id']?.toString() ??
            (postedByRaw is String ? postedByRaw : null) ??
            '');
    final posterName = _firstNonEmpty(
            postedBy,
            const ['name', 'fullName', 'full_name', 'username', 'displayName'])
        .isNotEmpty
        ? _firstNonEmpty(
            postedBy,
            const ['name', 'fullName', 'full_name', 'username', 'displayName'])
        : (json['poster_name']?.toString() ?? '');
    final posterRating = double.tryParse(
            (_firstNonEmpty(postedBy,
                        const ['rating', 'averageRating', 'average_rating'])
                    .isNotEmpty
                ? _firstNonEmpty(
                    postedBy,
                    const ['rating', 'averageRating', 'average_rating'])
                : (json['poster_rating']?.toString() ?? '0'))) ??
        0.0;

    // ── helper ───────────────────────────────────────────────────────────────
    final helper = json['helper'];
    final helperIdRaw = (json['helper_id']
        ?? json['accepted_by']
        ?? (helper is Map ? helper['id'] : null))?.toString();
    final helperName = (helper is Map ? helper['name'] : null)?.toString()
        ?? json['helper_name']?.toString();
    final helperPhone = (helper is Map ? helper['phone'] : null)?.toString()
        ?? json['helper_phone']?.toString();

    // ── status ───────────────────────────────────────────────────────────────
    // API uses 'active' for open/browse tasks; normalise to 'posted'
    final rawStatus = (json['status'] ?? 'active').toString();
    final status = rawStatus == 'active' ? 'posted' : rawStatus;

    return Task(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      budget: double.tryParse(
          (json['budget'] ?? json['price'] ?? json['amount'] ?? 0).toString()
      ) ?? 0.0,
      serviceCharge: json['service_charge'] != null
          ? double.tryParse(json['service_charge'].toString()) ?? 0.0
          : null,
      status: status,
      posterId: posterId,
      posterName: posterName.isNotEmpty ? posterName : 'Anonymous',
      posterAvatar: json['poster_avatar']?.toString() ?? (() {
            final a = _firstNonEmpty(postedBy, const [
              'avatar', 'profilePicture', 'profile_picture', 'photo', 'image',
            ]);
            return a.isNotEmpty ? a : null;
          })(),
      posterRating: posterRating,
      helperId: (helperIdRaw?.isEmpty ?? true) ? null : helperIdRaw,
      helperName: helperName,
      helperPhone: (helperPhone?.isEmpty ?? true) ? null : helperPhone,
      latitude: double.tryParse(
          (locLat ?? (pickup is Map ? pickup['lat'] : null) ?? json['latitude'] ?? json['lat'] ?? json['location_lat'] ?? 0).toString()
      ) ?? 0.0,
      longitude: double.tryParse(
          (locLng ?? (pickup is Map ? pickup['lng'] : null) ?? json['longitude'] ?? json['lng'] ?? json['location_lng'] ?? 0).toString()
      ) ?? 0.0,
      address: locAddr?.toString()
          ?? (pickup is Map ? pickup['address'] : null)?.toString()
          ?? json['address']?.toString()
          ?? json['location_address']?.toString(),
      city: json['city']?.toString(),
      distanceKm: (json['distance_km'] ?? json['distanceKm']) != null
          ? double.tryParse(
              (json['distance_km'] ?? json['distanceKm']).toString()
            ) ?? 0.0
          : null,
      createdAt: _parseDate(
          json['created_at'] ?? json['postedAt'] ?? json['posted_at']
      ),
      expiresAt: _parseDateOrNull(json['expiresAt'] ?? json['expires_at']),
      acceptedAt: _parseDateOrNull(json['accepted_at'] ?? json['acceptedAt']),
      completedAt: _parseDateOrNull(
          json['helper_final_completed_at'] ??
          json['paid_at'] ??
          json['payment_released_at'] ??
          json['completed_at'] ??
          json['completedAt'] ??
          json['verified_at']),
      helperRating: json['helper_rating'] != null
          ? double.tryParse(json['helper_rating'].toString()) ?? 0.0
          : null,
      completionProof: json['completion_proof']?.toString(),
      posterPhone: (() {
            final p = _firstNonEmpty(postedBy, const [
              'phone', 'phoneNumber', 'phone_number', 'mobile',
              'mobileNumber', 'mobile_number', 'contact', 'contactNumber',
            ]);
            return p.isNotEmpty
                ? p
                : (json['poster_phone']?.toString()
                    ?? json['posterPhone']?.toString()  // camelCase from some backends
                    ?? json['phone']?.toString());
          })(),
      isPaid: json['is_paid'] == true || json['status'] == 'paid' || json['status'] == 'payment_released' || json['status'] == 'done',
      isHidden: json['is_hidden'] == true,
      posterHasRatedHelper: json['poster_has_rated_helper'] == true,
      helperHasRatedPoster: json['helper_has_rated_poster'] == true,
      pickupAddress: (() {
        final direct = (pickup is Map ? pickup['address'] : null)?.toString()
            ?? json['pickup_address']?.toString()
            ?? json['pickupAddress']?.toString()
            ?? json['pickup_addr']?.toString()
            ?? json['from_address']?.toString();
        if (direct != null && direct.trim().isNotEmpty) return direct.trim();
        final rawAddr = locAddr?.toString() ?? json['address']?.toString() ?? json['location_address']?.toString() ?? '';
        final m = RegExp(r'Pickup:\s*(.+?)(?:\n|$)', caseSensitive: false).firstMatch(rawAddr);
        return m?.group(1)?.trim();
      })(),
      dropAddress: (() {
        final direct = (dropLoc is Map ? dropLoc['address'] : null)?.toString()
            ?? (destination is Map ? destination['address'] : null)?.toString()
            ?? json['drop_location_address']?.toString()
            ?? json['delivery_address']?.toString()
            ?? json['drop_address']?.toString()
            ?? json['dropAddress']?.toString()
            ?? json['deliveryAddress']?.toString()
            ?? json['to_address']?.toString()
            ?? json['destination_address']?.toString();
        if (direct != null && direct.trim().isNotEmpty) return direct.trim();
        final rawAddr = locAddr?.toString() ?? json['address']?.toString() ?? json['location_address']?.toString() ?? '';
        final m = RegExp(r'Drop:\s*(.+?)(?:\n|$)', caseSensitive: false).firstMatch(rawAddr);
        return m?.group(1)?.trim();
      })(),
      dropLatitude: (() {
        // Primary: drop_location nested object (browse/user-tasks API)
        if (dropLoc is Map && dropLoc['lat'] != null) {
          return double.tryParse(dropLoc['lat'].toString());
        }
        // Fallback: destination nested object (task-detail API)
        if (destination is Map && destination['lat'] != null) {
          return double.tryParse(destination['lat'].toString());
        }
        // Fallback: flat fields
        final f = json['drop_location_lat'] ?? json['drop_lat'] ?? json['drop_latitude'] ?? json['dropLat'] ?? json['destination_lat'];
        return f != null ? double.tryParse(f.toString()) : null;
      })(),
      dropLongitude: (() {
        if (dropLoc is Map && dropLoc['lng'] != null) {
          return double.tryParse(dropLoc['lng'].toString());
        }
        if (destination is Map && destination['lng'] != null) {
          return double.tryParse(destination['lng'].toString());
        }
        final f = json['drop_location_lng'] ?? json['drop_lng'] ?? json['drop_longitude'] ?? json['dropLng'] ?? json['destination_lng'];
        return f != null ? double.tryParse(f.toString()) : null;
      })(),
      releasePenalty: double.tryParse(
          (json['release_penalty'] ?? json['releasePenalty'] ?? json['penalty'] ?? 0).toString()
      ) ?? 0.0,
      dailyReleasesUsed: int.tryParse(
          (json['daily_releases_used'] ?? json['dailyReleasesUsed'] ?? json['dailyReleaseCount'] ?? 0).toString()
      ) ?? 0,
    );
  }

  /// True for task categories that involve a pickup-to-drop delivery route.
  bool get isDeliveryType =>
      const {'delivery', 'pickup', 'transport', 'moving'}.contains(category.toLowerCase());

  /// Whether this task belongs to delivery / pickup / transport / moving categories.
  bool get isDeliveryCategory =>
      const {'delivery', 'pickup', 'transport', 'moving'}.contains(category.toLowerCase());

  /// The effective pickup address (or standard task address).
  String get effectivePickupAddress {
    if (pickupAddress != null && pickupAddress!.trim().isNotEmpty) {
      return pickupAddress!.trim();
    }
    if (address != null && address!.trim().isNotEmpty) {
      final m = RegExp(r'Pickup:\s*(.+?)(?:\n|$)', caseSensitive: false).firstMatch(address!);
      if (m != null && m.group(1)!.trim().isNotEmpty) {
        return m.group(1)!.trim();
      }
      return address!.trim();
    }
    return '';
  }

  /// The effective drop address.
  String? get effectiveDropAddress {
    if (dropAddress != null && dropAddress!.trim().isNotEmpty) {
      return dropAddress!.trim();
    }
    if (address != null && address!.trim().isNotEmpty) {
      final m = RegExp(r'Drop:\s*(.+?)(?:\n|$)', caseSensitive: false).firstMatch(address!);
      if (m != null && m.group(1)!.trim().isNotEmpty) {
        return m.group(1)!.trim();
      }
    }
    return null;
  }

  /// Platform commission rate (20% inclusive of GST & platform fee).
  static const double platformCommission = 0.20;

  /// Per-task helper commission rate (20% for all categories including delivery, pickup, transport, moving; inclusive of GST).
  double get commissionRate => 0.20;

  /// Per-task poster commission / platform fee rate (20% for all categories including delivery, pickup, transport, moving; inclusive of GST).
  double get posterCommissionRate => 0.20;

  /// Poster platform fee & GST amount: 20% of budget.
  double get posterFee => budget * posterCommissionRate;

  /// Total base task value before helper commission: budget + service charge.
  double get totalTaskValue => budget + (serviceCharge ?? 0);

  /// Total amount the poster pays: budget + distance service charge + 20% platform fee.
  double get totalPosterCost => totalTaskValue + posterFee;

  /// Legacy alias for total poster payment amount.
  double get totalAmount => totalPosterCost;

  /// Minimum budget required for a given task category based on current market rates.
  static double minBudgetForCategory(String category) {
    switch (category.toLowerCase()) {
      // 1. Engineering & Skilled Trades
      case 'electrician':
      case 'plumbing':
        return 150.0;
      case 'carpentry':
      case 'vehicle':
        return 200.0;
      case 'repair':
      case 'tech_support':
      case 'tech-support':
        return 250.0;
      case 'painting':
        return 500.0;

      // 2. Home & Household
      case 'laundry':
        return 100.0;
      case 'household':
        return 150.0;
      case 'cooking':
      case 'gardening':
        return 250.0;
      case 'cleaning':
        return 300.0;

      // 3. Shopping, Errands & On-Demand
      case 'groceries':
        return 100.0;
      case 'shopping':
        return 150.0;
      case 'errands':
      case 'errand':
      case 'queue_standing':
      case 'queue-standing':
        return 200.0;
      case 'event_help':
      case 'event-help':
        return 400.0;

      // 4. Professional, Creative & Digital
      case 'data_entry':
      case 'data-entry':
        return 150.0;
      case 'tutoring':
      case 'beauty':
        return 250.0;
      case 'freelancer':
        return 300.0;
      case 'photography':
        return 1500.0;

      // 5. Care Services
      case 'pet_care':
      case 'petcare':
        return 150.0;
      case 'child_care':
      case 'babysitting':
        return 200.0;
      case 'elder_care':
      case 'eldercare':
        return 500.0;

      // Delivery & Moving - dynamic distance-based pricing (no static ₹100 floor)
      case 'delivery':
        return 0.0; // No minimum budget for delivery; calculated from distance
      case 'pickup':
        return 30.0; // Auto pick & drop base min
      case 'transport':
        return 50.0; // Vehicle transport base min
      case 'moving':
        return 400.0; // Moving & packing base min

      case 'other':
      default:
        return 100.0;
    }
  }

  /// Returns the per-km rate (in ₹) for a delivery-related category and vehicle.
  static double ratePerKmForCategory(String category, {String vehicle = 'bike'}) {
    switch (category.toLowerCase()) {
      case 'delivery':
        return vehicle.toLowerCase() == 'rikshaw' ? 18.0 : 12.0;
      case 'pickup':
        return 18.0; // Rikshaw / Auto rate
      case 'transport':
        return 18.0; // Cab / Transport rate
      case 'moving':
        return 35.0; // Moving & Tempo: ₹35/km
      default:
        return 12.0;
    }
  }

  /// Calculates the price (in ₹) based on distance, category, and vehicle.
  static double calculateDistancePrice(double distanceKm, String category, {String vehicle = 'bike'}) {
    if (distanceKm <= 0) return 0.0;
    final cat = category.toLowerCase();
    switch (cat) {
      case 'delivery':
        if (vehicle.toLowerCase() == 'rikshaw') {
          // Rikshaw delivery: ₹18/km, base min ₹30
          final raw = distanceKm * 18.0;
          return (raw < 30.0 ? 30.0 : raw).roundToDouble();
        } else {
          // Bike delivery: ₹12/km, base min ₹24
          final raw = distanceKm * 12.0;
          return (raw < 24.0 ? 24.0 : raw).roundToDouble();
        }
      case 'pickup':
        // Auto pick & drop: ₹18/km, base min ₹30
        final raw = distanceKm * 18.0;
        return (raw < 30.0 ? 30.0 : raw).roundToDouble();
      case 'transport':
        // Cab/Vehicle transport: ₹18/km, base min ₹50
        final raw = distanceKm * 18.0;
        return (raw < 50.0 ? 50.0 : raw).roundToDouble();
      case 'moving':
        // Moving & Packing: Base ₹400 (loading/unloading) + ₹35/km
        final fare = 400.0 + (distanceKm > 2 ? (distanceKm - 2) * 35.0 : 0.0);
        return (fare < 400.0 ? 400.0 : fare).roundToDouble();
      default:
        final raw = distanceKm * 12.0;
        return (raw < 24.0 ? 24.0 : raw).roundToDouble();
    }
  }

  /// Returns user-facing rate and pricing description.
  static String distancePriceDescription(double distanceKm, String category, {String vehicle = 'bike'}) {
    final cat = category.toLowerCase();
    switch (cat) {
      case 'delivery':
        return vehicle.toLowerCase() == 'rikshaw'
            ? '₹18 per km (Rikshaw)'
            : '₹12 per km (Bike)';
      case 'pickup':
        return '₹18 per km (Rikshaw)';
      case 'transport':
        return '₹18 per km';
      case 'moving':
        return '₹400 base + ₹35 per km';
      default:
        return '₹12 per km';
    }
  }

  /// Returns market-based suggested budget range based on category and selected area.
  static CategoryBudgetSuggestion getBudgetSuggestion(
    String category, {
    String? areaText,
    double? distanceKm,
    String vehicle = 'bike',
  }) {
    final cat = category.toLowerCase();
    final areaLower = (areaText ?? '').toLowerCase();

    double multiplier = 1.0;
    String tier = 'Standard Area';
    String detectedName = 'Your Area';

    // Premium & IT hubs (Pune)
    const premiumAreas = [
      'hinjewadi', 'baner', 'wakad', 'balewadi', 'koregaon', 'kalyani',
      'viman', 'kharadi', 'magarpatta', 'aundh', 'bavdhan', 'pashan',
      'sb road', 'senapati bapat', 'prabhat', 'model colony', 'boat club'
    ];
    // Central & Established
    const centralAreas = [
      'kothrud', 'shivaji nagar', 'shivajinagar', 'deccan', 'camp',
      'erandwane', 'sadashiv', 'swargate', 'bibvewadi', 'sahakar',
      'karve', 'wanowrie', 'nibm', 'kondhwa', 'peth'
    ];
    // Suburban / Developing
    const suburbanAreas = [
      'pimpri', 'chinchwad', 'bhosari', 'hadapsar', 'wagholi', 'nigdi',
      'akurdi', 'moshi', 'ambegaon', 'warje', 'ravet', 'punawale', 'tathawade'
    ];

    for (final a in premiumAreas) {
      if (areaLower.contains(a)) {
        multiplier = 1.25;
        tier = 'IT & High-Demand Hub';
        detectedName = a[0].toUpperCase() + a.substring(1);
        break;
      }
    }
    if (multiplier == 1.0) {
      for (final a in centralAreas) {
        if (areaLower.contains(a)) {
          multiplier = 1.10;
          tier = 'Central Pune';
          detectedName = a[0].toUpperCase() + a.substring(1);
          break;
        }
      }
    }
    if (multiplier == 1.0) {
      for (final a in suburbanAreas) {
        if (areaLower.contains(a)) {
          multiplier = 1.0;
          tier = 'Suburban Hub';
          detectedName = a[0].toUpperCase() + a.substring(1);
          break;
        }
      }
    }

    if (detectedName == 'Your Area' && areaText != null && areaText.trim().isNotEmpty) {
      final parts = areaText.split(RegExp(r'[, -]')).where((s) => s.trim().isNotEmpty).toList();
      if (parts.isNotEmpty) {
        final raw = parts.first.trim();
        detectedName = raw.length > 1 ? raw[0].toUpperCase() + raw.substring(1) : raw;
      }
    }

    double baseSuggested;
    double baseMax;

    switch (cat) {
      case 'electrician':
      case 'plumbing':
        baseSuggested = 200.0;
        baseMax = 400.0;
        break;
      case 'carpentry':
        baseSuggested = 250.0;
        baseMax = 500.0;
        break;
      case 'repair':
      case 'tech_support':
      case 'tech-support':
        baseSuggested = 350.0;
        baseMax = 650.0;
        break;
      case 'painting':
        baseSuggested = 700.0;
        baseMax = 1400.0;
        break;
      case 'vehicle':
        baseSuggested = 350.0;
        baseMax = 750.0;
        break;
      case 'cleaning':
        baseSuggested = 400.0;
        baseMax = 900.0;
        break;
      case 'cooking':
        baseSuggested = 350.0;
        baseMax = 650.0;
        break;
      case 'laundry':
        baseSuggested = 150.0;
        baseMax = 250.0;
        break;
      case 'household':
        baseSuggested = 200.0;
        baseMax = 400.0;
        break;
      case 'gardening':
        baseSuggested = 350.0;
        baseMax = 700.0;
        break;
      case 'groceries':
        baseSuggested = 150.0;
        baseMax = 250.0;
        break;
      case 'shopping':
        baseSuggested = 200.0;
        baseMax = 400.0;
        break;
      case 'errands':
      case 'errand':
      case 'queue_standing':
      case 'queue-standing':
        baseSuggested = 250.0;
        baseMax = 450.0;
        break;
      case 'event_help':
      case 'event-help':
        baseSuggested = 550.0;
        baseMax = 1000.0;
        break;
      case 'data_entry':
      case 'data-entry':
        baseSuggested = 250.0;
        baseMax = 450.0;
        break;
      case 'tutoring':
        baseSuggested = 350.0;
        baseMax = 700.0;
        break;
      case 'beauty':
        baseSuggested = 400.0;
        baseMax = 900.0;
        break;
      case 'freelancer':
        baseSuggested = 500.0;
        baseMax = 1500.0;
        break;
      case 'photography':
        baseSuggested = 2500.0;
        baseMax = 5500.0;
        break;
      case 'pet_care':
      case 'petcare':
        baseSuggested = 200.0;
        baseMax = 400.0;
        break;
      case 'child_care':
      case 'babysitting':
        baseSuggested = 300.0;
        baseMax = 600.0;
        break;
      case 'elder_care':
      case 'eldercare':
        baseSuggested = 700.0;
        baseMax = 1300.0;
        break;
      case 'moving':
        if (distanceKm != null && distanceKm > 0) {
          baseSuggested = calculateDistancePrice(distanceKm, 'moving');
          baseMax = (baseSuggested * 1.35).roundToDouble();
        } else {
          baseSuggested = 600.0;
          baseMax = 1500.0;
        }
        break;
      case 'delivery':
      case 'pickup':
      case 'transport':
        if (distanceKm != null && distanceKm > 0) {
          final distPrice = calculateDistancePrice(distanceKm, cat, vehicle: vehicle);
          baseSuggested = distPrice;
          baseMax = (distPrice * 1.30).roundToDouble();
        } else {
          baseSuggested = cat == 'delivery'
              ? (vehicle == 'rikshaw' ? 60.0 : 40.0)
              : (cat == 'pickup' ? 70.0 : 100.0);
          baseMax = baseSuggested * 1.5;
        }
        break;
      case 'other':
      default:
        baseSuggested = 200.0;
        baseMax = 450.0;
        break;
    }

    final minB = minBudgetForCategory(cat);
    double suggested = ((baseSuggested * multiplier) / 5).round() * 5.0;
    if (minB > 0 && suggested < minB) suggested = minB;
    double maxB = ((baseMax * multiplier) / 5).round() * 5.0;
    if (maxB <= suggested) maxB = suggested + 30.0;

    return CategoryBudgetSuggestion(
      minBudget: minB,
      suggestedBudget: suggested,
      maxBudget: maxB,
      localityName: detectedName,
      localityTier: tier,
    );
  }

  /// Returns the platform service charge estimate (in ₹) for a task category.
  /// The actual charge is distance-based and finalised by the backend.
  /// This is used as a front-end estimate in previews and confirmations.
  static int serviceChargeForCategory(String category) {
    switch (category) {
      case 'delivery':
      case 'pickup':
      case 'transport':
        return 25; // mid-range estimate (actual: ₹10–₹35 by distance)
      case 'moving':
        return 40; // estimate for large-item moves
      default:
        return 0;
    }
  }

  /// Net amount the helper earns after helper commission is deducted
  /// from the total task value (budget + service charge).
  double get netEarning => totalTaskValue * (1 - commissionRate);

  /// Max daily releases allowed before 48h suspension.
  static const int maxDailyReleases = 3;

  /// Remaining releases allowed today (0 to maxDailyReleases).
  int get remainingReleases => (maxDailyReleases - dailyReleasesUsed).clamp(0, maxDailyReleases);

  /// Returns a copy of this task with the given fields replaced.
  Task copyWith({
    String? status,
    DateTime? completedAt,
    bool? isPaid,
    String? helperName,
    String? helperId,
    String? helperPhone,
  }) {
    return Task(
      id: id,
      title: title,
      description: description,
      category: category,
      budget: budget,
      serviceCharge: serviceCharge,
      status: status ?? this.status,
      posterId: posterId,
      posterName: posterName,
      posterAvatar: posterAvatar,
      posterRating: posterRating,
      helperId: helperId ?? this.helperId,
      helperName: helperName ?? this.helperName,
      helperPhone: helperPhone ?? this.helperPhone,
      posterPhone: posterPhone,
      latitude: latitude,
      longitude: longitude,
      address: address,
      city: city,
      distanceKm: distanceKm,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
      completedAt: completedAt ?? this.completedAt,
      helperRating: helperRating,
      completionProof: completionProof,
      isPaid: isPaid ?? this.isPaid,
      isHidden: isHidden,
      posterHasRatedHelper: posterHasRatedHelper,
      helperHasRatedPoster: helperHasRatedPoster,
      pickupAddress: pickupAddress,
      dropAddress: dropAddress,
      dropLatitude: dropLatitude,
      dropLongitude: dropLongitude,
      releasePenalty: releasePenalty,
      dailyReleasesUsed: dailyReleasesUsed,
    );
  }

  /// Flat JSON map that can be fed back into [Task.fromJson].
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'budget': budget,
    if (serviceCharge != null) 'service_charge': serviceCharge,
    'status': status,
    'poster_id': posterId,
    'poster_name': posterName,
    if (posterAvatar != null) 'poster_avatar': posterAvatar,
    'poster_rating': posterRating,
    if (posterPhone != null) 'poster_phone': posterPhone,
    if (helperId != null) 'helper_id': helperId,
    if (helperName != null) 'helper_name': helperName,
    if (helperPhone != null) 'helper_phone': helperPhone,
    'latitude': latitude,
    'longitude': longitude,
    if (address != null) 'address': address,
    if (city != null) 'city': city,
    if (distanceKm != null) 'distance_km': distanceKm,
    'created_at': createdAt.toIso8601String(),
    if (acceptedAt != null) 'accepted_at': acceptedAt!.toIso8601String(),
    if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    if (helperRating != null) 'helper_rating': helperRating,
    if (completionProof != null) 'completion_proof': completionProof,
    'is_paid': isPaid,
    'is_hidden': isHidden,
    'poster_has_rated_helper': posterHasRatedHelper,
    'helper_has_rated_poster': helperHasRatedPoster,
    if (pickupAddress != null) 'pickup_address': pickupAddress,
    if (dropAddress != null) 'delivery_address': dropAddress,
    if (dropLatitude != null) 'drop_lat': dropLatitude,
    if (dropLongitude != null) 'drop_lng': dropLongitude,
    'release_penalty': releasePenalty,
    'daily_releases_used': dailyReleasesUsed,
  };

  String get statusLabel {
    switch (status) {
      case 'posted':
      case 'open':
      case 'active':
        return 'Open';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
      case 'verify_pending':
        return 'In Progress';
      case 'payment_released':
        return 'Payment Released';
      case 'completed':
        return 'Awaiting Verification';
      case 'verified':
      case 'paid':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

// Task categories matching the web app
class TaskCategory {
  final String id;
  final String label;
  final String icon;

  const TaskCategory({required this.id, required this.label, required this.icon});

  static const List<TaskCategory> all = [
    TaskCategory(id: 'delivery', label: 'Delivery', icon: '🚚'),
    // TaskCategory(id: 'pickup', label: 'Pickup', icon: '📦'),   // disabled
    // TaskCategory(id: 'transport', label: 'Transport', icon: '🚗'), // disabled
    TaskCategory(id: 'moving', label: 'Moving', icon: '🏠'),
    TaskCategory(id: 'groceries', label: 'Groceries', icon: '🛒'),
    TaskCategory(id: 'cooking', label: 'Cooking', icon: '🍳'),
    TaskCategory(id: 'cleaning', label: 'Cleaning', icon: '🧹'),
    TaskCategory(id: 'laundry', label: 'Laundry', icon: '👕'),
    TaskCategory(id: 'household', label: 'Household', icon: '🏡'),
    TaskCategory(id: 'shopping', label: 'Shopping', icon: '🛍️'),
    TaskCategory(id: 'electrician', label: 'Electrician', icon: '⚡'),
    TaskCategory(id: 'plumbing', label: 'Plumbing', icon: '🔧'),
    TaskCategory(id: 'carpentry', label: 'Carpentry', icon: '🪚'),
    TaskCategory(id: 'painting', label: 'Painting', icon: '🎨'),
    TaskCategory(id: 'repair', label: 'Repair', icon: '🔨'),
    TaskCategory(id: 'vehicle', label: 'Vehicle', icon: '🚘'),
    TaskCategory(id: 'tutoring', label: 'Tutoring', icon: '📚'),
    TaskCategory(id: 'freelancer', label: 'Freelancer', icon: '💼'),
    TaskCategory(id: 'data_entry', label: 'Data Entry', icon: '💻'),
    TaskCategory(id: 'photography', label: 'Photography', icon: '📷'),
    TaskCategory(id: 'gardening', label: 'Gardening', icon: '🌱'),
    TaskCategory(id: 'beauty', label: 'Beauty', icon: '💅'),
    TaskCategory(id: 'pet_care', label: 'Pet Care', icon: '🐾'),
    TaskCategory(id: 'child_care', label: 'Child Care', icon: '👶'),
    TaskCategory(id: 'elder_care', label: 'Elder Care', icon: '👴'),
    TaskCategory(id: 'errands', label: 'Errands', icon: '🏃'),
    TaskCategory(id: 'queue_standing', label: 'Queue Standing', icon: '🕐'),
    TaskCategory(id: 'event_help', label: 'Event Help', icon: '🎉'),
    TaskCategory(id: 'tech_support', label: 'Tech Support', icon: '💡'),
    TaskCategory(id: 'other', label: 'Other', icon: '📋'),
  ];

  /// Returns the icon emoji for [category], falling back to '📋' if not found.
  static String iconFor(String category) {
    return all.firstWhere(
      (c) => c.id == category,
      orElse: () => const TaskCategory(id: '', label: '', icon: '📋'),
    ).icon;
  }
}

/// A parent/group category for the hierarchical category picker in post task.
class TaskCategoryGroup {
  final String label;
  final String icon;
  final List<String> categoryIds;

  const TaskCategoryGroup({
    required this.label,
    required this.icon,
    required this.categoryIds,
  });

  List<TaskCategory> get subCategories => categoryIds
      .map((id) => TaskCategory.all.firstWhere(
            (c) => c.id == id,
            orElse: () => TaskCategory(id: id, label: id, icon: '📋'),
          ))
      .toList();

    static const List<TaskCategoryGroup> all = [
    TaskCategoryGroup(
      label: 'Repair',
      icon: '🔧',
      categoryIds: ['repair', 'electrician', 'plumbing', 'carpentry', 'vehicle', 'tech_support'],
    ),
    TaskCategoryGroup(
      label: 'Home & Lifestyle',
      icon: '🏠',
      categoryIds: ['cleaning', 'household', 'cooking', 'laundry', 'gardening', 'beauty'],
    ),
    TaskCategoryGroup(
      label: 'Delivery & Moving',
      icon: '🚚',
      categoryIds: ['delivery', 'moving'],
    ),
    TaskCategoryGroup(
      label: 'Shopping & Errands',
      icon: '🛒',
      categoryIds: ['shopping', 'groceries', 'errands', 'queue_standing', 'event_help'],
    ),
    TaskCategoryGroup(
      label: 'Professional',
      icon: '💼',
      categoryIds: ['freelancer', 'data_entry', 'photography', 'tutoring', 'painting'],
    ),
    TaskCategoryGroup(
      label: 'Care Services',
      icon: '❤️',
      categoryIds: ['child_care', 'elder_care', 'pet_care'],
    ),
    TaskCategoryGroup(
      label: 'Other',
      icon: '📋',
      categoryIds: ['other'],
    ),
  ];
}
