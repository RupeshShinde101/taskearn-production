class User {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatar;
  final String? bio;
  final double rating;
  final int tasksCompleted;
  final int tasksPosted;
  final bool isKycVerified;
  final bool isSuspended;
  final String? referralCode;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatar,
    this.bio,
    this.rating = 0.0,
    this.tasksCompleted = 0,
    this.tasksPosted = 0,
    this.isKycVerified = false,
    this.isSuspended = false,
    this.referralCode,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      avatar: json['avatar'],
      bio: json['bio'],
      rating: double.tryParse((json['rating'] ?? 0).toString()) ?? 0.0,
      tasksCompleted: json['tasks_completed'] ?? 0,
      tasksPosted: json['tasks_posted'] ?? 0,
      isKycVerified: json['kyc_verified'] ?? false,
      isSuspended: json['is_suspended'] ?? false,
      referralCode: json['referral_code'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'avatar': avatar,
        'bio': bio,
        'rating': rating,
        'tasks_completed': tasksCompleted,
        'tasks_posted': tasksPosted,
        'kyc_verified': isKycVerified,
        'is_suspended': isSuspended,
        'referral_code': referralCode,
        'created_at': createdAt.toIso8601String(),
      };
}
