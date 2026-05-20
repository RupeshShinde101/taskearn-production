import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

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
      _user = User.fromJson(data['user'] ?? data);
      _status = AuthStatus.authenticated;
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
      _user = User.fromJson(data['user'] ?? data);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> updateProfile({
    String? name,
    String? bio,
    String? avatarPath,
  }) async {
    _loading = true;
    notifyListeners();

    try {
      final data = await ApiService.put('/user/profile', body: {
        if (name != null) 'name': name,
        if (bio != null) 'bio': bio,
      });
      _user = User.fromJson(data['user'] ?? data);
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
}
