import 'dart:async';

import 'package:flutter/material.dart';
import 'package:patirchi/core/constants/enums.dart';
import 'package:patirchi/core/error/result.dart';
import 'package:patirchi/core/storage/guest_buyer_storage.dart';
import 'package:patirchi/features/auth/presentation/providers/auth_provider.dart';
import 'package:patirchi/features/buyer/cart/data/models/cart_item_model.dart';
import 'package:patirchi/features/buyer/cart/data/repositories/cart_repository.dart';
import 'package:patirchi/features/buyer/home/data/models/product_model.dart';

class CartProvider extends ChangeNotifier {
  CartProvider({CartRepository? repository, AuthProvider? authProvider})
      : _repository = repository ?? CartRepository(),
        _authProvider = authProvider {
    _lastLocalMode = _usesLocalCart;
    _authProvider?.addListener(_onAuthChanged);
    _initialLoad = loadCart();
    unawaited(_initialLoad);
  }

  final CartRepository _repository;
  final AuthProvider? _authProvider;
  final GuestBuyerStorage _guestStorage = GuestBuyerStorage();
  late final Future<void> _initialLoad;
  late bool _lastLocalMode;

  bool get _usesLocalCart => _authProvider?.isUsingLocalBuyerData ?? false;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  List<CartItemModel> _items = [];
  DeliveryMethod _deliveryMethod = DeliveryMethod.pickup;
  bool _isLoading = false;
  String? _error;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  List<CartItemModel> get items => _items;
  DeliveryMethod get deliveryMethod => _deliveryMethod;
  String? get couponCode => null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  int get subtotal => _items.fold(0, (sum, item) => sum + item.totalPrice);

  int get deliveryFee {
    if (_deliveryMethod != DeliveryMethod.courier || _items.isEmpty) return 0;
    final storeIds = _items
        .map((item) => item.product?.storeId ?? item.product?.store?.id)
        .whereType<int>()
        .toSet();
    final storeCount = storeIds.isEmpty ? 1 : storeIds.length;
    return 15000 * storeCount;
  }

  int get discount => 0;

  int get total => subtotal - discount + deliveryFee;

  // ---------------------------------------------------------------------------
  // Load cart from API
  // ---------------------------------------------------------------------------

  Future<void> loadCart() async {
    _setLoading(true);
    if (_usesLocalCart) {
      final cached = await _guestStorage.readCart();
      _items = cached
          .map(CartItemModel.fromCacheJson)
          .where((item) => item.product != null)
          .toList();
      _error = null;
      _setLoading(false);
      return;
    }
    final result = await _repository.getCart();
    result.fold(
      onSuccess: (cartModel) {
        _items = cartModel.items;
        _error = null;
      },
      onError: (failure) {
        _error = failure.message;
      },
    );
    _setLoading(false);
  }

  void _onAuthChanged() {
    final localMode = _usesLocalCart;
    if (localMode == _lastLocalMode) return;
    _lastLocalMode = localMode;
    unawaited(loadCart());
  }

  Future<void> _persistLocalCart() async {
    await _guestStorage.writeCart(
      _items
          .where((item) => item.product != null)
          .map((item) => item.toCacheJson())
          .toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Add item
  // ---------------------------------------------------------------------------

  /// Mahsulotni savatchaga qo'shadi va savatchani yangilaydi.
  Future<void> addItem(ProductModel product, {int quantity = 1}) async {
    await _initialLoad;
    _setLoading(true);

    // Optimistic local update
    final existingIdx = _items.indexWhere((i) => i.product?.id == product.id);
    if (existingIdx != -1) {
      _items[existingIdx].quantity += quantity;
      notifyListeners();
    } else {
      // Temporary local item (id=0 until server responds)
      _items.add(CartItemModel(id: 0, product: product, quantity: quantity));
      notifyListeners();
    }

    if (_usesLocalCart) {
      await _persistLocalCart();
      _setLoading(false);
      return;
    }

    final result = await _repository.addToCart(product.id, quantity);
    result.fold(
      onSuccess: (_) async {
        // Refresh from server to get real cart item IDs
        await _refreshCart();
      },
      onError: (failure) {
        // Rollback optimistic update
        if (existingIdx != -1) {
          _items[existingIdx].quantity -= quantity;
          if (_items[existingIdx].quantity <= 0) {
            _items.removeAt(existingIdx);
          }
        } else {
          _items.removeWhere((i) => i.product?.id == product.id && i.id == 0);
        }
        _error = failure.message;
      },
    );

    _setLoading(false);
  }

  // ---------------------------------------------------------------------------
  // Remove item
  // ---------------------------------------------------------------------------

  /// Savatcha elementini o'chiradi.
  ///
  /// [productId] — ProductModel.id (int). Savatcha elementining id'si
  /// topiladi va serverga yuboriladi.
  Future<void> removeItem(int productId) async {
    await _initialLoad;
    final idx = _items.indexWhere((i) => i.product?.id == productId);
    if (idx == -1) return;

    final cartItemId = _items[idx].id;
    final removed = _items.removeAt(idx);
    notifyListeners();

    if (_usesLocalCart) {
      await _persistLocalCart();
      return;
    }
    if (cartItemId == 0) return; // local-only item

    final result = await _repository.removeFromCart(cartItemId);
    result.fold(
      onSuccess: (_) {},
      onError: (failure) {
        // Rollback
        _items.insert(idx, removed);
        _error = failure.message;
        notifyListeners();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Update quantity
  // ---------------------------------------------------------------------------

  /// Savatcha elementining miqdorini yangilaydi.
  ///
  /// [productId] — ProductModel.id (int).
  /// [qty] <= 0 bo'lsa element o'chiriladi.
  Future<void> updateQuantity(int productId, int qty) async {
    await _initialLoad;
    final idx = _items.indexWhere((i) => i.product?.id == productId);
    if (idx == -1) return;

    if (qty <= 0) {
      await removeItem(productId);
      return;
    }

    final cartItemId = _items[idx].id;
    final oldQty = _items[idx].quantity;
    _items[idx].quantity = qty;
    notifyListeners();

    if (_usesLocalCart) {
      await _persistLocalCart();
      return;
    }
    if (cartItemId == 0) return; // local-only item

    final result = await _repository.updateQuantity(cartItemId, qty);
    result.fold(
      onSuccess: (_) {},
      onError: (failure) {
        // Rollback
        _items[idx].quantity = oldQty;
        _error = failure.message;
        notifyListeners();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Local-only helpers
  // ---------------------------------------------------------------------------

  void setDeliveryMethod(DeliveryMethod method) {
    _deliveryMethod = method;
    notifyListeners();
  }

  void applyCoupon(String code) {
    // Coupon support is not available in the order API yet.
  }

  void clear() {
    _items.clear();
    if (_usesLocalCart) unawaited(_guestStorage.clearCart());
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _refreshCart() async {
    final result = await _repository.getCart();
    result.fold(
      onSuccess: (cartModel) {
        _items = cartModel.items;
      },
      onError: (_) {},
    );
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    super.dispose();
  }
}
