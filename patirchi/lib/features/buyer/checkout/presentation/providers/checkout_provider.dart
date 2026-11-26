import 'package:flutter/material.dart';
import 'package:patirchi/core/constants/enums.dart';
import 'package:patirchi/core/error/result.dart';
import 'package:patirchi/features/buyer/address/data/models/address_model.dart';
import 'package:patirchi/features/buyer/cart/data/repositories/cart_repository.dart';
import 'package:patirchi/features/buyer/cart/presentation/providers/cart_provider.dart';
import 'package:patirchi/features/buyer/orders/data/models/order_model.dart';

enum PaymentMethod { cash, payme, click, uzum }

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'Naqd pul',
        PaymentMethod.payme => 'Payme',
        PaymentMethod.click => 'Click',
        PaymentMethod.uzum => 'Uzum Bank',
      };
}

class CheckoutProvider extends ChangeNotifier {
  CheckoutProvider({CartRepository? repository})
      : _repository = repository ?? CartRepository();

  final CartRepository _repository;
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  AddressModel? _selectedAddress;
  bool _isProcessing = false;
  String? _placedOrderNumber;
  String? _error;

  PaymentMethod get selectedPaymentMethod => _selectedPaymentMethod;
  AddressModel? get selectedAddress => _selectedAddress;
  bool get isProcessing => _isProcessing;
  String? get placedOrderNumber => _placedOrderNumber;
  String? get error => _error;

  void setPaymentMethod(PaymentMethod method) {
    if (method != PaymentMethod.cash) return;
    _selectedPaymentMethod = method;
    notifyListeners();
  }

  void setAddress(AddressModel? address) {
    _selectedAddress = address;
    notifyListeners();
  }

  Future<List<OrderModel>?> placeOrder(CartProvider cart) async {
    if (_selectedPaymentMethod != PaymentMethod.cash) {
      _error = 'Bu to\'lov usuli hozircha ishlamaydi.';
      notifyListeners();
      return null;
    }
    if (cart.deliveryMethod == DeliveryMethod.courier &&
        _selectedAddress == null) {
      _error = 'Yetkazib berish uchun manzil tanlang.';
      notifyListeners();
      return null;
    }

    _isProcessing = true;
    _error = null;
    notifyListeners();

    final result = await _repository.createOrders(
      fulfillmentType: cart.deliveryMethod == DeliveryMethod.pickup
          ? 'pickup'
          : 'delivery',
      deliveryAddress: cart.deliveryMethod == DeliveryMethod.courier
          ? _selectedAddress!.fullAddress
          : null,
    );
    final orders = result.dataOrNull;
    if (orders == null || orders.isEmpty) {
      _error = result.failureOrNull?.message ?? 'Buyurtma yaratilmadi.';
      _isProcessing = false;
      notifyListeners();
      return null;
    }

    _placedOrderNumber = orders.first.orderNumber;
    cart.clear();
    _isProcessing = false;
    notifyListeners();
    return orders;
  }

  void reset() {
    _selectedPaymentMethod = PaymentMethod.cash;
    _selectedAddress = null;
    _isProcessing = false;
    _placedOrderNumber = null;
    _error = null;
    notifyListeners();
  }
}
