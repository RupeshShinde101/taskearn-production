import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
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
      _user = User.fromJson(cachedJson);
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
      _user = User.fromJson(userJson);
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
        await StorageService.saveToken(token);
        _user = User.fromJson(data['user'] ?? data);
        await StorageService.saveUserId(_user!.id);
        await StorageService.saveUserJson(_user!.toJson());
        await StorageService.saveSessionExpiry(
            DateTime.now().add(_kSessionDuration));
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
        _registerFcmToken();
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
      if (dob != null && dob.isNotEmpty) 'date_of_birth': dob,
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
    try {
      await ApiService.post('/auth/logout');
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await StorageService.clearSession();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
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
      _user = User.fromJson(userJson);
      await StorageService.saveUserJson(userJson); // keep cache fresh
      notifyListeners();
    } catch (e) {
      debugPrint('[AUTH] refreshUser error: $e');
    }
  }

  Future<bool> updateProfile({
    String? name,
    String? bio,
    String? avatarPath,
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
      if (skills != null) body['skills'] = skills;
      if (phone != null && phone.trim().isNotEmpty) body['phone'] = phone.trim();
      if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();

      await ApiService.put('/user/profile', body: body);
      // Always refresh from server so skills and all fields are up-to-date
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
  /// Images are base64-encoded and sent as JSON to /user/kyc/submit.
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
      // Convert images to base64
      final frontBytes = await File(frontImagePath).readAsBytes();
      final frontBase64 = base64Encode(frontBytes);

      String? backBase64;
      if (backImagePath != null) {
        final backBytes = await File(backImagePath).readAsBytes();
        backBase64 = base64Encode(backBytes);
      }

      // Normalise document number (uppercase, no spaces)
      final normNumber = docNumber.trim().toUpperCase().replaceAll(' ', '');

      final body = <String, dynamic>{
        'documentType': docType,
        'documentNumber': normNumber,
        'documentImageFront': frontBase64,
        if (backBase64 != null) 'documentImageBack': backBase64,
        'acknowledged': true,
      };

      // Use a 120-second timeout: base64 images can be several MB
      final response = await ApiService.post(
        '/user/kyc/submit',
        body: body,
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
        // Send current location so backend can apply 10km radius filter
        try {
          final loc = await LocationService.getCurrentLocation();
          if (loc != null) await updateUserLocation(loc.latitude, loc.longitude);
        } catch (_) {}
      } else {
        debugPrint('[FCM] ⚠️ getToken() returned null');
      }
    } catch (e) {
      debugPrint('[FCM] _registerFcmToken error: $e');
    }
  }
}
