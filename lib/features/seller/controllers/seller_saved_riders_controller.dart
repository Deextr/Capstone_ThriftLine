import 'package:flutter/foundation.dart';

import '../data/seller_saved_rider.dart';
import '../data/seller_saved_riders_service.dart';

class SellerSavedRidersController extends ChangeNotifier {
  SellerSavedRidersController({required SellerSavedRidersService service})
      : _service = service {
    load();
  }

  final SellerSavedRidersService _service;

  List<SellerSavedRider> _riders = const [];
  bool _loading = true;
  String? _errorMessage;
  bool _deleting = false;

  List<SellerSavedRider> get riders => _riders;
  bool get isLoading => _loading;
  String? get errorMessage => _errorMessage;
  bool get isDeleting => _deleting;

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _riders = await _service.listMine();
    } catch (_) {
      _errorMessage = 'Could not load your saved riders.';
      _riders = const [];
    }

    _loading = false;
    notifyListeners();
  }

  Future<String?> deleteRider(String savedRiderId) async {
    _deleting = true;
    notifyListeners();

    final error = await _service.delete(savedRiderId);
    if (error == null) {
      _riders = _riders.where((r) => r.id != savedRiderId).toList();
    }

    _deleting = false;
    notifyListeners();
    return error;
  }
}
