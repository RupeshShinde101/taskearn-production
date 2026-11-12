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

  /// Normalizes category IDs across snake_case, kebab-case, space-separated, and legacy web keys.
  static String _normalizeCategoryKey(String category) {
    final clean = category.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    switch (clean) {
      case 'techsupport':
        return 'tech_support';
      case 'eventhelp':
        return 'event_help';
      case 'freelance':
        return 'freelancer';
      case 'petcare':
        return 'pet_care';
      case 'childcare':
      case 'babysitting':
        return 'child_care';
      case 'eldercare':
        return 'elder_care';
      case 'errand':
        return 'errands';
      case 'queuestanding':
        return 'queue_standing';
      case 'dataentry':
        return 'data_entry';
      case 'businessadmin':
        return 'business_admin';
      case 'graphicdesign':
        return 'graphic_design';
      case 'videoaudioediting':
        return 'video_audio_editing';
      case 'digitalmarketing':
        return 'digital_marketing';
      case 'webapptech':
        return 'web_app_tech';
      default:
        return clean;
    }
  }

  /// Minimum budget required for a given task category based on current market rates.
  static double minBudgetForCategory(String category, {String vehicle = 'bike'}) {
    switch (_normalizeCategoryKey(category)) {
      // 1. Engineering & Skilled Trades
      case 'electrician':
      case 'plumbing':
        return 150.0;
      case 'carpentry':
      case 'vehicle':
        return 200.0;
      case 'repair':
      case 'tech_support':
        return 250.0;
      case 'painting':
        return 500.0;

      // 2. Home & Household
      case 'laundry':
      case 'waste':
        return 100.0;
      case 'household':
      case 'tailoring':
        return 150.0;
      case 'cooking':
      case 'gardening':
      case 'fitness':
        return 250.0;
      case 'cleaning':
        return 300.0;

      // 3. Shopping, Errands & On-Demand
      case 'groceries':
        return 100.0;
      case 'shopping':
        return 150.0;
      case 'errands':
      case 'queue_standing':
        return 200.0;
      case 'event_help':
        return 400.0;
      case 'catering':
        return 500.0;

      // 4. Professional, Creative & Digital
      case 'data_entry':
        return 150.0;
      case 'tutoring':
      case 'beauty':
        return 250.0;
      case 'freelancer':
      case 'business_admin':
        return 300.0;
      case 'graphic_design':
        return 350.0;
      case 'video_audio_editing':
        return 400.0;
      case 'digital_marketing':
        return 500.0;
      case 'web_app_tech':
        return 800.0;
      case 'photography':
        return 1500.0;

      // 5. Care Services
      case 'pet_care':
        return 150.0;
      case 'child_care':
        return 200.0;
      case 'elder_care':
        return 500.0;

      // Delivery & Moving - distance-based pricing with vehicle/category base minimums
      case 'delivery':
        return vehicle.toLowerCase() == 'rikshaw' ? 30.0 : 24.0; // Vehicle base min
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
        // Moving & Packing: Base ₹400 + ₹35/km across full distance
        final fare = 400.0 + (distanceKm * 35.0);
        return (fare < 400.0 ? 400.0 : fare).roundToDouble();
      default:
        final raw = distanceKm * 12.0;
        return (raw < 24.0 ? 24.0 : raw).roundToDouble();
    }
  }

  // ── Distance Fare Helpers ─────────────────────────────────────────────────
  /// Returns user-facing itemized fare breakdown for a distance-priced category.
  static String distanceFareSummary(double distanceKm, String category, {String vehicle = 'bike'}) {
    final total = calculateDistancePrice(distanceKm, category, vehicle: vehicle).toInt();
    final cat = category.toLowerCase();
    if (cat == 'moving') {
      final distPart = (distanceKm * 35.0).round();
      return 'Min fare: ₹$total (₹400 base + ₹$distPart for ${distanceKm.toStringAsFixed(1)} km @ ₹35/km)';
    }
    final rate = ratePerKmForCategory(cat, vehicle: vehicle).toInt();
    final baseMin = minBudgetForCategory(cat, vehicle: vehicle).toInt();
    final raw = distanceKm * rate;
    final vehSuffix = cat == 'delivery'
        ? (vehicle.toLowerCase() == 'rikshaw' ? ' (Rikshaw)' : ' (Bike)')
        : (cat == 'pickup' ? ' (Rikshaw)' : '');
    if (raw < baseMin) {
      return 'Min fare: ₹$total (${distanceKm.toStringAsFixed(1)} km @ ₹$rate/km — ₹$baseMin min$vehSuffix)';
    }
    return 'Min fare: ₹$total (${distanceKm.toStringAsFixed(1)} km @ ₹$rate/km$vehSuffix)';
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

  /// Returns true for remote-friendly freelancer categories where physical location is optional/not needed.
  static bool isFreelancerCategory(String category) {
    final c = _normalizeCategoryKey(category);
    return c == 'freelancer' || TaskCategoryGroup.freelancerChildIds.contains(c);
  }

  static const Map<String, FreelancerPricingConfig> _freelancerPricingConfigs = {
    'web_app_tech': FreelancerPricingConfig(
      categoryId: 'web_app_tech',
      minHourlyRate: 400.0,
      defaultHourlyRate: 600.0,
      maxHourlyRate: 1200.0,
      minHours: 2,
      defaultHours: 3,
      maxHours: 40,
      shortUnitHint: 'From ₹800 · /page or /hr',
      separateCostsTitle: 'Domain & Hosting Separate',
      separateCostsDescription:
          'Domain registration (~₹900/yr), Hosting/VPS & paid APIs are paid directly by you (excluded from budget & 20% fee).',
      tiers: [
        FreelancerPackageTier(
          id: 'website_pages',
          label: 'Website (/page)',
          unitLabel: 'page',
          unitPlural: 'pages',
          baseMin: 0.0,
          baseSuggested: 0.0,
          baseMax: 0.0,
          perUnitMin: 800.0,
          perUnitSuggested: 1500.0,
          perUnitMax: 3000.0,
          minUnits: 1,
          defaultUnits: 1,
          maxUnits: 30,
          summaryHint: 'Responsive web pages, forms & basic SEO setup',
        ),
        FreelancerPackageTier(
          id: 'bug_fix',
          label: 'Bug Fix / Script',
          baseMin: 800.0,
          baseSuggested: 1200.0,
          baseMax: 2000.0,
          summaryHint: 'Targeted bug fix, plugin tweak or automation script',
        ),
        FreelancerPackageTier(
          id: 'landing_page',
          label: 'Landing Page',
          baseMin: 2000.0,
          baseSuggested: 3000.0,
          baseMax: 4500.0,
          summaryHint: 'Custom single-page conversion layout & lead form',
        ),
        FreelancerPackageTier(
          id: 'app_mvp',
          label: 'App / E-comm',
          baseMin: 12000.0,
          baseSuggested: 18000.0,
          baseMax: 35000.0,
          summaryHint: 'Multi-screen mobile app or store with checkout',
        ),
      ],
    ),
    'graphic_design': FreelancerPricingConfig(
      categoryId: 'graphic_design',
      minHourlyRate: 350.0,
      defaultHourlyRate: 500.0,
      maxHourlyRate: 900.0,
      minHours: 1,
      defaultHours: 2,
      maxHours: 40,
      shortUnitHint: 'From ₹350 · /design or /hr',
      separateCostsTitle: 'Print & Stock Licenses Separate',
      separateCostsDescription:
          'Printing costs, paid stock photography & commercial font licenses are paid separately by client.',
      tiers: [
        FreelancerPackageTier(
          id: 'per_design',
          label: 'Post / Flyer',
          unitLabel: 'design',
          unitPlural: 'designs',
          perUnitMin: 350.0,
          perUnitSuggested: 600.0,
          perUnitMax: 1200.0,
          minUnits: 1,
          defaultUnits: 1,
          maxUnits: 30,
          summaryHint: 'Social media creatives, posters, thumbnails or banners',
        ),
        FreelancerPackageTier(
          id: 'logo_pack',
          label: 'Logo Package',
          baseMin: 1200.0,
          baseSuggested: 2000.0,
          baseMax: 3500.0,
          summaryHint: '2 concepts, source SVG/PNG files & revisions',
        ),
        FreelancerPackageTier(
          id: 'brand_kit',
          label: 'Full Brand Kit',
          baseMin: 3500.0,
          baseSuggested: 5500.0,
          baseMax: 9000.0,
          summaryHint: 'Logo, palette, typography guide & business cards',
        ),
        FreelancerPackageTier(
          id: 'brochure_pages',
          label: 'Brochure / Menu',
          unitLabel: 'page',
          unitPlural: 'pages',
          perUnitMin: 400.0,
          perUnitSuggested: 650.0,
          perUnitMax: 1200.0,
          minUnits: 1,
          defaultUnits: 2,
          maxUnits: 24,
          summaryHint: 'Print-ready multi-page menu, catalogue or flyer',
        ),
      ],
    ),
    'video_audio_editing': FreelancerPricingConfig(
      categoryId: 'video_audio_editing',
      minHourlyRate: 400.0,
      defaultHourlyRate: 600.0,
      maxHourlyRate: 1000.0,
      minHours: 1,
      defaultHours: 2,
      maxHours: 40,
      shortUnitHint: 'From ₹400 · /reel or /hr',
      separateCostsTitle: 'Licensed Music & B-Roll Separate',
      separateCostsDescription:
          'Paid music/SFX licenses, stock footage & AI voiceover credits are paid separately if requested.',
      tiers: [
        FreelancerPackageTier(
          id: 'short_reel',
          label: 'Reel / Short',
          unitLabel: 'reel',
          unitPlural: 'reels',
          perUnitMin: 400.0,
          perUnitSuggested: 750.0,
          perUnitMax: 1500.0,
          minUnits: 1,
          defaultUnits: 1,
          maxUnits: 30,
          summaryHint: 'Vertical edit up to 60s with captions, cuts & BGM',
        ),
        FreelancerPackageTier(
          id: 'long_video_mins',
          label: 'Long Video (/min)',
          unitLabel: 'min',
          unitPlural: 'mins',
          baseMin: 600.0,
          baseSuggested: 1000.0,
          baseMax: 1500.0,
          perUnitMin: 400.0,
          perUnitSuggested: 600.0,
          perUnitMax: 1000.0,
          minUnits: 1,
          defaultUnits: 5,
          maxUnits: 45,
          summaryHint: 'Base ₹600 + ₹600/min edited for YouTube or promo videos',
        ),
        FreelancerPackageTier(
          id: 'audio_episode',
          label: 'Audio / Podcast',
          unitLabel: 'episode',
          unitPlural: 'episodes',
          perUnitMin: 400.0,
          perUnitSuggested: 700.0,
          perUnitMax: 1200.0,
          minUnits: 1,
          defaultUnits: 1,
          maxUnits: 20,
          summaryHint: 'Noise removal, levelling, intro/outro & mastering',
        ),
      ],
    ),
    'digital_marketing': FreelancerPricingConfig(
      categoryId: 'digital_marketing',
      minHourlyRate: 500.0,
      defaultHourlyRate: 800.0,
      maxHourlyRate: 1500.0,
      minHours: 1,
      defaultHours: 2,
      maxHours: 40,
      shortUnitHint: 'From ₹500 · /pkg or /hr',
      separateCostsTitle: 'Ad Wallet Spend Separate',
      separateCostsDescription:
          'Meta / Google Ad spend & SMS/CRM credits go straight to your ad account — budget is service fee only.',
      tiers: [
        FreelancerPackageTier(
          id: 'setup_audit',
          label: 'Audit / Setup',
          baseMin: 500.0,
          baseSuggested: 1000.0,
          baseMax: 2500.0,
          summaryHint: 'Google Business Profile, Pixel or quick SEO audit',
        ),
        FreelancerPackageTier(
          id: 'seo_pages',
          label: 'On-Page SEO',
          unitLabel: 'page',
          unitPlural: 'pages',
          perUnitMin: 500.0,
          perUnitSuggested: 800.0,
          perUnitMax: 1500.0,
          minUnits: 1,
          defaultUnits: 3,
          maxUnits: 30,
          summaryHint: 'Keywords, meta tags, speed & schema optimization',
        ),
        FreelancerPackageTier(
          id: 'ads_mgmt',
          label: 'Ads Campaign',
          unitLabel: 'campaign',
          unitPlural: 'campaigns',
          perUnitMin: 2500.0,
          perUnitSuggested: 4000.0,
          perUnitMax: 7500.0,
          minUnits: 1,
          defaultUnits: 1,
          maxUnits: 6,
          summaryHint: 'Meta / Google ad setup, targeting & optimization fee',
        ),
        FreelancerPackageTier(
          id: 'monthly_smm',
          label: 'Social Retainer',
          unitLabel: 'month',
          unitPlural: 'months',
          perUnitMin: 5000.0,
          perUnitSuggested: 8000.0,
          perUnitMax: 15000.0,
          minUnits: 1,
          defaultUnits: 1,
          maxUnits: 6,
          summaryHint: '12–15 posts/reels/month calendar, posting & growth',
        ),
      ],
    ),
    'business_admin': FreelancerPricingConfig(
      categoryId: 'business_admin',
      minHourlyRate: 300.0,
      defaultHourlyRate: 400.0,
      maxHourlyRate: 800.0,
      minHours: 1,
      defaultHours: 2,
      maxHours: 40,
      shortUnitHint: 'From ₹300 · /pkg or /hr',
      separateCostsTitle: 'Software & Portal Fees Separate',
      separateCostsDescription:
          'Paid software seats (MS 365, Tally, Zapier), government portal fees & courier charges are separate.',
      tiers: [
        FreelancerPackageTier(
          id: 'resume_doc',
          label: 'Resume / Doc',
          baseMin: 300.0,
          baseSuggested: 500.0,
          baseMax: 1000.0,
          summaryHint: 'ATS resume makeover, formatting or business letter',
        ),
        FreelancerPackageTier(
          id: 'slides',
          label: 'Pitch Deck (/slide)',
          unitLabel: 'slide',
          unitPlural: 'slides',
          perUnitMin: 150.0,
          perUnitSuggested: 250.0,
          perUnitMax: 450.0,
          minUnits: 2,
          defaultUnits: 10,
          maxUnits: 60,
          summaryHint: 'Designed PowerPoint / Google Slides presentation',
        ),
        FreelancerPackageTier(
          id: 'excel_workbook',
          label: 'Excel / Sheet',
          unitLabel: 'sheet',
          unitPlural: 'sheets',
          perUnitMin: 500.0,
          perUnitSuggested: 1000.0,
          perUnitMax: 2500.0,
          minUnits: 1,
          defaultUnits: 1,
          maxUnits: 15,
          summaryHint: 'Formulas, pivot dashboard or data cleanup workbook',
        ),
        FreelancerPackageTier(
          id: 'translation_pages',
          label: 'Translation / Typing',
          unitLabel: 'page',
          unitPlural: 'pages',
          perUnitMin: 150.0,
          perUnitSuggested: 250.0,
          perUnitMax: 400.0,
          minUnits: 2,
          defaultUnits: 3,
          maxUnits: 50,
          summaryHint: 'Document translation, proofreading or formatting',
        ),
      ],
    ),
    'freelancer': FreelancerPricingConfig(
      categoryId: 'freelancer',
      minHourlyRate: 300.0,
      defaultHourlyRate: 500.0,
      maxHourlyRate: 1200.0,
      minHours: 1,
      defaultHours: 2,
      maxHours: 40,
      shortUnitHint: 'From ₹300 · /project or /hr',
      separateCostsTitle: 'Third-Party Tools & Assets Separate',
      separateCostsDescription:
          'Domain, hosting, ad spend, printing & paid software licenses are billed directly to client.',
      tiers: [
        FreelancerPackageTier(
          id: 'general_project',
          label: 'Standard Project',
          baseMin: 300.0,
          baseSuggested: 500.0,
          baseMax: 1500.0,
          summaryHint: 'Single milestone freelance deliverable',
        ),
      ],
    ),
  };

  static FreelancerPricingConfig? freelancerPricingConfigFor(String category) {
    final c = category.toLowerCase().replaceAll('-', '_');
    return _freelancerPricingConfigs[c];
  }

  static String freelancerShortUnitHint(String category) {
    return freelancerPricingConfigFor(category)?.shortUnitHint ??
        'From ₹${minBudgetForCategory(category).toInt()}';
  }

  static FreelancerPriceQuote calculateFreelancerQuote(
    String category, {
    String mode = 'package',
    String? tierId,
    int? units,
    double? hourlyRate,
    int? hours,
  }) {
    final cat = category.toLowerCase().replaceAll('-', '_');
    final cfg = freelancerPricingConfigFor(cat) ?? _freelancerPricingConfigs['freelancer']!;
    final entryFloor = minBudgetForCategory(cat);

    if (mode == 'hourly') {
      final effHours = (hours ?? cfg.defaultHours).clamp(cfg.minHours, cfg.maxHours);
      final rawRate = hourlyRate ?? cfg.defaultHourlyRate;
      final effRate = rawRate < cfg.minHourlyRate
          ? cfg.minHourlyRate
          : (rawRate > 10000.0 ? 10000.0 : rawRate);
      double minB = (cfg.minHourlyRate * effHours).roundToDouble();
      if (minB < entryFloor) minB = entryFloor;
      double sugB = (effRate * effHours).roundToDouble();
      if (sugB < minB) sugB = minB;
      double maxB = (cfg.maxHourlyRate * effHours).roundToDouble();
      if (maxB <= sugB) maxB = (sugB * 1.35).roundToDouble();

      final hrsLabel = effHours == 1 ? '1 hr' : '$effHours hrs';
      return FreelancerPriceQuote(
        pricingMode: 'hourly',
        scopeSummary: 'Hourly (₹${effRate.toInt()}/hr × $hrsLabel)',
        minBudget: minB,
        suggestedBudget: sugB,
        maxBudget: maxB,
        hourlyRate: effRate,
        hours: effHours,
        separateCostsTitle: cfg.separateCostsTitle,
        separateCostsDescription: cfg.separateCostsDescription,
      );
    }

    final tier = cfg.tierById(tierId);
    final effUnits = tier.usesUnits
        ? (units ?? tier.defaultUnits).clamp(tier.minUnits, tier.maxUnits)
        : 1;
    double minB = (tier.baseMin + (tier.usesUnits ? effUnits * tier.perUnitMin : 0.0)).roundToDouble();
    if (minB < entryFloor) minB = entryFloor;
    double sugB = (tier.baseSuggested + (tier.usesUnits ? effUnits * tier.perUnitSuggested : 0.0)).roundToDouble();
    if (sugB < minB) sugB = minB;
    double maxB = (tier.baseMax + (tier.usesUnits ? effUnits * tier.perUnitMax : 0.0)).roundToDouble();
    if (maxB <= sugB) maxB = (sugB * 1.35).roundToDouble();

    final summary = tier.usesUnits
        ? '${tier.label} ($effUnits ${effUnits == 1 ? tier.unitLabel : tier.unitPlural})'
        : tier.label;

    return FreelancerPriceQuote(
      pricingMode: 'package',
      scopeSummary: summary,
      minBudget: minB,
      suggestedBudget: sugB,
      maxBudget: maxB,
      tier: tier,
      units: tier.usesUnits ? effUnits : null,
      separateCostsTitle: cfg.separateCostsTitle,
      separateCostsDescription: cfg.separateCostsDescription,
    );
  }

  static int? _extractUnitCount(String text, List<String> nouns) {
    final nounPattern = nouns.map(RegExp.escape).join('|');
    final rx = RegExp(
      '\\b(\\d{1,3})\\s*(?:[a-zA-Z]+\\s+){0,2}(?:$nounPattern)s?\\b',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  static FreelancerDetailsSuggestion suggestFreelancerFromDetails(
    String category, {
    String title = '',
    String description = '',
  }) {
    final cat = _normalizeCategoryKey(category);
    final cfg = freelancerPricingConfigFor(cat) ?? _freelancerPricingConfigs['freelancer']!;

    // Strip auto-generated scope/excluded lines so re-compilation doesn't loop.
    final cleanedDescLines = description
        .split('\n')
        .where((line) {
          final l = line.trim().toLowerCase();
          return !l.startsWith('• pricing scope:') &&
              !l.startsWith('• excluded costs:') &&
              !l.startsWith('• domain & hosting:');
        })
        .join(' ');
    final combined = '${title.trim()} $cleanedDescLines'.trim().toLowerCase();

    if (combined.isEmpty) {
      final defaultTier = cfg.tiers.first;
      final q = calculateFreelancerQuote(
        cat,
        mode: 'package',
        tierId: defaultTier.id,
        units: defaultTier.defaultUnits,
      );
      return FreelancerDetailsSuggestion(
        mode: 'package',
        tierId: defaultTier.id,
        units: defaultTier.usesUnits ? defaultTier.defaultUnits : null,
        hours: cfg.defaultHours,
        hourlyRate: cfg.defaultHourlyRate,
        hasDetailsMatch: false,
        reason: 'Standard ${q.scopeSummary}',
        quote: q,
      );
    }

    String mode = 'package';
    String tierId = cfg.tiers.first.id;
    int? units = cfg.tiers.first.usesUnits ? cfg.tiers.first.defaultUnits : null;
    int hours = cfg.defaultHours;
    double hourlyRate = cfg.defaultHourlyRate;
    bool matched = false;
    String reason = '';

    bool hasAny(List<String> keywords) =>
        keywords.any((k) => RegExp('\\b${RegExp.escape(k)}', caseSensitive: false).hasMatch(combined));

    final detectedHours = _extractUnitCount(combined, ['hr', 'hour']);

    switch (cat) {
      case 'web_app_tech':
        if (hasAny(['mobile app', 'flutter', 'android', 'ios', 'ecommerce', 'e-commerce', 'shopify', 'store', 'checkout', 'mvp', 'saas', 'full stack'])) {
          tierId = 'app_mvp';
          matched = true;
          reason = 'App / E-commerce scope in task details';
        } else if (hasAny(['landing page', 'one page', 'single page', 'conversion page'])) {
          tierId = 'landing_page';
          matched = true;
          reason = 'Landing page scope in task details';
        } else if (hasAny(['bug', 'fix', 'error', 'issue', 'debug', 'crash', 'script', 'plugin', 'automation'])) {
          tierId = 'bug_fix';
          matched = true;
          reason = 'Bug fix / script scope in task details';
        } else if (hasAny(['website', 'site', 'wordpress', 'react', 'web app', 'page', 'screen'])) {
          tierId = 'website_pages';
          final pages = _extractUnitCount(combined, ['page', 'screen']);
          if (pages != null && pages > 0) {
            units = pages;
            reason = '$pages ${pages == 1 ? 'page' : 'pages'} detected in task details';
          } else {
            units = 1;
            reason = 'Website scope detected in task details';
          }
          matched = true;
        } else if (detectedHours != null && detectedHours > 0) {
          mode = 'hourly';
          hours = detectedHours;
          matched = true;
          reason = '$hours ${hours == 1 ? 'hr' : 'hrs'} estimated in task details';
        }
        break;

      case 'graphic_design':
        if (hasAny(['brand kit', 'brand identity', 'branding', 'stationery', 'guidelines'])) {
          tierId = 'brand_kit';
          matched = true;
          reason = 'Full Brand Kit detected in task details';
        } else if (hasAny(['logo'])) {
          tierId = 'logo_pack';
          matched = true;
          reason = 'Logo package detected in task details';
        } else if (hasAny(['brochure', 'menu', 'catalogue', 'catalog', 'booklet', 'pamphlet'])) {
          tierId = 'brochure_pages';
          final pages = _extractUnitCount(combined, ['page', 'side']);
          units = (pages != null && pages > 0) ? pages : 2;
          matched = true;
          reason = '$units-page brochure/menu scope in task details';
        } else if (hasAny(['poster', 'flyer', 'banner', 'thumbnail', 'instagram', 'social', 'post', 'creative', 'design'])) {
          tierId = 'per_design';
          final cnt = _extractUnitCount(combined, ['design', 'post', 'poster', 'flyer', 'banner', 'thumbnail', 'creative']);
          units = (cnt != null && cnt > 0) ? cnt : 1;
          matched = true;
          reason = '$units ${units == 1 ? 'design' : 'designs'} detected in task details';
        } else if (detectedHours != null && detectedHours > 0) {
          mode = 'hourly';
          hours = detectedHours;
          matched = true;
          reason = '$hours ${hours == 1 ? 'hr' : 'hrs'} estimated in task details';
        }
        break;

      case 'video_audio_editing':
        if (hasAny(['podcast', 'audio', 'voiceover', 'voice', 'episode', 'mastering', 'noise'])) {
          tierId = 'audio_episode';
          final eps = _extractUnitCount(combined, ['episode', 'track', 'audio', 'podcast']);
          units = (eps != null && eps > 0) ? eps : 1;
          matched = true;
          reason = '$units audio/podcast ${units == 1 ? 'episode' : 'episodes'} in task details';
        } else if (hasAny(['youtube', 'long video', 'documentary', 'explainer', 'vlog', 'promo video']) ||
            _extractUnitCount(combined, ['min', 'minute']) != null) {
          tierId = 'long_video_mins';
          final mins = _extractUnitCount(combined, ['min', 'minute']);
          units = (mins != null && mins > 0) ? mins : 5;
          matched = true;
          reason = '$units min video edit detected in task details';
        } else if (hasAny(['reel', 'reels', 'short', 'shorts', 'vertical', 'instagram', 'tiktok'])) {
          tierId = 'short_reel';
          final reels = _extractUnitCount(combined, ['reel', 'short', 'video', 'clip']);
          units = (reels != null && reels > 0) ? reels : 1;
          matched = true;
          reason = '$units ${units == 1 ? 'reel' : 'reels'} detected in task details';
        } else if (detectedHours != null && detectedHours > 0) {
          mode = 'hourly';
          hours = detectedHours;
          matched = true;
          reason = '$hours ${hours == 1 ? 'hr' : 'hrs'} estimated in task details';
        }
        break;

      case 'digital_marketing':
        if (hasAny(['monthly', 'retainer', 'month', 'smm', 'social media management', 'manage instagram'])) {
          tierId = 'monthly_smm';
          final mos = _extractUnitCount(combined, ['month']);
          units = (mos != null && mos > 0) ? mos : 1;
          matched = true;
          reason = '$units month social retainer in task details';
        } else if (hasAny(['ads', 'meta', 'facebook', 'google ads', 'ppc', 'campaign', 'lead gen'])) {
          tierId = 'ads_mgmt';
          final camps = _extractUnitCount(combined, ['campaign', 'ad']);
          units = (camps != null && camps > 0) ? camps : 1;
          matched = true;
          reason = 'Ads campaign setup/mgmt in task details';
        } else if (hasAny(['seo', 'on-page', 'keyword', 'ranking', 'schema', 'backlink'])) {
          tierId = 'seo_pages';
          final pages = _extractUnitCount(combined, ['page', 'url', 'blog', 'article']);
          units = (pages != null && pages > 0) ? pages : 3;
          matched = true;
          reason = 'SEO ($units pages) detected in task details';
        } else if (hasAny(['audit', 'pixel', 'analytics', 'google business', 'gbp'])) {
          tierId = 'setup_audit';
          matched = true;
          reason = 'Audit / setup scope in task details';
        } else if (detectedHours != null && detectedHours > 0) {
          mode = 'hourly';
          hours = detectedHours;
          matched = true;
          reason = '$hours ${hours == 1 ? 'hr' : 'hrs'} estimated in task details';
        }
        break;

      case 'business_admin':
        if (hasAny(['pitch deck', 'deck', 'ppt', 'powerpoint', 'slides', 'slide', 'presentation'])) {
          tierId = 'slides';
          final sl = _extractUnitCount(combined, ['slide']);
          units = (sl != null && sl >= 2) ? sl : 10;
          matched = true;
          reason = '$units slides presentation in task details';
        } else if (hasAny(['excel', 'spreadsheet', 'sheet', 'pivot', 'macro', 'vba', 'dashboard', 'formula'])) {
          tierId = 'excel_workbook';
          final sh = _extractUnitCount(combined, ['sheet', 'workbook', 'tab', 'dashboard']);
          units = (sh != null && sh > 0) ? sh : 1;
          matched = true;
          reason = 'Excel / workbook ($units) in task details';
        } else if (hasAny(['translate', 'translation', 'proofread', 'typing', 'transcription', 'type'])) {
          tierId = 'translation_pages';
          final pg = _extractUnitCount(combined, ['page', 'doc', 'document']);
          units = (pg != null && pg >= 2) ? pg : 3;
          matched = true;
          reason = 'Translation/typing ($units pages) in task details';
        } else if (hasAny(['resume', 'cv', 'cover letter', 'linkedin', 'letter'])) {
          tierId = 'resume_doc';
          matched = true;
          reason = 'Resume / document makeover in task details';
        } else if (detectedHours != null && detectedHours > 0) {
          mode = 'hourly';
          hours = detectedHours;
          matched = true;
          reason = '$hours ${hours == 1 ? 'hr' : 'hrs'} estimated in task details';
        }
        break;

      case 'freelancer':
      default:
        if (detectedHours != null && detectedHours > 0) {
          mode = 'hourly';
          hours = detectedHours;
          matched = true;
          reason = '$hours ${hours == 1 ? 'hr' : 'hrs'} scope in task details';
        } else if (hasAny(['website', 'app', 'ecommerce', 'dashboard', 'full'])) {
          mode = 'hourly';
          hours = 4;
          matched = true;
          reason = 'Multi-step project scope in task details';
        } else if (hasAny(['urgent', 'asap', 'complex', 'custom', 'content', 'writing', 'article'])) {
          mode = 'hourly';
          hours = 2;
          matched = true;
          reason = 'Custom freelance scope in task details';
        }
        break;
    }

    var quote = calculateFreelancerQuote(
      cat,
      mode: mode,
      tierId: tierId,
      units: units,
      hourlyRate: hourlyRate,
      hours: hours,
    );

    // Subtle urgency/complexity uplift (+20% rounded to ₹50) when urgent delivery or 4K/motion cues exist
    final isUrgentOrComplex = hasAny(['urgent', 'asap', 'same day', '4k', 'motion graphics', 'animation', 'custom api']);
    if (isUrgentOrComplex) {
      final bumpSug = ((quote.suggestedBudget * 1.20) / 50).round() * 50.0;
      final adjSug = bumpSug > quote.suggestedBudget ? bumpSug : quote.suggestedBudget;
      final adjMax = quote.maxBudget <= adjSug ? (adjSug * 1.35).roundToDouble() : quote.maxBudget;
      quote = FreelancerPriceQuote(
        pricingMode: quote.pricingMode,
        scopeSummary: '${quote.scopeSummary} · Priority',
        minBudget: quote.minBudget,
        suggestedBudget: adjSug,
        maxBudget: adjMax,
        hourlyRate: quote.hourlyRate,
        hours: quote.hours,
        tier: quote.tier,
        units: quote.units,
        separateCostsTitle: quote.separateCostsTitle,
        separateCostsDescription: quote.separateCostsDescription,
      );
      matched = true;
      reason = reason.isNotEmpty
          ? '$reason (+priority uplift)'
          : 'Priority / complex scope in task details';
    }

    if (reason.isEmpty) {
      reason = 'Based on ${quote.scopeSummary} (no location required)';
    }

    return FreelancerDetailsSuggestion(
      mode: mode,
      tierId: tierId,
      units: units,
      hours: hours,
      hourlyRate: hourlyRate,
      hasDetailsMatch: matched,
      reason: reason,
      quote: quote,
    );
  }

  static bool _matchesAreaToken(String areaLower, String token) {
    final escaped = RegExp.escape(token);
    return RegExp('(^|[\\s,/\\-])$escaped(\$|[\\s,/\\-])').hasMatch(areaLower);
  }

  static String _formatLocalityTitle(String raw) {
    const upperAcronyms = {'bkc', 'omr', 'hsr', 'btm', 'dlf', 'mg', 'sb', 'fc', 'jm', 'jp', 'nibm', 'sg', 'ncr'};
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) {
          final lower = w.toLowerCase();
          if (upperAcronyms.contains(lower)) return lower.toUpperCase();
          return w.length > 1 ? w[0].toUpperCase() + lower.substring(1) : w.toUpperCase();
        })
        .join(' ');
  }

  static String _extractFallbackLocality(String areaText) {
    final segments = areaText
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final skipGeneric = RegExp(
      r'^(flat|house|plot|shop|room|floor|wing|bldg|building|sector|phase|block|apt|apartment|society|road|rd|near|opp|opposite|behind|india|maharashtra|karnataka|delhi|telangana|tamil nadu|west bengal|gujarat|\d+[a-z]?|\d{5,6})$',
      caseSensitive: false,
    );
    for (final seg in segments) {
      if (RegExp(r'^\d+$').hasMatch(seg)) continue;
      final firstWord = seg.split(RegExp(r'\s+')).first;
      if (skipGeneric.hasMatch(seg) ||
          RegExp(r'^(flat|house|plot|shop|room|floor)\b', caseSensitive: false).hasMatch(firstWord)) {
        continue;
      }
      final cleaned = seg.replaceAll(RegExp(r'\s*\b\d{6}\b$'), '').trim();
      if (cleaned.length >= 2) {
        return _formatLocalityTitle(cleaned);
      }
    }
    if (segments.isNotEmpty) {
      return _formatLocalityTitle(segments.first);
    }
    return 'Your Area';
  }

  static CategoryBudgetSuggestion getBudgetSuggestion(
    String category, {
    String? areaText,
    double? distanceKm,
    String vehicle = 'bike',
    String? freelancerMode,
    String? tierId,
    int? units,
    double? hourlyRate,
    int? hours,
    String? title,
    String? description,
  }) {
    final cat = _normalizeCategoryKey(category);
    if (isFreelancerCategory(cat)) {
      if (freelancerMode != null) {
        final q = calculateFreelancerQuote(
          cat,
          mode: freelancerMode,
          tierId: tierId,
          units: units,
          hourlyRate: hourlyRate,
          hours: hours,
        );
        return CategoryBudgetSuggestion(
          minBudget: q.minBudget,
          suggestedBudget: q.suggestedBudget,
          maxBudget: q.maxBudget,
          localityName: freelancerMode == 'hourly' ? 'Hourly Rate' : 'Task Scope',
          localityTier: q.scopeSummary,
        );
      }
      final det = suggestFreelancerFromDetails(
        cat,
        title: title ?? '',
        description: description ?? '',
      );
      return CategoryBudgetSuggestion(
        minBudget: det.quote.minBudget,
        suggestedBudget: det.quote.suggestedBudget,
        maxBudget: det.quote.maxBudget,
        localityName: det.hasDetailsMatch ? 'Task Details' : 'Remote Service',
        localityTier: det.reason,
      );
    }
    final areaRaw = (areaText ?? '').trim();
    final areaLower = areaRaw.toLowerCase();

    double multiplier = 1.0;
    String tier = 'Standard Area';
    String detectedName = 'Your Area';

    // 1. Premium & IT / High-Demand Hubs nationwide (1.25x)
    const premiumAreas = <String, String>{
      // Pune
      'koregaon park': 'IT & High-Demand Hub',
      'kalyani nagar': 'IT & High-Demand Hub',
      'viman nagar': 'IT & High-Demand Hub',
      'model colony': 'IT & High-Demand Hub',
      'senapati bapat': 'IT & High-Demand Hub',
      'boat club': 'IT & High-Demand Hub',
      'prabhat road': 'IT & High-Demand Hub',
      'sb road': 'IT & High-Demand Hub',
      'hinjewadi': 'IT & High-Demand Hub',
      'balewadi': 'IT & High-Demand Hub',
      'magarpatta': 'IT & High-Demand Hub',
      'koregaon': 'IT & High-Demand Hub',
      'kalyani': 'IT & High-Demand Hub',
      'kharadi': 'IT & High-Demand Hub',
      'baner': 'IT & High-Demand Hub',
      'wakad': 'IT & High-Demand Hub',
      'aundh': 'IT & High-Demand Hub',
      'bavdhan': 'IT & High-Demand Hub',
      'pashan': 'IT & High-Demand Hub',
      'viman': 'IT & High-Demand Hub',
      'prabhat': 'IT & High-Demand Hub',
      // Mumbai
      'bandra kurla': 'Metro High-Demand Hub',
      'nariman point': 'Metro High-Demand Hub',
      'cuffe parade': 'Metro High-Demand Hub',
      'malabar hill': 'Metro High-Demand Hub',
      'lower parel': 'Metro High-Demand Hub',
      'andheri west': 'Metro High-Demand Hub',
      'goregaon east': 'Metro High-Demand Hub',
      'bandra': 'Metro High-Demand Hub',
      'worli': 'Metro High-Demand Hub',
      'powai': 'Metro High-Demand Hub',
      'juhu': 'Metro High-Demand Hub',
      'colaba': 'Metro High-Demand Hub',
      'prabhadevi': 'Metro High-Demand Hub',
      'versova': 'Metro High-Demand Hub',
      'bkc': 'Metro High-Demand Hub',
      // Bengaluru
      'electronic city': 'IT & High-Demand Hub',
      'sadashivanagar': 'Metro High-Demand Hub',
      'hsr layout': 'IT & High-Demand Hub',
      'marathahalli': 'IT & High-Demand Hub',
      'koramangala': 'IT & High-Demand Hub',
      'indiranagar': 'IT & High-Demand Hub',
      'whitefield': 'IT & High-Demand Hub',
      'bellandur': 'IT & High-Demand Hub',
      'sarjapur': 'IT & High-Demand Hub',
      'manyata': 'IT & High-Demand Hub',
      'mg road': 'Metro High-Demand Hub',
      'ulsoor': 'Metro High-Demand Hub',
      'hebbal': 'IT & High-Demand Hub',
      'hsr': 'IT & High-Demand Hub',
      // Delhi NCR
      'connaught place': 'Metro High-Demand Hub',
      'golf course road': 'IT & High-Demand Hub',
      'greater kailash': 'Metro High-Demand Hub',
      'defence colony': 'Metro High-Demand Hub',
      'south extension': 'Metro High-Demand Hub',
      'chanakyapuri': 'Metro High-Demand Hub',
      'vasant vihar': 'Metro High-Demand Hub',
      'vasant kunj': 'Metro High-Demand Hub',
      'cyber city': 'IT & High-Demand Hub',
      'dlf phase': 'IT & High-Demand Hub',
      'hauz khas': 'Metro High-Demand Hub',
      'saket': 'Metro High-Demand Hub',
      'dlf': 'IT & High-Demand Hub',
      // Hyderabad
      'financial district': 'IT & High-Demand Hub',
      'jubilee hills': 'Metro High-Demand Hub',
      'banjara hills': 'Metro High-Demand Hub',
      'hitec city': 'IT & High-Demand Hub',
      'hitech city': 'IT & High-Demand Hub',
      'gachibowli': 'IT & High-Demand Hub',
      'madhapur': 'IT & High-Demand Hub',
      'kondapur': 'IT & High-Demand Hub',
      'kokapet': 'IT & High-Demand Hub',
      // Chennai
      'besant nagar': 'Metro High-Demand Hub',
      'nungambakkam': 'Metro High-Demand Hub',
      'sholinganallur': 'IT & High-Demand Hub',
      'anna nagar': 'Metro High-Demand Hub',
      'poes garden': 'Metro High-Demand Hub',
      'alwarpet': 'Metro High-Demand Hub',
      't nagar': 'Metro High-Demand Hub',
      'adyar': 'Metro High-Demand Hub',
      'omr': 'IT & High-Demand Hub',
      // Kolkata
      'ballygunge': 'Metro High-Demand Hub',
      'park street': 'Metro High-Demand Hub',
      'salt lake': 'IT & High-Demand Hub',
      'sector v': 'IT & High-Demand Hub',
      'new town': 'IT & High-Demand Hub',
      'alipore': 'Metro High-Demand Hub',
      // Ahmedabad
      'sindhu bhavan': 'Metro High-Demand Hub',
      'prahlad nagar': 'Metro High-Demand Hub',
      'sg highway': 'Metro High-Demand Hub',
      'bodakdev': 'Metro High-Demand Hub',
      'satellite': 'Metro High-Demand Hub',
    };

    // 2. Central & Established City Areas (1.10x)
    const centralAreas = <String, String>{
      // Pune Central
      'shivaji nagar': 'Central Pune',
      'shivajinagar': 'Central Pune',
      'sahakar nagar': 'Central Pune',
      'karve nagar': 'Central Pune',
      'sadashiv peth': 'Central Pune',
      'erandwane': 'Central Pune',
      'bibvewadi': 'Central Pune',
      'wanowrie': 'Central Pune',
      'sadashiv': 'Central Pune',
      'kothrud': 'Central Pune',
      'swargate': 'Central Pune',
      'kondhwa': 'Central Pune',
      'deccan': 'Central Pune',
      'sahakar': 'Central Pune',
      'fc road': 'Central Pune',
      'jm road': 'Central Pune',
      'karve': 'Central Pune',
      'camp': 'Central Pune',
      'nibm': 'Central Pune',
      'peth': 'Central Pune',
      // Mumbai Suburbs / Established
      'vile parle': 'Metro City Area',
      'ghatkopar': 'Metro City Area',
      'santacruz': 'Metro City Area',
      'kandivali': 'Metro City Area',
      'borivali': 'Metro City Area',
      'andheri': 'Metro City Area',
      'goregaon': 'Metro City Area',
      'matunga': 'Metro City Area',
      'chembur': 'Metro City Area',
      'mulund': 'Metro City Area',
      'kharghar': 'Metro City Area',
      'dadar': 'Metro City Area',
      'malad': 'Metro City Area',
      'vashi': 'Metro City Area',
      'kurla': 'Metro City Area',
      'thane': 'Metro City Area',
      // Bengaluru Established
      'malleshwaram': 'Metro City Area',
      'malleswaram': 'Metro City Area',
      'banashankari': 'Metro City Area',
      'rajajinagar': 'Metro City Area',
      'vijayanagar': 'Metro City Area',
      'btm layout': 'Metro City Area',
      'yelahanka': 'Metro City Area',
      'jayanagar': 'Metro City Area',
      'jp nagar': 'Metro City Area',
      'btm': 'Metro City Area',
      // Delhi NCR Established
      'rajouri garden': 'Metro City Area',
      'lajpat nagar': 'Metro City Area',
      'mayur vihar': 'Metro City Area',
      'indirapuram': 'Metro City Area',
      'karol bagh': 'Metro City Area',
      'pitampura': 'Metro City Area',
      'janakpuri': 'Metro City Area',
      'new delhi': 'Metro City Area',
      'gurugram': 'Metro City Area',
      'gurgaon': 'Metro City Area',
      'dwarka': 'Metro City Area',
      'rohini': 'Metro City Area',
      'noida': 'Metro City Area',
      'delhi': 'Metro City Area',
      // Other Metro Hubs & City Names
      'secunderabad': 'Metro City Area',
      'thoraipakkam': 'Metro City Area',
      'tollygunge': 'Metro City Area',
      'navrangpura': 'Metro City Area',
      'velachery': 'Metro City Area',
      'mylapore': 'Metro City Area',
      'bengaluru': 'Metro City Area',
      'bangalore': 'Metro City Area',
      'hyderabad': 'Metro City Area',
      'ahmedabad': 'Metro City Area',
      'chandigarh': 'Metro City Area',
      'guindy': 'Metro City Area',
      'behala': 'Metro City Area',
      'bopal': 'Metro City Area',
      'mumbai': 'Metro City Area',
      'chennai': 'Metro City Area',
      'kolkata': 'Metro City Area',
      'pune': 'Metro City Area',
    };

    // 3. Suburban / Developing & Tier-2 Cities (1.0x)
    const broadCityTokens = <String>{
      'nashik', 'surat', 'kochi', 'patna', 'jaipur', 'indore', 'bhopal',
      'nagpur', 'lucknow', 'vadodara', 'coimbatore', 'visakhapatnam',
      'howrah', 'faridabad', 'ghaziabad', 'navi mumbai', 'greater noida',
      'mohali', 'mumbai', 'pune', 'bengaluru', 'bangalore', 'delhi',
      'new delhi', 'hyderabad', 'chennai', 'kolkata', 'ahmedabad',
      'chandigarh', 'gurugram', 'gurgaon', 'noida', 'thane',
    };
    const suburbanAreas = <String>[
      'navi mumbai', 'greater noida', 'visakhapatnam', 'coimbatore',
      'chinchwad', 'tathawade', 'ambegaon', 'dombivli', 'punawale',
      'faridabad', 'ghaziabad', 'vadodara', 'hadapsar', 'pimpri',
      'bhosari', 'wagholi', 'mira road', 'zirakpur', 'lucknow',
      'akurdi', 'kalyan', 'panvel', 'howrah', 'mohali', 'nagpur',
      'jaipur', 'indore', 'bhopal', 'nigdi', 'moshi', 'warje',
      'ravet', 'katraj', 'dhayari', 'vasai', 'virar', 'nashik',
      'surat', 'kochi', 'patna',
    ];

    String? matchedToken;
    if (areaLower.isNotEmpty) {
      for (final entry in premiumAreas.entries) {
        if (_matchesAreaToken(areaLower, entry.key)) {
          multiplier = 1.25;
          tier = entry.value;
          matchedToken = entry.key;
          detectedName = _formatLocalityTitle(entry.key);
          break;
        }
      }
      if (multiplier == 1.0) {
        for (final entry in centralAreas.entries) {
          if (_matchesAreaToken(areaLower, entry.key)) {
            multiplier = 1.10;
            tier = entry.value;
            matchedToken = entry.key;
            detectedName = _formatLocalityTitle(entry.key);
            break;
          }
        }
      }
      if (multiplier == 1.0) {
        for (final a in suburbanAreas) {
          if (_matchesAreaToken(areaLower, a)) {
            multiplier = 1.0;
            tier = 'Suburban Hub';
            matchedToken = a;
            detectedName = _formatLocalityTitle(a);
            break;
          }
        }
      }
    }

    if (areaRaw.isNotEmpty &&
        (detectedName == 'Your Area' ||
            (matchedToken != null && broadCityTokens.contains(matchedToken)))) {
      final fallback = _extractFallbackLocality(areaRaw);
      if (fallback != 'Your Area') {
        detectedName = fallback;
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
      case 'waste':
        baseSuggested = 150.0;
        baseMax = 350.0;
        break;
      case 'household':
        baseSuggested = 200.0;
        baseMax = 400.0;
        break;
      case 'tailoring':
        baseSuggested = 250.0;
        baseMax = 600.0;
        break;
      case 'gardening':
        baseSuggested = 350.0;
        baseMax = 700.0;
        break;
      case 'fitness':
        baseSuggested = 400.0;
        baseMax = 900.0;
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
      case 'queue_standing':
        baseSuggested = 250.0;
        baseMax = 450.0;
        break;
      case 'event_help':
        baseSuggested = 550.0;
        baseMax = 1000.0;
        break;
      case 'catering':
        baseSuggested = 1500.0;
        baseMax = 5000.0;
        break;
      case 'data_entry':
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
      case 'graphic_design':
        baseSuggested = 600.0;
        baseMax = 1500.0;
        break;
      case 'web_app_tech':
        baseSuggested = 1500.0;
        baseMax = 4000.0;
        break;
      case 'video_audio_editing':
        baseSuggested = 750.0;
        baseMax = 2000.0;
        break;
      case 'digital_marketing':
        baseSuggested = 1000.0;
        baseMax = 2500.0;
        break;
      case 'business_admin':
        baseSuggested = 500.0;
        baseMax = 1000.0;
        break;
      case 'photography':
        baseSuggested = 2500.0;
        baseMax = 5500.0;
        break;
      case 'pet_care':
        baseSuggested = 200.0;
        baseMax = 400.0;
        break;
      case 'child_care':
        baseSuggested = 300.0;
        baseMax = 600.0;
        break;
      case 'elder_care':
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

    final catMin = minBudgetForCategory(cat, vehicle: vehicle);
    const distCats = {'delivery', 'pickup', 'transport', 'moving'};
    final distFloor = (distCats.contains(cat) && distanceKm != null && distanceKm > 0)
        ? calculateDistancePrice(distanceKm, cat, vehicle: vehicle)
        : 0.0;
    final minB = distFloor > catMin ? distFloor : catMin;
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
        return 0; // extra service charge removed (distance included in budget)
      case 'moving':
        return 0; // extra service charge removed for moving
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
    TaskCategory(id: 'carpentry', label: 'Carpentry', icon: '🛠️'),
    TaskCategory(id: 'painting', label: 'Painting', icon: '🎨'),
    TaskCategory(id: 'repair', label: 'Repair', icon: '🔨'),
    TaskCategory(id: 'vehicle', label: 'Vehicle', icon: '🚘'),
    TaskCategory(id: 'tutoring', label: 'Tutoring', icon: '📚'),
    TaskCategory(id: 'freelancer', label: 'Freelancer', icon: '💼'),
    TaskCategory(id: 'graphic_design', label: 'Graphic Design & Branding', icon: '🎨'),
    TaskCategory(id: 'web_app_tech', label: 'Web, App & Tech Projects', icon: '🌐'),
    TaskCategory(id: 'video_audio_editing', label: 'Video & Audio Editing', icon: '🎬'),
    TaskCategory(id: 'digital_marketing', label: 'Digital Marketing', icon: '📣'),
    TaskCategory(id: 'business_admin', label: 'Business, Office & Admin', icon: '📊'),
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

  static const Set<String> subcatAssetIds = {
    'beauty',
    'business_admin',
    'carpentry',
    'child_care',
    'cleaning',
    'cooking',
    'data_entry',
    'delivery',
    'digital_marketing',
    'elder_care',
    'electrician',
    'errands',
    'event_help',
    'freelancer',
    'gardening',
    'graphic_design',
    'groceries',
    'household',
    'laundry',
    'moving',
    'other',
    'painting',
    'pet_care',
    'photography',
    'plumbing',
    'queue_standing',
    'repair',
    'shopping',
    'tech_support',
    'tutoring',
    'vehicle',
    'video_audio_editing',
    'web_app_tech',
  };

  /// Returns the custom squircle PNG asset path for [category], or null.
  static String? subcatAssetFor(String category) {
    if (subcatAssetIds.contains(category)) {
      return 'assets/images/subcats/$category.png';
    }
    return null;
  }

  /// Returns the icon emoji for [category], falling back to '📋' if not found.
  static String iconFor(String category) {
    return all.firstWhere(
      (c) => c.id == category,
      orElse: () => const TaskCategory(id: '', label: '', icon: '📋'),
    ).icon;
  }
}

class FreelancerPackageTier {
  final String id;
  final String label;
  final String unitLabel;
  final String unitPlural;
  final double baseMin;
  final double baseSuggested;
  final double baseMax;
  final double perUnitMin;
  final double perUnitSuggested;
  final double perUnitMax;
  final int minUnits;
  final int defaultUnits;
  final int maxUnits;
  final String summaryHint;

  const FreelancerPackageTier({
    required this.id,
    required this.label,
    this.unitLabel = '',
    this.unitPlural = '',
    this.baseMin = 0.0,
    this.baseSuggested = 0.0,
    this.baseMax = 0.0,
    this.perUnitMin = 0.0,
    this.perUnitSuggested = 0.0,
    this.perUnitMax = 0.0,
    this.minUnits = 1,
    this.defaultUnits = 1,
    this.maxUnits = 1,
    this.summaryHint = '',
  });

  bool get usesUnits => perUnitMin > 0 && maxUnits > 1;
}

class FreelancerPricingConfig {
  final String categoryId;
  final List<FreelancerPackageTier> tiers;
  final double minHourlyRate;
  final double defaultHourlyRate;
  final double maxHourlyRate;
  final int minHours;
  final int defaultHours;
  final int maxHours;
  final String shortUnitHint;
  final String separateCostsTitle;
  final String separateCostsDescription;

  const FreelancerPricingConfig({
    required this.categoryId,
    required this.tiers,
    required this.minHourlyRate,
    required this.defaultHourlyRate,
    required this.maxHourlyRate,
    this.minHours = 1,
    this.defaultHours = 2,
    this.maxHours = 40,
    required this.shortUnitHint,
    required this.separateCostsTitle,
    required this.separateCostsDescription,
  });

  FreelancerPackageTier tierById(String? id) {
    if (id != null) {
      for (final t in tiers) {
        if (t.id == id) return t;
      }
    }
    return tiers.first;
  }
}

class FreelancerPriceQuote {
  final String pricingMode;
  final String scopeSummary;
  final double minBudget;
  final double suggestedBudget;
  final double maxBudget;
  final double? hourlyRate;
  final int? hours;
  final FreelancerPackageTier? tier;
  final int? units;
  final String separateCostsTitle;
  final String separateCostsDescription;

  const FreelancerPriceQuote({
    required this.pricingMode,
    required this.scopeSummary,
    required this.minBudget,
    required this.suggestedBudget,
    required this.maxBudget,
    this.hourlyRate,
    this.hours,
    this.tier,
    this.units,
    required this.separateCostsTitle,
    required this.separateCostsDescription,
  });
}

class FreelancerDetailsSuggestion {
  final String mode;
  final String tierId;
  final int? units;
  final int hours;
  final double hourlyRate;
  final bool hasDetailsMatch;
  final String reason;
  final FreelancerPriceQuote quote;

  const FreelancerDetailsSuggestion({
    required this.mode,
    required this.tierId,
    required this.units,
    required this.hours,
    required this.hourlyRate,
    required this.hasDetailsMatch,
    required this.reason,
    required this.quote,
  });
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

  static const List<String> freelancerChildIds = [
    'graphic_design',
    'web_app_tech',
    'video_audio_editing',
    'digital_marketing',
    'business_admin',
  ];

  static const TaskCategoryGroup freelancerGroup = TaskCategoryGroup(
    label: 'Freelancer',
    icon: '💼',
    categoryIds: freelancerChildIds,
  );

  bool containsCategory(String id) {
    if (categoryIds.contains(id)) return true;
    if (categoryIds.contains('freelancer') && freelancerChildIds.contains(id)) {
      return true;
    }
    return false;
  }

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
      categoryIds: ['repair', 'electrician', 'plumbing', 'carpentry', 'vehicle'],
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
      categoryIds: ['freelancer', 'data_entry', 'photography', 'tutoring', 'painting', 'tech_support'],
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
