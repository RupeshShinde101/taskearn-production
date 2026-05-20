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

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      budget: double.tryParse((json['budget'] ?? json['price'] ?? 0).toString()) ?? 0.0,
      serviceCharge: json['service_charge'] != null
          ? double.tryParse(json['service_charge'].toString()) ?? 0.0
          : null,
      status: json['status'] ?? 'posted',
      posterId: json['poster_id']?.toString() ?? '',
      posterName: json['poster_name'] ?? json['poster']?['name'] ?? '',
      posterAvatar: json['poster_avatar'] ?? json['poster']?['avatar'],
      posterRating:
          double.tryParse((json['poster_rating'] ?? json['poster']?['rating'] ?? 0).toString()) ?? 0.0,
      helperId: json['helper_id']?.toString(),
      helperName: json['helper_name'] ?? json['helper']?['name'],
      latitude: double.tryParse((json['latitude'] ?? json['lat'] ?? 0).toString()) ?? 0.0,
      longitude: double.tryParse((json['longitude'] ?? json['lng'] ?? 0).toString()) ?? 0.0,
      address: json['address'],
      city: json['city'],
      distanceKm: json['distance_km'] != null
          ? double.tryParse(json['distance_km'].toString()) ?? 0.0
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.tryParse(json['accepted_at'])
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'])
          : null,
      helperRating: json['helper_rating'] != null
          ? double.tryParse(json['helper_rating'].toString()) ?? 0.0
          : null,
      completionProof: json['completion_proof'],
      isPaid: json['is_paid'] ?? false,
      isHidden: json['is_hidden'] ?? false,
    );
  }

  double get totalAmount => budget + (serviceCharge ?? 0);

  String get statusLabel {
    switch (status) {
      case 'posted':
        return 'Open';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'verified':
        return 'Verified';
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
