import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  User? _user;
  AuthStatus _status = AuthStatus.unknown;
  bool _loading = false;
  String? _error;
  String? _kycSubmitMessage;
  /// Locally-uploaded avatar (data: URI). Persisted to a dedicated storage key
  /// so it survives refreshUser() calls where the backend ignores the field.
  String? _localAvatarUri;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '874101147109-st0q2a3h1r2109vguko7g1cu0nmabcju.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  User? get user => _user;
  AuthStatus get status => _status;
  bool get isLoggedIn => _status == AuthStatus.authenticated;
  bool get isLoading => _loading;
  String? get error => _error;

  /// Client-side session duration: 30 days after last successful login.
  static const Duration _kSessionDuration = Duration(days: 30);

  AuthProvider() {
    // Register a global 401 handler so any API call that receives an
    // "Invalid or expired token" response automatically clears the session
    // and redirects the user to login — regardless of where in the app it fires.
    ApiService.onUnauthorized = _handleUnauthorized;
    _checkAuth();
  }

  /// Called by [ApiService] whenever the backend returns 401 while a JWT is
  /// stored.  Clears the session and marks the user as unauthenticated so the
  /// go_router redirect guard navigates to /login automatically.
  void _handleUnauthorized() async {
    // No-op if already logged out (guard against multiple concurrent 401s).
    if (_status == AuthStatus.unauthenticated) return;
    debugPrint('[AUTH] Received 401 — token expired or invalid. Forcing logout.');
    // Best-effort: delete Firebase token so the device stops receiving FCM
    // messages even if the backend call below fails.
    try { await NotificationService.clearFcmToken(); } catch (_) {}
    await StorageService.clearSession();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> _checkAuth() async {
    final token = StorageService.getToken();
    if (token == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    // ── Client-side session expiry ─────────────────────────────────────────
    final expiry = StorageService.getSessionExpiry();
    if (expiry != null && DateTime.now().isAfter(expiry)) {
      debugPrint('[AUTH] Session expired at $expiry — clearing session.');
      await StorageService.clearSession();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    // ── Restore user instantly from local cache (no network wait) ──────────
    final cachedJson = StorageService.getUserJson();
    if (cachedJson != null) {
      // Inject locally-saved gender into the cached JSON so the emoji shows
      // immediately on startup without waiting for the network /auth/me call.
      if (cachedJson['gender'] == null || cachedJson['gender'].toString().isEmpty) {
        final localGender = StorageService.getGender();
        if (localGender != null) cachedJson['gender'] = localGender;
      }
      _user = User.fromJson(cachedJson);
      // Load and apply locally-uploaded avatar override
      _localAvatarUri = StorageService.getString('user_avatar_local');
      if (_localAvatarUri != null && _localAvatarUri!.isNotEmpty) {
        _user = _user!.copyWithAvatar(_localAvatarUri);
      }
      _status = AuthStatus.authenticated;
      notifyListeners(); // show the app immediately
    }

    // ── Background server verification ─────────────────────────────────────
    try {
      final data = await ApiService.get('/auth/me');
      final userJson = Map<String, dynamic>.from((data['user'] ?? data) as Map);
      debugPrint('[AUTH] _checkAuth KYC fields: '
          'kyc_verified=${userJson["kyc_verified"]} '
          'kyc_status=${userJson["kyc_status"]} '
          'kycVerified=${userJson["kycVerified"]} '
          'kycStatus=${userJson["kycStatus"]}');
      // Inject locally-saved gender if server didn't return it (e.g. backend
      // not yet deployed with the gender column).
      if (userJson['gender'] == null || userJson['gender'].toString().isEmpty) {
        final localGender = StorageService.getGender();
        if (localGender != null) userJson['gender'] = localGender;
      } else {
        // Backend returned gender — keep local copy in sync.
        await StorageService.saveGender(userJson['gender'].toString());
      }
      _user = User.fromJson(userJson);
      // Re-apply locally-uploaded avatar if server doesn't return one
      if (_localAvatarUri != null && _localAvatarUri!.isNotEmpty) {
        _user = _user!.copyWithAvatar(_localAvatarUri);
      }
      await StorageService.saveUserJson(userJson); // keep cache fresh
      _status = AuthStatus.authenticated;
      _registerFcmToken();
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        // Token explicitly rejected by server — full logout
        await StorageService.clearSession();
        _user = null;
        _status = AuthStatus.unauthenticated;
      }
      // Other API errors (5xx, timeout): keep the cached user logged in
    } catch (_) {
      // Network unavailable — keep cached user, stay logged in
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await ApiService.post('/auth/login', body: {
        'email': email.trim(),
        'password': password,
      });

      final token = data['token'] ?? data['access_token'];
      if (token != null) {
        // Parallel storage writes — don't await each one sequentially
        await Future.wait([
          StorageService.saveToken(token),
          StorageService.saveUserId(''),  // will be set below
          StorageService.saveSessionExpiry(DateTime.now().add(_kSessionDuration)),
        ]);
        _user = User.fromJson(data['user'] ?? data);
        await Future.wait([
          StorageService.saveUserId(_user!.id),
          StorageService.saveUserJson(_user!.toJson()),
        ]);
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
        unawaited(_registerFcmToken());
        return true;
      }

      _error = data['message'] ?? 'Login failed';
      _loading = false;
      notifyListeners();
      return false;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? dob,
    String? inviteCode,
    String? referralCode,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    // ── Pre-flight connectivity check ─────────────────────────────────────
    final connectivityResults = await Connectivity().checkConnectivity();
    final hasNetwork =
        connectivityResults.any((r) => r != ConnectivityResult.none);
    if (!hasNetwork) {
      _error =
          'No internet connection. Please enable mobile data or Wi-Fi and try again.';
      _loading = false;
      notifyListeners();
      return false;
    }

    final body = {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      if (phone != null) 'phone': phone,
      if (dob != null && dob.isNotEmpty) 'dob': dob,
      if (inviteCode != null && inviteCode.isNotEmpty)
        'invite_code': inviteCode.trim().toUpperCase(),
      if (referralCode != null && referralCode.isNotEmpty)
        'referral_code': referralCode.trim(),
    };

    // ── Attempt registration (one auto-retry on transient network errors) ──
    ApiException? lastNetworkError;
    for (int attempt = 0; attempt < 2; attempt++) {
      if (attempt == 1) {
        // Brief pause before retry — lets DNS/connection recover
        await Future.delayed(const Duration(seconds: 3));
        debugPrint('[AUTH] register: retrying after transient network error…');
      }
      try {
        final data =
            await ApiService.post('/auth/register', body: body);

        final token = data['token'] ?? data['access_token'];
        if (token != null) {
          await StorageService.saveToken(token);
          _user = User.fromJson(data['user'] ?? data);
          await StorageService.saveUserId(_user!.id);
          await StorageService.saveUserJson(_user!.toJson());
          await StorageService.saveSessionExpiry(
              DateTime.now().add(_kSessionDuration));
          _status = AuthStatus.authenticated;
        }

        _loading = false;
        notifyListeners();
        return true;
      } on ApiException catch (e) {
        if (e.statusCode != null) {
          // Server responded with an error — don't retry, surface immediately
          _error = e.message;
          _loading = false;
          notifyListeners();
          return false;
        }
        // statusCode == null → network/connection error — save and maybe retry
        lastNetworkError = e;
      }
    }

    // Both attempts failed with a network error
    _error = lastNetworkError?.message ??
        'Could not connect to the server. Please try again.';
    _loading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    // Clear local state IMMEDIATELY so GoRouter redirects to /login right away.
    _user = null;
    _localAvatarUri = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();

    // Network clean-up runs in the background — don't block the UI.
    unawaited(() async {
      try { await NotificationService.clearFcmToken(); } catch (_) {}
      try { await ApiService.post('/auth/logout'); } catch (_) {}
      try { await _googleSignIn.signOut(); } catch (_) {}
      await StorageService.clearSession();
      await StorageService.setString('user_avatar_local', '');
    }());
  }

  /// Permanently delete the user's account and all data.
  Future<Map<String, dynamic>> deleteAccount({String? password}) async {
    try {
      final body = <String, dynamic>{};
      if (password != null && password.isNotEmpty) body['password'] = password;
      final res = await ApiService.post('/user/delete-account', body: body);
      if (res['success'] == true) {
        try { await _googleSignIn.signOut(); } catch (_) {}
        await StorageService.clearSession();
        _user = null;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return {'success': true};
      }
      return {'success': false, 'message': res['message'] ?? 'Failed to delete account'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<void> refreshUser() async {
    try {
      final data = await ApiService.get('/auth/me');
      final userJson = Map<String, dynamic>.from(
          (data['user'] ?? data) as Map);
      // DEBUG: log KYC-related fields from API response
      debugPrint('[AUTH] /auth/me raw KYC fields: '
          'kyc_verified=${userJson["kyc_verified"]} '
          'kyc_status=${userJson["kyc_status"]} '
          'kycVerified=${userJson["kycVerified"]} '
          'kycStatus=${userJson["kycStatus"]} '
          'is_kyc_verified=${userJson["is_kyc_verified"]}');
      debugPrint('[AUTH] All keys: ${userJson.keys.toList()}');
      // Inject locally-saved gender if backend didn't return it.
      if (userJson['gender'] == null || userJson['gender'].toString().isEmpty) {
        final localGender = StorageService.getGender();
        if (localGender != null) userJson['gender'] = localGender;
      } else {
        await StorageService.saveGender(userJson['gender'].toString());
      }
      _user = User.fromJson(userJson);
      // Always re-apply locally-uploaded avatar — backend ignores the avatar
      // field on PUT /user/profile so /auth/me won't return our new photo.
      if (_localAvatarUri != null && _localAvatarUri!.isNotEmpty) {
        _user = _user!.copyWithAvatar(_localAvatarUri);
      }
      await StorageService.saveUserJson(userJson); // keep cache fresh
      notifyListeners();
    } catch (e) {
      debugPrint('[AUTH] refreshUser error: $e');
    }
  }

  Future<bool> updateProfile({
    String? name,
    String? bio,
    String? gender,
    String? avatarDataUri,
    List<String>? skills,
    String? phone,
    String? email,
  }) async {
    _loading = true;
    notifyListeners();

    try {
      final body = <String, dynamic>{};
      if (name != null && name.trim().isNotEmpty) body['name'] = name.trim();
      if (bio != null) body['bio'] = bio.trim();
      if (gender != null) body['gender'] = gender;
      if (skills != null) body['skills'] = skills;
      if (phone != null && phone.trim().isNotEmpty) body['phone'] = phone.trim();
      if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();
      if (avatarDataUri != null && avatarDataUri.isNotEmpty) {
        body['profile_photo'] = avatarDataUri;
      }

      await ApiService.put('/user/profile', body: body);
      // Persist gender locally immediately so the home emoji updates even
      // before the backend returns the field in /auth/me response.
      if (gender != null) await StorageService.saveGender(gender);

      // Store avatar locally and apply immediately.
      // Backend ignores the avatar field on PUT /user/profile, so we keep
      // it in-memory (_localAvatarUri) and re-apply after every server fetch.
      if (avatarDataUri != null && avatarDataUri.isNotEmpty) {
        _localAvatarUri = avatarDataUri;
        await StorageService.setString('user_avatar_local', avatarDataUri);
        if (_user != null) {
          _user = _user!.copyWithAvatar(avatarDataUri);
          notifyListeners(); // Immediate visual feedback — no waiting for server
        }
      }

      await refreshUser();
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Register a device FCM token with the backend for push notifications.
  Future<void> updateFcmToken(String token) async {
    try {
      final res = await ApiService.post('/user/device-token', body: {
        'token': token,
        'platform': 'android',
      });
      debugPrint('[FCM] device-token saved: $res');
    } catch (e) {
      debugPrint('[FCM] updateFcmToken error: $e');
    }
  }

  /// Send current GPS coordinates to the backend.
  /// The backend uses this to push matched-task notifications within 10 km.
  Future<void> updateUserLocation(double lat, double lng) async {
    try {
      await ApiService.post('/user/location', body: {
        'lat': lat,
        'lng': lng,
      });
      debugPrint('[AUTH] Location sent to backend: $lat, $lng');
    } catch (_) {} // non-critical, fail silently
  }

  /// Message returned by the backend after a KYC submit (e.g. "auto-verified" vs "pending").
  String? get kycSubmitMessage => _kycSubmitMessage;

  /// Submit KYC with Aadhaar (front + back) or PAN (front only).
  /// Images are sent as multipart/form-data (binary bytes, ~25% smaller than
  /// base64 JSON) so the request stays well under proxy size limits.
  /// The backend converts the files to base64 data URIs before storing in the
  /// DB, ensuring the admin panel can render them inline without 414 errors.
  Future<bool> submitKyc({
    required String docType,
    required String docNumber,
    required String frontImagePath,
    String? backImagePath, // required for aadhaar, null for pan
  }) async {
    _loading = true;
    _error = null;
    _kycSubmitMessage = null;
    notifyListeners();
    try {
      // Normalise document number (uppercase, no spaces)
      final normNumber = docNumber.trim().toUpperCase().replaceAll(' ', '');

      final fields = <String, String>{
        'documentType': docType,
        'documentNumber': normNumber,
        'acknowledged': 'true',
      };

      final filePaths = <String, String>{
        'documentImageFront': frontImagePath,
        if (backImagePath != null) 'documentImageBack': backImagePath,
      };

      // Send binary files via multipart — backend converts to base64 data URI
      // and stores in DB so the admin panel can display images as inline <img>.
      final response = await ApiService.postMultipart(
        '/user/kyc/submit',
        fields: fields,
        filePaths: filePaths,
        timeout: const Duration(seconds: 120),
      );
      _kycSubmitMessage = response['message'] as String?;
      await refreshUser();
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to submit KYC. Please try again.';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithGoogle({
    String? inviteCode,
    String? referralCode,
    DateTime? dob,
    String? phone,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Always sign out first to clear any stale session from a previous
      // logout — prevents null idToken / PlatformException on re-sign-in.
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final account = await _googleSignIn.signIn();
      if (account == null) {
        // User cancelled the account picker
        _loading = false;
        notifyListeners();
        return false;
      }

      // Fetch authentication tokens — wrap separately because this can throw
      // a PlatformException independent of signIn() on some Android versions.
      String? idToken;
      try {
        final googleAuth = await account.authentication;
        idToken = googleAuth.idToken;
      } catch (e) {
        debugPrint('[Google] account.authentication error: $e');
        _error = 'Google authentication failed. Please try again.';
        _loading = false;
        notifyListeners();
        return false;
      }

      if (idToken == null) {
        _error = 'Could not get ID token from Google. Please try again.';
        _loading = false;
        notifyListeners();
        return false;
      }

      final data = await ApiService.post('/auth/google', body: {
        'credential': idToken,
        'email': account.email,
        'name': account.displayName,
        'avatar': account.photoUrl,
        if (inviteCode != null && inviteCode.isNotEmpty)
          'invite_code': inviteCode,
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
        if (dob != null)
          'dob':
              '${dob.year}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}',
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      });

      final token = data['token'] ?? data['access_token'];
      if (token != null) {
        await StorageService.saveToken(token);
        _user = User.fromJson(data['user'] ?? data);
        await StorageService.saveUserId(_user!.id);
        await StorageService.saveUserJson(_user!.toJson());
        await StorageService.saveSessionExpiry(
            DateTime.now().add(_kSessionDuration));
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
        _registerFcmToken(); // register FCM + sync location after Google login
        return true;
      }

      _error = data['message'] ?? 'Google sign-in failed';
      _loading = false;
      notifyListeners();
      return false;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } on PlatformException catch (e) {
      debugPrint('[Google] PlatformException: code=${e.code} message=${e.message}');
      if (e.message != null && (e.message!.contains(': 10') || e.message!.contains('DEVELOPER_ERROR'))) {
        _error = 'Google sign-in is not configured for this app build. Please contact support.';
      } else if (e.code == 'network_error') {
        _error = 'Network error. Please check your connection and try again.';
      } else {
        _error = 'Google sign-in failed. Please try again.';
      }
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[Google] loginWithGoogle error: $e');
      _error = 'Google sign-in failed. Please try again.';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    _kycSubmitMessage = null;
    notifyListeners();
  }

  // ── Change Password ────────────────────────────────────────────────────────
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await ApiService.post('/auth/change-password', body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ── Forgot Password — Step 1: send OTP to email ──────────────────────────
  /// Returns the resetToken on success (needed for steps 2 & 3), or null on failure.
  Future<String?> forgotPasswordSendOtp(String email) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.post('/auth/forgot-password', body: {'email': email.trim()});
      _loading = false;
      notifyListeners();
      final token = data['resetToken']?.toString() ??
          data['reset_token']?.toString() ??
          data['token']?.toString();
      return token; // may be null if backend omits it (some implementations)
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  // ── Forgot Password — Step 2: verify OTP ────────────────────────────────
  /// Verifies the OTP against the resetToken from step 1.
  Future<bool> verifyForgotPasswordOtp({
    required String resetToken,
    required String otp,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await ApiService.post('/auth/verify-otp', body: {
        'resetToken': resetToken,
        'otp': otp.trim(),
      });
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ── Forgot Password — Step 3: reset password with token ──────────────────
  Future<bool> resetPasswordWithToken({
    required String resetToken,
    required String newPassword,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await ApiService.post('/auth/reset-password', body: {
        'resetToken': resetToken,
        'newPassword': newPassword,
      });
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ── Email Verification — send OTP ─────────────────────────────────────────
  Future<bool> sendEmailVerificationOtp() async {
    _error = null;
    try {
      await ApiService.post('/auth/send-verification-otp',
          body: {'email': _user?.email ?? ''});
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  // ── Email Verification — verify OTP ──────────────────────────────────────
  Future<bool> verifyEmailOtp(String otp) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await ApiService.post('/auth/verify-email', body: {
        'email': _user?.email ?? '',
        'otp': otp.trim(),
      });
      await refreshUser();
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Registers the FCM device token with the backend after login.
  Future<void> _registerFcmToken() async {
    try {
      final token = await NotificationService.getToken();
      debugPrint('[FCM] Device token: ${token?.substring(0, 20)}...');
      if (token != null) {
        await updateFcmToken(token);
        NotificationService.onTokenRefresh(updateFcmToken);
        // GPS location update: fire-and-forget, don't block FCM registration
        try {
          LocationService.getCurrentLocation().then((loc) {
            if (loc != null) updateUserLocation(loc.latitude, loc.longitude);
          });
        } catch (_) {}
      } else {
        debugPrint('[FCM] ⚠️ getToken() returned null');
      }
    } catch (e) {
      debugPrint('[FCM] _registerFcmToken error: $e');
    }
  }
}
