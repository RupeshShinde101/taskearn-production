class User {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatar;
  final String? bio;
  final List<String> skills;
  final double rating;
  final int tasksCompleted;
  final int tasksPosted;
  final bool isKycVerified;
  final String? kycStatus; // 'pending', 'approved', 'rejected', null
  final bool isEmailVerified;
  final bool isSuspended;
  final DateTime? suspendedUntil;
  final String? referralCode;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatar,
    this.bio,
    this.skills = const [],
    this.rating = 0.0,
    this.tasksCompleted = 0,
    this.tasksPosted = 0,
    this.isKycVerified = false,
    this.kycStatus,
    this.isEmailVerified = false,
    this.isSuspended = false,
    this.suspendedUntil,
    this.referralCode,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final kycStatus = json['kyc_status']?.toString();
    return User(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'],
      avatar: json['avatar'] ?? json['profilePhoto'],
      bio: json['bio'],
      skills: (json['skills'] as List? ?? []).map((s) => s.toString()).toList(),
      rating: double.tryParse((json['rating'] ?? 0).toString()) ?? 0.0,
      tasksCompleted: json['tasks_completed'] ?? 0,
      tasksPosted: json['tasks_posted'] ?? 0,
      // Treat as verified when ANY known KYC field indicates approval
      isKycVerified: (json['kyc_verified'] == true) ||
          (json['kycVerified'] == true) ||
          (json['is_kyc_verified'] == true) ||
          (kycStatus == 'approved') ||
          (kycStatus == 'verified') ||
          (json['kycStatus']?.toString() == 'approved') ||
          (json['kycStatus']?.toString() == 'verified'),
      kycStatus: kycStatus ?? json['kycStatus']?.toString(),
      isEmailVerified: json['email_verified'] == true ||
          json['is_email_verified'] == true ||
          json['emailVerified'] == true,
      isSuspended: json['is_suspended'] ?? false,
      suspendedUntil: json['suspended_until'] != null
          ? DateTime.tryParse(json['suspended_until'].toString())
          : (json['suspension_ends_at'] != null
              ? DateTime.tryParse(json['suspension_ends_at'].toString())
              : null),
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
        'skills': skills,
        'rating': rating,
        'tasks_completed': tasksCompleted,
        'tasks_posted': tasksPosted,
        'kyc_verified': isKycVerified,
        'kyc_status': kycStatus,
        'email_verified': isEmailVerified,
        'is_suspended': isSuspended,
        'referral_code': referralCode,
        'created_at': createdAt.toIso8601String(),
      };
}
