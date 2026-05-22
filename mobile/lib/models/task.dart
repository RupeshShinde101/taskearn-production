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
  });

  // Parse a date string that may be ISO-8601 or RFC-2822
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    final s = value.toString().trim();
    // Try ISO-8601 first
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // Fallback: today (RFC-2822 format not natively supported)
    return DateTime.now();
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
      latitude: double.tryParse(
          (locLat ?? json['latitude'] ?? json['lat'] ?? json['location_lat'] ?? 0).toString()
      ) ?? 0.0,
      longitude: double.tryParse(
          (locLng ?? json['longitude'] ?? json['lng'] ?? json['location_lng'] ?? 0).toString()
      ) ?? 0.0,
      address: locAddr?.toString()
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
      acceptedAt: json['accepted_at'] != null ? _parseDate(json['accepted_at']) : null,
      completedAt: json['completed_at'] != null ? _parseDate(json['completed_at']) : null,
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
                : (json['poster_phone']?.toString() ?? json['phone']?.toString());
          })(),
      isPaid: json['is_paid'] == true || json['status'] == 'paid',
      isHidden: json['is_hidden'] == true,
    );
  }

  double get totalAmount => budget + (serviceCharge ?? 0);

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
    TaskCategory(id: 'pickup', label: 'Pickup', icon: '📦'),
    TaskCategory(id: 'transport', label: 'Transport', icon: '🚗'),
    TaskCategory(id: 'moving', label: 'Moving', icon: '🏠'),
    TaskCategory(id: 'groceries', label: 'Groceries', icon: '🛒'),
    TaskCategory(id: 'cooking', label: 'Cooking', icon: '🍳'),
    TaskCategory(id: 'cleaning', label: 'Cleaning', icon: '🧹'),
    TaskCategory(id: 'laundry', label: 'Laundry', icon: '👕'),
    TaskCategory(id: 'electrician', label: 'Electrician', icon: '⚡'),
    TaskCategory(id: 'plumbing', label: 'Plumbing', icon: '🔧'),
    TaskCategory(id: 'carpentry', label: 'Carpentry', icon: '🪚'),
    TaskCategory(id: 'painting', label: 'Painting', icon: '🎨'),
    TaskCategory(id: 'repair', label: 'Repair', icon: '🔨'),
    TaskCategory(id: 'tutoring', label: 'Tutoring', icon: '📚'),
    TaskCategory(id: 'data_entry', label: 'Data Entry', icon: '💻'),
    TaskCategory(id: 'photography', label: 'Photography', icon: '📷'),
    TaskCategory(id: 'gardening', label: 'Gardening', icon: '🌱'),
    TaskCategory(id: 'pet_care', label: 'Pet Care', icon: '🐾'),
    TaskCategory(id: 'child_care', label: 'Child Care', icon: '👶'),
    TaskCategory(id: 'elder_care', label: 'Elder Care', icon: '👴'),
    TaskCategory(id: 'errands', label: 'Errands', icon: '🏃'),
    TaskCategory(id: 'queue_standing', label: 'Queue Standing', icon: '🕐'),
    TaskCategory(id: 'event_help', label: 'Event Help', icon: '🎉'),
    TaskCategory(id: 'tech_support', label: 'Tech Support', icon: '💡'),
    TaskCategory(id: 'other', label: 'Other', icon: '📋'),
  ];
}
