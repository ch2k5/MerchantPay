import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _accessKey = 'mp_access_token';
  static const _refreshKey = 'mp_refresh_token';
  static const _userKey = 'mp_user_json';

  static final _secureStorage = const FlutterSecureStorage();

  static Future<void> saveTokens({required String access, required String refresh}) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessKey, access);
      await prefs.setString(_refreshKey, refresh);
    } else {
      await _secureStorage.write(key: _accessKey, value: access);
      await _secureStorage.write(key: _refreshKey, value: refresh);
    }
  }

  static Future<String?> getAccessToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_accessKey);
    }
    return await _secureStorage.read(key: _accessKey);
  }

  static Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_refreshKey);
    }
    return await _secureStorage.read(key: _refreshKey);
  }

  static Future<void> saveUserJson(String jsonStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonStr);
  }

  static Future<String?> getUserJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userKey);
  }

  static Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessKey);
      await prefs.remove(_refreshKey);
      await prefs.remove(_userKey);
    } else {
      await _secureStorage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
    }
  }
}
