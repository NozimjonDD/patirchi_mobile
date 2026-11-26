import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token va foydalanuvchi ma'lumotlarini xavfsiz saqlash xizmati.
///
/// Tokenlarni platformaning himoyalangan omborida saqlaydi.
///
/// Foydalanish:
/// ```dart
/// final storage = SecureStorageService.instance;
/// await storage.saveToken('eyJ...');
/// final token = await storage.getToken();
/// ```
class SecureStorageService {
  SecureStorageService._();

  static final SecureStorageService instance = SecureStorageService._();

  // ---------------------------------------------------------------------------
  // Kalit konstantalar
  // ---------------------------------------------------------------------------

  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUser = 'current_user';

  // ---------------------------------------------------------------------------
  // Xotiradagi nusxa sinxron getter va debug panel uchun ishlatiladi.
  // ---------------------------------------------------------------------------

  final Map<String, String> _store = {};
  static final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // ---------------------------------------------------------------------------
  // Token operatsiyalari
  // ---------------------------------------------------------------------------

  /// Access tokenni saqlaydi.
  Future<void> saveToken(String token) async {
    _store[_keyAccessToken] = token;
    await _secureStorage.write(key: _keyAccessToken, value: token);
  }

  /// Saqlangan access tokenni qaytaradi. Mavjud bo'lmasa `null`.
  Future<String?> getToken() async {
    final value = _store[_keyAccessToken] ??
        await _secureStorage.read(key: _keyAccessToken);
    if (value != null) _store[_keyAccessToken] = value;
    return value;
  }

  /// Refresh tokenni saqlaydi.
  Future<void> saveRefreshToken(String token) async {
    _store[_keyRefreshToken] = token;
    await _secureStorage.write(key: _keyRefreshToken, value: token);
  }

  /// Saqlangan refresh tokenni qaytaradi. Mavjud bo'lmasa `null`.
  Future<String?> getRefreshToken() async {
    final value = _store[_keyRefreshToken] ??
        await _secureStorage.read(key: _keyRefreshToken);
    if (value != null) _store[_keyRefreshToken] = value;
    return value;
  }

  /// Tokenlarni o'chiradi.
  Future<void> deleteToken() async {
    _store.remove(_keyAccessToken);
    _store.remove(_keyRefreshToken);
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
  }

  // ---------------------------------------------------------------------------
  // Foydalanuvchi ma'lumotlari
  // ---------------------------------------------------------------------------

  /// Foydalanuvchi ma'lumotlarini JSON string sifatida saqlaydi.
  Future<void> saveUser(Map<String, dynamic> userJson) async {
    final encoded = jsonEncode(userJson);
    _store[_keyUser] = encoded;
    await _secureStorage.write(key: _keyUser, value: encoded);
  }

  /// [saveUser] bilan bir xil — API integratsiyasida qulaylik uchun alias.
  Future<void> saveUserJson(Map<String, dynamic> userJson) => saveUser(userJson);

  /// Saqlangan foydalanuvchi ma'lumotlarini qaytaradi. Mavjud bo'lmasa `null`.
  Future<Map<String, dynamic>?> getUser() async {
    final raw = _store[_keyUser] ?? await _secureStorage.read(key: _keyUser);
    if (raw == null) return null;
    _store[_keyUser] = raw;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  /// [getUser] bilan bir xil — API integratsiyasida qulaylik uchun alias.
  Future<Map<String, dynamic>?> getUserJson() => getUser();

  /// Foydalanuvchi ma'lumotlarini o'chiradi.
  Future<void> deleteUser() async {
    _store.remove(_keyUser);
    await _secureStorage.delete(key: _keyUser);
  }

  // ---------------------------------------------------------------------------
  // Umumiy operatsiyalar
  // ---------------------------------------------------------------------------

  /// Boshqa (custom) qiymatni saqlaydi.
  Future<void> write(String key, String value) async {
    _store[key] = value;
    await _secureStorage.write(key: key, value: value);
  }

  /// Saqlangan qiymatni o'qiydi. Mavjud bo'lmasa `null`.
  Future<String?> read(String key) async {
    final value = _store[key] ?? await _secureStorage.read(key: key);
    if (value != null) _store[key] = value;
    return value;
  }

  /// Bitta yozuvni o'chiradi.
  Future<void> delete(String key) async {
    _store.remove(key);
    await _secureStorage.delete(key: key);
  }

  /// Barcha ma'lumotlarni tozalaydi (logout).
  Future<void> clear() async {
    _store.clear();
    await _secureStorage.deleteAll();
  }

  // ---------------------------------------------------------------------------
  // Developer mode
  // ---------------------------------------------------------------------------

  static const String _keyDevMode = 'dev_mode_enabled';

  /// Developer mode yoqilganligini qaytaradi.
  Future<bool> getDevMode() async {
    return await read(_keyDevMode) == 'true';
  }

  /// Developer mode holatini saqlaydi.
  Future<void> setDevMode(bool value) async {
    await write(_keyDevMode, value.toString());
  }

  // ---------------------------------------------------------------------------
  // Debug utilities
  // ---------------------------------------------------------------------------

  /// Barcha kalit-qiymatlarni qaytaradi (tokenlar qisman yashirilgan).
  Future<Map<String, String?>> getAllForDebug() async {
    return _store.map((key, value) {
      // Tokenlar va maxfiy kalitlarni qisman yashirish
      if (key.contains('token') && value.length > 20) {
        final masked =
            '${value.substring(0, 10)}...${value.substring(value.length - 10)}';
        return MapEntry(key, masked);
      }
      return MapEntry(key, value);
    });
  }

  /// Barcha ma'lumotlarni tozalaydi — dev mode ham.
  /// [clear] faqat auth ma'lumotlarini o'chiradi, bu esa hammasini.
  Future<void> clearAll() async {
    _store.clear();
    await _secureStorage.deleteAll();
  }

  // ---------------------------------------------------------------------------
  // Login holati
  // ---------------------------------------------------------------------------

  /// Sinxron: hozirgi vaqtda token bormi?
  ///
  /// In-memory saqlashda sinxron tekshirish mumkin.
  /// flutter_secure_storage ga o'tganda async versiya ishlating.
  bool get isLoggedIn {
    final token = _store[_keyAccessToken];
    return token != null && token.isNotEmpty;
  }

  /// Async versiya — eski kod bilan moslik uchun.
  Future<bool> get isLoggedInAsync async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
