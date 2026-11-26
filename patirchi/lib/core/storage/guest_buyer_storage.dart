import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Guest savat va sevimlilarini qurilmada saqlaydi.
class GuestBuyerStorage {
  GuestBuyerStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _cartKey = 'guest_buyer_cart_v1';
  static const _wishlistKey = 'guest_buyer_wishlist_v1';
  static const _cartSyncIdKey = 'guest_buyer_cart_sync_id_v1';
  static const _deviceIdKey = 'registered_device_id_v1';

  Future<List<Map<String, dynamic>>> readCart() async {
    final raw = await _preferences.getString(_cartKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> writeCart(List<Map<String, dynamic>> items) async {
    await _preferences.setString(_cartKey, jsonEncode(items));
  }

  Future<void> clearCart() => _preferences.remove(_cartKey);

  Future<List<Map<String, dynamic>>> readWishlist() async {
    final raw = await _preferences.getString(_wishlistKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> writeWishlist(List<Map<String, dynamic>> products) async {
    await _preferences.setString(_wishlistKey, jsonEncode(products));
  }

  Future<void> clearWishlist() => _preferences.remove(_wishlistKey);

  Future<String> cartSyncId() async {
    final stored = await _preferences.getString(_cartSyncIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final generated = _newUuid();
    await _preferences.setString(_cartSyncIdKey, generated);
    return generated;
  }

  Future<void> clearCartSyncId() => _preferences.remove(_cartSyncIdKey);

  Future<String> deviceId() async {
    final stored = await _preferences.getString(_deviceIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final generated = _newUuid();
    await _preferences.setString(_deviceIdKey, generated);
    return generated;
  }

  String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
