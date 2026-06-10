import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── Token ──────────────────────────────────────────────────────────────────
  static Future<void> saveToken(String token) async {
    await _prefs.setString('auth_token', token);
  }

  static String? getToken() => _prefs.getString('auth_token');

  static Future<void> clearToken() async {
    await _prefs.remove('auth_token');
  }

  // ─── Session expiry ──────────────────────────────────────────────────────────
  /// Persists the absolute expiry time as epoch milliseconds.
  static Future<void> saveSessionExpiry(DateTime expiry) async {
    await _prefs.setInt('session_expiry_ms', expiry.millisecondsSinceEpoch);
  }

  /// Returns the stored expiry time, or null if never set.
  static DateTime? getSessionExpiry() {
    final ms = _prefs.getInt('session_expiry_ms');
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  // ─── Cached user JSON (for instant offline restoration) ─────────────────────
  static Future<void> saveUserJson(Map<String, dynamic> json) async {
    await _prefs.setString('cached_user_json', jsonEncode(json));
  }

  static Map<String, dynamic>? getUserJson() {
    final raw = _prefs.getString('cached_user_json');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  // ─── Full session clear (token + user cache + expiry) ───────────────────────
  static Future<void> clearSession() async {
    await _prefs.remove('auth_token');
    await _prefs.remove('cached_user_json');
    await _prefs.remove('session_expiry_ms');
  }

  // ─── User ───────────────────────────────────────────────────────────────────
  static Future<void> saveUserId(String id) async {
    await _prefs.setString('user_id', id);
  }

  static String? getUserId() => _prefs.getString('user_id');

  // ─── Theme ──────────────────────────────────────────────────────────────────
  static Future<void> saveThemeMode(String mode) async {
    await _prefs.setString('theme_mode', mode);
  }

  static String getThemeMode() => _prefs.getString('theme_mode') ?? 'system';

  // ─── General ────────────────────────────────────────────────────────────────
  static Future<void> clear() async {
    await _prefs.clear();
  }

  static Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  static bool getBool(String key, {bool defaultValue = false}) =>
      _prefs.getBool(key) ?? defaultValue;

  static Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  static String? getString(String key) => _prefs.getString(key);

  // ─── Gender (persisted locally so emoji works even before server returns it) ─
  static Future<void> saveGender(String gender) async {
    await _prefs.setString('user_gender', gender);
  }

  static String? getGender() => _prefs.getString('user_gender');

  static Future<void> clearGender() async {
    await _prefs.remove('user_gender');
  }
}
