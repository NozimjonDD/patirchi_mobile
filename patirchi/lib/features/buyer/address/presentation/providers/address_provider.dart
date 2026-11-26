import 'package:flutter/material.dart';
import 'package:patirchi/features/buyer/address/data/models/address_model.dart';

class AddressProvider extends ChangeNotifier {
  final List<AddressModel> _addresses = [];

  AddressModel? _selectedAddress;

  List<AddressModel> get addresses => List.unmodifiable(_addresses);

  AddressModel? get selectedAddress =>
      _selectedAddress ??
      (_addresses.isNotEmpty
          ? _addresses.firstWhere(
              (a) => a.isDefault,
              orElse: () => _addresses.first,
            )
          : null);

  void selectAddress(AddressModel address) {
    _selectedAddress = address;
    notifyListeners();
  }

  void addAddress(AddressModel address) {
    final newAddress = address.copyWith(
      id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (_addresses.isEmpty || address.isDefault) {
      final updated = _addresses
          .map((a) => a.copyWith(isDefault: false))
          .toList();
      _addresses.clear();
      _addresses.addAll(updated);
      _addresses.add(newAddress.copyWith(isDefault: true));
    } else {
      _addresses.add(newAddress);
    }
    notifyListeners();
  }

  void updateAddress(AddressModel address) {
    final idx = _addresses.indexWhere((a) => a.id == address.id);
    if (idx != -1) {
      _addresses[idx] = address;
      notifyListeners();
    }
  }

  void deleteAddress(String id) {
    _addresses.removeWhere((a) => a.id == id);
    if (_selectedAddress?.id == id) {
      _selectedAddress = null;
    }
    notifyListeners();
  }

  void setDefault(String id) {
    for (var i = 0; i < _addresses.length; i++) {
      _addresses[i] = _addresses[i].copyWith(isDefault: _addresses[i].id == id);
    }
    notifyListeners();
  }
}
