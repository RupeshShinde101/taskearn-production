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

  // Parse a date string that may be ISO-8601 or RFC-2822.
  // PostgreSQL returns UTC timestamps WITHOUT a 'Z' suffix (e.g. "2026-07-13 10:30:00").
  // DateTime.tryParse() without a timezone treats the string as LOCAL time.
  // Fix: if no timezone marker is present, append 'Z' so Dart treats it as UTC
  // and converts to local for display.
  static bool _hasTimezone(String s) =>
      s.endsWith('Z') ||
      s.endsWith('z') ||
      RegExp(r'[+\-]\d{2}:?\d{2}$').hasMatch(s);

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now().toUtc();
    final s = value.toString().trim();
    if (s.isEmpty) return DateTime.now().toUtc();
    final DateTime? iso;
    if (_hasTimezone(s)) {
      iso = DateTime.tryParse(s);
    } else {
      // No timezone marker — server sends UTC; append 'Z' to parse correctly.
      iso = DateTime.tryParse('${s}Z') ?? DateTime.tryParse(s);
    }
    // Always return UTC so microsecondsSinceEpoch gives the true epoch.
    if (iso != null) return iso.isUtc ? iso : iso.toUtc();
    return DateTime.now().toUtc();
  }

  /// Like [_parseDate] but returns null for null/empty/unparseable values.
  static DateTime? _parseDateOrNull(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    final DateTime? iso;
    if (_hasTimezone(s)) {
      iso = DateTime.tryParse(s);
    } else {
      iso = DateTime.tryParse('${s}Z') ?? DateTime.tryParse(s);
    }
    if (iso == null) return null;
    return iso.isUtc ? iso : iso.toUtc();
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
      acceptedAt: _parseDateOrNull(json['accepted_at'] ?? json['acceptedAt']),
      completedAt: _parseDateOrNull(
          json['completed_at'] ?? json['completedAt'] ??
          json['helper_final_completed_at']),  // 'done' tasks use this column
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
      isPaid: json['is_paid'] == true || json['status'] == 'paid',
      isHidden: json['is_hidden'] == true,
      posterHasRatedHelper: json['poster_has_rated_helper'] == true,
      helperHasRatedPoster: json['helper_has_rated_poster'] == true,
      pickupAddress: (pickup is Map ? pickup['address'] : null)?.toString()
          ?? json['pickup_address']?.toString()
          ?? json['pickupAddress']?.toString()
          ?? json['pickup_addr']?.toString()
          ?? json['from_address']?.toString()
          ?? locAddr?.toString(),  // location.address IS the pickup for delivery tasks
      dropAddress: (dropLoc is Map ? dropLoc['address'] : null)?.toString()
          ?? (destination is Map ? destination['address'] : null)?.toString()
          ?? json['drop_location_address']?.toString()
          ?? json['delivery_address']?.toString()
          ?? json['drop_address']?.toString()
          ?? json['dropAddress']?.toString()
          ?? json['deliveryAddress']?.toString()
          ?? json['to_address']?.toString()
          ?? json['destination_address']?.toString(),
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

  double get totalAmount => budget + (serviceCharge ?? 0);

  /// Platform commission rate:
  /// 15% for delivery/pickup/transport/moving; 17% for all other categories.
  static const double platformCommission = 0.15;

  /// Per-task commission rate based on category.
  double get commissionRate {
    const deliveryTypes = {'delivery', 'pickup', 'transport', 'moving'};
    return deliveryTypes.contains(category) ? 0.15 : 0.17;
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

  /// Net amount the helper earns after [platformCommission] is deducted
  /// from the total task value (budget + service charge).
  double get netEarning => totalAmount * (1 - commissionRate);

  /// Max daily releases allowed before 48h suspension.
  static const int maxDailyReleases = 3;

  /// Remaining releases allowed today (0 to maxDailyReleases).
  int get remainingReleases => (maxDailyReleases - dailyReleasesUsed).clamp(0, maxDailyReleases);

  /// True for task categories that involve a pickup-to-drop delivery route.
  bool get isDeliveryType =>
      const {'delivery', 'pickup', 'transport', 'moving'}.contains(category);

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
  final List<String> categoryIds; // ids from TaskCategory.all

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
      label: 'Engineering & Repair',
      icon: '🔧',
      categoryIds: ['electrician', 'plumbing', 'repair', 'carpentry', 'painting', 'vehicle', 'tech_support'],
    ),
    TaskCategoryGroup(
      label: 'Home & Lifestyle',
      icon: '🏠',
      categoryIds: ['cleaning', 'laundry', 'cooking', 'household', 'gardening', 'beauty'],
    ),
    TaskCategoryGroup(
      label: 'Delivery & Moving',
      icon: '🚚',
      categoryIds: ['delivery', 'moving'],
    ),
    TaskCategoryGroup(
      label: 'Shopping & Errands',
      icon: '🛒',
      categoryIds: ['groceries', 'shopping', 'errands', 'event_help', 'queue_standing'],
    ),
    TaskCategoryGroup(
      label: 'Professional',
      icon: '💼',
      categoryIds: ['freelancer', 'data_entry', 'photography', 'tutoring'],
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
