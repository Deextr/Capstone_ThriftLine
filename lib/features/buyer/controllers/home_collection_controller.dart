import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../models/product_model.dart';
import '../../../models/seller_profile.dart';
import '../data/catalog_product_query.dart';
import '../data/home_feed_query.dart';
import 'home_controller.dart';

class HomeCollectionController extends ChangeNotifier {
  HomeCollectionController({
    required SupabaseService supabase,
    required this.type,
  }) : _supabase = supabase {
    load();
  }

  final SupabaseService _supabase;
  final HomeCollectionType type;

  List<ProductModel> _products = [];
  List<SellerProfile> _sellers = [];
  Map<String, int> _cartCounts = const {};
  bool _isLoading = false;
  String? _errorMessage;
  bool _isOffline = false;

  List<ProductModel> get products => _products;
  List<SellerProfile> get sellers => _sellers;
  Map<String, int> get cartCounts => _cartCounts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  bool get isOffline => _isOffline;

  String get title => switch (type) {
    HomeCollectionType.endingSoon => 'Ending Soon',
    HomeCollectionType.suggested => 'Suggested for You',
    HomeCollectionType.bidding => 'Bidding Products',
    HomeCollectionType.verifiedSellers => 'Verified Sellers',
  };

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    _isOffline = false;
    notifyListeners();

    final client = _supabase.client;
    try {
      if (type == HomeCollectionType.verifiedSellers) {
        final map = await fetchSellerProfilesMap(client);
        _sellers = verifiedSellersFromProfiles(map);
        _products = [];
      } else {
        List<dynamic> rows;
        List<String>? orderIds;
        if (type == HomeCollectionType.endingSoon) {
          orderIds = await fetchEndingSoonProductIds(client, limit: 40);
          rows = await fetchCatalogProductRows(
            client,
            limit: 40,
            productIds: orderIds,
          );
        } else if (type == HomeCollectionType.bidding) {
          rows = await fetchCatalogProductRows(
            client,
            limit: 60,
            listingType: 'auction',
          );
        } else {
          try {
            rows = await fetchCatalogProductRows(
              client,
              limit: 40,
              orderColumn: 'views',
            );
          } catch (_) {
            rows = await fetchCatalogProductRows(client, limit: 40);
          }
        }

        final extraIds = rows
            .map((r) => (r as Map<String, dynamic>)['seller_id'] as String?)
            .whereType<String>();
        final sellers = await fetchSellerProfilesMap(
          client,
          extraSellerIds: extraIds,
          includeApproved: false,
        );
        var products = hydrateCatalogProducts(
          rows,
          sellers,
        ).where(isLiveBuyerHomeListing).toList();

        if (type == HomeCollectionType.endingSoon) {
          products = sortProductsByIdOrder(products, orderIds ?? const []);
        }

        _products = products;
        _cartCounts = await fetchProductCartCounts(
          client,
          products
              .where((p) => p.sellingType == SellingType.fixedPrice)
              .map((p) => p.id),
        );
      }
      _errorMessage = null;
    } catch (e) {
      debugPrint('HomeCollectionController.load: $e');
      _isOffline = isHomeOfflineError(e);
      _errorMessage = _isOffline
          ? 'You appear to be offline. Connect and try again.'
          : 'Could not load this collection. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
