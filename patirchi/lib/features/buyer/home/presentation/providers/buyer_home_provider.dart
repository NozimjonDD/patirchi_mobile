import 'dart:async';

import 'package:flutter/material.dart';
import 'package:patirchi/core/network/api_client.dart';
import 'package:patirchi/core/network/api_endpoints.dart';
import 'package:patirchi/core/storage/guest_buyer_storage.dart';
import 'package:patirchi/core/error/result.dart';
import 'package:patirchi/features/auth/presentation/providers/auth_provider.dart';
import 'package:patirchi/features/buyer/home/data/datasources/buyer_home_local_datasource.dart';
import 'package:patirchi/features/buyer/home/data/models/product_model.dart';
import 'package:patirchi/features/buyer/home/data/models/shop_model.dart';
import 'package:patirchi/features/buyer/home/data/repositories/buyer_repository.dart';

class BuyerHomeProvider extends ChangeNotifier {
  BuyerHomeProvider({BuyerRepository? repository, AuthProvider? authProvider})
      : _repository = repository ?? BuyerRepository(),
        _authProvider = authProvider {
    _lastLocalMode = _usesLocalBuyerData;
    _authProvider?.addListener(_onAuthChanged);
    loadData();
  }

  final BuyerRepository _repository;
  final AuthProvider? _authProvider;
  final GuestBuyerStorage _guestStorage = GuestBuyerStorage();
  final Map<int, ProductModel> _favoriteProducts = {};
  late bool _lastLocalMode;

  bool get _usesLocalBuyerData =>
      _authProvider?.isUsingLocalBuyerData ?? true;

  static const int _pageSize = 20;

  List<ProductModel> _products = [];
  List<ShopModel> _shops = [];
  List<ProductCategory> _categories = [];
  String _searchQuery = '';
  int _selectedCategoryIndex = 0;
  int? _selectedCategoryId;

  // Pagination state
  int _offset = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;
  bool _isInitialLoading = true;
  String? _error;

  // Getters
  List<ProductModel> get products {
    if (_searchQuery.isNotEmpty) {
      final lower = _searchQuery.toLowerCase();
      return _products
          .where((p) => p.name.toLowerCase().contains(lower))
          .toList();
    }
    return _products;
  }

  List<ShopModel> get shops => _shops;
  List<ProductModel> get favoriteProducts =>
      List.unmodifiable(_favoriteProducts.values);
  List<ProductCategory> get categories => _categories;
  int get selectedCategory => _selectedCategoryIndex;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get isRefreshing => _isRefreshing;
  bool get isInitialLoading => _isInitialLoading;
  String? get error => _error;

  // ---------------------------------------------------------------------------
  // Initial load
  // ---------------------------------------------------------------------------

  Future<void> loadData() async {
    _isInitialLoading = true;
    _error = null;
    notifyListeners();

    await _loadWishlist();
    await Future.wait([
      _loadProducts(reset: true),
      _loadShops(),
      _loadCategories(),
    ]);

    _isInitialLoading = false;
    notifyListeners();
  }

  void _onAuthChanged() {
    final localMode = _usesLocalBuyerData;
    if (localMode == _lastLocalMode) return;
    _lastLocalMode = localMode;
    unawaited(_loadWishlist().then((_) {
      _applyFavorites();
      notifyListeners();
    }));
  }

  Future<void> _loadWishlist() async {
    if (_usesLocalBuyerData) {
      final cached = await _guestStorage.readWishlist();
      _favoriteProducts
        ..clear()
        ..addEntries(cached.map((item) {
          final product = ProductModel.fromCacheJson(item);
          return MapEntry(product.id, product.copyWith(isFavorite: true));
        }));
      _applyFavorites();
      return;
    }

    try {
      final response = await ApiClient.instance.get(ApiEndpoints.wishlist);
      final rawProducts = response['products'] as List<dynamic>? ?? [];
      _favoriteProducts
        ..clear()
        ..addEntries(rawProducts
            .whereType<Map<String, dynamic>>()
            .map((item) {
          final product = ProductModel.fromJson(item).copyWith(isFavorite: true);
          return MapEntry(product.id, product);
        }));
      if (rawProducts.isEmpty) {
        final ids = (response['product_ids'] as List<dynamic>? ?? [])
            .whereType<num>()
            .map((id) => id.toInt())
            .toSet();
        for (final product in _products.where((item) => ids.contains(item.id))) {
          _favoriteProducts[product.id] = product.copyWith(isFavorite: true);
        }
      }
      _applyFavorites();
    } on Object {
      // Tarmoq vaqtincha ishlamasa, hozirgi ro'yxatni ekranda saqlab turamiz.
    }
  }

  void _applyFavorites() {
    final ids = _favoriteProducts.keys.toSet();
    for (final product in _products) {
      product.isFavorite = ids.contains(product.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------

  Future<void> _loadProducts({bool reset = false}) async {
    if (reset) {
      _offset = 0;
      _hasMore = true;
    }

    final result = await _repository.getProducts(
      limit: _pageSize,
      offset: _offset,
      category: _selectedCategoryId,
    );

    result.fold(
      onSuccess: (items) {
        if (reset) {
          _products = items;
        } else {
          _products = [..._products, ...items];
        }
        _hasMore = items.length >= _pageSize;
        _offset = _products.length;
        _error = null;
        _applyFavorites();
      },
      onError: (failure) {
        if (reset) {
          // Fallback to local data on initial load failure
          _products = List.from(BuyerHomeLocalDatasource.products);
          _hasMore = false;
        }
        _error = failure.message;
      },
    );
  }

  /// Pull-to-refresh
  Future<void> refresh() async {
    _isRefreshing = true;
    notifyListeners();

    await Future.wait([
      _loadProducts(reset: true),
      _loadShops(),
    ]);

    _isRefreshing = false;
    notifyListeners();
  }

  /// Infinite scroll — load next page
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore || _searchQuery.isNotEmpty) return;

    _isLoadingMore = true;
    notifyListeners();

    await _loadProducts(reset: false);

    _isLoadingMore = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Shops
  // ---------------------------------------------------------------------------

  Future<void> _loadShops() async {
    final result = await _repository.getStores();
    result.fold(
      onSuccess: (shops) {
        _shops = shops;
      },
      onError: (_) {
        if (_shops.isEmpty) {
          _shops = List.from(BuyerHomeLocalDatasource.shops);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  Future<void> _loadCategories() async {
    final result = await _repository.getCategories();
    result.fold(
      onSuccess: (cats) => _categories = cats,
      onError: (_) {},
    );
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  void search(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Category filter
  // ---------------------------------------------------------------------------

  void selectCategory(int index, {int? categoryId}) {
    _selectedCategoryIndex = index;
    _selectedCategoryId = categoryId;
    _loadProducts(reset: true).then((_) => notifyListeners());
  }

  // ---------------------------------------------------------------------------
  // Favorites (local-only toggle)
  // ---------------------------------------------------------------------------

  void toggleFavorite(int productId) {
    ProductModel? current = _favoriteProducts[productId];
    if (current == null) {
      for (final product in _products) {
        if (product.id == productId) {
          current = product;
          break;
        }
      }
    }
    if (current == null) return;
    final removing = _favoriteProducts.containsKey(productId);
    if (removing) {
      _favoriteProducts.remove(productId);
    } else {
      _favoriteProducts[productId] = current.copyWith(isFavorite: true);
    }
    _applyFavorites();
    notifyListeners();
    unawaited(_persistWishlistChange(productId, removing));
  }

  Future<void> _persistWishlistChange(int productId, bool removing) async {
    if (_usesLocalBuyerData) {
      await _guestStorage.writeWishlist(
        _favoriteProducts.values.map((product) => product.toCacheJson()).toList(),
      );
      return;
    }
    try {
      if (removing) {
        await ApiClient.instance.delete(ApiEndpoints.wishlistItem(productId));
      } else {
        await ApiClient.instance.post(
          ApiEndpoints.wishlistSync,
          body: {'product_ids': [productId]},
        );
      }
    } on Object {
      // Lokal holat ko'rinib turadi; keyingi kirishda server bilan yangilanadi.
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    super.dispose();
  }
}
