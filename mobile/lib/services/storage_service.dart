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
}
