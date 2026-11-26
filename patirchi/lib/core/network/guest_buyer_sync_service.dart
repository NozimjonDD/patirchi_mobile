import 'package:patirchi/core/network/api_client.dart';
import 'package:patirchi/core/network/api_endpoints.dart';
import 'package:patirchi/core/storage/guest_buyer_storage.dart';

/// Login paytida guest savati va sevimlilarini hisobga birlashtiradi.
class GuestBuyerSyncService {
  GuestBuyerSyncService({ApiClient? api, GuestBuyerStorage? storage})
      : _api = api ?? ApiClient.instance,
        _storage = storage ?? GuestBuyerStorage();

  final ApiClient _api;
  final GuestBuyerStorage _storage;

  Future<bool> sync() async {
    var succeeded = true;
    final cart = await _storage.readCart();
    if (cart.isNotEmpty) {
      try {
        await _api.post(
          ApiEndpoints.guestCartMerge,
          body: {
            'sync_id': await _storage.cartSyncId(),
            'items': cart
                .map((item) => {
                      'product_id': item['product_id'],
                      'quantity': item['quantity'],
                    })
                .toList(),
          },
        );
        await _storage.clearCart();
        await _storage.clearCartSyncId();
      } on Object {
        succeeded = false;
      }
    }

    final wishlist = await _storage.readWishlist();
    if (wishlist.isNotEmpty) {
      try {
        await _api.post(
          ApiEndpoints.wishlistSync,
          body: {
            'product_ids': wishlist.map((item) => item['id']).toList(),
          },
        );
        await _storage.clearWishlist();
      } on Object {
        succeeded = false;
      }
    }
    return succeeded;
  }
}
