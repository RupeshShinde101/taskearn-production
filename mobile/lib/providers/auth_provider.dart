import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  User? _user;
  AuthStatus _status = AuthStatus.unknown;
  bool _loading = false;
  String? _error;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '874101147109-st0q2a3h1r2109vguko7g1cu0nmabcju.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  User? get user => _user;
  AuthStatus get status => _status;
  bool get isLoggedIn => _status == AuthStatus.authenticated;
  bool get isLoading => _loading;
  String? get error => _error;

  AuthProvider() {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = StorageService.getToken();
    if (token == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      final data = await ApiService.get('/auth/me');
      final userJson = Map<String, dynamic>.from((data['user'] ?? data) as Map);
      debugPrint('[AUTH] _checkAuth KYC fields: '
          'kyc_verified=${userJson["kyc_verified"]} '
          'kyc_status=${userJson["kyc_status"]} '
          'kycVerified=${userJson["kycVerified"]} '
          'kycStatus=${userJson["kycStatus"]}');
      _user = User.fromJson(userJson);
      _status = AuthStatus.authenticated;
      _registerFcmToken();
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await StorageService.clearToken();
        _status = AuthStatus.unauthenticated;
      } else {
        // Network/server error — keep token, user stays logged in
        _status = AuthStatus.authenticated;
      }
    } catch (_) {
      // Network unavailable on startup — keep token, stay logged in
      _status = AuthStatus.authenticated;
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
    String? referralCode,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await ApiService.post('/auth/register', body: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        if (phone != null) 'phone': phone,
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
      });

      final token = data['token'] ?? data['access_token'];
      if (token != null) {
        await StorageService.saveToken(token);
        _user = User.fromJson(data['user'] ?? data);
        await StorageService.saveUserId(_user!.id);
        _status = AuthStatus.authenticated;
      }

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

  Future<void> logout() async {
    try {
      await ApiService.post('/auth/logout');
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await StorageService.clearToken();
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
  }) async {
    _loading = true;
    notifyListeners();

    try {
      final body = <String, dynamic>{};
      if (name != null && name.trim().isNotEmpty) body['name'] = name.trim();
      if (bio != null) body['bio'] = bio.trim();
      if (skills != null) body['skills'] = skills;

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

  /// Submit a KYC document (aadhaar / pan / selfie path).
  Future<bool> submitKyc({
    required String docType,
    required String docNumber,
    String? frontImagePath,
    String? selfieImagePath,
  }) async {
    _loading = true;
    notifyListeners();
    try {
      final body = <String, dynamic>{
        'doc_type': docType,
        'doc_number': docNumber,
      };
      await ApiService.put('/user/kyc', body: body);
      if (frontImagePath != null) {
        try {
          await ApiService.uploadFile(
              '/user/kyc/upload', frontImagePath, 'kyc_doc');
        } catch (_) {}
      }
      if (selfieImagePath != null) {
        try {
          await ApiService.uploadFile(
              '/user/kyc/selfie', selfieImagePath, 'selfie');
        } catch (_) {}
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

  Future<bool> loginWithGoogle() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        // User cancelled
        _loading = false;
        notifyListeners();
        return false;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

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
      });

      final token = data['token'] ?? data['access_token'];
      if (token != null) {
        await StorageService.saveToken(token);
        _user = User.fromJson(data['user'] ?? data);
        await StorageService.saveUserId(_user!.id);
        _status = AuthStatus.authenticated;
        _loading = false;
        notifyListeners();
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
      _error = 'Google sign-in error: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
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
      } else {
        debugPrint('[FCM] ⚠️ getToken() returned null');
      }
    } catch (e) {
      debugPrint('[FCM] _registerFcmToken error: $e');
    }
  }
}
