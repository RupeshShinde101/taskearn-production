class User {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatar;
  final String? bio;
  final String? gender; // 'male' | 'female' | null
  final List<String> skills;
  final double rating;
  final int tasksCompleted;
  final int tasksPosted;
  final int reviewsCount;
  final String rank;
  final bool isKycVerified;
  final String? kycStatus; // 'pending', 'approved', 'rejected', null
  final bool isEmailVerified;
  final bool isSuspended;
  final DateTime? suspendedUntil;
  final String? referralCode;
  final DateTime createdAt;
  /// Number of task releases made today (resets daily). Max 3 before suspension.
  final int dailyReleaseCount;
  final String? authProvider; // 'email' | 'google' | null

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatar,
    this.bio,
    this.gender,
    this.skills = const [],
    this.rating = 0.0,
    this.tasksCompleted = 0,
    this.tasksPosted = 0,
    this.reviewsCount = 0,
    this.rank = 'New',
    this.isKycVerified = false,
    this.kycStatus,
    this.isEmailVerified = false,
    this.isSuspended = false,
    this.suspendedUntil,
    this.referralCode,
    required this.createdAt,
    this.dailyReleaseCount = 0,
    this.authProvider,
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
      gender: json['gender']?.toString(),
      skills: (json['skills'] as List? ?? []).map((s) => s.toString()).toList(),
      rating: double.tryParse((json['rating'] ?? 0).toString()) ?? 0.0,
      tasksCompleted: json['tasksCompleted'] ?? json['tasks_completed'] ?? 0,
      tasksPosted: json['tasksPosted'] ?? json['tasks_posted'] ?? 0,
      reviewsCount: json['reviewsCount'] ?? json['reviews_count'] ?? 0,
      rank: json['rank'] ?? 'New',
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
      dailyReleaseCount: int.tryParse(
              (json['dailyReleaseCount'] ?? json['daily_release_count'] ?? 0).toString()) ?? 0,
      authProvider: json['auth_provider']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'avatar': avatar,
        'bio': bio,
        'gender': gender,
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
        'dailyReleaseCount': dailyReleaseCount,
      };

  /// Returns a copy of this User with only the avatar replaced.
  /// Preserves ALL fields (unlike toJson→fromJson which loses rank etc.).
  User copyWithAvatar(String? newAvatar) => User(
        id: id,
        name: name,
        email: email,
        phone: phone,
        avatar: newAvatar,
        bio: bio,
        gender: gender,
        skills: skills,
        rating: rating,
        tasksCompleted: tasksCompleted,
        tasksPosted: tasksPosted,
        reviewsCount: reviewsCount,
        rank: rank,
        isKycVerified: isKycVerified,
        kycStatus: kycStatus,
        isEmailVerified: isEmailVerified,
        isSuspended: isSuspended,
        suspendedUntil: suspendedUntil,
        referralCode: referralCode,
        createdAt: createdAt,
        dailyReleaseCount: dailyReleaseCount,
        authProvider: authProvider,
      );
}
